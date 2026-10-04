-- NOTIFICATION SYSTEM — PHASE 3: competitive / rank movement (spec §6.7A).
--
--   Overtaken        "{anon name} just passed you — you're #{rank} now"  MINOR
--   Rank dropped     "You dropped {n} places in {community} today"       STANDARD
--   Regained         "You're back above {anon name} 🔥"                  STANDARD
--   Streak overtaken "{anon name} has a longer streak than you now"      STANDARD
--
-- ANON NAMES ONLY, real positions, real counts, max once per day each.
--
-- ===================== ANONYMITY (the Phase 2 lesson) ================
-- actor_id is NULL on every row below and no dedupe_key contains anyone's
-- id but the recipient's own. A leaderboard notification names a person by
-- their ANON handle on purpose — that handle is what the leaderboard itself
-- shows — but storing the real user in actor_id would hand the client
-- `actor:users!notifications_actor_id_fkey(name)`, i.e. the real name, and
-- silently undo the whole point. Same failure Phase 2 found in
-- pinned_post_view; not repeating it here.
--
-- ======================= REAL NUMBERS ONLY ===========================
-- Every position and count comes from two dated snapshots of a real
-- ordering. Nothing is estimated, padded or inferred: if there is no
-- yesterday row for a user, that user simply produces no comparison.

-- ------------------------- snapshot store ----------------------------
-- Generalises the existing leaderboard_rank_snapshots (global score only)
-- to the three orderings Phase 3 compares. Kept as a separate table rather
-- than altering that one, because notify_last_call still writes and reads
-- it and a scope column would have to be back-filled for 11 days of
-- history to keep its own query correct.
--
-- scope: 'global'            — users.total_score, the score leaderboard
--        'streak'            — users.daily_streak, the 🔴 personal streak
--        'community:<uuid>'  — one community's board
CREATE TABLE IF NOT EXISTS public.rank_snapshots (
  scope    text NOT NULL,
  user_id  uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  on_date  date NOT NULL,
  rank     integer NOT NULL,
  PRIMARY KEY (scope, user_id, on_date)
);
CREATE INDEX IF NOT EXISTS rank_snapshots_scope_date_idx
  ON public.rank_snapshots (scope, on_date);

-- Server-side only: these rows are another user's competitive position and
-- nothing in the app reads them directly. RLS on with no policy = no client
-- can select, same posture as pinned_people.
ALTER TABLE public.rank_snapshots ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.rank_snapshots IS
  'Daily rank per user per ordering, written by notify_rank_movement(). The '
  'ONLY source of the positions quoted in rank notifications — nothing is '
  'estimated. No client policy: ranks of other users never leave the server '
  'except as an anon name in notification copy.';

-- --------------------------- the ranker ------------------------------
CREATE OR REPLACE FUNCTION public.snapshot_ranks(p_day date)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int := 0; m int;
BEGIN
  -- Global score board. Mirrors score_leaderboard's ordering exactly
  -- (total_score DESC, id) so a quoted "#7" matches what the user sees.
  INSERT INTO public.rank_snapshots (scope, user_id, on_date, rank)
  SELECT 'global', u.id, p_day,
         (row_number() OVER (ORDER BY COALESCE(u.total_score,0) DESC, u.id))::int
    FROM public.users u
   WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  ON CONFLICT (scope, user_id, on_date) DO UPDATE SET rank = EXCLUDED.rank;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  -- Personal 🔴 streak board.
  INSERT INTO public.rank_snapshots (scope, user_id, on_date, rank)
  SELECT 'streak', u.id, p_day,
         (row_number() OVER (ORDER BY COALESCE(u.daily_streak,0) DESC, u.id))::int
    FROM public.users u
   WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  ON CONFLICT (scope, user_id, on_date) DO UPDATE SET rank = EXCLUDED.rank;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  -- Per-community boards. Ordering copied from community_leaderboard's own
  -- `ranked` CTE (effective streak, then community XP, then id) so the
  -- place count a member is told matches the board they can open.
  INSERT INTO public.rank_snapshots (scope, user_id, on_date, rank)
  SELECT 'community:' || c.id::text, u.id, p_day,
         (row_number() OVER (
            PARTITION BY c.id
            ORDER BY public.effective_community_streak(u.daily_streak, u.daily_streak_last) DESC,
                     COALESCE(cs.xp,0) DESC, u.id))::int
    FROM public.communities c
    JOIN public.community_members cm ON cm.community_id = c.id
    JOIN public.users u ON u.auth_id = cm.user_id
    LEFT JOIN public.community_streaks cs ON cs.community_id = c.id AND cs.user_id = u.id
   WHERE c.deleted_at IS NULL AND u.deleted_at IS NULL
  ON CONFLICT (scope, user_id, on_date) DO UPDATE SET rank = EXCLUDED.rank;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  RETURN n;
END;
$function$;

-- --------------------- the four notifications ------------------------
CREATE OR REPLACE FUNCTION public.notify_rank_movement()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_yday  date := v_today - 1;
  n int := 0; r record;
