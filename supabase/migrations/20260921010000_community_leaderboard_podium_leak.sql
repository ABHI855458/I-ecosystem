-- COMMUNITY_LEADERBOARD — item #2 of the security audit.
--
-- Two fixes in this pass, same reasoning as Fix #1: both are found by
-- re-reading a function that already trusted an author-identifying field
-- without noticing it, exactly the class of bug that keeps surfacing
-- tonight.
--
-- 1. PODIUM AVATAR LEAK (live, confirmed with real production data).
--    'avatar_url', r.profile_photo_url in the 'podium' block exposed the
--    REAL photo next to an @anon_name handle, unconditionally, on every
--    community's weekly top-3 — the underlying storage URL even spells out
--    the real user_id in cleartext. Verified live against General:
--
--      #1 @anon cat        avatar_url=.../avatars/726dc111-....jpg (real)
--      #2 @cvguy_ghost     avatar_url=.../avatars/0a4cad77-....jpg (real)
--      #3 @quiet.reviewer  avatar_url=.../avatars/adcaa2d7-....jpg (real)
--
--    Fixed by switching to r.anon_photo_url — the same persona-photo field
--    already trusted by posts_feed (see 20260921000000). The client's
--    _PodiumSpot widget already renders a null avatar_url as an initial
--    letter (community_streaks_tab.dart:610-612), so this is a pure
--    subtraction of leaked data, not a new failure mode: a member with no
--    persona photo set (25% of current members) simply shows their initial,
--    same as before this fix for anyone whose real photo happened to be
--    missing too.
--
-- 2. HANDLE FALLBACK HARDENING (latent — 0 of 72 current members trigger
--    it, confirmed by live count before writing this). Every handle in
--    every section (me/podium/leaders/top_streaks/around_you/rival) was
--    built as COALESCE('@' || r.anon_name, r.name) — string concatenation
--    with a NULL anon_name yields NULL, which falls the COALESCE through to
--    the REAL NAME. Not exploitable today because every current member has
--    a non-empty anon_name, but that is a property of today's data, not
--    something the query enforces — bundled into this same migration rather
--    than tracked separately, since it is the identical class of bug in the
--    identical function, found while already in here.
--
--    Hardened to fall back to a fixed '@anonymous' rather than ever
--    resolving to r.name. NULLIF(btrim(...), '') also guards an anon_name
--    of all-whitespace, which plain NULL-checking would miss.
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
      -- THE FIX (part 2, applied at the source): a safe, never-real-name
      -- handle computed once here rather than repeated per-section.
      COALESCE(NULLIF('@' || NULLIF(btrim(u.anon_name), ''), '@'), '@anonymous') AS safe_handle,
      u.anon_name,
      u.name,
      u.anon_photo_url,  -- THE FIX (part 1): read alongside profile_photo_url...
      u.profile_photo_url,
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
        'week_xp', me.week_xp, 'week_rank', me.week_rnk,
        'days', COALESCE((SELECT days FROM days_json WHERE users_id = me.users_id), '[]'::jsonb)
      ) FROM me
    ),
    'podium', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.week_rnk, 'handle', r.safe_handle,
        'initial', upper(left(COALESCE(r.anon_name, r.name, '?'), 1)),
        'avatar_url', r.anon_photo_url, 'week_xp', r.week_xp
      ) ORDER BY r.week_rnk)
      FROM ranked r WHERE r.week_rnk <= 3
    ), '[]'::jsonb),
    'leaders', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'rank', r.week_rnk, 'handle', r.safe_handle,
        'initial', upper(left(COALESCE(r.anon_name, r.name, '?'), 1)),
        'week_xp', r.week_xp,
        'progress', CASE WHEN (SELECT max(week_xp) FROM ranked) > 0
                         THEN r.week_xp::float / (SELECT max(week_xp) FROM ranked) ELSE 0 END
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
