-- ---------------------------------------------------------------------------
-- STREAK SYSTEM v4 — two colours, four display surfaces.
--
-- Applied exactly per the reviewed Step 1 schema. Summary of the model:
--
--   RED  — personal anon streak. An ANON POST, once per day. Ping does not
--          feed it. Shown on the user's own profile AND the community
--          leaderboard. Already existed (users.daily_streak +
--          bump_daily_streak, fired by award_anon_post_score) — this
--          migration only fixes its day boundary.
--
--   BLUE 1 — one-to-one ping streak, per friend pair. Already existed and
--          is DERIVED, not stored (ping_streak_with / my_ping_streaks) —
--          deliberately no new table, per the reviewed decision.
--
--   BLUE 2 — the group's SHARED, all-or-nothing streak. Any member sends
--          the daily group ping; EVERY member must reply before the day
--          ends or the shared streak resets to zero for everyone. A day
--          with no ping at all is a no-op, not a break. Group profile only.
--          Fully new.
--
--   BLUE 3 — each member's OWN reply streak to the group ping, independent
--          of the group's verdict. Group posts only. Fully new.
--
-- REMOVED: the old per-user Dip streak (group_streaks + bump_group_streak +
-- effective_group_streak). Dip posting itself is untouched — only its
-- streak tracking is cut. Live rows are archived first, per explicit
-- instruction ("snapshot it first, don't drop outright with no record").
-- ---------------------------------------------------------------------------

-- ═══ BLOCK 0 ─ snapshot the old Dip streak before removing it ═══════════
-- Kept in-database as well as in the repo
-- (supabase/snapshots/group_streaks_snapshot_20260914.json) so the numbers
-- survive here even if the file is lost. Plain table, no RLS consumers —
-- nothing reads it; it exists to be recoverable.
CREATE TABLE IF NOT EXISTS public.group_streaks_archive_20260914 AS
  SELECT *, now() AS archived_at FROM public.group_streaks;

-- ═══ BLOCK 1 ─ remove the old Dip streak ════════════════════════════════
DROP TRIGGER IF EXISTS dips_bump_streak ON public.dips;
DROP FUNCTION IF EXISTS public.bump_group_streak() CASCADE;
DROP FUNCTION IF EXISTS public.effective_group_streak(uuid, uuid);
DROP TABLE IF EXISTS public.group_streaks;

