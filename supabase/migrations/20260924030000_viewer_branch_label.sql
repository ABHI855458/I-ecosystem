-- VIEWED BY — non-pinned viewers get a branch label instead of "someone".
--
-- Explicit request: apart from pinned people (who already get shown by real
-- name), nobody else's identity should be revealed — but instead of the flat
-- generic "someone", show which branch they're in: "someone in CS",
-- "someone in EC", "someone in CV", etc. profiles.branch already carries
-- this (parsed at signup from the rvce.edu.in email's own '.cs25'/'.cv25'/
-- '.ec25' local-part convention — confirmed on live data: 'cs', 'cv' present
-- for real accounts, null for gmail/admin ones with no branch to show).
--
-- profiles.id is the AUTH id, so the join is through users.auth_id, not
-- users.id — same join shape community_screen.dart's own profile lookup
-- already uses.
--
-- branch is returned UNCONDITIONALLY (never masked) — it's the same
-- academic-branch fact already shown in public profile headers elsewhere in
-- the app, not a new exposure. Only name/username/avatar_url stay pinned-
-- gated, exactly as before; the client picks the display string (real name
-- if pinned, "someone in {BRANCH}" if not and a branch exists, else the
-- untouched "someone" fallback).
--
-- Both DROP first: this adds a column to each RETURNS TABLE, and a bare
-- CREATE OR REPLACE fails with "cannot change return type of existing
-- function" (same shape of change hit for real on score_leaderboard and
-- ping_inbox earlier).
DROP FUNCTION IF EXISTS public.my_post_viewers(integer);
DROP FUNCTION IF EXISTS public.my_profile_viewers(integer);

CREATE OR REPLACE FUNCTION public.my_post_viewers(p_limit integer DEFAULT 60)
RETURNS TABLE(user_id uuid, username text, name text, avatar_url text, is_pinned boolean, post_id uuid, viewed_at timestamp with time zone, branch text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (
    select id from public.users where auth_id = auth.uid()
  ),
  latest as (
    select distinct on (pv.viewer_id)
      pv.viewer_id,
      pv.post_id,
      pv.created_at
    from public.post_views pv
    join public.posts p
      on p.id = pv.post_id
     and p.user_id = (select id from me)
     and p.deleted_at is null
    order by pv.viewer_id, pv.created_at desc
  )
  select
    u.id,
    case when pp.pinned_user_id is not null then u.username else null end,
    case when pp.pinned_user_id is not null then u.name else null end,
    case when pp.pinned_user_id is not null then u.profile_photo_url else null end,
    (pp.pinned_user_id is not null) as is_pinned,
    l.post_id,
    l.created_at,
    prof.branch
  from latest l
  join public.users u on u.id = l.viewer_id
  left join public.pinned_people pp
    on pp.user_id = (select id from me)
   and pp.pinned_user_id = l.viewer_id
  left join public.profiles prof on prof.id = u.auth_id
  order by 5 desc, l.created_at desc
  limit p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.my_profile_viewers(p_limit integer DEFAULT 50)
RETURNS TABLE(user_id uuid, username text, name text, avatar_url text, is_pinned boolean, viewed_at timestamp with time zone, branch text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (
    select id from public.users where auth_id = auth.uid()
  ),
  latest as (
    select distinct on (pv.viewer_id)
      pv.viewer_id,
      pv.created_at
    from public.profile_views pv
    where pv.viewed_user_id = (select id from me)
    order by pv.viewer_id, pv.created_at desc
  )
  select
    u.id,
    case when pp.pinned_user_id is not null then u.username else null end,
    case when pp.pinned_user_id is not null then u.name else null end,
    case when pp.pinned_user_id is not null then u.profile_photo_url else null end,
    (pp.pinned_user_id is not null) as is_pinned,
    l.created_at,
    prof.branch
  from latest l
  join public.users u on u.id = l.viewer_id
  left join public.pinned_people pp
    on pp.user_id = (select id from me)
   and pp.pinned_user_id = l.viewer_id
  left join public.profiles prof on prof.id = u.auth_id
  order by 5 desc, l.created_at desc
  limit p_limit;
$function$;
