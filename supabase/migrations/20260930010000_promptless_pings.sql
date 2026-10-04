-- Promptless pings (user decision 2026-09-30): pinging a person from the
-- Friends feed or the Ping page no longer asks for a prompt — it sends
-- instantly with prompt = ''. Prompts stay for Dip and group pings.
-- The receiver can answer three ways, all of which are ordinary
-- ping_replies (so all count for the streak): a photo, text, or a one-tap
-- "Ping back", which the app sends as a text reply of '👋'.
--
--  * notify_ping: an empty prompt means no notification body.
--  * notify_ping_reply: a '👋' reply reads "X pinged you back 👋".
CREATE OR REPLACE FUNCTION public.notify_ping()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_who text; v_src uuid; v_src_type text; v_src_vis text; v_title text;
BEGIN
  IF NEW.receiver_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sender_id = NEW.receiver_id THEN RETURN NEW; END IF;

  IF NEW.anonymous IS TRUE THEN
    SELECT NULLIF(btrim(t.anon_display_name), '') INTO v_who
      FROM public.ping_threads t WHERE t.id = NEW.thread_id;
  ELSE
    SELECT COALESCE(NULLIF(btrim(name), ''), anon_name) INTO v_who
      FROM public.users WHERE id = NEW.sender_id;
  END IF;

  BEGIN
    v_src := NULLIF(current_setting('app.ping_source_post', true), '')::uuid;
  EXCEPTION WHEN others THEN
    v_src := NULL;
  END;
  IF v_src IS NOT NULL THEN
    SELECT post_type, visibility INTO v_src_type, v_src_vis
      FROM public.posts WHERE id = v_src;
  END IF;

  v_title := CASE
    WHEN v_src_type = 'us'
      THEN COALESCE(v_who, 'Someone') || ' pinged you from your Duo post 💞'
    WHEN v_src_vis = 'anonymous'
      THEN COALESCE(v_who, 'Someone') || ' pinged you about your Dip 👀'
    WHEN v_src IS NOT NULL
      THEN COALESCE(v_who, 'Someone') || ' pinged you about your post 💭'
    WHEN NEW.anonymous IS TRUE
      THEN COALESCE(v_who, 'Someone') || ' is thinking about you 👀'
    ELSE COALESCE(v_who, 'Someone') || ' pinged you 💭'
  END;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.receiver_id, 'ping',
          CASE WHEN NEW.anonymous IS TRUE THEN NULL ELSE NEW.sender_id END,
          'major', v_title,
          -- A promptless ping (Friends feed / Ping page) has prompt '' —
          -- no body at all rather than an empty one.
          NULLIF(btrim(NEW.prompt), ''),
          jsonb_build_object('screen','ping','ping_id', NEW.id, 'source_post_id', v_src),
          'ping:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_ping_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_sender uuid; v_who text; v_title text; v_body text;
BEGIN
  SELECT sender_id INTO v_sender FROM public.pings WHERE id = NEW.ping_id;
  IF v_sender IS NULL OR v_sender = NEW.replier_id THEN RETURN NEW; END IF;

  -- The replier is always identified to the ping's sender.
  SELECT COALESCE(NULLIF(btrim(name), ''), anon_name) INTO v_who
    FROM public.users WHERE id = NEW.replier_id;

  IF NEW.photo_url IS NULL AND btrim(COALESCE(NEW.body, '')) = '👋' THEN
    -- The one-tap "Ping back" reply.
    v_title := COALESCE(v_who, 'Someone') || ' pinged you back 👋';
    v_body := NULL;
  ELSE
    v_title := 'Your ping got an answer 🔥';
    v_body := 'Dekho kya bola 👀';
  END IF;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (v_sender, 'ping_answered', NEW.replier_id, 'major',
          v_title, v_body,
          jsonb_build_object('screen','ping_reveal','ping_id', NEW.ping_id, 'ping_reply_id', NEW.id),
          'ping_answered:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;
