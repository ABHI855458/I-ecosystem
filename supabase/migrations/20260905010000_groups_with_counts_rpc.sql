-- Explicit report — "why does the profile page load so much": MyProfileScreen
-- and TheirProfileScreen's own groups sections each did fetchMyGroups() (1
-- request) then, PER GROUP, fetchMembers() + fetchPosts() just to read
-- `.length` off the results — a real N+1 (2N+1 requests for N groups) that
-- fires on every single profile open. One aggregate RPC replaces the whole
-- fan-out with a single request.
create or replace function public.groups_with_counts_for_user(p_user_id uuid)
returns table(
  id uuid,
  name text,
  icon_url text,
  banner_url text,
  created_at timestamptz,
  member_count bigint,
  post_count bigint
)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid;
begin
  v_me := public.current_user_id();
  if v_me is null then
    return;
  end if;

  -- Same authorization group_members_select_friend/groups_select_friend_member
  -- already grant: your own groups always, anyone else's only if you're a
  -- friend of theirs (migration 20260904180000_group_visibility_for_friends).
  -- Re-checked here explicitly since SECURITY DEFINER bypasses RLS.
  if p_user_id <> v_me and not public.is_friend_of(p_user_id) then
    return;
  end if;

  return query
  select
    g.id,
    g.name,
    g.icon_url,
    g.banner_url,
    g.created_at,
    (select count(*) from public.group_members gm2 where gm2.group_id = g.id) as member_count,
    (select count(*) from public.group_posts gp2 where gp2.group_id = g.id) as post_count
  from public.groups g
  join public.group_members gm on gm.group_id = g.id
  where gm.user_id = p_user_id
  order by g.created_at desc;
end;
$function$;

grant execute on function public.groups_with_counts_for_user(uuid) to authenticated;
