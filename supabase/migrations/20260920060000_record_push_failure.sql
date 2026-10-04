-- The failure half of push dispatch accounting.
--
-- set_push_sent() stamps push_sent_at AND increments push_attempts, and was
-- the only thing notify-dispatch called — on EVERY due row, whether its FCM
-- send actually succeeded or not (settled.push(...) ran unconditionally
-- after the send loop). Consequences:
--   * a row whose send genuinely failed was marked delivered and dropped
--     on the floor, silently, with no trace outside the function logs;
--   * push_attempts could never exceed 1, so the column that exists to be
--     a retry ceiling never counted anything;
--   * an FCM outage would burn every queued notification in one sweep.
--
-- This is the counterpart: it records that an attempt happened and failed,
-- WITHOUT stamping push_sent_at. The row therefore stays eligible for the
-- next 5-minute sweep (the due query filters push_sent_at IS NULL), and
-- push_attempts finally becomes a real, incrementing retry counter that the
-- dispatcher can cap against.
--
-- Deliberately NOT stamping push_sent_at on give-up either: once a row
-- exceeds the attempt ceiling the dispatcher simply stops selecting it.
-- Leaving push_sent_at NULL keeps the record honest — that notification was
-- never delivered, and a stamped "sent" timestamp would claim otherwise.
CREATE OR REPLACE FUNCTION public.record_push_failure(p_ids uuid[])
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int;
BEGIN
  -- Same trusted-write flag set_push_sent uses: lock_notification_fields()
  -- pins most columns back to OLD on any UPDATE, and push_attempts would be
  -- reverted with them otherwise.
  PERFORM set_config('app.notif_trusted', 'on', true);
  UPDATE public.notifications
     SET push_attempts = push_attempts + 1
   WHERE id = ANY(p_ids) AND push_sent_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END; $function$;