BEGIN
  PERFORM public.snapshot_ranks(v_today);
  PERFORM set_config('app.notif_trusted', 'on', true);

  -- 1. OVERTAKEN (global). Someone who was BELOW me yesterday is ABOVE me
  --    today. Where several did, the nearest one above me now is named —
  --    that is the person the user is actually racing.
  FOR r IN
    SELECT mt.user_id,
           mt.rank AS my_rank,
           (SELECT COALESCE(NULLIF(btrim(o.anon_name), ''), 'someone')
              FROM public.rank_snapshots ot
              JOIN public.rank_snapshots oy
                ON oy.user_id = ot.user_id AND oy.scope = 'global' AND oy.on_date = v_yday
              JOIN public.users o ON o.id = ot.user_id
             WHERE ot.scope = 'global' AND ot.on_date = v_today
               AND oy.rank > my.rank        -- was below me yesterday
               AND ot.rank < mt.rank        -- is above me today
             ORDER BY ot.rank DESC          -- nearest above me
             LIMIT 1) AS passer
      FROM public.rank_snapshots mt
      JOIN public.rank_snapshots my
        ON my.user_id = mt.user_id AND my.scope = 'global' AND my.on_date = v_yday
      JOIN public.users me ON me.id = mt.user_id
     WHERE mt.scope = 'global' AND mt.on_date = v_today
       AND mt.rank > my.rank
       AND me.deleted_at IS NULL
  LOOP
    CONTINUE WHEN r.passer IS NULL;
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    VALUES (r.user_id, 'rank_overtaken', NULL, 'minor',
            r.passer || ' just passed you — you''re #' || r.my_rank || ' now',
            jsonb_build_object('screen','leaderboard'),
            'rank_overtaken:' || r.user_id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- 2. REGAINED (global). Someone who was ABOVE me yesterday is BELOW me
  --    today — the mirror of 1, and the reason to come back.
  FOR r IN
    SELECT mt.user_id,
           (SELECT COALESCE(NULLIF(btrim(o.anon_name), ''), 'someone')
              FROM public.rank_snapshots ot
              JOIN public.rank_snapshots oy
                ON oy.user_id = ot.user_id AND oy.scope = 'global' AND oy.on_date = v_yday
              JOIN public.users o ON o.id = ot.user_id
             WHERE ot.scope = 'global' AND ot.on_date = v_today
               AND oy.rank < my.rank        -- was above me yesterday
               AND ot.rank > mt.rank        -- is below me today
             ORDER BY ot.rank ASC           -- nearest below me
             LIMIT 1) AS passed
      FROM public.rank_snapshots mt
      JOIN public.rank_snapshots my
        ON my.user_id = mt.user_id AND my.scope = 'global' AND my.on_date = v_yday
      JOIN public.users me ON me.id = mt.user_id
     WHERE mt.scope = 'global' AND mt.on_date = v_today
       AND me.deleted_at IS NULL
  LOOP
    CONTINUE WHEN r.passed IS NULL;
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    VALUES (r.user_id, 'rank_regained', NULL, 'standard',
            'You''re back above ' || r.passed || ' 🔥',
            jsonb_build_object('screen','leaderboard'),
            'rank_regained:' || r.user_id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- 3. STREAK RANK OVERTAKEN. Same shape as 1, on the 🔴 streak ordering.
  FOR r IN
    SELECT mt.user_id,
           (SELECT COALESCE(NULLIF(btrim(o.anon_name), ''), 'someone')
              FROM public.rank_snapshots ot
              JOIN public.rank_snapshots oy
                ON oy.user_id = ot.user_id AND oy.scope = 'streak' AND oy.on_date = v_yday
              JOIN public.users o ON o.id = ot.user_id
             WHERE ot.scope = 'streak' AND ot.on_date = v_today
               AND oy.rank > my.rank AND ot.rank < mt.rank
             ORDER BY ot.rank DESC LIMIT 1) AS passer
      FROM public.rank_snapshots mt
      JOIN public.rank_snapshots my
        ON my.user_id = mt.user_id AND my.scope = 'streak' AND my.on_date = v_yday
      JOIN public.users me ON me.id = mt.user_id
     WHERE mt.scope = 'streak' AND mt.on_date = v_today
       AND mt.rank > my.rank AND me.deleted_at IS NULL
  LOOP
    CONTINUE WHEN r.passer IS NULL;
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    VALUES (r.user_id, 'streak_rank_overtaken', NULL, 'standard',
            r.passer || ' has a longer streak than you now',
            jsonb_build_object('screen','leaderboard'),
            'streak_rank_overtaken:' || r.user_id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- 4. RANK DROPPED, per community. One row per community per day; the
  --    community is named because the place count is meaningless without
  --    saying which board it happened on.
  FOR r IN
    SELECT mt.user_id, c.id AS community_id, c.name AS cname,
           (mt.rank - my.rank) AS dropped
      FROM public.rank_snapshots mt
      JOIN public.rank_snapshots my
        ON my.user_id = mt.user_id AND my.scope = mt.scope AND my.on_date = v_yday
      JOIN public.communities c
        ON mt.scope = 'community:' || c.id::text
      JOIN public.users me ON me.id = mt.user_id
     WHERE mt.on_date = v_today AND mt.rank > my.rank
       AND c.deleted_at IS NULL AND me.deleted_at IS NULL
  LOOP
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    VALUES (r.user_id, 'leaderboard_movement', NULL, 'standard',
            'You dropped ' || r.dropped || ' place' ||
              CASE WHEN r.dropped = 1 THEN '' ELSE 's' END ||
              ' in ' || r.cname || ' today',
            jsonb_build_object('screen','community','community_id', r.community_id),
            'leaderboard_movement:' || r.user_id::text || ':'
              || r.community_id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
