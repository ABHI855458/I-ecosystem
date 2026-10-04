-- STALE STREAK FIX — the flame kept claiming a run that had already died.
--
-- Reported from the Group Wall: a member's 🔥 badge read "1" while their
-- last reply was FIVE days old. Verified live on Ping QA Group —
-- abisheksdpatel: current_streak = 1, last_reply_on = 2026-09-15, today
-- 2026-09-20.
--
-- The counters themselves are correct; the READS were not. Both
-- group_ping_member_streak_map() and group_ping_streak() returned the
-- stored current_streak verbatim, with no comparison against today. A
-- streak is a claim about consecutive days ending NOW, so a stored number
-- only means anything alongside the date it was last advanced.
--
-- Why it froze: the reset path exists, but it lives inside
-- resolve_group_ping_day(), which only runs for a date that HAS a
-- group_ping_days row. Ping QA Group has rows for 09-09, 09-12 and 09-15
-- only — all resolved. With no ping day opened since, there was nothing to
-- resolve, so nothing zeroed the counter and the UI rendered a five-day-old
-- value as if it were live. Any group that goes a few days without a ping
-- day hits this; it is not specific to that group or to test data.
--
-- Fixed at the read rather than with a new cron or a backfill, deliberately:
--   * a cron would leave the same stale window between ticks, and the value
--     would still be wrong for anyone reading at the wrong moment;
--   * a backfill fixes today's rows and nothing about tomorrow's;
--   * computing liveness at read time makes the flame correct the instant
--     it is drawn, with no job to run, miss, or re-run.
-- Same reasoning as the injected-prompt expiry: derive it from a boundary
-- comparison so there is no state to keep in sync.
--
-- The freshness rule MIRRORS the write rule exactly. resolve_group_ping_day
-- continues a run only when `last_reply_on = p_date - 1`, i.e. a gap longer
-- than a single day breaks it. So a run is alive iff it was last advanced
-- today or yesterday. Yesterday counts because today is not over — a member
-- who replied yesterday and has not yet replied today still has a live
-- streak, and zeroing it at midnight would break the run a day early.
--
-- Campus date (Asia/Kolkata), matching resolve_group_ping_yesterday()'s own
-- day basis, so the flame turns over when the campus day does and not when
-- UTC midnight passes.
--
-- The stored columns are untouched. The write path stays the single source
-- of truth for advancing a run; these functions only decline to report a run
-- that has already lapsed.

CREATE OR REPLACE FUNCTION public.group_ping_member_streak_map(p_group_id uuid)
 RETURNS TABLE(user_id uuid, streak integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ms.user_id,
         CASE
           WHEN ms.last_reply_on IS NULL THEN 0
           WHEN ms.last_reply_on
                >= ((now() AT TIME ZONE 'Asia/Kolkata')::date - 1)
             THEN ms.current_streak
           ELSE 0
         END
    FROM public.group_ping_member_streaks ms
   WHERE ms.group_id = p_group_id
     AND public.is_group_member(p_group_id, public.current_user_id());
$function$;

CREATE OR REPLACE FUNCTION public.group_ping_streak(p_group_id uuid)
 RETURNS TABLE(current_streak integer, longest_streak integer, today_replied integer, today_total integer, today_open boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    -- Same freshness rule as the per-member map above, against the group's
    -- own last_complete_on. longest_streak is a historical record and is
    -- deliberately NOT gated — it is true whether or not the run is alive.
    CASE
      WHEN gs.last_complete_on IS NULL THEN 0
      WHEN gs.last_complete_on >= (v_today - 1) THEN COALESCE(gs.current_streak, 0)
      ELSE 0
    END,
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
END $function$;
