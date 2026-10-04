-- LAUNCH-BLOCKING: anon de-anonymization via community_leaderboard() podium.
--
-- THE BUG. The podium block emitted the member's REAL profile photo beside
-- their ANONYMOUS handle:
--     'handle', COALESCE('@' || r.anon_name, r.name),
--     'avatar_url', r.profile_photo_url,     <-- removed
-- The board ranks anonymous activity (the day-grid CTEs filter
-- p.visibility = 'anonymous'), so the top-3 told any community member
-- exactly which real person was behind a given anonymous persona.
--
-- podium was the LONE outlier: leaders / top_streaks / around_you in this
-- same function already return only  and no photo. This makes
-- podium match them; it is not a new policy, it is the existing one applied
-- to the block that missed it.
--
-- Impersonated probe (real authenticated user, before): 8 real photos
-- exposed across 6 communities. Required after: 0.
--
-- Client needs no change: community_streaks_tab.dart:610-613 already renders
-- the member's initial when avatar_url is null, which is exactly how
-- the non-podium blocks already display.
--
-- Body below is VERBATIM from the live pg_get_functiondef; the ONLY change
-- is removing that one key (diffed line-by-line before running).
-- Return type is unchanged, so CREATE OR REPLACE is safe.

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
      u.anon_name,
      u.name,
      u.profile_photo_url,
      -- STREAK SYSTEM v4: the leaderboard now ranks on the RED personal
      -- anon streak (users.daily_streak, one anon post a day) instead of
      -- the per-community posting streak it used to show. Reviewed
      -- decision: "replace community_streaks.current_streak with
      -- users.daily_streak entirely — don't show both." XP below is
      -- untouched and still community-scoped; only the streak moved.
      COALESCE(u.daily_streak, 0)     AS current_streak,
      COALESCE(u.daily_streak, 0)     AS longest_streak,
      effective_community_streak(u.daily_streak, u.daily_streak_last) AS eff_streak,
      COALESCE(cs.xp, 0)      AS xp,
      COALESCE(cs.week_xp, 0) AS week_xp,
      cs.last_post_on
    FROM community_members m
    JOIN users u ON u.auth_id = m.user_id
    LEFT JOIN community_streaks cs ON cs.community_id = p_community AND cs.user_id = u.id
    WHERE m.community_id = p_community
  ),
  ranked AS (
    SELECT *,
      RANK() OVER (ORDER BY eff_streak DESC, xp DESC, users_id ASC) AS rnk,
      RANK() OVER (ORDER BY week_xp DESC, xp DESC, users_id ASC)    AS week_rnk
    FROM member_rows
  ),
  -- Post-count-per-day, last 14 days, bucketed to the mockup's 0/.25/.5/1
  -- steps (0 posts / 1 / 2 / 3+) so _streakColor() keeps working unchanged.
  daily AS (
    SELECT p.user_id, (p.created_at AT TIME ZONE 'Asia/Kolkata')::date AS d, count(*) AS c
    FROM posts p
    WHERE p.visibility = 'anonymous' AND p.community_id = p_community
      AND p.created_at >= now() - INTERVAL '14 days'
    GROUP BY 1, 2
  ),
  -- All-time qualifying post count per member — backs "148 POSTS" under
  -- each TOP STREAKS row. Deliberately unbounded (not the 14-day window
  -- `daily` uses for the day-grid), since a long-tenured member's total
  -- post count is the whole point of that line.
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
        'rank', me.rnk, 'handle', COALESCE('@' || me.anon_name, me.name),
        'streak', me.eff_streak, 'longest', me.longest_streak,
        'xp', me.xp,
        'level', community_level_number(me.xp), 'level_name', community_level_name(me.xp),
        'next_level_xp', community_next_level_xp(me.xp), 'next_level_name', community_next_level_name(me.xp),
        'week_xp', me.week_xp, 'week_rank', me.week_rnk,
        'days', COALESCE((SELECT days FROM days_json WHERE users_id = me.users_id), '[]'::jsonb)
      ) FROM me
    ),
    'podium', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.week_rnk, 'handle', COALESCE('@' || r.anon_name, r.name),
        'initial', upper(left(COALESCE(r.anon_name, r.name, '?'), 1)),
        'week_xp', r.week_xp
      ) ORDER BY r.week_rnk)
      FROM ranked r WHERE r.week_rnk <= 3
    ), '[]'::jsonb),
    'leaders', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.week_rnk, 'handle', COALESCE('@' || r.anon_name, r.name),
        'initial', upper(left(COALESCE(r.anon_name, r.name, '?'), 1)),
        'week_xp', r.week_xp,
        'progress', CASE WHEN (SELECT max(week_xp) FROM ranked) > 0
                         THEN r.week_xp::float / (SELECT max(week_xp) FROM ranked) ELSE 0 END
      ) ORDER BY r.week_rnk)
      FROM ranked r WHERE r.week_rnk BETWEEN 4 AND 6
    ), '[]'::jsonb),
    'top_streaks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.rnk, 'handle', COALESCE('@' || r.anon_name, r.name),
        'streak', r.eff_streak,
        'post_count', COALESCE((SELECT c FROM post_counts WHERE user_id = r.users_id), 0),
        'days', COALESCE((SELECT days FROM days_json WHERE users_id = r.users_id), '[]'::jsonb),
        'is_top', r.rnk = 1
      ) ORDER BY r.rnk)
      FROM ranked r WHERE r.rnk <= 8
    ), '[]'::jsonb),
    'around_you', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.rnk, 'handle', COALESCE('@' || r.anon_name, r.name),
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
        'handle', COALESCE('@' || rival.anon_name, rival.name),
        'rank', rival.rnk,
        'streak', rival.eff_streak,
        'fires_behind', GREATEST(rival.eff_streak - (SELECT eff_streak FROM me), 1)
      ) FROM rival
    )
  ) INTO result;

  RETURN result;
END $function$;
