-- ============================================================================
-- Per-community streak + XP + leaderboard, driven by the EXISTING anonymous
-- feed — not the new community_posts noticeboard from 20260904000000.
--
-- CONFIRMED against the live database on 2026-09-04 via the Supabase MCP:
--   * `posts` has visibility CHECK IN ('anonymous','everyone','community')
--     and a nullable community_id; all 36 live rows have community_id NULL
--     today, so this migration changes nothing for existing data — every
--     community streak starts at zero.
--   * No community-scoped streak/XP/leaderboard table or RPC exists
--     anywhere. group_streaks (20260903020000) is the closest analogue and
--     is copied deliberately below (Asia/Kolkata day boundary, read-time
--     decay) — see that file's own header for why the app uses IST.
--   * `reactions` and `post_realmoji_reactions` both carry `post_id`
--     (20260902020000 added group_post_id alongside it, post_id predates
--     that migration).
--
-- PRODUCT RULE, confirmed with the user, not inferred: only an ANONYMOUS
-- post to a community — i.e. posts.visibility = 'anonymous' AND
-- posts.community_id IS NOT NULL, made through the existing composer's Anon
-- destination — advances that community's streak/XP. The new
-- community_posts noticeboard (named or anonymous) earns nothing. This is
-- why the trigger below is on `posts`, not on `community_posts`.
--
-- Every statement is idempotent, safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. community_streaks — SELECT-only from the client; only the SECURITY
-- DEFINER triggers below ever write a row. Mirrors group_streaks's
-- current_streak/longest_streak/last_*_on shape, plus xp/week_xp/
-- week_start_on for the level system and the "Top Engaged This Week" card.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.community_streaks (
  community_id   UUID NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES public.users(id)       ON DELETE CASCADE,
  current_streak INT  NOT NULL DEFAULT 0,
  longest_streak INT  NOT NULL DEFAULT 0,
  last_post_on   DATE,
  xp             INT  NOT NULL DEFAULT 0,
  week_xp        INT  NOT NULL DEFAULT 0,
  week_start_on  DATE,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (community_id, user_id)
);

COMMENT ON COLUMN public.community_streaks.week_xp IS
  'XP earned since week_start_on (the most recent Monday, Asia/Kolkata). Drives the "Top Engaged This Week" podium/leaders and the RANK delta pill. Rolled over lazily on write, not by cron.';

CREATE INDEX IF NOT EXISTS community_streaks_community_idx
  ON public.community_streaks (community_id);

ALTER TABLE public.community_streaks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_streaks' AND policyname = 'community_streaks_select') THEN
    CREATE POLICY "community_streaks_select" ON public.community_streaks FOR SELECT USING (
      is_community_member(community_id, auth.uid())
    );
  END IF;
END $$;
-- No INSERT/UPDATE/DELETE policy: only the SECURITY DEFINER triggers write.

-- ---------------------------------------------------------------------------
-- 2. bump_community_streak — AFTER INSERT on posts, filtered by a WHEN
-- clause so it only fires for the qualifying rows (see PRODUCT RULE above).
-- Streak math is a straight copy of bump_group_streak's day-boundary logic;
-- XP and the weekly bucket are new.
--
-- current_week_start() is factored out because both this trigger and the
-- reaction-XP trigger below need the same "which Monday is it" answer.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.current_week_start()
RETURNS DATE LANGUAGE sql STABLE AS $$
  SELECT (((now() AT TIME ZONE 'Asia/Kolkata')::date)
          - (EXTRACT(ISODOW FROM (now() AT TIME ZONE 'Asia/Kolkata')::date)::int - 1));
$$;

CREATE OR REPLACE FUNCTION public.bump_community_streak()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  d      DATE := (new.created_at AT TIME ZONE 'Asia/Kolkata')::date;
  wk     DATE := current_week_start();
  prev   DATE;
  prevwk DATE;
