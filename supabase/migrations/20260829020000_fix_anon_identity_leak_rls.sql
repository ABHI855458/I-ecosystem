-- ============================================================================
-- CRITICAL FIX — comments/reactions/post_realmoji_reactions SELECT policies
-- leaked real user identity on anonymous posts to ANY caller, including
-- fully unauthenticated ones. LIVE issue, found 2026-08-29 while starting
-- what was originally scoped as a schema-drift cleanup (see TICKET 1/2 in
-- TODO_TICKETS.md for that original, unrelated scope).
--
-- NOT RUN YET — for review. Per explicit instruction, YOU run this manually
-- in the Supabase SQL Editor once approved, same as every other migration
-- tonight — I am not executing this one myself given its severity.
-- ============================================================================
--
-- THE BUG (confirmed via direct introspection of the LIVE policies, not
-- assumed):
--   comments_select              USING (deleted_at IS NULL)
--   reactions_select              USING (EXISTS (SELECT 1 FROM posts WHERE id = post_id))
--   post_realmoji_reactions_select USING (EXISTS (SELECT 1 FROM posts WHERE id = post_id))
-- All three have empty `polroles` (applies to PUBLIC — every role,
-- including the fully unauthenticated `anon` role) and none of them check
-- the POST's visibility at all. Any client — logged in or not — can query
-- these three tables directly via the Supabase REST API and read every
-- comment, every reaction, and every RealMoji reactor's real `user_id` on
-- every post, including posts with visibility='anonymous'.
--
-- This directly undermines this app's own established anon-identity
-- protection model: `posts_select` itself (confirmed live) already gets
-- this right —
--   USING (deleted_at IS NULL AND (
--     visibility IS DISTINCT FROM 'anonymous'
--     OR auth.uid() IN (SELECT auth_id FROM users WHERE id = posts.user_id)
--   ))
-- — i.e. non-anonymous posts are visible to everyone; an anonymous post is
-- visible ONLY to its own author. `posts_feed` (the view the Anon feed
-- actually queries) leans on this same rule to mask identity. But
-- `comments`/`reactions`/`post_realmoji_reactions` never inherited it —
-- they're base tables, directly queryable via PostgREST regardless of
-- whether the app's own UI ever goes through `posts_feed`.
--
-- THE FIX — mirror `posts_select`'s exact rule via an EXISTS join back to
-- `posts` in all three SELECT policies. A comment/reaction is visible only
-- if the POST it belongs to would itself be visible under that same rule.
--
-- post_realmoji_reactions ALSO had two now-fully-redundant SELECT
-- policies ("anon scope select poster only", "everyone scope select
-- full") that were clearly an earlier, correct attempt at exactly this
-- restriction — moot because Postgres OR's every permissive policy
-- together, so the third, unrestricted "post_realmoji_reactions_select"
-- policy already granted everything on its own regardless of the other
-- two. Dropped as part of this fix (consolidated into one correct policy)
-- rather than left as confusing dead weight.
--
-- SCOPE NOTE: `posts_select` also has a second policy, "close_group_view_
-- posts" (follows-based visibility for non-anonymous posts from people you
-- follow) — that's a SEPARATE, additive visibility grant orthogonal to the
-- anon-masking rule this fix targets, and none of the three broken
-- policies here ever attempted to support it. Not added in this fix —
-- out of scope for closing the anon-identity leak specifically.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "comments_select" ON comments;

CREATE POLICY "comments_select" ON comments FOR SELECT USING (
  deleted_at IS NULL
  AND EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = comments.post_id
    AND p.deleted_at IS NULL
    AND (
      p.visibility IS DISTINCT FROM 'anonymous'
      OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
    )
  )
);

-- ---------------------------------------------------------------------------
-- reactions
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "reactions_select" ON reactions;

CREATE POLICY "reactions_select" ON reactions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = reactions.post_id
    AND p.deleted_at IS NULL
    AND (
      p.visibility IS DISTINCT FROM 'anonymous'
      OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
    )
  )
);

-- ---------------------------------------------------------------------------
-- post_realmoji_reactions — also drops the two now-redundant policies
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "post_realmoji_reactions_select" ON post_realmoji_reactions;
DROP POLICY IF EXISTS "anon scope select poster only" ON post_realmoji_reactions;
DROP POLICY IF EXISTS "everyone scope select full" ON post_realmoji_reactions;

CREATE POLICY "post_realmoji_reactions_select" ON post_realmoji_reactions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = post_realmoji_reactions.post_id
    AND p.deleted_at IS NULL
    AND (
      p.visibility IS DISTINCT FROM 'anonymous'
      OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
    )
  )
);
