-- ============================================================================
-- Ping-back and photo-reply notifications say WHO and carry the STREAK
-- (explicit request, 2026-10-03: "pinging them back, they shall receive a
-- notification 'X pinged you back — streak now increased to …'; and if
-- they replied via photo, show them like that").
--
-- notify_ping_reply (a reply to MY ping lands):
--   * one-tap ping back (👋, no photo):  "X pinged you back"
--   * photo reply:                      "X sent you a photo 📸"
--   * words:                            "X replied to your ping"
--   Body, for a one-to-one ping with a live streak:
--     "🔥 Streak now increased to N"  — when THIS reply is the first
--                                       exchange between the two of them
--                                       today (IST), i.e. the one that
--                                       moved the streak;
--     "🔥 Streak: N"                   — otherwise (already counted today).
--   Group pings keep no streak line: the pair streak is one-to-one.
--
-- notify_ping, ping-back path (send_ping_back): the same "X pinged you
-- back" title, with the current streak in the body. A NEW ping doesn't
-- complete an exchange, so it never claims an increase.
--
-- Both are rewritten from the versions in 20261002000000_ping_back_push.sql
-- (diffed against live before applying — identical but for whitespace).
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

-- The pair's streak line, or NULL when there is no streak to talk about.
CREATE OR REPLACE FUNCTION public.ping_streak_line(
  p_a uuid,
  p_b uuid,
  p_reply uuid DEFAULT NULL
)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_streak int;
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_earlier boolean;
BEGIN
  IF p_a IS NULL OR p_b IS NULL OR p_a = p_b THEN RETURN NULL; END IF;
  v_streak := COALESCE(public.ping_streak_between(p_a, p_b), 0);
  IF v_streak <= 0 THEN RETURN NULL; END IF;

  -- No reply given = a fresh ping (send_ping_back): never an increase.
  IF p_reply IS NULL THEN
    RETURN '🔥 Streak: ' || v_streak;
  END IF;

  -- Did these two already complete an exchange earlier today? If not,
  -- this reply is the one that moved the streak.
  SELECT EXISTS (
    SELECT 1 FROM public.ping_replies r2
      JOIN public.pings p2 ON p2.id = r2.ping_id
     WHERE r2.id <> p_reply
       AND p2.group_id IS NULL
       AND ((p2.sender_id = p_a AND r2.replier_id = p_b)
         OR (p2.sender_id = p_b AND r2.replier_id = p_a))
       AND (r2.created_at::timestamptz AT TIME ZONE 'Asia/Kolkata')::date = v_today
  ) INTO v_earlier;

  RETURN CASE WHEN v_earlier
              THEN '🔥 Streak: ' || v_streak
              ELSE '🔥 Streak now increased to ' || v_streak
         END;
END;
$function$;

REVOKE ALL ON FUNCTION public.ping_streak_line(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_ping_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_sender uuid; v_group uuid; v_who text; v_title text; v_body text;
BEGIN
  SELECT sender_id, group_id INTO v_sender, v_group
    FROM public.pings WHERE id = NEW.ping_id;
  IF v_sender IS NULL OR v_sender = NEW.replier_id THEN RETURN NEW; END IF;

  -- The replier is always identified to the ping's sender.
  SELECT COALESCE(NULLIF(btrim(name), ''), anon_name) INTO v_who
    FROM public.users WHERE id = NEW.replier_id;
  v_who := COALESCE(v_who, 'Someone');

  IF NEW.photo_url IS NULL AND btrim(COALESCE(NEW.body, '')) = '👋' THEN
    v_title := v_who || ' pinged you back';
  ELSIF NEW.photo_url IS NOT NULL THEN
    v_title := v_who || ' sent you a photo 📸';
  ELSE
    v_title := v_who || ' replied to your ping';
  END IF;

  -- Streak line for one-to-one pings only.
  IF v_group IS NULL THEN
    v_body := public.ping_streak_line(v_sender, NEW.replier_id, NEW.id);
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

CREATE OR REPLACE FUNCTION public.notify_ping()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_who text; v_src uuid; v_src_type text; v_src_vis text; v_title text; v_is_back boolean; v_body text;
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

  v_body := CASE
    -- A ping back carries the pair's current streak (a new ping doesn't
    -- complete an exchange, so it never claims an increase).
    WHEN v_is_back AND NEW.anonymous IS NOT TRUE
      THEN public.ping_streak_line(NEW.sender_id, NEW.receiver_id, NULL)
    WHEN v_is_back THEN NULL
    ELSE COALESCE(NULLIF(btrim(NEW.prompt), ''), public.ping_greeting(NEW.id))
  END;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.receiver_id, 'ping',
          CASE WHEN NEW.anonymous IS TRUE THEN NULL ELSE NEW.sender_id END,
          'major', v_title, v_body,
          jsonb_build_object('screen','ping','ping_id', NEW.id, 'source_post_id', v_src),
          'ping:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

COMMIT;
