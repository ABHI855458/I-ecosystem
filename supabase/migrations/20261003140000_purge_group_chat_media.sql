-- ============================================================================
-- Group chat expiry removes the PHOTOS too, not just the rows.
--
-- The old hourly job ran `DELETE FROM group_messages WHERE created_at < now()
-- - 48h`, which left every attached photo in storage forever (storage files
-- can't be deleted from SQL — storage.objects has a protect_delete trigger).
-- The job now calls the purge-expired-media edge function, which removes the
-- files through the Storage API first and only then the rows. Same auth as
-- dispatch_push (private_settings base URL + shared secret).
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.purge_group_chat_media()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_base   text;
  v_secret text;
BEGIN
  SELECT value INTO v_base   FROM public.private_settings WHERE key = 'edge_function_base_url';
  SELECT value INTO v_secret FROM public.private_settings WHERE key = 'dispatch_secret';
  IF v_base IS NULL OR v_secret IS NULL THEN
    -- No way to reach the function: fall back to the old row-only purge so
    -- expired messages still disappear from the app.
    DELETE FROM public.group_messages WHERE created_at < now() - interval '48 hours';
    RETURN;
  END IF;
  PERFORM net.http_post(
    url     := v_base || '/purge-expired-media',
    headers := jsonb_build_object('Content-Type','application/json','x-dispatch-secret', v_secret),
    body    := '{}'::jsonb
  );
END; $function$;

-- Internal only (security lockdown 2026-09-27: revoke internal definer fns).
REVOKE ALL ON FUNCTION public.purge_group_chat_media() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('purge-group-messages');
SELECT cron.schedule('purge-group-messages', '23 * * * *', $$SELECT public.purge_group_chat_media();$$);

COMMIT;
