-- Internal SECURITY DEFINER functions were callable by any client.
--
-- Every function below runs with the owner's privileges, takes the target
-- user (or nothing) as a parameter, and never checks who is calling. They
-- still carried Postgres's default EXECUTE-to-PUBLIC, so anon and
-- authenticated could call them straight through PostgREST (/rpc/...):
--
--   log_score_event(p_user, p_type, p_points)  -> grant anyone any points
--   bump_daily_streak(p_user), apply_score_decay()
--   apply_pin_slot(p_me, ...)                   -> act as another user
--   fold_reaction_notification / notify_graduation -> forge notifications
--   notify_* cron jobs                          -> push-spam every user
--   resolve_group_ping_*, snapshot_ranks, recalc_lifecycle
--   record_push_failure                         -> tamper with push retries
--   user_is_minor(p_user), activation_state(p_user) -> read others' data
--
-- Audit 2026-09-27: none is called by the app, the admin dashboards or any
-- RLS policy / view / invoker function. Callers are pg_cron (runs as the
-- owner), other SECURITY DEFINER functions (run as the owner), triggers
-- (EXECUTE is not checked when a trigger fires) and the notify-dispatch
-- edge function (service_role, re-granted below).

do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as sig
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in (
         'apply_score_decay', 'bump_daily_streak', 'log_score_event',
         'apply_pin_slot', 'fold_reaction_notification',
         'notify_activation_drip', 'notify_break_live_count',
         'notify_day_digest', 'notify_graduation', 'notify_lifecycle',
         'notify_midday_report', 'notify_moment_reply_reminders',
         'notify_rank_movement', 'notify_start_streak_nudge',
         'notify_streak_escalation', 'notify_streak_standing',
         'notify_unanswered_pings', 'notify_window_change',
         'recalc_lifecycle', 'record_push_failure',
         'resolve_group_ping_day', 'resolve_group_ping_yesterday',
         'snapshot_ranks', 'activation_state', 'user_is_minor'
       )
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', fn.sig);
    execute format('grant execute on function %s to service_role', fn.sig);
  end loop;
end $$;
