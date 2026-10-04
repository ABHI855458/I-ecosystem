-- ---------------------------------------------------------------------------
-- STREAK SYSTEM v4 — the daily resolver's schedule.
--
-- pg_cron is installed on this project (confirmed: extension present,
-- v1.6.4), so this runs as a real scheduled job rather than the lazy
-- resolve-on-read fallback that was the contingency.
--
-- 18:35 UTC == 00:05 IST. pg_cron schedules in UTC and has no timezone
-- setting per job, so the conversion is baked into the expression here;
-- the resolver itself does all of its own date maths in Asia/Kolkata.
-- Five past midnight, not midnight exactly, so a ping replied to at 23:59:5x
-- is safely committed before the day is judged.
--
-- resolve_group_ping_yesterday() sweeps EVERY unresolved past day, not just
-- yesterday, so a missed run (deploy, outage, project paused) self-heals on
-- the next tick instead of leaving a day permanently unjudged.
-- ---------------------------------------------------------------------------

-- Idempotent: unschedule first so re-running this migration doesn't stack
-- duplicate jobs (cron.schedule with the same name would otherwise add a
-- second one on some versions).
SELECT cron.unschedule('resolve-group-ping-streaks')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'resolve-group-ping-streaks');

SELECT cron.schedule(
  'resolve-group-ping-streaks',
  '5 18 * * *',
  $$SELECT public.resolve_group_ping_yesterday();$$
);
