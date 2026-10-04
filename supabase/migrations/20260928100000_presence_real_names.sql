-- "Here" (presence) pill: real names for everyone.
--
-- Explicit request: "let the presence pill show real names only". It used
-- to mask everyone the caller hadn't pinned (no id/name/photo, just an
-- opaque viewer_key), which made the live list a column of "someone"s.
-- Now every row carries the real id, name and photo; is_pinned still sorts
-- pinned people first.
--
-- The list also now includes people who OPENED the post within the same
-- window (p_since, 3h by default) — previously the client merged those in
-- from post_viewers/group_post_viewers, which stay masked (they back the
-- SEEN pill, which shows "someone in CS" — 20260928090000). Doing the merge
-- here gives those rows real names too and removes the client-side
-- key-matching that would otherwise list one person twice.
--
-- Visibility gate unchanged: same post / group-post checks as before.

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
