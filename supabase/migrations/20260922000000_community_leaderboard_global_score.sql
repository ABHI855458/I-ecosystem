-- COMMUNITY LEADERBOARD — switch to real, global total_score.
--
-- The podium/leaders numbers were community_streaks.week_xp (per-community
-- weekly engagement points) while "TOP SCORES" on the same screen shows
-- users.total_score (real, all-actions-everywhere score). Confirmed live:
-- the podium said anon cat=30 while their real total_score is 2058 —
-- correct per the OLD field's own meaning, but not what the screen visually
-- claims to be showing the same numbers as (both slots say "score").
--
-- Explicit product decision: total_score is a genuinely GLOBAL number (every
-- action anywhere, entire user base), so it is re-ranked and re-displayed as
-- such here too, not scoped to community_streaks any more. This also means
-- the ranking, not just the number, changes: #3 was quiet.reviewer (week_xp
-- 0) but lknnj (total_score 273, no week_xp row at all) genuinely outranks
-- them by the real metric — swapping only the displayed number and leaving
-- the OLD week_xp-based rank order would have shown the wrong person in
-- 3rd place with someone else's score.
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
      COALESCE(NULLIF('@' || NULLIF(btrim(u.anon_name), ''), '@'), '@anonymous') AS safe_handle,
      u.anon_name,
      u.name,
      u.anon_photo_url,
      u.profile_photo_url,
      COALESCE(u.daily_streak, 0)     AS current_streak,
      COALESCE(u.daily_streak, 0)     AS longest_streak,
      effective_community_streak(u.daily_streak, u.daily_streak_last) AS eff_streak,
      COALESCE(cs.xp, 0)      AS xp,
      -- THE FIX: real, global score replaces the per-community weekly
      -- counter as both the ranking key and the displayed number.
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
