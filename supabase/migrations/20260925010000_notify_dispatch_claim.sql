-- BUG FIX (reported: "my friends were getting the same notification several
-- times"). The device-token half of this bug already has two fixes in place
-- (registerDeviceToken's stale-token delete, the one-time
-- 20260924000000_dedupe_device_tokens.sql cleanup) — but there is a SEPARATE,
-- still-live cause: dispatch_push() itself has no claiming/locking.
--
-- It is invoked from two independent, uncoordinated places:
--   * trg_dispatch_push (AFTER INSERT on notifications) — fires immediately
--     whenever a freshly-inserted row is already due;
--   * the notify-dispatch-sweep pg_cron job, every 5 minutes.
-- notify-dispatch/index.ts's due-row query has always been a plain SELECT of
-- every unsent, due row, followed by sending, followed only THEN by stamping
-- push_sent_at via set_push_sent(). Two overlapping invocations — a burst of
-- inserts each firing the AFTER INSERT trigger, or a trigger firing while
-- the cron sweep is mid-flight — can both select the same not-yet-stamped
-- row and both push it, before either has stamped it sent. Nothing before
-- this migration made claim-then-send atomic.
--
-- Fix: give notify-dispatch an atomic claim step. claim_due_notifications()
-- selects AND marks rows claimed in one statement (a CTE with
-- FOR UPDATE SKIP LOCKED feeding the UPDATE that stamps push_claimed_at), so
-- two concurrent callers can never claim the same row. A 2-minute claim TTL
-- means a mid-send crash (claimed, then the edge function dies before
-- stamping push_sent_at or recording failure) self-heals on the next sweep
-- instead of stranding the row forever.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS push_claimed_at timestamptz;

-- Same treatment as push_sent_at: an untrusted (client) UPDATE must not be
-- able to forge or clear this, since it's the thing preventing double-send.
CREATE OR REPLACE FUNCTION public.lock_notification_fields()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path TO 'public','pg_temp' AS $$
BEGIN
  IF current_setting('app.notif_trusted', true) = 'on' THEN
    RETURN NEW;                       -- server-side path, see header
  END IF;
  NEW.recipient_id    := OLD.recipient_id;
  NEW.type            := OLD.type;
  NEW.actor_id        := OLD.actor_id;
  NEW.post_id         := OLD.post_id;
  NEW.tier            := OLD.tier;
  NEW.title           := OLD.title;
  NEW.body            := OLD.body;
  NEW.data            := OLD.data;
  NEW.dedupe_key      := OLD.dedupe_key;
  NEW.created_at      := OLD.created_at;
  NEW.push_sent_at    := OLD.push_sent_at;
  NEW.push_claimed_at := OLD.push_claimed_at;
  RETURN NEW;
END;
$$;

-- Claim-and-select in one atomic statement. p_limit mirrors notify-dispatch's
-- own batch size; the push_attempts ceiling (5) mirrors its MAX_PUSH_ATTEMPTS
-- constant -- keep both in sync if either changes.
CREATE OR REPLACE FUNCTION public.claim_due_notifications(p_limit integer DEFAULT 500)
RETURNS SETOF public.notifications
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);
  RETURN QUERY
    WITH candidates AS (
      SELECT id
        FROM public.notifications
       WHERE push_sent_at IS NULL
         AND push_after IS NOT NULL
         AND push_after <= now()
         AND push_attempts < 5
         AND (push_claimed_at IS NULL OR push_claimed_at < now() - interval '2 minutes')
       ORDER BY push_after ASC
       LIMIT p_limit
         FOR UPDATE SKIP LOCKED
    )
    UPDATE public.notifications n
       SET push_claimed_at = now()
      FROM candidates c
     WHERE n.id = c.id
    RETURNING n.*;
  PERFORM set_config('app.notif_trusted', 'off', true);
END; $function$;
REVOKE EXECUTE ON FUNCTION public.claim_due_notifications(integer) FROM PUBLIC, anon, authenticated;

-- On failure, release the claim immediately rather than waiting out the
-- 2-minute TTL, so a row that still has attempts left is retryable right
-- away by the next sweep.
CREATE OR REPLACE FUNCTION public.record_push_failure(p_ids uuid[])
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);
  UPDATE public.notifications
     SET push_attempts = push_attempts + 1,
         push_claimed_at = NULL
   WHERE id = ANY(p_ids) AND push_sent_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END; $function$;

-- Recurring safety net for the OTHER half of the "same notification several
-- times" bug: registerDeviceToken's stale-token delete
-- (lib/core/notification_service.dart) runs on every token refresh, but its
-- failure was silently swallowed (see the same commit that fixed the catch
-- block), and the only DB-side cleanup before this was the one-time
-- 20260924000000_dedupe_device_tokens.sql migration. A recurring sweep means
-- a duplicate that slips past the client fix (offline, RLS hiccup, a race)
-- doesn't survive more than 15 minutes.
CREATE OR REPLACE FUNCTION public.dedupe_device_tokens()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
BEGIN
  DELETE FROM public.device_tokens a
   USING public.device_tokens b
  WHERE a.user_id = b.user_id
    AND a.platform = b.platform
    AND a.updated_at < b.updated_at;
END; $function$;
REVOKE EXECUTE ON FUNCTION public.dedupe_device_tokens() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule('device-tokens-dedupe-sweep')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'device-tokens-dedupe-sweep');
SELECT cron.schedule('device-tokens-dedupe-sweep', '*/15 * * * *',
                     $$SELECT public.dedupe_device_tokens();$$);
