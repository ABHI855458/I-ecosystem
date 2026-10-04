-- Fixes a real, live bug: inserting into group_members (creating a new
-- group's first admin row, or adding a member) can hit
-- "42P17: infinite recursion detected in policy for relation group_members".
--
-- Root cause: last night's 20260904180000_group_visibility_for_friends.sql
-- added `groups_select_friend_member` as a RAW subquery on group_members
-- (`EXISTS (SELECT 1 FROM group_members gm WHERE ... AND is_friend_of(...))`)
-- instead of wrapping it in a SECURITY DEFINER function the way its own
-- sibling `group_members_select_friend` correctly does. The cycle:
--   INSERT group_members -> WITH CHECK admin_add_members (subqueries `groups`)
--   -> evaluating groups' own SELECT RLS -> groups_select_friend_member's
--   raw subquery on group_members -> group_members RLS evaluated again
--   -> recursion.
-- Exact same bug class as the us_albums/us_album_photos recursion fixed
-- earlier this session (20260904171000) — same fix shape: a SECURITY
-- DEFINER helper breaks the cycle since its internal query bypasses RLS
-- entirely rather than re-triggering it.
create or replace function public.group_has_friend_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and public.is_friend_of(gm.user_id)
  );
$$;

drop policy if exists groups_select_friend_member on public.groups;
create policy groups_select_friend_member on public.groups
  for select
  using (public.group_has_friend_member(id));
