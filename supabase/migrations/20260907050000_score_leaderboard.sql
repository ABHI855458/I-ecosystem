-- ---------------------------------------------------------------------------
-- Public leaderboard, ranked by the COMBINED score, shown by ANON NAME only.
--
-- Identity is the whole point of the shape here: it returns anon_name and a
-- rank and nothing else — no user id, no real name, no avatar — so a client
-- holding the full list still cannot map a row back to an account. That is
-- also why it is a function rather than a view with RLS: a view would have to
-- expose users.id to be joinable, and the leaderboard has no need of it.
-- ---------------------------------------------------------------------------

create or replace function public.score_leaderboard(p_limit integer default 50)
returns table (
  rank integer,
  anon_name text,
  total_score integer,
  level integer,
  is_me boolean
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with me as (select id from public.users where auth_id = auth.uid())
  select
    (row_number() over (order by u.total_score desc, u.id))::int,
    coalesce(nullif(trim(u.anon_name), ''), 'anonymous'),
    u.total_score,
    u.level,
    u.id = (select id from me)
  from public.users u
  where u.deleted_at is null
    and u.auth_id is not null
    and u.total_score > 0
  order by u.total_score desc, u.id
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

revoke all on function public.score_leaderboard(integer) from public;
grant execute on function public.score_leaderboard(integer) to authenticated;