-- ═══ BLOCK 2 ─ RED: align the day boundary to IST ═══════════════════════
-- bump_daily_streak used bare current_date (UTC) while every other streak
-- function in this schema uses Asia/Kolkata, so the personal streak rolled
-- over at 05:30 IST — mid-morning — and disagreed with the community
-- streak it sits next to on the leaderboard.
CREATE OR REPLACE FUNCTION public.bump_daily_streak(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE
  v_last  date;
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  SELECT daily_streak_last INTO v_last FROM public.users WHERE id = p_user;
  IF v_last = v_today THEN
    RETURN;                                   -- already counted today
  ELSIF v_last = v_today - 1 THEN
    UPDATE public.users
       SET daily_streak = daily_streak + 1,
           daily_streak_last = v_today
     WHERE id = p_user;                       -- consecutive day
  ELSE
    UPDATE public.users
       SET daily_streak = 1,
           daily_streak_last = v_today
     WHERE id = p_user;                       -- first day, or the run broke
  END IF;
END $$;

-- ═══ BLOCK 3 ─ BLUE 2: the group's SHARED streak ════════════════════════
CREATE TABLE IF NOT EXISTS public.group_ping_streaks (
  group_id         uuid PRIMARY KEY REFERENCES public.groups(id) ON DELETE CASCADE,
  current_streak   int  NOT NULL DEFAULT 0,
  longest_streak   int  NOT NULL DEFAULT 0,
  -- The last day the group actually COMPLETED (everyone replied). NOT the
  -- last day a ping was sent: a day with no ping is a no-op, so this is
  -- what "consecutive" is measured against.
  last_complete_on date,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- One daily group ping per group per IST day. This is the row the resolver
-- judges.
CREATE TABLE IF NOT EXISTS public.group_ping_days (
  group_id   uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  on_date    date NOT NULL,
  thread_id  uuid NOT NULL,
  started_by uuid NOT NULL REFERENCES public.users(id),
  -- The roster AS IT WAS when the ping went out. Without this snapshot,
  -- someone joining later in the day would retroactively break a streak
  -- for a ping they were never asked to answer.
  member_ids uuid[] NOT NULL,
  resolved   boolean NOT NULL DEFAULT false,
  PRIMARY KEY (group_id, on_date)
);

CREATE INDEX IF NOT EXISTS group_ping_days_unresolved_idx
  ON public.group_ping_days (on_date) WHERE NOT resolved;

-- ═══ BLOCK 4 ─ BLUE 3: per-person reply streak to the group ping ════════
CREATE TABLE IF NOT EXISTS public.group_ping_member_streaks (
  group_id       uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  current_streak int  NOT NULL DEFAULT 0,
  longest_streak int  NOT NULL DEFAULT 0,
  last_reply_on  date,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

-- ═══ BLOCK 5 ─ RLS ══════════════════════════════════════════════════════
-- All three are readable by members of the group in question and written
-- ONLY by the resolver (SECURITY DEFINER, runs as postgres). No client
-- INSERT/UPDATE/DELETE policies at all — a streak nobody can write from a
-- device is a streak nobody can forge.
ALTER TABLE public.group_ping_streaks        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_ping_days           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_ping_member_streaks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS group_ping_streaks_select ON public.group_ping_streaks;
CREATE POLICY group_ping_streaks_select ON public.group_ping_streaks
  FOR SELECT USING (public.is_group_member(group_id, public.current_user_id()));

DROP POLICY IF EXISTS group_ping_days_select ON public.group_ping_days;
CREATE POLICY group_ping_days_select ON public.group_ping_days
  FOR SELECT USING (public.is_group_member(group_id, public.current_user_id()));

DROP POLICY IF EXISTS group_ping_member_streaks_select ON public.group_ping_member_streaks;
CREATE POLICY group_ping_member_streaks_select ON public.group_ping_member_streaks
  FOR SELECT USING (public.is_group_member(group_id, public.current_user_id()));

-- ═══ BLOCK 6 ─ opening the daily group ping ═════════════════════════════
-- Called when a member sends the group's ping for the day. Idempotent per
-- (group, IST day): the first send of the day creates the row and every
-- later one is a no-op, so "the daily group ping" is exactly one event a
-- day no matter how many people press it.
CREATE OR REPLACE FUNCTION public.open_group_ping_day(p_group_id uuid, p_thread_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE
  v_me      uuid := public.current_user_id();
  v_today   date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_members uuid[];
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;
  IF NOT public.is_group_member(p_group_id, v_me) THEN
    RAISE EXCEPTION 'Not a member of this group.';
  END IF;

  SELECT array_agg(gm.user_id) INTO v_members
    FROM public.group_members gm WHERE gm.group_id = p_group_id;

  INSERT INTO public.group_ping_days (group_id, on_date, thread_id, started_by, member_ids)
  VALUES (p_group_id, v_today, p_thread_id, v_me, COALESCE(v_members, '{}'))
  ON CONFLICT (group_id, on_date) DO NOTHING;

  RETURN FOUND;
END $$;

-- ═══ BLOCK 7 ─ the daily resolver (the all-must-reply mechanic) ═════════
-- Judges one past day:
--   • no ping that day        → no row, nothing to do, streak preserved
--   • ping sent, all replied  → group +1, and each replier +1
--   • ping sent, someone missed→ group RESET TO 0; repliers still +1,
--                                non-repliers reset to 0
CREATE OR REPLACE FUNCTION public.resolve_group_ping_day(p_date date)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE
  d             record;
  v_replied     uuid[];
  v_all_replied boolean;
  n             int := 0;
BEGIN
  FOR d IN SELECT * FROM public.group_ping_days
            WHERE on_date = p_date AND NOT resolved LOOP

    SELECT COALESCE(array_agg(DISTINCT r.replier_id), '{}')
      INTO v_replied
      FROM public.ping_replies r
      JOIN public.pings p ON p.id = r.ping_id
     WHERE p.thread_id = d.thread_id;

    SELECT bool_and(m = ANY(v_replied)) INTO v_all_replied
      FROM unnest(d.member_ids) m;
    v_all_replied := COALESCE(v_all_replied, false);

    INSERT INTO public.group_ping_streaks AS gs
      (group_id, current_streak, longest_streak, last_complete_on)
    VALUES (
      d.group_id,
      CASE WHEN v_all_replied THEN 1 ELSE 0 END,
      CASE WHEN v_all_replied THEN 1 ELSE 0 END,
      CASE WHEN v_all_replied THEN p_date END
    )
    ON CONFLICT (group_id) DO UPDATE SET
      current_streak = CASE
        WHEN NOT v_all_replied THEN 0
        WHEN gs.last_complete_on = p_date - 1 THEN gs.current_streak + 1
        ELSE 1 END,
      longest_streak = GREATEST(gs.longest_streak, CASE
        WHEN NOT v_all_replied THEN 0
        WHEN gs.last_complete_on = p_date - 1 THEN gs.current_streak + 1
        ELSE 1 END),
      last_complete_on = CASE WHEN v_all_replied THEN p_date
                              ELSE gs.last_complete_on END,
      updated_at = now();

    -- Per-person counters are independent of the group's verdict: you keep
    -- your own run for showing up even on a day the group as a whole broke.
    INSERT INTO public.group_ping_member_streaks AS ms
      (group_id, user_id, current_streak, longest_streak, last_reply_on)
    SELECT d.group_id, m, 1, 1, p_date
      FROM unnest(d.member_ids) m
     WHERE m = ANY(v_replied)
    ON CONFLICT (group_id, user_id) DO UPDATE SET
      current_streak = CASE WHEN ms.last_reply_on = p_date - 1
                            THEN ms.current_streak + 1 ELSE 1 END,
      longest_streak = GREATEST(ms.longest_streak,
                        CASE WHEN ms.last_reply_on = p_date - 1
                             THEN ms.current_streak + 1 ELSE 1 END),
      last_reply_on = p_date,
      updated_at = now();

    UPDATE public.group_ping_member_streaks
       SET current_streak = 0, updated_at = now()
     WHERE group_id = d.group_id
       AND user_id = ANY(d.member_ids)
       AND NOT (user_id = ANY(v_replied));

    UPDATE public.group_ping_days SET resolved = true
     WHERE group_id = d.group_id AND on_date = p_date;

    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

-- Convenience wrapper: judge yesterday (IST). This is what cron calls, and
-- it also lets any unresolved older day be swept if a run was ever missed.
CREATE OR REPLACE FUNCTION public.resolve_group_ping_yesterday()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE
  d date;
  n int := 0;
BEGIN
  -- Sweeps EVERY unresolved past day, not just yesterday, so a skipped
  -- run (deploy, outage) self-heals on the next tick instead of leaving a
  -- day permanently unjudged.
  FOR d IN
    SELECT DISTINCT on_date FROM public.group_ping_days
     WHERE NOT resolved
       AND on_date < (now() AT TIME ZONE 'Asia/Kolkata')::date
     ORDER BY on_date
  LOOP
    n := n + public.resolve_group_ping_day(d);
  END LOOP;
  RETURN n;
END $$;

-- ═══ BLOCK 8 ─ read helpers for the app ═════════════════════════════════
-- The group's shared streak, plus today's live progress (how many of the
-- roster have replied so far) — the group profile shows both, and today's
-- progress is what makes the all-or-nothing rule legible BEFORE midnight
-- rather than only after it.
CREATE OR REPLACE FUNCTION public.group_ping_streak(p_group_id uuid)
RETURNS TABLE(current_streak int, longest_streak int,
              today_replied int, today_total int, today_open boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE
  v_me    uuid := public.current_user_id();
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_day   record;
BEGIN
  IF v_me IS NULL OR NOT public.is_group_member(p_group_id, v_me) THEN
    RETURN;
  END IF;

  SELECT * INTO v_day FROM public.group_ping_days
   WHERE group_id = p_group_id AND on_date = v_today;

  RETURN QUERY
  SELECT
    COALESCE(gs.current_streak, 0),
    COALESCE(gs.longest_streak, 0),
    CASE WHEN v_day IS NULL THEN 0 ELSE (
      SELECT count(DISTINCT r.replier_id)::int
        FROM public.ping_replies r
        JOIN public.pings p ON p.id = r.ping_id
       WHERE p.thread_id = v_day.thread_id
         AND r.replier_id = ANY(v_day.member_ids)
    ) END,
    CASE WHEN v_day IS NULL THEN 0
         ELSE array_length(v_day.member_ids, 1) END,
    (v_day IS NOT NULL)
  FROM (SELECT 1) _
  LEFT JOIN public.group_ping_streaks gs ON gs.group_id = p_group_id;
END $$;

-- Every member's own group-ping reply streak, for the group-posts surface.
CREATE OR REPLACE FUNCTION public.group_ping_member_streak_map(p_group_id uuid)
RETURNS TABLE(user_id uuid, streak int)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
  SELECT ms.user_id, ms.current_streak
    FROM public.group_ping_member_streaks ms
   WHERE ms.group_id = p_group_id
     AND public.is_group_member(p_group_id, public.current_user_id());
$$;

REVOKE ALL ON FUNCTION public.resolve_group_ping_day(date) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_group_ping_yesterday() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.open_group_ping_day(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.group_ping_streak(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.group_ping_member_streak_map(uuid) TO authenticated;

-- ═══ BLOCK 9 ─ cascade repair: group_public_profile ═════════════════════
-- Dropping group_streaks broke this function, which joined it to report a
-- per-member Dip streak on the non-member ("public") group view. Caught by
-- calling it straight after the drop: it failed with 42P01, relation
-- "group_streaks" does not exist.
--
-- The roster no longer reports a streak at all, deliberately. The Dip
-- streak it used to show is gone by design, and BLUE 3 (each member's
-- group-ping reply streak) is scoped to GROUP POSTS only per the reviewed
-- spec — putting it on the roster instead would be a different surface
-- than the one that was signed off. 'streak' is kept as a key returning 0
-- so existing clients parsing this JSON don't hit a missing field.
CREATE OR REPLACE FUNCTION public.group_public_profile(p_group_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'id',           g.id,
    'name',         g.name,
    'icon_url',     g.icon_url,
    'member_count', (SELECT count(*) FROM group_members m WHERE m.group_id = g.id),
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'user_id',           u.id,
               'name',              u.name,
               'profile_photo_url', u.profile_photo_url,
               'streak',            0
             ) ORDER BY u.name)
      FROM group_members m
      JOIN users u ON u.id = m.user_id
      WHERE m.group_id = g.id
    ), '[]'::jsonb)
  )
  FROM groups g
  WHERE g.id = p_group_id;
$function$;

DROP FUNCTION IF EXISTS public.effective_group_streak(integer, date);
