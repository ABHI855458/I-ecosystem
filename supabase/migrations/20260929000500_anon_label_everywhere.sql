-- "someone" → the viewer's anon persona + branch, everywhere a viewer is
-- masked (by product request): Dip AND Friends seen pills, group post
-- viewers, "who viewed your profile / posts", and the profile-view /
-- group-profile-view notifications. e.g. "darth_vader · CS".
--
-- Pinned viewers are unchanged (real name, only to the person who pinned
-- them). Real id / name / photo are still never returned for anyone else.
-- The branch half follows the viewer's show_branch_signal opt-out; a
-- viewer with no anon name falls back to the previous branch-only wording.
--
-- Builds on 20260928090000 (branch column), 20260928120000 (post_viewers
-- anon_label) and 20260927290000 (masking). Return types change for
-- group_post_viewers / my_*_viewers → drop + create.

create or replace function public.viewer_anon_label(p_viewer uuid)
returns text
language sql stable security definer
set search_path = public, pg_temp
as $$
  select case when nullif(btrim(u.anon_name), '') is null then null
         else btrim(u.anon_name)
              || coalesce(' · ' || case when coalesce(pr.show_branch_signal, true)
                   then upper(nullif(btrim(coalesce(
                          (select db.branch from public.derive_branch(a.email) db),
                          pr.branch)), '')) end, '')
         end
    from public.users u
    left join public.profiles pr on pr.id = u.auth_id
    left join auth.users a on a.id = u.auth_id
   where u.id = p_viewer;
$$;
revoke all on function public.viewer_anon_label(uuid) from public, anon, authenticated;

-- Notifications: "darth_vader · CS viewed your profile 👀".
create or replace function public.viewer_branch_phrase(p_viewer uuid)
returns text
language sql stable security definer
set search_path = public, pg_temp
as $function$
  select coalesce(
    public.viewer_anon_label(p_viewer),
    (select 'Someone in ' || upper(btrim(p.branch))
       from public.users u join public.profiles p on p.id = u.auth_id
      where u.id = p_viewer
        and nullif(btrim(p.branch), '') is not null
        and p.show_branch_signal is true
        and (select count(*) from public.branch_student_counts() b
              where b.branch = p.branch and b.student_count >=
                    coalesce((select (value #>> '{}')::int from public.app_config
                               where key = 'visitor_branch_min_students'), 1)) > 0),
    'Someone');
$function$;

-- ── post_viewers: anon label for every unpinned viewer, any post ─────────
drop function if exists public.post_viewers(uuid, integer);
create function public.post_viewers(p_post_id uuid, p_window_hours integer default null)
returns table(user_id uuid, viewer_key text, username text, name text,
              avatar_url text, is_pinned boolean, viewed_at timestamptz,
              branch text, anon_label text, anon_avatar_url text)
language sql stable security definer
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
         else upper((select db.branch from public.derive_branch(a.email) db)) end,
    case when v.pinned then null else public.viewer_anon_label(u.id) end,
    case when v.pinned then null else u.anon_photo_url end
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

-- ── group_post_viewers ───────────────────────────────────────────────────
drop function if exists public.group_post_viewers(uuid);
create function public.group_post_viewers(p_group_post_id uuid)
returns table(user_id uuid, viewer_key text, username text, name text,
              avatar_url text, is_pinned boolean, viewed_at timestamptz,
              branch text, anon_label text, anon_avatar_url text)
language sql stable security definer
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
         else upper((select db.branch from public.derive_branch(a.email) db)) end,
    case when v.pinned then null else public.viewer_anon_label(u.id) end,
    case when v.pinned then null else u.anon_photo_url end
  from v
  join public.users u on u.id = v.viewer_id
  left join auth.users a on a.id = u.auth_id
  order by 6 desc, 7 desc;
$function$;
revoke execute on function public.group_post_viewers(uuid) from public, anon;
grant execute on function public.group_post_viewers(uuid) to authenticated, service_role;

-- ── my_profile_viewers ───────────────────────────────────────────────────
drop function if exists public.my_profile_viewers(integer);
create function public.my_profile_viewers(p_limit integer default 50)
returns table(user_id uuid, viewer_key text, username text, name text, avatar_url text,
              is_pinned boolean, viewed_at timestamptz, branch text,
              anon_label text, anon_avatar_url text)
language sql stable security definer
set search_path = public, pg_temp
as $$
  with me as (select id from public.users where auth_id = auth.uid()),
  latest as (
    select distinct on (pv.viewer_id) pv.viewer_id, pv.created_at
      from public.profile_views pv
     where pv.viewed_user_id = (select id from me)
     order by pv.viewer_id, pv.created_at desc
  )
  select
    case when pp.pinned_user_id is not null then u.id end,
    case when pp.pinned_user_id is not null then null else public.viewer_key((select id from me), u.id) end,
    case when pp.pinned_user_id is not null then u.username end,
    case when pp.pinned_user_id is not null then u.name end,
    case when pp.pinned_user_id is not null then u.profile_photo_url end,
    (pp.pinned_user_id is not null),
    l.created_at,
    prof.branch,
    case when pp.pinned_user_id is not null then null else public.viewer_anon_label(u.id) end,
    case when pp.pinned_user_id is not null then null else u.anon_photo_url end
  from latest l
  join public.users u on u.id = l.viewer_id
  left join public.pinned_people pp
    on pp.user_id = (select id from me) and pp.pinned_user_id = l.viewer_id
  left join public.profiles prof on prof.id = u.auth_id
  order by 6 desc, 7 desc
  limit p_limit;
$$;

-- ── my_post_viewers ──────────────────────────────────────────────────────
drop function if exists public.my_post_viewers(integer);
create function public.my_post_viewers(p_limit integer default 60)
returns table(user_id uuid, viewer_key text, username text, name text, avatar_url text,
              is_pinned boolean, post_id uuid, viewed_at timestamptz, branch text,
              anon_label text, anon_avatar_url text)
language sql stable security definer
set search_path = public, pg_temp
as $$
  with me as (select id from public.users where auth_id = auth.uid()),
  latest as (
    select distinct on (pv.viewer_id) pv.viewer_id, pv.post_id, pv.created_at
      from public.post_views pv
      join public.posts p
        on p.id = pv.post_id and p.user_id = (select id from me) and p.deleted_at is null
     order by pv.viewer_id, pv.created_at desc
  )
  select
    case when pp.pinned_user_id is not null then u.id end,
    case when pp.pinned_user_id is not null then null else public.viewer_key((select id from me), u.id) end,
    case when pp.pinned_user_id is not null then u.username end,
    case when pp.pinned_user_id is not null then u.name end,
    case when pp.pinned_user_id is not null then u.profile_photo_url end,
    (pp.pinned_user_id is not null),
    l.post_id,
    l.created_at,
    prof.branch,
    case when pp.pinned_user_id is not null then null else public.viewer_anon_label(u.id) end,
    case when pp.pinned_user_id is not null then null else u.anon_photo_url end
  from latest l
  join public.users u on u.id = l.viewer_id
  left join public.pinned_people pp
    on pp.user_id = (select id from me) and pp.pinned_user_id = l.viewer_id
  left join public.profiles prof on prof.id = u.auth_id
  order by 6 desc, 8 desc
  limit p_limit;
$$;

revoke all on function public.my_profile_viewers(integer) from public, anon;
revoke all on function public.my_post_viewers(integer) from public, anon;
grant execute on function public.my_profile_viewers(integer) to authenticated;
grant execute on function public.my_post_viewers(integer) to authenticated;
