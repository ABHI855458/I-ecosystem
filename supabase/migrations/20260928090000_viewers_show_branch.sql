-- Seen dropdown: unpinned viewers read "someone in CS" / "someone in EC",
-- or "someone from outside" when there is no RVCE branch.
--
-- post_viewers / group_post_viewers already mask everyone the caller hasn't
-- pinned (no id, name or photo — just an opaque viewer_key), so the list
-- showed a row of identical "someone"s. Explicit request: show which branch
-- they're from instead. Only the BRANCH is added for an unpinned viewer —
-- derived from their college email by derive_branch() ("x.cs25@rvce.edu.in"
-- -> "cs"), never the email itself, their name or any id. A non-RVCE email
-- has no branch and comes back null ("someone from outside"). Pinned viewers
-- are unchanged (named, as before). Return type changes, so drop + create.

drop function if exists public.post_viewers(uuid, integer);
create function public.post_viewers(p_post_id uuid, p_window_hours integer default null)
returns table(user_id uuid, viewer_key text, username text, name text,
              avatar_url text, is_pinned boolean, viewed_at timestamptz,
              branch text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select id from public.users where auth_id = auth.uid()),
  v as (
    select pv.viewer_id, pv.created_at,
           exists (select 1 from public.pinned_people pp
                    where pp.user_id = (select id from me) and pp.pinned_user_id = pv.viewer_id) as pinned
      from public.post_views pv
     where pv.post_id = p_post_id
       and (select id from me) is not null
       and public.post_engagement_visible(p_post_id)
  )
  select
    case when v.pinned then u.id end,
    case when v.pinned then null else public.viewer_key((select id from me), u.id) end,
    case when v.pinned then u.username end,
    case when v.pinned then u.name end,
    case when v.pinned then u.profile_photo_url end,
    v.pinned,
    v.created_at,
    case when v.pinned then null
         else upper((select db.branch from public.derive_branch(a.email) db)) end
  from v
  join public.users u on u.id = v.viewer_id
  left join auth.users a on a.id = u.auth_id
  where p_window_hours is null
     or v.created_at >= now() - make_interval(hours => p_window_hours)
     or v.pinned
  order by 6 desc, 7 desc;
$function$;
revoke execute on function public.post_viewers(uuid, integer) from public, anon;
grant execute on function public.post_viewers(uuid, integer) to authenticated, service_role;

drop function if exists public.group_post_viewers(uuid);
create function public.group_post_viewers(p_group_post_id uuid)
returns table(user_id uuid, viewer_key text, username text, name text,
              avatar_url text, is_pinned boolean, viewed_at timestamptz,
              branch text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select id from public.users where auth_id = auth.uid()),
  v as (
    select gpv.viewer_id, gpv.created_at,
           exists (select 1 from public.pinned_people pp
                    where pp.user_id = (select id from me) and pp.pinned_user_id = gpv.viewer_id) as pinned
      from public.group_post_views gpv
      join public.group_posts gp on gp.id = gpv.group_post_id
     where gpv.group_post_id = p_group_post_id
       and public.is_group_member(gp.group_id, (select id from me))
  )
  select
    case when v.pinned then u.id end,
    case when v.pinned then null else public.viewer_key((select id from me), u.id) end,
    case when v.pinned then u.username end,
    case when v.pinned then u.name end,
    case when v.pinned then u.profile_photo_url end,
    v.pinned,
    v.created_at,
    case when v.pinned then null
         else upper((select db.branch from public.derive_branch(a.email) db)) end
  from v
  join public.users u on u.id = v.viewer_id
  left join auth.users a on a.id = u.auth_id
  order by 6 desc, 7 desc;
$function$;
revoke execute on function public.group_post_viewers(uuid) from public, anon;
grant execute on function public.group_post_viewers(uuid) to authenticated, service_role;
