-- ============================================================================
-- Feed rules: 24-hour anon expiry + "already reacted" exclusion
-- ============================================================================
--
-- Two feed behaviors, both implemented as QUERY FILTERS (no destructive
-- deletes, no new expiry column):
--
--   1. 24-HOUR ANON RULE — anonymous posts stop appearing in the Anon feed
--      and the author's own Anon profile tab exactly 24h after creation.
--      Implemented as `created_at > NOW() - INTERVAL '24 hours'` at the
--      query layer (see FeedService.fetchAnonFeed / PostService's own anon
--      queries), NOT as a delete or an expires_at column: rows stay in the
--      DB so comments/reactions//moderation history remain intact and the
--      window is trivially adjustable later. `posts` already has a
--      created_at DEFAULT NOW() (schema.sql) — nothing to add there.
--
--   2. ALREADY-REACTED EXCLUSION — once a user has REACTED to a post it
--      never reappears in their feeds. Per explicit product decision this
--      keys on reactions ONLY (a plain view/scroll-past does NOT hide a
--      post), so no view-tracking table is needed at all.
--
--      "Reacted" spans BOTH reaction systems this app runs in parallel:
--        * `reactions`                 — emoji reactions (ReactionService)
--        * `post_realmoji_reactions`   — RealMoji selfies (RealmojiService)
--      A reaction in either one hides the post.
--
-- This migration adds only the indexes those filters need; no table or
-- column changes, so it is safe to re-run and safe to roll back by simply
-- dropping the indexes.
-- ============================================================================

-- 24h anon window: the Anon feed's hot path is
--   WHERE visibility = 'anonymous' AND created_at > (now - 24h)
--   ORDER BY created_at DESC
-- A composite index on (visibility, created_at DESC) serves the filter and
-- the ordering together. schema.sql already has separate posts_visibility_idx
-- and posts_created_idx, but Postgres can only use one of them for this
-- combined predicate+sort; the composite avoids a re-sort of the matched set.
CREATE INDEX IF NOT EXISTS posts_visibility_created_idx
  ON posts(visibility, created_at DESC);

-- Already-reacted lookup: "give me every post_id THIS user has reacted to".
-- schema.sql indexes reactions(user_id) and reactions(post_id) separately;
-- this composite makes the per-user lookup an index-only scan rather than a
-- filter over every row that user has ever reacted to.
CREATE INDEX IF NOT EXISTS reactions_user_post_idx
  ON reactions(user_id, post_id);

-- Same lookup against the RealMoji side. Guarded in a DO block because
-- post_realmoji_reactions is NOT created by schema.sql (it exists in the
-- live database and is referenced by that file's own RLS policies/triggers,
-- but its CREATE TABLE lives outside version control — a known pre-existing
-- schema drift). Without the guard this migration would fail outright on any
-- environment where that table hasn't been provisioned yet.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'post_realmoji_reactions'
  ) THEN
    CREATE INDEX IF NOT EXISTS post_realmoji_reactions_user_post_idx
      ON post_realmoji_reactions(user_id, post_id);

    -- group_post_id is nullable and only present on some deployments (the
    -- same drift noted above — runtime logs show environments where this
    -- column is missing), so index it only if it actually exists.
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'post_realmoji_reactions'
        AND column_name = 'group_post_id'
    ) THEN
      CREATE INDEX IF NOT EXISTS post_realmoji_reactions_user_group_post_idx
        ON post_realmoji_reactions(user_id, group_post_id);
    END IF;
  END IF;
END $$;

-- Group posts already flow into the Friends feed via
-- GroupService.fetchFeedPosts (group_members -> group_posts), and into the
-- shared Group Profile via GroupService.fetchPosts. Both already order by
-- created_at DESC over a group_id set, which group_posts_group_idx covers.
-- Adding the composite so the ordering doesn't require a re-sort either.
CREATE INDEX IF NOT EXISTS group_posts_group_created_idx
  ON group_posts(group_id, created_at DESC);

-- ============================================================================
-- TODO(feed): add engagement counts to posts_feed  [FOLLOW-UP, NOT IN THIS FILE]
-- ============================================================================
--
-- PROBLEM
--   `posts_feed` returns no reaction or comment counts, so a feed row
--   arrives with those counts UNKNOWN. AnonFeedPost.fromRow therefore
--   leaves them null (deliberately NOT 0 — "0" renders as a confident
--   "nobody reacted" on a post that may have plenty), and the Anon feed
--   screen backfills them with a per-post round-trip
--   (_AnonFeedScreenV2State._hydrateCounts), showing a shimmer skeleton in
--   the meantime (_CountOrSkeleton).
--
--   That's an N+1: one query for the page, then 2 more per post in it
--   (ReactionService.fetchSummary + CommentService.fetchCount). At the
--   current page size of 20 that's up to 41 queries to render one page.
--
-- FIX
--   Add reaction_count and comment_count to the posts_feed view, e.g. as
--   correlated subqueries or a LEFT JOIN against grouped counts over
--   `reactions` / `post_realmoji_reactions` / `comments`. Then fromRow can
--   read them directly and _hydrateCounts + _CountOrSkeleton can both be
--   deleted outright.
--
-- WHY NOT NOW
--   posts_feed is a security-sensitive view (it masks user_id on anonymous
--   posts — see schema.sql; every anon-privacy guarantee in the app leans
--   on that masking). Changing its shape deserves its own migration and
--   its own review of the anon-leak surface, rather than riding along with
--   an index-only change. Counting reactions per post also has to respect
--   the same RLS the base tables do, or the count itself becomes a leak
--   (e.g. revealing that a hidden post exists).
-- ============================================================================
