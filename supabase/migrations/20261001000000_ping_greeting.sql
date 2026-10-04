-- ============================================================================
-- Promptless pings carry a friendly, time-of-day greeting in the push body
-- (explicit request: "hola, hello, what's up… based on time"). Same pools
-- as the app's pingGreeting(); India time. The stored prompt stays '' so
-- promptless handling is unchanged.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.ping_greeting(p_id uuid)
RETURNS text LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  WITH h AS (SELECT extract(hour FROM now() AT TIME ZONE 'Asia/Kolkata')::int AS hr),
  pool AS (
    SELECT CASE
      WHEN hr >= 5  AND hr < 12 THEN ARRAY['Good morning ☀️','Morning! Slept well? 😴','Rise and shine 🌅','Hola, early bird 🐦','Coffee yet? ☕']
      WHEN hr >= 12 AND hr < 17 THEN ARRAY['Hey, what''s up? 👋','Hello hello 😄','Lunch done? 🍛','Afternoon check-in ✌️','Hola! How''s the day going? 🌤️']
      WHEN hr >= 17 AND hr < 22 THEN ARRAY['Good evening 🌆','Hey! How was your day? 😊','What''s up tonight? 🎧','Evening vibes ✨','Hola 👋 free to talk?']
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
          -- A promptless ping (Friends feed / Ping page) has prompt '' —
          -- no body at all rather than an empty one.
          COALESCE(NULLIF(btrim(NEW.prompt), ''), public.ping_greeting(NEW.id)),
          jsonb_build_object('screen','ping','ping_id', NEW.id, 'source_post_id', v_src),
          'ping:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

COMMIT;
