-- score_leaderboard() — add anon_photo_url so the global podium (top 3) can
-- show a real avatar instead of just an initial. Same field the (community-
-- scoped) community_leaderboard() podium already exposes — the anon
-- persona's photo, never profile_photo_url/real identity, so this doesn't
-- change what's de-anonymizable versus what was already public elsewhere in
-- the app (anon feed posts already show this same photo to every user).
-- DROP first, not a bare CREATE OR REPLACE: this ADDS a column to the
-- RETURNS TABLE, and Postgres refuses that with "cannot change return type
-- of existing function". Hit for real when applying this live; without the
-- DROP a fresh rebuild/replay of the migration chain fails here.
DROP FUNCTION IF EXISTS public.score_leaderboard(integer);

CREATE OR REPLACE FUNCTION public.score_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE(rank integer, anon_name text, total_score integer, level integer, is_me boolean, anon_photo_url text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  with me_id as (select id from public.users where auth_id = auth.uid()),
  ranked as (
    select
      (row_number() over (order by u.total_score desc, u.id))::int as rnk,
      coalesce(nullif(trim(u.anon_name), ''), 'anonymous') as anon_name,
      u.total_score,
      u.level,
      (u.id = (select id from me_id)) as is_me,
      u.anon_photo_url
    from public.users u
    where u.deleted_at is null
      and u.auth_id is not null
      and u.total_score > 0
  ),
  top as (
    select rnk, anon_name, total_score, level, is_me, anon_photo_url
    from ranked
    order by rnk
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ),
  mine as (
    select rnk, anon_name, total_score, level, is_me, anon_photo_url
    from ranked
    where is_me and rnk > (select coalesce(max(rnk), 0) from top)
  )
  select rnk, anon_name, total_score, level, is_me, anon_photo_url from top
  union all
  select rnk, anon_name, total_score, level, is_me, anon_photo_url from mine
  order by 1;
$function$;
