-- ---------------------------------------------------------------------------
-- Fix: soft-deleting a post/community/announcement is silently refused.
--
-- Reported: "removing posts via the admin dashboard does NOT actually
-- remove them — they're still visible after deletion."
--
-- ROOT CAUSE (proved live, via BEGIN/ROLLBACK probes against real rows,
-- documented in full in the session that produced this migration):
--
-- PostgreSQL RLS applies a table's SELECT policies to the rows an UPDATE's
-- WHERE clause is allowed to even SEE, in addition to that UPDATE's own
-- USING/CHECK. Every soft-deletable table here gates its SELECT policy on
-- `deleted_at IS NULL` (obviously — that's the whole point of a soft
-- delete), which produces two different failures depending on whether the
-- row was visible to the caller BEFORE the edit:
--
--   1. Row visible pre-edit (e.g. a post's own author, viewing their own
--      row): the UPDATE's WHERE-scan finds it, but the POST-image (with
--      deleted_at now set) no longer satisfies the same SELECT-derived
--      visibility check, which Postgres also applies as an implicit
--      WITH CHECK when a command policy doesn't declare its own. Result:
--      an explicit 42501 error. Verified for `posts` (owner and the dean,
--      both real accounts) and `community_posts` (the post's own author).
--
--   2. Row NOT visible pre-edit (e.g. a global moderator who isn't a member
--      of the community the post lives in — `community_posts_select`
--      requires `is_community_member`): the WHERE-scan never finds the row
--      at all. No error. UPDATE reports success having touched zero rows.
--      This is the exact "still visible after deletion" symptom, on the
--      dean's dashboard account specifically. Verified for `community_posts`
--      and `communities`.
--
-- FIX: one additive PERMISSIVE SELECT policy per table, granting visibility
-- to a row regardless of `deleted_at` to (a) that row's own owner and
-- (b) anyone `can_moderate_community()` (or `is_admin_or_global_mod()` for
-- communities, which have no per-community moderator concept) authorises.
-- Permissive policies OR together, so this can only ADD visibility on top
-- of what posts_select/community_posts_select/etc. already grant — it
-- cannot narrow anything.
--
-- This is safe for every existing read path: every own-posts/own-content
-- query in both the app and the dashboard already filters
-- `.isFilter('deleted_at', null)` / `.is('deleted_at', null)` client-side
-- (grepped and confirmed across feed_service.dart, community_feed_service.
-- dart, institutional.js), so a soft-deleted row becoming SELECT-visible at
-- the RLS layer does not leak it back into any feed or list.
-- ---------------------------------------------------------------------------

-- ═══ posts ══════════════════════════════════════════════════════════════
create policy "posts_select_own_or_moderator_always" on public.posts
  for select using (
    auth.uid() in (select auth_id from public.users where id = posts.user_id)
    or public.can_moderate_community(community_id)
  );

-- ═══ community_posts ═══════════════════════════════════════════════════
create policy "community_posts_select_own_or_moderator_always" on public.community_posts
  for select using (
    auth.uid() in (select auth_id from public.users where id = community_posts.user_id)
    or public.can_moderate_community(community_id)
  );

-- ═══ communities ════════════════════════════════════════════════════════
-- No per-community moderator concept for this table (communities_update_
-- moderator itself gates on is_admin_or_global_mod(), not
-- can_moderate_community) and no per-user owner column — only a global
-- admin/global_moderator manages communities at all.
create policy "communities_select_moderator_always" on public.communities
  for select using ( public.is_admin_or_global_mod() );

-- ═══ community_feed_items ═══════════════════════════════════════════════
-- Dashboard-authored content only (announcements/priority posts) — no
-- per-user owner concept, moderation-only.
create policy "community_feed_items_select_moderator_always" on public.community_feed_items
  for select using ( public.can_moderate_community(community_id) );

-- ═══ comments ═══════════════════════════════════════════════════════════
-- The app has no self-delete-a-comment path today (grepped, confirmed) and
-- the dashboard's comment removal already goes through the resolve_report
-- SECURITY DEFINER RPC, which bypasses RLS entirely as `postgres` and was
-- never actually affected by this bug. Added anyway for consistency and to
-- close the gap before a self-delete feature is ever added — same shape,
-- same fix, comments.post_id can be null for a group-post comment so the
-- community lookup goes through both possible parents.
create policy "comments_select_own_or_moderator_always" on public.comments
  for select using (
    auth.uid() in (select auth_id from public.users where id = comments.user_id)
    or public.can_moderate_community(
      (select p.community_id from public.posts p where p.id = comments.post_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Fix: remove_group_post() raises "not signed in" for a dashboard-only
-- moderator account.
--
-- A dashboard moderator (Principal/Dean/community moderator) authenticates
-- via Supabase auth but has NO `users` row — that table is the app's own
-- account, keyed by `auth_id`, and dashboard accounts were never onboarded
-- into it (confirmed: `moderators` and `users` are two separate identity
-- tables, joined only by email, never by auth uid). The old body did
-- `SELECT u.id INTO v_me FROM users u WHERE u.auth_id = auth.uid()` and
-- RAISE EXCEPTION'd on NULL before ever checking moderator status — so a
-- dashboard moderator could never reach the moderation branch at all,
-- regardless of role.
--
-- Fixed by checking moderator status FIRST, independent of having a
-- `users` row: `is_admin_or_global_mod()`/`can_moderate_community()` key
-- off `current_moderator_role()`, which reads `moderators` by
-- `auth.email()` and needs no `users` row. Ownership (a real app user
-- removing their own group post) is still checked as before when a
-- `users` row does exist.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.remove_group_post(p_post_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me       uuid;  -- users.id, if the caller has an app account. May be NULL.
  v_author   uuid;
  v_group    uuid;
  v_allowed  boolean := false;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();

  SELECT gp.user_id, gp.group_id INTO v_author, v_group
    FROM public.group_posts gp
   WHERE gp.id = p_post_id AND gp.deleted_at IS NULL;

  IF v_author IS NULL THEN
    RETURN false;   -- already gone, or never existed
  END IF;

  v_allowed :=
    -- A dashboard moderator, checked first — needs no `users` row at all.
    COALESCE(public.can_moderate_community(NULL), false)
    -- A real app user removing their own post, or a group admin.
    OR (v_me IS NOT NULL AND (
      v_author = v_me
      OR EXISTS (
        SELECT 1 FROM public.group_members gm
         WHERE gm.group_id = v_group AND gm.user_id = v_me AND gm.role = 'admin'
      )
    ));

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'not allowed to remove this post';
  END IF;

  UPDATE public.group_posts SET deleted_at = now() WHERE id = p_post_id;
  RETURN true;
END;
$function$;
