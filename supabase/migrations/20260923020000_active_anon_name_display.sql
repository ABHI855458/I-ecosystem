-- ANON IDENTITY — honour active_anon_slot on the public display surfaces.
--
-- THE BUG (found live, not theoretical)
-- users has anon_name / anon_name_2 / active_anon_slot, and the client has a
-- resolver for exactly this (lib/services/anon_identity.dart activeAnonName()).
-- The SERVER side never had one: every RPC/view reads u.anon_name directly, so
-- anyone who has shuffled to their second alias still renders under their
-- FIRST one everywhere the server does the naming. Confirmed on live rows:
--
--   shreyasgalag  slot=2  anon_name='cvguy_ghost'  anon_name_2='hehe'
--   adithii643    slot=2  anon_name='lknnj'        anon_name_2='known'
--
-- Both showed as cvguy_ghost / lknnj on the community leaderboard podium —
-- i.e. the alias they had switched away from. For a feature whose whole point
-- is which identity you are wearing, that is a correctness bug, not cosmetics.
--
-- SCOPE OF THIS MIGRATION
-- The three PUBLIC surfaces where the displayed anon name IS the identity:
-- score_leaderboard, community_leaderboard, and posts_feed (the anon feed).
-- Deliberately NOT changed here, because whether they should track the alias
-- or stay pinned to the canonical first name is a product call, not a bug:
--   admin_list_users, provision_institutional_account, dashboard_feed
--     (moderation/admin surfaces — a stable name is arguably the point)
--   anon_post_comments, get_moment_replies
--   notify_comment, notify_friend_accepted, notify_friend_request,
--   notify_group_streak_broken, notify_pair_streak_milestone,
--   notify_rank_movement, notify_streak_escalation, notify_us_album_invite,
--   notify_us_album_mutual

