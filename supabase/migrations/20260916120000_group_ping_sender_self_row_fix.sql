-- A group ping gives the SENDER their own `pings` row too, so they have a
-- slot on their own wall and must answer it like everyone else. That row is
-- not an outbound ping to anyone, but enforce_ping_limit counted it, so a
-- sender at their 5-thread daily cap could no longer be given one — and the
-- backfill below could not run at all.
CREATE OR REPLACE FUNCTION public.enforce_ping_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c INT;
BEGIN
  -- The sender's own slot on their own wall — not a ping sent to someone.
  IF NEW.sender_id = NEW.receiver_id THEN
    RETURN NEW;
  END IF;

  SELECT count(DISTINCT COALESCE(t.thread_id, t.id)) INTO c
  FROM (
    SELECT p.thread_id, p.id FROM public.pings p
     WHERE p.sender_id = NEW.sender_id
       AND p.created_at > now() - interval '24 hours'
    UNION ALL
    SELECT NEW.thread_id, NEW.id
  ) t;

  IF c > 5 THEN
    RAISE EXCEPTION 'Ping limit reached (5 per 24h).';
  END IF;
  RETURN NEW;
END;
$function$;

-- Group threads created BEFORE the sender started getting a self-row have
-- none, so my_group_walls() reports my_ping_id = NULL for the person who
-- asked. The wall composer's Post handler is wrapped in `if (myPingId !=
-- null)`, so on those threads Post silently sent nothing while still
-- clearing the draft — the wall never unlocked and you could "reply"
-- forever, which is the personal-ping behaviour leaking into the group wall.
--
-- notify_ping already skips sender = receiver, and award_ping_sent_score
-- returns early for group pings, so this creates no notifications and no
-- score.
INSERT INTO public.pings
  (thread_id, sender_id, receiver_id, group_id, prompt, anonymous, window_hours, photo_url)
SELECT t.id, t.sender_id, t.sender_id, t.group_id, t.prompt,
       t.anonymous, t.window_hours, t.photo_url
FROM public.ping_threads t
WHERE t.kind = 'group'
  AND t.group_id IS NOT NULL
  AND public.is_group_member(t.group_id, t.sender_id)
  AND NOT EXISTS (
    SELECT 1 FROM public.pings p
    WHERE p.thread_id = t.id AND p.receiver_id = t.sender_id
  );
