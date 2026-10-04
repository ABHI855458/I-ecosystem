-- ============================================================================
-- POST PRESENCE — backs the "N here" pill + dropdown
-- (post_card_shared.dart's LivePresencePill/LivePresenceDropdown), which
-- until now rendered demoLivePresence()'s hash-seeded FAKE names — there was
-- no presence table at all. `schema.sql` claims an `active_sessions` table
-- for this; it does not exist on the live DB (confirmed by direct
-- introspection), so this is a new table, not a drift-fix of an existing
-- one.
--
-- Rows are a simple heartbeat: (post_id | group_post_id, user_id) ->
-- last_seen_at, upserted by PresenceService.touch() while a post card is on
-- screen. Mirrors comments/reactions' own post_id XOR group_post_id split —
-- group posts (design_group_card.dart / group_card_shared.dart) live in
-- `group_posts`, not `posts`, and this table needs to back presence on
-- both. "Here now" vs "last 3 hours" is a client-side split on
-- last_seen_at, not two tables.
-- ============================================================================

CREATE TABLE IF NOT EXISTS post_presence (
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  group_post_id UUID REFERENCES group_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT post_presence_post_xor_group_post
    CHECK ((post_id IS NOT NULL) <> (group_post_id IS NOT NULL))
);

-- Partial unique indexes stand in for a composite PRIMARY KEY here since
-- exactly one of post_id/group_post_id is ever set per row (see the XOR
-- check above) — a single PK on (post_id, group_post_id, user_id) would
-- accept multiple rows per user on the same post as long as one of the two
-- id columns differs by being NULL vs NULL, which defeats upsert dedup.
CREATE UNIQUE INDEX IF NOT EXISTS post_presence_post_user_key
  ON post_presence(post_id, user_id) WHERE post_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS post_presence_group_post_user_key
  ON post_presence(group_post_id, user_id) WHERE group_post_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS post_presence_post_recent_idx
  ON post_presence(post_id, last_seen_at DESC) WHERE post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS post_presence_group_post_recent_idx
  ON post_presence(group_post_id, last_seen_at DESC) WHERE group_post_id IS NOT NULL;

ALTER TABLE post_presence ENABLE ROW LEVEL SECURITY;

-- A user may only stamp their OWN presence.
CREATE POLICY "post_presence_upsert_own" ON post_presence FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "post_presence_update_own" ON post_presence FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- Presence is visible to exactly whoever could see the underlying post —
-- mirrors posts_select's own rule (see the anon-identity-leak migration,
-- 20260829020000) for personal/everyone/anon posts, and group_posts_select
-- (group membership) for group posts, rather than inventing separate rules,
-- so an anonymous post's presence can never out its viewers and a
-- non-member can never see who's on a group post.
CREATE POLICY "post_presence_select" ON post_presence FOR SELECT USING (
  (
    post_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM posts p
      WHERE p.id = post_presence.post_id
        AND p.deleted_at IS NULL
        AND (
          p.visibility IS DISTINCT FROM 'anonymous'
          OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
        )
    )
  ) OR (
    group_post_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM group_posts gp
      JOIN group_members gm ON gm.group_id = gp.group_id
      JOIN users u ON u.id = gm.user_id
      WHERE gp.id = post_presence.group_post_id
        AND u.auth_id = auth.uid()
    )
  )
);

-- Rows older than the 3h window this feature ever reads are dead weight —
-- swept opportunistically from the same RPC PresenceService.touch() calls,
-- rather than requiring a cron/pg_cron extension for a low-volume table.
-- Exactly one of p_post_id/p_group_post_id must be passed (mirrors the
-- table's own XOR constraint).
CREATE OR REPLACE FUNCTION touch_post_presence(
  p_post_id UUID DEFAULT NULL,
  p_group_post_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  IF (p_post_id IS NOT NULL) = (p_group_post_id IS NOT NULL) THEN
    RAISE EXCEPTION 'touch_post_presence: pass exactly one of p_post_id / p_group_post_id';
  END IF;

  SELECT id INTO v_user_id FROM users WHERE auth_id = auth.uid();
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  IF p_post_id IS NOT NULL THEN
    INSERT INTO post_presence (post_id, user_id, last_seen_at)
    VALUES (p_post_id, v_user_id, now())
    ON CONFLICT (post_id, user_id) WHERE post_id IS NOT NULL
    DO UPDATE SET last_seen_at = now();
  ELSE
    INSERT INTO post_presence (group_post_id, user_id, last_seen_at)
    VALUES (p_group_post_id, v_user_id, now())
    ON CONFLICT (group_post_id, user_id) WHERE group_post_id IS NOT NULL
    DO UPDATE SET last_seen_at = now();
  END IF;

  DELETE FROM post_presence WHERE last_seen_at < now() - INTERVAL '3 hours';
END;
$$;
