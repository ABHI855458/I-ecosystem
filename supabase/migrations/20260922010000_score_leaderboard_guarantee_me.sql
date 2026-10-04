-- score_leaderboard() — guarantee the caller's own row is always present.
--
-- Root cause of "podium and list don't match" (community_streaks_tab.dart):
-- the Streaks tab renders TWO different total_score rankings side by side —
-- community_leaderboard()'s podium/leaders (population = current community's
-- members only) and score_leaderboard()'s "TOP SCORES / ALL COMMUNITIES"
-- list (population = every user in the app). Same person, same total_score,
-- two different rank numbers depending on which query you're in. The client
-- fix (this migration's companion Dart change) unifies the podium onto this
-- one, truly-global RPC — but that only works if the caller's own row is
-- guaranteed to be present so "Your rank" can read a real global rank number
-- instead of the community-scoped one. Previously this RPC silently dropped
-- your row if you weren't in the top p_limit (default 20 from the client).
CREATE OR REPLACE FUNCTION public.score_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE(rank integer, anon_name text, total_score integer, level integer, is_me boolean)
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
      (u.id = (select id from me_id)) as is_me
    from public.users u
    where u.deleted_at is null
      and u.auth_id is not null
      and u.total_score > 0
  ),
  top as (
    select rnk, anon_name, total_score, level, is_me
    from ranked
    order by rnk
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ),
  mine as (
    select rnk, anon_name, total_score, level, is_me
    from ranked
    where is_me and rnk > (select coalesce(max(rnk), 0) from top)
  )
  select rnk, anon_name, total_score, level, is_me from top
  union all
  select rnk, anon_name, total_score, level, is_me from mine
  order by 1;
$function$;
