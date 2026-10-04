-- Attach the notification push-slot trigger + backfill the queued rows.
--
-- Bug: public.set_notification_push_slot() existed and was correct, but was
-- never attached to public.notifications as a trigger. Every row therefore
-- landed with push_after = NULL, and public.dispatch_push() only picks up
-- rows matching `push_after IS NOT NULL AND push_after <= now()` — so the
-- whole queue was invisible to the sweep and dispatch reported {"sent":0}
-- no matter how correct the FCM credentials were.
--
-- Backfill deliberately routes through public.next_push_slot(...) instead of
-- copying created_at: push_after is the quiet-hours / digest-batching slot,
-- not a timestamp echo. Using created_at would have made every backlogged
-- row bypass the batching rules the column exists to enforce.

DROP TRIGGER IF EXISTS trg_set_notification_push_slot ON public.notifications;

CREATE TRIGGER trg_set_notification_push_slot
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_notification_push_slot();

UPDATE public.notifications
   SET push_after = public.next_push_slot(tier, type, COALESCE(created_at, now()))
 WHERE push_after IS NULL
   AND push_sent_at IS NULL;