BEGIN
  SELECT last_post_on, week_start_on INTO prev, prevwk
    FROM community_streaks
   WHERE community_id = new.community_id AND user_id = new.user_id;

  INSERT INTO community_streaks (
    community_id, user_id, current_streak, longest_streak, last_post_on,
    xp, week_xp, week_start_on, updated_at
  )
  VALUES (new.community_id, new.user_id, 1, 1, d, 10, 10, wk, now())
  ON CONFLICT (community_id, user_id) DO UPDATE SET
    current_streak = CASE
      WHEN community_streaks.last_post_on = d THEN community_streaks.current_streak       -- already posted today
      WHEN community_streaks.last_post_on = d - 1 THEN community_streaks.current_streak + 1
      ELSE 1
    END,
    longest_streak = GREATEST(community_streaks.longest_streak, CASE
      WHEN community_streaks.last_post_on = d THEN community_streaks.current_streak
      WHEN community_streaks.last_post_on = d - 1 THEN community_streaks.current_streak + 1
      ELSE 1
    END),
    last_post_on = d,
    -- XP is awarded once per post regardless of streak continuity; a second
    -- post the same day still earns XP (it just doesn't extend the streak).
    xp      = community_streaks.xp + 10,
    week_xp = CASE WHEN community_streaks.week_start_on = wk
                   THEN community_streaks.week_xp + 10 ELSE 10 END,
    week_start_on = wk,
    updated_at    = now();
  RETURN new;
END $$;

DROP TRIGGER IF EXISTS posts_bump_community_streak ON public.posts;
CREATE TRIGGER posts_bump_community_streak AFTER INSERT ON public.posts
  FOR EACH ROW WHEN (new.visibility = 'anonymous' AND new.community_id IS NOT NULL)
  EXECUTE FUNCTION public.bump_community_streak();

-- ---------------------------------------------------------------------------
-- 3. award_community_reaction_xp — +2 XP to a qualifying anon post's author
-- when someone reacts to it. Fires on both reaction tables (a face reaction
-- and a RealMoji reaction are both "a reaction" for this purpose). Looks up
-- the post itself to confirm it is a qualifying community post, so a
-- reaction on an ordinary Everyone/Anon-without-community post is a no-op.
-- Self-reaction is excluded (the author reacting to their own post should
-- not inflate their own XP).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.award_community_reaction_xp()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  p RECORD;
  wk DATE := current_week_start();
BEGIN
  SELECT user_id, community_id INTO p
    FROM posts
   WHERE id = new.post_id AND visibility = 'anonymous' AND community_id IS NOT NULL;

  IF p.user_id IS NULL OR p.user_id = new.user_id THEN
    RETURN new;
  END IF;

  INSERT INTO community_streaks (community_id, user_id, xp, week_xp, week_start_on, updated_at)
  VALUES (p.community_id, p.user_id, 2, 2, wk, now())
  ON CONFLICT (community_id, user_id) DO UPDATE SET
    xp      = community_streaks.xp + 2,
    week_xp = CASE WHEN community_streaks.week_start_on = wk
                   THEN community_streaks.week_xp + 2 ELSE 2 END,
    week_start_on = wk,
    updated_at    = now();
  RETURN new;
END $$;

DROP TRIGGER IF EXISTS reactions_award_community_xp ON public.reactions;
CREATE TRIGGER reactions_award_community_xp AFTER INSERT ON public.reactions
  FOR EACH ROW WHEN (new.post_id IS NOT NULL)
  EXECUTE FUNCTION public.award_community_reaction_xp();

DROP TRIGGER IF EXISTS realmoji_award_community_xp ON public.post_realmoji_reactions;
CREATE TRIGGER realmoji_award_community_xp AFTER INSERT ON public.post_realmoji_reactions
  FOR EACH ROW WHEN (new.post_id IS NOT NULL)
  EXECUTE FUNCTION public.award_community_reaction_xp();

-- ---------------------------------------------------------------------------
-- 4. effective_community_streak — read-time decay, identical in spirit to
-- effective_group_streak. Declared STABLE (not IMMUTABLE): the original
-- calls now() while marked IMMUTABLE, which is technically wrong volatility
-- that only happens to be safe there because it's never indexed. Not
-- repeating that here.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.effective_community_streak(p_current INT, p_last DATE)
RETURNS INT LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN p_last IS NULL THEN 0
    WHEN p_last >= ((now() AT TIME ZONE 'Asia/Kolkata')::date - 1) THEN COALESCE(p_current, 0)
    ELSE 0
  END;
$$;

-- ---------------------------------------------------------------------------
-- 5. community_leaderboard — one round trip for the entire STREAKS tab.
-- SECURITY DEFINER + an explicit membership check inside (rather than
-- relying on RLS, since this reads across all members of the community, not
-- just the caller's own row) so a non-member gets an empty/error result
-- rather than a leak. Level thresholds/names are a fixed ladder; see the
-- Dart-side LEVELS constant this must be kept in sync with.
--
-- ASSUMPTION (flagged for confirmation, not silently shipped): XP ladder is
-- threshold(n) = 10*(n-1)*(n+2) for level n, i.e. L1 0, L2 30, L3 80, L4
-- 150, L5 240, L6 350, L7 480, L8 630, L9 800, L10 990, with names
-- NEWCOMER/LURKER/REGULAR/SCRIBE/CHRONICLER/KEEPER/ARCHIVIST/CURATOR/
-- ORACLE/LEGEND. Beyond L10, level = 10 + floor((xp-990)/200), name LEGEND.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.community_leaderboard(p_community UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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
      COALESCE(cs.current_streak, 0)  AS current_streak,
      COALESCE(cs.longest_streak, 0)  AS longest_streak,
      effective_community_streak(cs.current_streak, cs.last_post_on) AS eff_streak,
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
        'avatar_url', r.profile_photo_url, 'week_xp', r.week_xp
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
        -- Only the viewer's own row actually renders a day-grid
        -- (_AroundYouRow's isYou branch) — included for every row anyway
        -- so the client never has to special-case a missing field.
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
END $$;

REVOKE ALL ON FUNCTION public.community_leaderboard(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.community_leaderboard(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Level ladder helpers — kept as separate SQL functions (not inlined
-- expressions) so the Dart client can call the identical formula if it ever
-- needs to render a level client-side without a round trip, and so the
-- ladder is defined exactly once.
--
-- Threshold for level n (n=1..10) is T(n) = 10*(n-1)*(n+1): T(1)=0, T(2)=30,
-- T(3)=80, T(4)=150, T(5)=240, T(6)=350, T(7)=480, T(8)=630, T(9)=800,
-- T(10)=990 — matches the ladder stated in the plan. Beyond level 10, every
-- further level costs a flat 200 XP.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.community_level_number(p_xp INT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_xp < 990 THEN (
      SELECT max(n) FROM generate_series(1, 10) AS n
      WHERE 10 * (n - 1) * (n + 1) <= p_xp
    )
    ELSE 10 + floor((p_xp - 990) / 200.0)::int
  END;
$$;

CREATE OR REPLACE FUNCTION public.community_next_level_xp(p_xp INT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN community_level_number(p_xp) < 10
      THEN 10 * community_level_number(p_xp) * (community_level_number(p_xp) + 2)
    ELSE 990 + (community_level_number(p_xp) - 9) * 200
  END;
$$;

CREATE OR REPLACE FUNCTION public.community_level_name(p_xp INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT (ARRAY['NEWCOMER','LURKER','REGULAR','SCRIBE','CHRONICLER','KEEPER','ARCHIVIST','CURATOR','ORACLE','LEGEND'])
         [LEAST(community_level_number(p_xp), 10)];
$$;

CREATE OR REPLACE FUNCTION public.community_next_level_name(p_xp INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN community_level_number(p_xp) >= 10 THEN 'LEGEND'
         ELSE (ARRAY['NEWCOMER','LURKER','REGULAR','SCRIBE','CHRONICLER','KEEPER','ARCHIVIST','CURATOR','ORACLE','LEGEND'])
              [community_level_number(p_xp) + 1]
  END;
$$;
