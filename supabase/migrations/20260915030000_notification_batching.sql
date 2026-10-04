-- notification_system_spec.md §5.4 (batching) + the timing hook.
--
-- Two pieces:
--
-- 1. set_notification_push_slot() — a BEFORE INSERT trigger on
--    `notifications` that stamps push_after from next_push_slot(). Doing it
--    here rather than in each notify_* function means every notification
--    type, the nine that already existed and every one added below, obeys
--    §1's windows without any of them knowing the windows exist. Rows that
--    predate this (push_after IS NULL) are never picked up by the
--    dispatcher, so turning push on does not blast the existing backlog.
--
-- 2. notify_batched() — the "increment, don't insert" pattern §5.4 asks
--    for. "A friend posts" is the highest-volume event in the app and must
--    never be twelve rows; it is one row per recipient per day whose count
--    goes up. Because ON CONFLICT DO UPDATE deliberately leaves push_after
--    and push_sent_at alone, the count keeps climbing while the row waits
--    for its window and exactly one push goes out carrying the final total.

CREATE OR REPLACE FUNCTION public.set_notification_push_slot()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path TO 'public','pg_temp' AS $$
BEGIN
  IF NEW.push_after IS NULL AND NEW.push_sent_at IS NULL THEN
    NEW.push_after := public.next_push_slot(
      NEW.tier, NEW.type, COALESCE(NEW.created_at, now())
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_notification_push_slot ON public.notifications;
CREATE TRIGGER trg_set_notification_push_slot
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_notification_push_slot();

-- p_one  : title while the count is 1 ("A friend posted")
-- p_many : format() template, %s is the running count ("%s friends posted today")
CREATE OR REPLACE FUNCTION public.notify_batched(
  p_recipient uuid,
  p_type      text,
  p_tier      text,
  p_dedupe    text,
  p_one       text,
  p_many      text,
  p_data      jsonb DEFAULT '{}'::jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
BEGIN
  IF p_recipient IS NULL THEN RETURN; END IF;

  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key)
  VALUES
    (p_recipient, p_type, p_tier, p_one,
     p_data || jsonb_build_object('count', 1), p_dedupe)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL
  DO UPDATE SET
    data = notifications.data || jsonb_build_object(
             'count', COALESCE((notifications.data->>'count')::int, 1) + 1),
    title = format(p_many, COALESCE((notifications.data->>'count')::int, 1) + 1),
    -- Re-surface it in the inbox: a batch that grew is new information.
    read_at    = NULL,
    created_at = now();
    -- push_after / push_sent_at intentionally untouched — see header.
END;
$$;
