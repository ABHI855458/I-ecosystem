-- Unanswered-ping reminders + curiosity copy.
--
-- Rule the copy follows everywhere below: never name a person. A nudge says
-- how many are outstanding, a reply says "someone", and the name is only
-- revealed by opening the app. Explicit instruction: "dont name the non
-- responders ... let it be like someone on ping qa group replied ... in all
-- notifications you shall create curiosity".
--
-- Reminders fire at the HALFWAY point of whatever window the sender chose
-- (windows in this data run 3-5h), computed off expires_at rather than
-- created_at because created_at is `timestamp without time zone` and would
-- need a tz assumption; expires_at is timestamptz and already exact.

-- 1 ----------------------------------------------------------------------
-- Personal ping: the receiver hasn't replied and the window is half gone.
-- major tier, because standard/minor are blocked during class_1/2/3 and
-- wind_down, which on a 3h window would land the nudge after expiry.

CREATE OR REPLACE FUNCTION public.notify_unanswered_pings()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  -- Personal, unanswered, past halfway, not yet expired.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'ping_unanswered', NULL, 'major',
         'Someone is still waiting on you 👀',
         p.prompt,
         jsonb_build_object('screen','ping','ping_id', p.id),
         'ping_unanswered:' || p.id::text
  FROM public.pings p
  WHERE p.group_id IS NULL
    AND p.receiver_id IS NOT NULL
    AND p.receiver_id <> p.sender_id
    AND p.replied_at IS NULL
    AND p.expires_at IS NOT NULL
    AND p.expires_at > now()
    AND now() >= p.expires_at - (p.window_hours * INTERVAL '30 minutes')
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  -- Group: at least one member hasn't replied. Goes to EVERY member of the
  -- thread, repliers included — explicit instruction ("to all the members
  -- msg shall go if one person hasnt replyed") — and carries a count, never
  -- a name.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT mem.receiver_id, 'group_ping_waiting', NULL, 'major',
         CASE WHEN t.waiting = 1
              THEN 'Someone in ' || COALESCE(g.name,'your group') || ' still hasn''t replied 👀'
              ELSE t.waiting || ' people in ' || COALESCE(g.name,'your group') || ' still haven''t replied 👀'
         END,
         t.prompt,
         jsonb_build_object('screen','group','group_id', t.group_id, 'thread_id', t.thread_id),
         'group_ping_waiting:' || t.thread_id::text || ':' || mem.receiver_id::text
  FROM (
    SELECT p.thread_id, p.group_id, min(p.prompt) AS prompt,
           count(*) FILTER (WHERE p.replied_at IS NULL) AS waiting,
           max(p.expires_at) AS expires_at,
           max(p.window_hours) AS window_hours
    FROM public.pings p
    WHERE p.group_id IS NOT NULL AND p.thread_id IS NOT NULL
    GROUP BY p.thread_id, p.group_id
    HAVING count(*) FILTER (WHERE p.replied_at IS NULL) > 0
  ) t
  JOIN public.groups g ON g.id = t.group_id
  JOIN public.pings mem ON mem.thread_id = t.thread_id AND mem.receiver_id IS NOT NULL
  WHERE t.expires_at IS NOT NULL
    AND t.expires_at > now()
    AND now() >= t.expires_at - (t.window_hours * INTERVAL '30 minutes')
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
END;
$$;

-- 2 ----------------------------------------------------------------------
-- Group ping: someone replied. Fires on the FIRST reply in a thread only —
-- the dedupe key is per (thread, member), so a second replier doesn't
-- re-notify. One curiosity hit per thread, not one per reply.

CREATE OR REPLACE FUNCTION public.notify_group_ping_first_reply()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_thread uuid; v_group uuid; v_name text;
BEGIN
  SELECT p.thread_id, p.group_id INTO v_thread, v_group
  FROM public.pings p WHERE p.id = NEW.ping_id;

  IF v_thread IS NULL OR v_group IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT name INTO v_name FROM public.groups WHERE id = v_group;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  SELECT mem.receiver_id, 'group_ping_replied', NULL, 'standard',
         'Someone in ' || COALESCE(v_name,'your group') || ' replied 👀',
         jsonb_build_object('screen','group','group_id', v_group, 'thread_id', v_thread),
         'group_ping_replied:' || v_thread::text || ':' || mem.receiver_id::text
  FROM public.pings mem
  WHERE mem.thread_id = v_thread
    AND mem.receiver_id IS NOT NULL
    AND mem.receiver_id <> NEW.replier_id   -- not the person who just replied
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_group_ping_first_reply ON public.ping_replies;
CREATE TRIGGER trg_notify_group_ping_first_reply
  AFTER INSERT ON public.ping_replies
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_ping_first_reply();

-- 3 ----------------------------------------------------------------------
-- Curiosity rewrite of the three existing ping notifications. Behaviour is
-- unchanged; only the visible copy drops the name. actor_id is still stored
-- on the row, so the in-app list can reveal identity under the existing
-- pin rules — it is only the PUSH text that stays anonymous.

CREATE OR REPLACE FUNCTION public.notify_ping()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  IF NEW.receiver_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sender_id = NEW.receiver_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
  VALUES (NEW.receiver_id, 'ping',
          CASE WHEN NEW.anonymous IS TRUE THEN NULL ELSE NEW.sender_id END,
          'major', 'Someone pinged you 👋', NEW.prompt, 'ping:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_ping_reply()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_sender uuid;
BEGIN
  SELECT sender_id INTO v_sender FROM public.pings WHERE id = NEW.ping_id;
  IF v_sender IS NULL OR v_sender = NEW.replier_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (v_sender, 'ping_answered', NEW.replier_id, 'major',
          'Someone answered your ping 🔥', NULL,
          jsonb_build_object('screen','ping_reveal','ping_id', NEW.ping_id, 'ping_reply_id', NEW.id),
          'ping_answered:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_group_ping_opened()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_group text; v_streak int; v_title text; r record;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;

  SELECT current_streak INTO v_streak FROM public.group_ping_streak(NEW.group_id);
  v_streak := COALESCE(v_streak, 0);

  v_title := 'Someone pinged ' || v_group ||
             CASE WHEN v_streak > 0 THEN ' — reply to keep the ' || v_streak || '-day streak alive'
                  ELSE ' — reply to start a streak' END;

  FOR r IN SELECT unnest(NEW.member_ids) AS uid LOOP
    IF r.uid <> NEW.started_by THEN
      INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
      VALUES (r.uid, 'group_streak_ping', NEW.started_by, 'major', v_title,
              jsonb_build_object('screen','group','group_id', NEW.group_id, 'thread_id', NEW.thread_id),
              'group_streak_ping:' || NEW.group_id::text || ':' || NEW.on_date::text || ':' || r.uid::text)
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;
