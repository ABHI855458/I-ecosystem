-- "Visited someone's profile, see the groups they've joined, visible to
-- friends" (explicit spec). Live RLS on group_members only let the VIEWER
-- see a row if they themselves are a member of that group
-- (group_members_select: is_group_member(group_id, viewer)) — a friend who
-- isn't in the same group could not see which groups their friend belongs
-- to at all, and `groups` had the matching restriction on the group
-- metadata itself. Additive: both existing policies are untouched, these
-- are extra PERMISSIVE policies that OR in friend-based visibility without
-- narrowing anything already working.

create or replace function public.is_friend_of(target_user_id uuid)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from users viewer
    join friendships f on f.status = 'accepted'
      and ((f.requester_id = viewer.id and f.addressee_id = target_user_id)
        or (f.addressee_id = viewer.id and f.requester_id = target_user_id))
    where viewer.auth_id = auth.uid()
  );
$$;

create policy group_members_select_friend on group_members
  for select
  using (is_friend_of(user_id));

-- A friend can see a group's own metadata (name/icon/banner) once they can
-- already see at least one membership row proving a friend of theirs
-- belongs to it — same "friend of a member" reach as the policy above,
-- expressed against `groups` directly since that table has no user_id of
-- its own to check is_friend_of against.
create policy groups_select_friend_member on groups
  for select
  using (
    exists (
      select 1 from group_members gm
      where gm.group_id = groups.id and is_friend_of(gm.user_id)
    )
  );
