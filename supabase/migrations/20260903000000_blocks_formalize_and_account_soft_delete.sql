-- ============================================================================
-- Blocks: capture schema drift + enforce block filtering + account soft-delete
--
-- `blocks` and `is_blocked(uuid,uuid)` already exist LIVE in this project but
-- were never captured into a migration (confirmed via a live schema dump —
-- same doc-drift class this project has hit before with post_realmoji_reactions
-- / user_realmojis). This migration is written to be a no-op against the
-- live DB (IF NOT EXISTS / CREATE OR REPLACE throughout) while bringing the
-- repo's tracked schema back in sync, then adds the pieces that were missing
-- outright: a bridge from the auth-UID-keyed `blocks` table to the
-- `users.id`-keyed content tables, RESTRICTIVE policies that actually apply
-- that bridge to reads, and `users.deleted_at` for account deletion.
--
-- KEY-SPACE NOTE: blocks.blocker_id/blocked_id reference profiles(id), which
-- is the raw auth.uid() — NOT users.id, which is what posts/comments/
-- group_posts/reactions/post_realmoji_reactions all FK to (see
-- current_user_service.dart's own doc on this duality). Existing client code
-- in settings_screen.dart queries `blocks` with a users.id and has silently
-- never worked (undetected only because the table has 0 rows). Every new
-- reference below goes through auth.uid()/users.auth_id, not users.id.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Capture the drift: blocks table + its RLS + the existing is_blocked().
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.blocks (
  blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT no_self_block CHECK (blocker_id <> blocked_id)
);

ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS blk_read ON public.blocks;
CREATE POLICY blk_read ON public.blocks
  FOR SELECT USING (blocker_id = auth.uid());

DROP POLICY IF EXISTS blk_ins ON public.blocks;
CREATE POLICY blk_ins ON public.blocks
  FOR INSERT WITH CHECK (blocker_id = auth.uid());

DROP POLICY IF EXISTS blk_del ON public.blocks;
CREATE POLICY blk_del ON public.blocks
  FOR DELETE USING (blocker_id = auth.uid());

-- Mutual (order-independent) block check between two auth UIDs — matches the
-- live definition.
CREATE OR REPLACE FUNCTION public.is_blocked(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  select exists(select 1 from public.blocks
    where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a));
$$;

REVOKE ALL ON FUNCTION public.is_blocked(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_blocked(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_blocked(uuid, uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. Bridge helper: is a *content-table* author (a users.id) blocked
--    relative to the current viewer (an auth uid)? This is the piece that
--    was missing outright — nothing previously connected `blocks` to any
--    content table.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_blocked_user(viewer_auth uuid, target_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocks b
    JOIN public.users u ON u.id = target_user_id
    WHERE (b.blocker_id = viewer_auth AND b.blocked_id = u.auth_id)
       OR (b.blocker_id = u.auth_id  AND b.blocked_id = viewer_auth)
  );
$$;

REVOKE ALL ON FUNCTION public.is_blocked_user(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_blocked_user(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.is_blocked_user(uuid, uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. Enforcement via RESTRICTIVE policies.
--
-- posts and group_posts each already carry TWO permissive SELECT policies
-- (posts_select + close_group_view_posts; group_posts_select +
-- members_view_posts) — adding a clause to only one of an OR'd pair would be
-- silently bypassed by the other. A RESTRICTIVE policy ANDs with every
-- permissive policy on the table regardless of how many there are, so this
-- is the only shape that actually closes the gap.
--
-- ANONYMOUS CARVE-OUT, DELIBERATE: anon posts/comments/reactions are exempt
-- below. If a blocked person's anon content vanished the instant you
-- blocked them, that would let the blocker infer authorship from a single
-- action — exactly the anon-identity leak
-- 20260829020000_fix_anon_identity_leak_rls.sql was written to close. Named
-- content is filtered; anon content is not. Revisit if stricter hiding is
-- wanted despite that leak.
--
-- No RESTRICTIVE policy is added to `users` itself — that would also hide
-- the blocked person's own row from the Blocked Users list, which needs to
-- read their name. Search-result filtering for blocked users is instead
-- done client-side (BlockService.blockedUserIds()).
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS posts_block_filter ON public.posts;
CREATE POLICY posts_block_filter ON public.posts
  AS RESTRICTIVE FOR SELECT
  USING (
    visibility = 'anonymous'
    OR NOT public.is_blocked_user(auth.uid(), user_id)
  );

DROP POLICY IF EXISTS group_posts_block_filter ON public.group_posts;
CREATE POLICY group_posts_block_filter ON public.group_posts
  AS RESTRICTIVE FOR SELECT
  USING (NOT public.is_blocked_user(auth.uid(), user_id));

DROP POLICY IF EXISTS comments_block_filter ON public.comments;
CREATE POLICY comments_block_filter ON public.comments
  AS RESTRICTIVE FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = comments.post_id AND p.visibility = 'anonymous'
    )
    OR NOT public.is_blocked_user(auth.uid(), comments.user_id)
  );

DROP POLICY IF EXISTS reactions_block_filter ON public.reactions;
CREATE POLICY reactions_block_filter ON public.reactions
  AS RESTRICTIVE FOR SELECT
  USING (NOT public.is_blocked_user(auth.uid(), reactions.user_id));

DROP POLICY IF EXISTS post_realmoji_reactions_block_filter ON public.post_realmoji_reactions;
CREATE POLICY post_realmoji_reactions_block_filter ON public.post_realmoji_reactions
  AS RESTRICTIVE FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_realmoji_reactions.post_id AND p.visibility = 'anonymous'
    )
    OR NOT public.is_blocked_user(auth.uid(), post_realmoji_reactions.user_id)
  );

-- ----------------------------------------------------------------------------
-- 4. users.deleted_at — soft-delete for account deletion (Item 4), matching
--    the deleted_at convention already used on posts/comments/groups/etc.
-- ----------------------------------------------------------------------------

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS users_deleted_idx ON public.users (deleted_at);

DROP POLICY IF EXISTS users_not_deleted ON public.users;
CREATE POLICY users_not_deleted ON public.users
  AS RESTRICTIVE FOR SELECT
  USING (deleted_at IS NULL OR auth.uid() = auth_id);
