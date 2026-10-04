-- ============================================================================
-- "X pinged you back" push (explicit request, 2026-10-02): answering a ping
-- or a reply with a fresh ping ("Ping back" on the Open Loops row, a
-- revealed reply, or a photo-reply viewer's CTA) used to land as the
-- ordinary notify_ping push — "X pinged you 💭" — same as a brand new ping,
-- which read wrong. A text-reply ping back (the one-tap 👋 on a promptless
-- ping) already got its own push via notify_ping_reply; this covers the
-- OTHER ping-back path, which goes through send_ping/notify_ping.
--
-- send_ping_back() is send_ping() with one added bit: a session-local flag
-- (`app.ping_back`) notify_ping() reads to pick its title. Nothing else
-- about the write changes — same thread/pings rows, same 5-per-24h quota,
-- same PING_ALREADY_OPEN/blocks.
--
-- Also drops the hand emoji from both this title and notify_ping_reply's
-- own 👋-reply title (client-side equivalent, 2026-10-02: "no need of
-- showing that hand emoji ... only show when they have sent a photo"), and
-- from ping_greeting()'s pool, matching the client's pingGreeting() edit.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.send_ping_back(p_receiver_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM set_config('app.ping_back', '1', true);
  RETURN public.send_ping(p_receiver_id, '');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.send_ping_back(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.ping_greeting(p_id uuid)
RETURNS text LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  WITH h AS (SELECT extract(hour FROM now() AT TIME ZONE 'Asia/Kolkata')::int AS hr),
  pool AS (
    SELECT CASE
      WHEN hr >= 5  AND hr < 12 THEN ARRAY['Good morning ☀️','Morning! Slept well? 😴','Rise and shine 🌅','Hola, early bird 🐦','Coffee yet? ☕']
      WHEN hr >= 12 AND hr < 17 THEN ARRAY['Hey, what''s up?','Hello hello 😄','Lunch done? 🍛','Afternoon check-in ✌️','Hola! How''s the day going? 🌤️']
      WHEN hr >= 17 AND hr < 22 THEN ARRAY['Good evening 🌆','Hey! How was your day? 😊','What''s up tonight? 🎧','Evening vibes ✨','Hola, free to talk?']
      ELSE ARRAY['Still up? 🌙','Late night hello 🦉','Can''t sleep either? 😅','Hey night owl ✨','Psst… you awake? 👀']
    END AS a FROM h
  )
  SELECT a[1 + (abs(hashtext(p_id::text)) % 5)] FROM pool;
$$;

CREATE OR REPLACE FUNCTION public.notify_ping()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_who text; v_src uuid; v_src_type text; v_src_vis text; v_title text; v_is_back boolean;
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

  v_is_back := COALESCE(current_setting('app.ping_back', true), '') = '1';

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
    WHEN v_is_back
      THEN COALESCE(v_who, 'Someone') || ' pinged you back'
    WHEN v_src_type = 'us'
      THEN COALESCE(v_who, 'Someone') || ' pinged you from your Duo post 💞'
    WHEN v_src_vis = 'anonymous'
      THEN COALESCE(v_who, 'Someone') || ' pinged you about your Anon 👀'
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
          -- A promptless ping (Friends feed / Ping page / ping back) has
          -- prompt '' — no greeting body for a ping back, which already
          -- says enough in its title; the ordinary promptless case still
          -- gets ping_greeting()'s body.
          CASE WHEN v_is_back THEN NULL
               ELSE COALESCE(NULLIF(btrim(NEW.prompt), ''), public.ping_greeting(NEW.id))
          END,
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
    -- The one-tap "Ping back" reply — no hand emoji in the title any more
    -- (client-side equivalent: PingPage._cardLine / kPromptlessReplyTo).
    v_title := COALESCE(v_who, 'Someone') || ' pinged you back';
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

COMMIT;
