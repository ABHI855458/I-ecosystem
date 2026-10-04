-- score_leaderboard() — return a WINDOW of neighbours around the caller,
-- not just the caller's own lone row.
--
-- 20260922010000 guaranteed the caller always appears, but as a single
-- detached row: a user ranked #47 got rows 1..N plus a bare #47, with
-- nobody either side of them. The Streaks tab now renders "top 8, then a
-- jump straight to where you actually sit, with the people you're actually
-- racing" (explicit request), and that needs #44-#50, not #47 alone.
--
-- +/-3 gives 7 rows centred on the caller. The `rnk > max(top)` guard is
-- what keeps this from duplicating rows the top block already returned:
-- when the caller is inside the top block the window is empty and the
-- result is byte-identical to before, so the only behaviour that changes
-- is the previously-lonely out-of-top case.
--
-- CREATE OR REPLACE (no DROP) is correct here: the RETURNS TABLE signature
-- is unchanged, only the body. Compare 20260922020000, which DID need a
-- DROP because it added a column.
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
      coalesce(nullif(trim(public.active_anon_name(u.anon_name, u.anon_name_2, u.active_anon_slot)), ''), 'anonymous') as anon_name,
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
  my_rank as (select rnk from ranked where is_me),
  mine as (
    select r.rnk, r.anon_name, r.total_score, r.level, r.is_me, r.anon_photo_url
    from ranked r, my_rank m
    where r.rnk between m.rnk - 3 and m.rnk + 3
      and r.rnk > (select coalesce(max(rnk), 0) from top)
  )
  select rnk, anon_name, total_score, level, is_me, anon_photo_url from top
  union all
  select rnk, anon_name, total_score, level, is_me, anon_photo_url from mine
  order by 1;
$function$;
