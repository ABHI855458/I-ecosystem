-- notification_system_spec.md §2 (tiers) and §3 (copy) applied to the nine
-- notifications that already existed. Each change below is a line the spec
-- states differently from what shipped — nothing here is invented.
--
--   ping           "…pinged you"                    → adds 👋
--   friend_request "…sent you a friend request"     → "…wants to be friends"
--   friend_accepted                                  → adds 🎉
--   branch_view    minor → STANDARD, "viewed"       → "checked out … 👀"
--   us_album_mutual standard → MAJOR, and the line the spec actually gives
--   report_filed   minor → STANDARD

CREATE OR REPLACE FUNCTION public.notify_ping() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp' AS $$
DECLARE v_actor_name text;
BEGIN
  IF NEW.receiver_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.anonymous IS TRUE THEN
    -- §6: an anonymous ping never names its sender and never sets actor_id.
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
    VALUES (NEW.receiver_id, 'ping', NULL, 'major', 'Someone pinged you 👋', NEW.prompt,
            'ping:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  ELSE
    SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name
      FROM public.users WHERE id = NEW.sender_id;
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
    VALUES (NEW.receiver_id, 'ping', NEW.sender_id, 'major',
            COALESCE(v_actor_name,'someone') || ' pinged you 👋', NEW.prompt,
            'ping:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.notify_friend_request() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp' AS $$
DECLARE v_actor_name text;
BEGIN
  IF NEW.status <> 'pending' THEN RETURN NEW; END IF;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name
    FROM public.users WHERE id = NEW.requester_id;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, dedupe_key)
  VALUES (NEW.addressee_id, 'friend_request', NEW.requester_id, 'standard',
          COALESCE(v_actor_name,'someone') || ' wants to be friends',
          'friend_request:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.notify_friend_accepted() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp' AS $$
DECLARE v_actor_name text;
BEGIN
  IF NOT (OLD.status = 'pending' AND NEW.status = 'accepted') THEN RETURN NEW; END IF;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name
    FROM public.users WHERE id = NEW.addressee_id;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, dedupe_key)
  VALUES (NEW.requester_id, 'friend_accepted', NEW.addressee_id, 'standard',
          COALESCE(v_actor_name,'someone') || ' accepted your friend request 🎉',
          'friend_accepted:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.notify_us_album_mutual() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp' AS $$
DECLARE v_recipient uuid; v_actor_name text;
BEGIN
  IF NOT (OLD.visibility <> 'mutual' AND NEW.visibility = 'mutual') THEN RETURN NEW; END IF;
  SELECT CASE WHEN user_a = NEW.uploaded_by THEN user_b ELSE user_a END
    INTO v_recipient FROM public.us_albums WHERE id = NEW.album_id;
  IF v_recipient IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name
    FROM public.users WHERE id = NEW.uploaded_by;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, dedupe_key)
  VALUES (v_recipient, 'us_album_mutual', NEW.uploaded_by, 'major',
          COALESCE(v_actor_name,'someone') || ' made a photo visible to both of you',
          'us_album_mutual:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;