-- The server-side twin of activeAnonName() in anon_identity.dart. IMMUTABLE so
-- it is free to call inside the view and any index/plan that wants it.
CREATE OR REPLACE FUNCTION public.active_anon_name(
  p_anon_name text,
  p_anon_name_2 text,
  p_active_slot integer
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_active_slot = 2 AND NULLIF(btrim(COALESCE(p_anon_name_2, '')), '') IS NOT NULL
      THEN btrim(p_anon_name_2)
    ELSE p_anon_name
  END;
$function$;

GRANT EXECUTE ON FUNCTION public.active_anon_name(text, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.active_anon_name(text, text, integer) TO anon;

-- 1/3 — score_leaderboard. Reproduced from the live definition; ONLY the
-- anon_name expression changes (it now resolves the active slot).
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

-- 2/3 — community_leaderboard. Only safe_handle's source changes.
CREATE OR REPLACE FUNCTION public.community_leaderboard(p_community uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  my_users_id UUID;
  result JSONB;
BEGIN
  IF NOT is_community_member(p_community, auth.uid()) THEN
    RAISE EXCEPTION 'not a member of this community';
  END IF;

  SELECT id INTO my_users_id FROM users WHERE auth_id = auth.uid();

  WITH member_rows AS (
    SELECT
      m.user_id AS auth_id,
      u.id      AS users_id,
      COALESCE(NULLIF('@' || NULLIF(btrim(public.active_anon_name(u.anon_name, u.anon_name_2, u.active_anon_slot)), ''), '@'), '@anonymous') AS safe_handle,
      public.active_anon_name(u.anon_name, u.anon_name_2, u.active_anon_slot) AS anon_name,
      u.name,
      u.anon_photo_url,
      u.profile_photo_url,
      COALESCE(u.daily_streak, 0)     AS current_streak,
      COALESCE(u.daily_streak, 0)     AS longest_streak,
      effective_community_streak(u.daily_streak, u.daily_streak_last) AS eff_streak,
      COALESCE(cs.xp, 0)      AS xp,
      COALESCE(u.total_score, 0) AS total_score,
      cs.last_post_on
    FROM community_members m
    JOIN users u ON u.auth_id = m.user_id
    LEFT JOIN community_streaks cs ON cs.community_id = p_community AND cs.user_id = u.id
    WHERE m.community_id = p_community
  ),
  ranked AS (
    SELECT *,
      RANK() OVER (ORDER BY eff_streak DESC, xp DESC, users_id ASC) AS rnk,
      RANK() OVER (ORDER BY total_score DESC, users_id ASC)         AS week_rnk
    FROM member_rows
  ),
  daily AS (
    SELECT p.user_id, (p.created_at AT TIME ZONE 'Asia/Kolkata')::date AS d, count(*) AS c
    FROM posts p
    WHERE p.visibility = 'anonymous' AND p.community_id = p_community
      AND p.created_at >= now() - INTERVAL '14 days'
    GROUP BY 1, 2
  ),
  post_counts AS (
    SELECT p.user_id, count(*) AS c
    FROM posts p
    WHERE p.visibility = 'anonymous' AND p.community_id = p_community
    GROUP BY 1
  ),
  days_json AS (
    SELECT r.users_id,
      jsonb_agg(
        CASE WHEN d.c IS NULL OR d.c = 0 THEN 0.0
             WHEN d.c = 1 THEN 0.25 WHEN d.c = 2 THEN 0.5 ELSE 1.0 END
        ORDER BY offs
      ) AS days
    FROM ranked r
    CROSS JOIN generate_series(13, 0, -1) AS offs
    LEFT JOIN daily d ON d.user_id = r.users_id
      AND d.d = ((now() AT TIME ZONE 'Asia/Kolkata')::date - offs)
    GROUP BY r.users_id
  ),
  me AS (SELECT * FROM ranked WHERE users_id = my_users_id),
  rival AS (SELECT * FROM ranked WHERE rnk = (SELECT rnk - 1 FROM me) LIMIT 1)
  SELECT jsonb_build_object(
    'community', jsonb_build_object(
      'id', p_community,
      'member_count', (SELECT count(*) FROM ranked)
    ),
    'me', (
      SELECT jsonb_build_object(
        'rank', me.rnk, 'handle', me.safe_handle,
        'streak', me.eff_streak, 'longest', me.longest_streak,
        'xp', me.xp,
        'level', community_level_number(me.xp), 'level_name', community_level_name(me.xp),
        'next_level_xp', community_next_level_xp(me.xp), 'next_level_name', community_next_level_name(me.xp),
        'week_xp', me.total_score, 'week_rank', me.week_rnk,
        'days', COALESCE((SELECT days FROM days_json WHERE users_id = me.users_id), '[]'::jsonb)
      ) FROM me
    ),
    'podium', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.week_rnk, 'handle', r.safe_handle,
        'initial', upper(left(COALESCE(r.anon_name, r.name, '?'), 1)),
        'avatar_url', r.anon_photo_url, 'week_xp', r.total_score
      ) ORDER BY r.week_rnk)
      FROM ranked r WHERE r.week_rnk <= 3
    ), '[]'::jsonb),
    'leaders', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.week_rnk, 'handle', r.safe_handle,
        'initial', upper(left(COALESCE(r.anon_name, r.name, '?'), 1)),
        'week_xp', r.total_score,
        'progress', CASE WHEN (SELECT max(total_score) FROM ranked) > 0
                         THEN r.total_score::float / (SELECT max(total_score) FROM ranked) ELSE 0 END
      ) ORDER BY r.week_rnk)
      FROM ranked r WHERE r.week_rnk BETWEEN 4 AND 6
    ), '[]'::jsonb),
    'top_streaks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.rnk, 'handle', r.safe_handle,
        'streak', r.eff_streak,
        'post_count', COALESCE((SELECT c FROM post_counts WHERE user_id = r.users_id), 0),
        'days', COALESCE((SELECT days FROM days_json WHERE users_id = r.users_id), '[]'::jsonb),
        'is_top', r.rnk = 1
      ) ORDER BY r.rnk)
      FROM ranked r WHERE r.rnk <= 8
    ), '[]'::jsonb),
    'around_you', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.rnk, 'handle', r.safe_handle,
        'streak', r.eff_streak,
        'is_you', r.users_id = my_users_id,
        'is_rival', r.rnk = (SELECT rnk - 1 FROM me),
        'level', community_level_number(r.xp),
        'days', COALESCE((SELECT days FROM days_json WHERE users_id = r.users_id), '[]'::jsonb)
      ) ORDER BY r.rnk)
      FROM ranked r
      WHERE r.rnk BETWEEN (SELECT rnk - 2 FROM me) AND (SELECT rnk + 2 FROM me)
    ), '[]'::jsonb),
    'rival', (
      SELECT jsonb_build_object(
        'handle', rival.safe_handle,
        'rank', rival.rnk,
        'streak', rival.eff_streak,
        'fires_behind', GREATEST(rival.eff_streak - (SELECT eff_streak FROM me), 1)
      ) FROM rival
    )
  ) INTO result;

  RETURN result;
END $function$;
