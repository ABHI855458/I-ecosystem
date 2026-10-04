-- PHASE 7a — the two streak/ping notifications that still had no fixing link.
--
-- Sweep result: 9 of 11 streak/ping reminders already deep-link into the
-- action that resolves them. These two did not, and both name an action in
-- their own copy, which is exactly the case §7 is about — a notification
-- that tells you what to do and then drops you on a tab.
CREATE OR REPLACE FUNCTION public.notify_pair_streak_milestone()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_sender uuid; v_streak int; v_a_name text; v_b_name text;
BEGIN
  SELECT sender_id INTO v_sender FROM public.pings WHERE id = NEW.ping_id;
  IF v_sender IS NULL OR v_sender = NEW.replier_id THEN RETURN NEW; END IF;
  v_streak := public.ping_streak_between(v_sender, NEW.replier_id);
  IF v_streak NOT IN (7, 30, 100) THEN RETURN NEW; END IF;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_a_name FROM public.users WHERE id = v_sender;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_b_name FROM public.users WHERE id = NEW.replier_id;

  -- Deep link to the ping thread with that person: the celebration is about
  -- a shared streak, so the useful next tap is the conversation it came from,
  -- not the app's front door.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  VALUES (v_sender, 'streak_milestone_blue', NEW.replier_id, 'major',
          'You + ' || v_b_name || ' hit ' || v_streak || ' days 🔵🎉',
          jsonb_build_object('screen','ping','user_id', NEW.replier_id),
          'streak_milestone_blue:' || v_sender::text || ':' || NEW.replier_id::text || ':' || v_streak)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  VALUES (NEW.replier_id, 'streak_milestone_blue', v_sender, 'major',
          'You + ' || v_a_name || ' hit ' || v_streak || ' days 🔵🎉',
          jsonb_build_object('screen','ping','user_id', v_sender),
          'streak_milestone_blue:' || NEW.replier_id::text || ':' || v_sender::text || ':' || v_streak)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;
