-- Dip seen pill: on an ANONYMOUS post, an unpinned viewer reads as their anon
-- persona + branch ("darth_vader · CS") instead of "someone in CS".
-- Builds on 20260928090000 (branch column, derived from college email) —
-- `branch` is kept for every other post; `anon_label` / `anon_avatar_url` are
-- only filled for unpinned viewers of an anonymous post. Real identity is
-- still only returned to someone who pinned the viewer. The anon persona is
-- already public on that person's own Dips.
--
-- Also re-applies 20260928100000's post_presence_people verbatim (real names
-- in the "here" pill), which an intermediate migration had overwritten.

drop function if exists public.post_viewers(uuid, integer);
create function public.post_viewers(p_post_id uuid, p_window_hours integer default null)
returns table(user_id uuid, viewer_key text, username text, name text,
              avatar_url text, is_pinned boolean, viewed_at timestamptz,
              branch text, anon_label text, anon_avatar_url text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select id from public.users where auth_id = auth.uid()),
  post as (select (visibility = 'anonymous') as is_anon from public.posts where id = p_post_id),
  v as (
    select pv.viewer_id, pv.created_at,
           exists (select 1 from public.pinned_people pp
                    where pp.user_id = (select id from me) and pp.pinned_user_id = pv.viewer_id) as pinned
      from public.post_views pv
     where pv.post_id = p_post_id
       and (select id from me) is not null
       and public.post_engagement_visible(p_post_id)
  ),
  rows as (
    select v.*, u.id as uid, u.username, u.name, u.profile_photo_url,
           u.anon_name, u.anon_photo_url,
           upper((select db.branch from public.derive_branch(a.email) db)) as br
      from v
      join public.users u on u.id = v.viewer_id
      left join auth.users a on a.id = u.auth_id
  )
  select
    case when r.pinned then r.uid end,
    case when r.pinned then null else public.viewer_key((select id from me), r.uid) end,
    case when r.pinned then r.username end,
    case when r.pinned then r.name end,
    case when r.pinned then r.profile_photo_url end,
    r.pinned,
    r.created_at,
    case when r.pinned then null else r.br end,
    case when not r.pinned and coalesce((select is_anon from post), false)
              and nullif(btrim(r.anon_name), '') is not null
         then btrim(r.anon_name) || coalesce(' · ' || r.br, '') end,
    case when not r.pinned and coalesce((select is_anon from post), false)
         then r.anon_photo_url end
  from rows r
  where p_window_hours is null
     or r.created_at >= now() - make_interval(hours => p_window_hours)
     or r.pinned
  order by 6 desc, 7 desc;
$function$;
revoke execute on function public.post_viewers(uuid, integer) from public, anon;
grant execute on function public.post_viewers(uuid, integer) to authenticated, service_role;

drop function if exists public.post_presence_people(uuid, uuid, timestamptz);
create or replace function public.post_presence_people(
  p_post_id uuid default null,
  p_group_post_id uuid default null,
  p_since timestamptz default (now() - interval '3 hours')
)
returns table(user_id uuid, viewer_key text, name text, avatar_url text,
              is_pinned boolean, last_seen_at timestamptz)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select id from public.users where auth_id = auth.uid()),
  allowed as (
    select (
      (p_post_id is not null and exists (
         select 1 from public.posts p
          where p.id = p_post_id and p.deleted_at is null
            and (p.visibility is distinct from 'anonymous' or p.user_id = (select id from me))
            and public.post_engagement_visible(p_post_id)))
      or
      (p_group_post_id is not null and exists (
         select 1 from public.group_posts gp
          where gp.id = p_group_post_id
            and public.is_group_member(gp.group_id, (select id from me))))
    ) and (select id from me) is not null as ok
  ),
  live as (
    select ps.user_id as uid, ps.last_seen_at as at
      from public.post_presence ps
     where (select ok from allowed)
       and ps.user_id <> (select id from me)
       and ((p_post_id is not null and ps.post_id = p_post_id)
         or (p_group_post_id is not null and ps.group_post_id = p_group_post_id))
  ),
  opened as (
    select pv.viewer_id as uid, pv.created_at as at
      from public.post_views pv
     where p_post_id is not null and pv.post_id = p_post_id
       and (select ok from allowed) and pv.viewer_id <> (select id from me)
    union all
    select gv.viewer_id, gv.created_at
      from public.group_post_views gv
     where p_group_post_id is not null and gv.group_post_id = p_group_post_id
       and (select ok from allowed) and gv.viewer_id <> (select id from me)
  ),
  pinned_ids as (
    select pp.pinned_user_id as uid from public.pinned_people pp
     where pp.user_id = (select id from me)
  ),
  merged as (
    -- one row per person: their latest live heartbeat, else their latest
    -- open within the window; pinned people keep a live row at any age.
    select uid, max(at) as at from (
      select uid, at from live
       where at >= p_since or uid in (select uid from pinned_ids)
      union all
      select uid, at from opened where at >= p_since
    ) x
    group by uid
  )
  select u.id,
         public.viewer_key((select id from me), u.id),
         coalesce(nullif(u.username, ''), u.name),
         u.profile_photo_url,
         (m.uid in (select uid from pinned_ids)),
         m.at
    from merged m
    join public.users u on u.id = m.uid
   where not public.is_blocked_user(auth.uid(), u.id)
   order by 5 desc, 6 desc;
$function$;

revoke all on function public.post_presence_people(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.post_presence_people(uuid, uuid, timestamptz) to authenticated;
