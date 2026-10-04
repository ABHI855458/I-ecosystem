-- Group pings: one reply per person, ever, per thread. Personal and
-- anonymous pings are explicitly UNCHANGED — they keep multi-reply.
--
-- The "wall opens once you've replied" HALF of this was already fully
-- built: can_see_ping_reply() gates a group thread's replies on
-- has_answered_thread(thread_id, viewer), and the client
-- (ping_page.dart's `locked = !t.unlocked`) already swaps the composer for
-- the wall the moment that flips. What was missing is anything stopping a
-- SECOND reply from ever being written in the first place — the RLS
-- insert policy only checks `is_ping_receiver(ping_id)`, which stays true
-- forever, so nothing capped the count.
--
-- Gated on pings.group_id IS NOT NULL, not on thread_id — thread_id exists
-- on BOTH kinds ('person' and 'group' in ping_threads.kind; verified live,
-- 26 personal + 20 group pings all carry one), so group_id is the only
-- column that actually discriminates.
CREATE OR REPLACE FUNCTION public.enforce_group_ping_reply_once()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_group_id uuid;
  v_thread   uuid;
BEGIN
  SELECT p.group_id, p.thread_id INTO v_group_id, v_thread
    FROM public.pings p WHERE p.id = NEW.ping_id;

  -- Not a group ping (personal/anonymous) -> no cap, unchanged behaviour.
  IF v_group_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.ping_replies r
    JOIN public.pings p2 ON p2.id = r.ping_id
    WHERE p2.thread_id = v_thread
      AND r.replier_id = NEW.replier_id
      AND r.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'You''ve already replied to this group ping.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_group_ping_reply_once ON public.ping_replies;
CREATE TRIGGER trg_enforce_group_ping_reply_once
  BEFORE INSERT ON public.ping_replies
  FOR EACH ROW EXECUTE FUNCTION public.enforce_group_ping_reply_once();
