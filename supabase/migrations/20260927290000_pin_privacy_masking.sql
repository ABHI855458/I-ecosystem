-- Pin privacy: a viewer's identity is only ever revealed to someone who has
-- pinned that viewer. Everyone else gets NULL id/name/photo plus an opaque
-- per-caller viewer_key (for de-duping), so:
--   * nobody can learn who someone else has pinned,
--   * unpinning takes effect on the next read (pins are evaluated at read
--     time, and an unpinned viewer's old views come back as "someone"),
--   * a masked row can't be tapped through to a real profile.
--
-- Before this: post_viewers / group_post_viewers returned every viewer's
-- real id+name+photo, my_*_viewers leaked the real id, profile_views and
-- post_presence were directly readable, and all were anon-executable.

-- Server-only salt so viewer_key can't be reversed by hashing known ids.
insert into public.private_settings(key, value)
values ('viewer_key_salt', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (key) do nothing;

create or replace function public.viewer_key(p_caller uuid, p_viewer uuid)
returns text
language sql stable security definer
set search_path = public, pg_temp
as $$
  select md5((select value from public.private_settings where key = 'viewer_key_salt')
             || ':' || p_caller::text || ':' || p_viewer::text);
$$;
revoke all on function public.viewer_key(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- post_viewers
drop function if exists public.post_viewers(uuid, integer);
create function public.post_viewers(p_post_id uuid, p_window_hours integer default null)
returns table(user_id uuid, viewer_key text, username text, name text, avatar_url text,
              is_pinned boolean, viewed_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp
as $$
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
    v.created_at
  from v join public.users u on u.id = v.viewer_id
  where p_window_hours is null
     or v.created_at >= now() - make_interval(hours => p_window_hours)
     or v.pinned
  order by 6 desc, 7 desc;
$$;

-- ---------------------------------------------------------- group_post_viewers
drop function if exists public.group_post_viewers(uuid);
create function public.group_post_viewers(p_group_post_id uuid)
returns table(user_id uuid, viewer_key text, username text, name text, avatar_url text,
              is_pinned boolean, viewed_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp
as $$
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
    v.created_at
  from v join public.users u on u.id = v.viewer_id
  order by 6 desc, 7 desc;
$$;

-- ---------------------------------------------------------- my_profile_viewers
drop function if exists public.my_profile_viewers(integer);
create function public.my_profile_viewers(p_limit integer default 50)
returns table(user_id uuid, viewer_key text, username text, name text, avatar_url text,
              is_pinned boolean, viewed_at timestamptz, branch text)
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
    prof.branch
  from latest l
  join public.users u on u.id = l.viewer_id
  left join public.pinned_people pp
    on pp.user_id = (select id from me) and pp.pinned_user_id = l.viewer_id
  left join public.profiles prof on prof.id = u.auth_id
  order by 6 desc, 7 desc
  limit p_limit;
$$;

-- ------------------------------------------------------------- my_post_viewers
drop function if exists public.my_post_viewers(integer);
create function public.my_post_viewers(p_limit integer default 60)
returns table(user_id uuid, viewer_key text, username text, name text, avatar_url text,
              is_pinned boolean, post_id uuid, viewed_at timestamptz, branch text)
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
    prof.branch
  from latest l
  join public.users u on u.id = l.viewer_id
  left join public.pinned_people pp
    on pp.user_id = (select id from me) and pp.pinned_user_id = l.viewer_id
  left join public.profiles prof on prof.id = u.auth_id
  order by 6 desc, 8 desc
  limit p_limit;
$$;

-- -------------------------------------------------------- post_presence_people
-- Replaces the client's direct post_presence select. Same visibility gate
-- the old select policy had; excludes the caller; masks the unpinned.
create or replace function public.post_presence_people(
  p_post_id uuid default null,
  p_group_post_id uuid default null,
  p_since timestamptz default now() - interval '3 hours'
)
returns table(user_id uuid, viewer_key text, name text, avatar_url text,
              is_pinned boolean, last_seen_at timestamptz)
language sql stable security definer
set search_path = public, pg_temp
as $$
  with me as (select id from public.users where auth_id = auth.uid()),
  pr as (
    select ps.user_id as uid, ps.last_seen_at,
           exists (select 1 from public.pinned_people pp
                    where pp.user_id = (select id from me) and pp.pinned_user_id = ps.user_id) as pinned
      from public.post_presence ps
     where (select id from me) is not null
       and ps.user_id <> (select id from me)
       and (
         (p_post_id is not null and ps.post_id = p_post_id and exists (
            select 1 from public.posts p
             where p.id = p_post_id and p.deleted_at is null
               and (p.visibility is distinct from 'anonymous' or p.user_id = (select id from me))
               and public.post_engagement_visible(p_post_id)))
         or
         (p_group_post_id is not null and ps.group_post_id = p_group_post_id and exists (
            select 1 from public.group_posts gp
             where gp.id = p_group_post_id
               and public.is_group_member(gp.group_id, (select id from me))))
       )
  )
  select
    case when pr.pinned then u.id end,
    case when pr.pinned then null else public.viewer_key((select id from me), u.id) end,
    case when pr.pinned then coalesce(nullif(u.username, ''), u.name) end,
    case when pr.pinned then u.profile_photo_url end,
    pr.pinned,
    pr.last_seen_at
  from pr join public.users u on u.id = pr.uid
  where pr.last_seen_at >= p_since or pr.pinned
  order by 5 desc, 6 desc;
$$;

-- Direct table reads: own rows only. Everything else goes through the
-- masked RPCs above.
drop policy if exists post_presence_select on public.post_presence;
create policy post_presence_select on public.post_presence for select
  using (auth.uid() in (select users.auth_id from public.users where users.id = post_presence.user_id));

drop policy if exists profile_views_select on public.profile_views;
create policy profile_views_select on public.profile_views for select
  using (auth.uid() in (select users.auth_id from public.users where users.id = profile_views.viewer_id));

revoke all on function public.post_viewers(uuid, integer) from public, anon;
revoke all on function public.group_post_viewers(uuid) from public, anon;
revoke all on function public.my_profile_viewers(integer) from public, anon;
revoke all on function public.my_post_viewers(integer) from public, anon;
revoke all on function public.post_presence_people(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.post_viewers(uuid, integer) to authenticated;
grant execute on function public.group_post_viewers(uuid) to authenticated;
grant execute on function public.my_profile_viewers(integer) to authenticated;
grant execute on function public.my_post_viewers(integer) to authenticated;
grant execute on function public.post_presence_people(uuid, uuid, timestamptz) to authenticated;
