-- Push delivery — the wiring that turns a `notifications` row into an
-- actual push. See supabase/functions/notify-dispatch/index.ts for the
-- sender itself and why delivery is centralised there instead of in the
-- per-source-table notify-* functions.
--
-- Config lives in a table, not in database GUCs. supabase/functions/
-- README.md's original instructions used
--   ALTER DATABASE postgres SET app.settings.service_role_key = '…'
-- but this project's role is not permitted to set those parameters
-- (42501: permission denied to set parameter), and putting a service_role
-- key in a GUC would also make it readable by anything that can call
-- current_setting(). private_settings has RLS on with no policies and all
-- grants revoked, so only SECURITY DEFINER functions and the service role
-- can read it.

CREATE TABLE IF NOT EXISTS public.private_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
ALTER TABLE public.private_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.private_settings FROM PUBLIC, anon, authenticated;

-- Required rows (values are per-environment, set out of band):
--   edge_function_base_url = https://<ref>.supabase.co/functions/v1
--   dispatch_secret        = a random secret, also set as the
--                            DISPATCH_SECRET Edge Function secret

-- Stamping push_sent_at has to go through here: lock_notification_fields()
-- reverts push_sent_at on any untrusted UPDATE, and without the flag the
-- dispatcher's stamp would be silently discarded — every row would stay
-- eligible and be re-pushed on the next sweep, forever.
CREATE OR REPLACE FUNCTION public.set_push_sent(p_ids uuid[])
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE n int;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);
  UPDATE public.notifications
     SET push_sent_at = now(), push_attempts = push_attempts + 1
   WHERE id = ANY(p_ids) AND push_sent_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END; $$;
REVOKE EXECUTE ON FUNCTION public.set_push_sent(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.dispatch_push()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_base text; v_secret text;
BEGIN
  SELECT value INTO v_base   FROM public.private_settings WHERE key = 'edge_function_base_url';
  SELECT value INTO v_secret FROM public.private_settings WHERE key = 'dispatch_secret';
  IF v_base IS NULL OR v_secret IS NULL THEN
    RETURN;   -- unconfigured: no-op rather than a failing http_post per row
  END IF;
  PERFORM net.http_post(
    url     := v_base || '/notify-dispatch',
    headers := jsonb_build_object('Content-Type','application/json',
                                  'x-dispatch-secret', v_secret),
    body    := '{}'::jsonb);
END; $$;
REVOKE EXECUTE ON FUNCTION public.dispatch_push() FROM PUBLIC, anon, authenticated;

-- Send-now path: a MAJOR raised at lunch should not wait up to five minutes
-- for the sweep. Rows whose push_after is in the future are left for cron.
CREATE OR REPLACE FUNCTION public.trigger_dispatch_if_due()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
BEGIN
  IF NEW.push_after IS NOT NULL AND NEW.push_sent_at IS NULL
     AND NEW.push_after <= now() THEN
    PERFORM public.dispatch_push();
  END IF;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS trg_dispatch_push ON public.notifications;
CREATE TRIGGER trg_dispatch_push AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.trigger_dispatch_if_due();

-- Queue sweep: picks up everything that was queued out of its window and
-- has since become due (the 07:30 wake digest, the 11:00 and 12:30 peaks).
SELECT cron.unschedule('notify-dispatch-sweep')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-dispatch-sweep');
SELECT cron.schedule('notify-dispatch-sweep', '*/5 * * * *',
                     $$SELECT public.dispatch_push();$$);
