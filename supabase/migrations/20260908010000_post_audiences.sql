-- ============================================================================
-- post_audiences — lets a `posts` row be visible to Friends AND/OR one-or-
-- more Communities, multi-select and combined (not exclusive), plus a
-- feed-visibility toggle. Unblocks two things previously impossible:
--   A1: a personal post visible only to the poster's friends — there was no
--       'friends' value in posts.visibility's CHECK and no audience table at
--       all, so FeedService.fetchEveryoneFeed applied no audience filter.
--   C1: the composer's "Friends and/or one-or-more Communities" multi-select
--       audience picker — same missing schema.
--
-- Idempotent, safe to re-run (mirrors 20260904000000_community_posts.sql's
-- own IF NOT EXISTS / DO $$ guard style).
-- ============================================================================

-- 1. 'friends' becomes a valid posts.visibility value alongside the existing
--    three. A post's PRIMARY visibility stays a single value (unchanged
--    column, unchanged meaning for 'anonymous'/'everyone'/'community'); a
--    'friends'-visibility post additionally consults post_audiences for
--    which communities (if any) are ALSO allowed in, per C1's "combined"
--    model — see can_view_post below.
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_visibility_check;
ALTER TABLE posts ADD CONSTRAINT posts_visibility_check
  CHECK (visibility IN ('anonymous', 'everyone', 'community', 'friends'));

-- 2. Feed-visibility toggle (C1: "whether it appears in the feed").
ALTER TABLE posts ADD COLUMN IF NOT EXISTS show_in_feed BOOLEAN NOT NULL DEFAULT true;

-- 3. post_audiences — one row per extra audience a 'friends'-visibility post
--    is also opened up to. audience_kind='friends' is implicit in
--    visibility='friends' and not stored here; only 'community' rows are
--    stored, one per selected community, so a post can name several.
CREATE TABLE IF NOT EXISTS post_audiences (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id        UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  audience_kind  TEXT NOT NULL CHECK (audience_kind IN ('friends', 'community')),
  community_id   UUID REFERENCES communities(id) ON DELETE CASCADE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT post_audiences_community_kind_match CHECK (
    (audience_kind = 'community' AND community_id IS NOT NULL) OR
    (audience_kind = 'friends' AND community_id IS NULL)
  )
);

-- Unique per (post, kind, community): 'friends' can only appear once per
-- post; a given community can only be selected once per post. NULLS are
-- distinct in a unique index, so two 'friends' rows (community_id both
-- NULL) would NOT collide on a plain UNIQUE constraint — hence the partial
-- index below for that case, and a separate one for 'community' rows.
CREATE UNIQUE INDEX IF NOT EXISTS post_audiences_friends_unique
  ON post_audiences (post_id) WHERE audience_kind = 'friends';
CREATE UNIQUE INDEX IF NOT EXISTS post_audiences_community_unique
  ON post_audiences (post_id, community_id) WHERE audience_kind = 'community';

CREATE INDEX IF NOT EXISTS post_audiences_post_idx ON post_audiences(post_id);

ALTER TABLE post_audiences ENABLE ROW LEVEL SECURITY;

-- 4. can_view_post — SECURITY DEFINER, mirroring is_community_member's own
-- reasoning (20260904000000_community_posts.sql): a plain client-side query
-- CANNOT compute "is viewer a friend of the author" because friendships'
-- own RLS (friendships_select_own) only lets a user read rows they are a
-- party to — a third-party viewer has no grant to read the AUTHOR's
-- friendship rows. This is exactly the constraint TODO_TICKETS.md's TICKET 3
-- flagged for Us-album 'mutual' visibility; same fix shape here.
CREATE OR REPLACE FUNCTION can_view_post(p_post_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer_id UUID;
  v_author_id UUID;
  v_visibility TEXT;
BEGIN
  SELECT id INTO v_viewer_id FROM users WHERE auth_id = auth.uid();
  IF v_viewer_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT user_id, visibility INTO v_author_id, v_visibility
    FROM posts WHERE id = p_post_id;
  IF v_author_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF v_viewer_id = v_author_id THEN
    RETURN TRUE;
  END IF;

  -- Only 'friends' visibility is audience-gated by this function; the other
  -- three values keep whatever posts_select already decides for them
  -- (this function is OR'd into posts_select only for the 'friends' case —
  -- see the policy below).
  IF v_visibility <> 'friends' THEN
    RETURN TRUE;
  END IF;

  IF EXISTS (
    SELECT 1 FROM friendships
    WHERE status = 'accepted'
      AND (
        (requester_id = v_author_id AND addressee_id = v_viewer_id) OR
        (requester_id = v_viewer_id AND addressee_id = v_author_id)
      )
  ) THEN
    RETURN TRUE;
  END IF;

  -- Combined audience: also allowed in via any selected community the
  -- viewer belongs to. Reuses is_community_member rather than duplicating
  -- its auth.uid()-keyed community_members check.
  IF EXISTS (
    SELECT 1 FROM post_audiences pa
    WHERE pa.post_id = p_post_id
      AND pa.audience_kind = 'community'
      AND is_community_member(pa.community_id, auth.uid())
  ) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION can_view_post(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION can_view_post(UUID) TO authenticated;

-- 5. Fold can_view_post into posts_select. Only ADDS a gate for the new
-- 'friends' value — every other branch of the existing policy (anonymous
-- author-only, deleted_at) is preserved unchanged.
DROP POLICY IF EXISTS "posts_select" ON posts;
CREATE POLICY "posts_select" ON posts FOR SELECT USING (
  deleted_at IS NULL
  AND (
    visibility IS DISTINCT FROM 'anonymous'
    OR auth.uid() IN (SELECT auth_id FROM users WHERE id = posts.user_id)
  )
  AND (
    visibility IS DISTINCT FROM 'friends'
    OR can_view_post(posts.id)
  )
);

-- 6. post_audiences RLS — readable iff the underlying post is readable
-- (mirrors group_post_reactions' "inherits posts_select's grant" pattern
-- noted elsewhere in this schema); writable only by the post's own author.
CREATE POLICY "post_audiences_select" ON post_audiences FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = post_audiences.post_id
      AND p.deleted_at IS NULL
      AND (
        p.visibility IS DISTINCT FROM 'anonymous'
        OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
      )
  )
);

CREATE POLICY "post_audiences_insert_own" ON post_audiences FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = post_audiences.post_id
      AND auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
  )
);

CREATE POLICY "post_audiences_delete_own" ON post_audiences FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = post_audiences.post_id
      AND auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
  )
);
