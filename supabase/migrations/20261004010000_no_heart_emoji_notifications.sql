-- ============================================================================
-- No heart emoji in notifications (explicit request, 2026-10-04: "nowhere in
-- the app shall the heart emoji appear ... I meant in notifications").
--
-- Six functions wrote a heart into notification text:
--   notify_duo_post            "X posted to your Duo 💞"
--   notify_us_album_invite     "X picked you for a Duo 💞"
--   notify_ping                "X pinged you from your Duo post 💞"
--   notify_graduation          "Your first Duo, with X 💙"
--   toggle_ping_reply_reaction "X liked your photo ❤️"
--   end_duo                    "X ended your Duo 💔"
--
-- Each definition below is the LIVE one with the heart characters removed and
-- the spacing they left behind tidied; no logic is changed. The emptied
-- graduation title gained "is open." so it reads as a sentence, and the
-- already-delivered rows are cleaned at the end.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.notify_duo_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_who text;
BEGIN
  IF NEW.partner_user_id IS NULL
     OR NEW.partner_user_id = NEW.user_id
     OR NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Your Duo')
    INTO v_who FROM public.users u WHERE u.id = NEW.user_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.partner_user_id, 'duo_post', NEW.user_id, 'major',
          COALESCE(v_who, 'Your Duo') || ' posted to your Duo',
          'Choose your audience and post it to your friends too',
          jsonb_build_object(
            'screen', 'duo_post',
            'post_id', NEW.id,
            'us_album_id', NEW.us_album_id
          ),
          'duo_post:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_graduation(p_user uuid, p_kind text, p_label text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_title text;
BEGIN
  IF p_user IS NULL THEN RETURN; END IF;
  v_title := CASE p_kind
    WHEN 'group'  THEN 'You just made your first Group 🎉 — ' || COALESCE(p_label,'it') || ' is live.'
    WHEN 'album'  THEN 'Your first Duo, with ' || COALESCE(p_label,'them') || ' is open.'
    ELSE               'Your first Circle — ' || COALESCE(p_label,'it') || ' is set.'
  END;
  PERFORM set_config('app.notif_trusted', 'on', true);
  INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
  VALUES (p_user, 'graduation', 'major', v_title,
          jsonb_build_object('screen',
            CASE p_kind WHEN 'group' THEN 'groups' WHEN 'album' THEN 'profile' ELSE 'circles' END),
          'graduation:' || p_user::text || ':' || p_kind)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  PERFORM set_config('app.notif_trusted', 'off', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_us_album_invite()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_recipient uuid; v_name text;
BEGIN
  v_recipient := CASE WHEN NEW.created_by = NEW.user_a THEN NEW.user_b ELSE NEW.user_a END;
  IF v_recipient IS NULL OR v_recipient = NEW.created_by THEN RETURN NEW; END IF;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_name FROM public.users WHERE id = NEW.created_by;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (v_recipient, 'us_album_invite', NEW.created_by, 'major',
          v_name || ' picked you for a Duo',
          'One album. Just you two. Say yes?',
          jsonb_build_object('screen','us_album','album_id', NEW.id),
          'us_album_invite:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.toggle_ping_reply_reaction(p_reply_id uuid)
 RETURNS TABLE(liked boolean, reaction_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me       uuid;
  v_sender   uuid;
  v_replier  uuid;
  v_ping_id  uuid;
  v_group    uuid;
  v_thread   uuid;
  v_photo    text;
  v_anon     boolean;
  v_who      text;
  v_existed  boolean;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  SELECT p.sender_id, r.replier_id, r.ping_id, p.group_id, p.thread_id, r.photo_url, p.anonymous
    INTO v_sender, v_replier, v_ping_id, v_group, v_thread, v_photo, v_anon
  FROM public.ping_replies r
  JOIN public.pings p ON p.id = r.ping_id
  WHERE r.id = p_reply_id AND r.deleted_at IS NULL;

  IF v_ping_id IS NULL THEN
    RAISE EXCEPTION 'reply not found';
  END IF;

  IF v_group IS NULL THEN
    IF v_sender IS DISTINCT FROM v_me THEN
      RAISE EXCEPTION 'only the ping sender can react to this reply';
    END IF;
  ELSE
    IF v_replier IS NOT DISTINCT FROM v_me THEN
      RAISE EXCEPTION 'cannot react to your own reply';
    END IF;
    IF NOT public.has_answered_thread(v_thread, v_me) THEN
      RAISE EXCEPTION 'answer this wall before reacting to it';
    END IF;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.ping_reply_reactions
     WHERE reply_id = p_reply_id AND reactor_id = v_me
  ) INTO v_existed;

  IF v_existed THEN
    DELETE FROM public.ping_reply_reactions
     WHERE reply_id = p_reply_id AND reactor_id = v_me;
  ELSE
    INSERT INTO public.ping_reply_reactions (reply_id, reactor_id)
    VALUES (p_reply_id, v_me)
    ON CONFLICT (reply_id, reactor_id) DO NOTHING;

    IF v_replier IS DISTINCT FROM v_me THEN
      IF v_group IS NULL AND v_anon IS TRUE THEN
        SELECT NULLIF(btrim(anon_display_name), '') INTO v_who
          FROM public.ping_threads WHERE id = v_thread;
      ELSE
        SELECT COALESCE(NULLIF(btrim(name), ''), anon_name) INTO v_who
          FROM public.users WHERE id = v_me;
      END IF;

      INSERT INTO public.notifications
        (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
      VALUES (v_replier, 'ping_reply_liked',
              CASE WHEN v_group IS NULL AND v_anon IS TRUE THEN NULL ELSE v_me END,
              'minor',
              COALESCE(v_who, 'Someone') || ' liked your '
                || CASE WHEN v_photo IS NULL THEN 'reply' ELSE 'photo' END,
              NULL,
              jsonb_build_object('screen','ping_reveal','ping_id', v_ping_id, 'ping_reply_id', p_reply_id),
              'ping_reply_liked:' || p_reply_id::text || ':' || v_me::text)
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    END IF;
  END IF;

  RETURN QUERY
  SELECT (NOT v_existed),
         (SELECT count(*)::int FROM public.ping_reply_reactions WHERE reply_id = p_reply_id);
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
      THEN COALESCE(v_who, 'Someone') || ' pinged you from your Duo post'
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

CREATE OR REPLACE FUNCTION public.end_duo(p_album uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id(); v_album public.us_albums%ROWTYPE;
        v_other uuid; v_name text;
BEGIN
  SELECT * INTO v_album FROM public.us_albums WHERE id = p_album;
  IF v_album.id IS NULL OR v_me IS NULL OR v_me NOT IN (v_album.user_a, v_album.user_b) THEN
    RAISE EXCEPTION 'Duo not found';
  END IF;
  v_other := CASE WHEN v_album.user_a = v_me THEN v_album.user_b ELSE v_album.user_a END;

  DELETE FROM public.us_albums WHERE id = p_album;

  IF v_album.status = 'accepted' AND v_other IS NOT NULL THEN
    SELECT COALESCE(NULLIF(btrim(name), ''), anon_name, 'Someone') INTO v_name
      FROM public.users WHERE id = v_me;
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    VALUES (v_other, 'us_album_ended', v_me, 'standard',
            v_name || ' ended your Duo',
            jsonb_build_object('screen','profile'),
            'us_album_ended:' || p_album::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;
END $function$;

-- lock_notification_fields() silently reverts title/body edits unless this
-- trusted flag is set (the same switch the server-side writers use).
select set_config('app.notif_trusted','on',false);
update public.notifications
   set title = btrim(regexp_replace(title, '[❤♥💞💙💛💚💜🖤🤍🤎🧡💕💖💗💓💔💘💝💟😍🥰]️?', '', 'g')),
       body  = nullif(btrim(regexp_replace(coalesce(body,''), '[❤♥💞💙💛💚💜🖤🤍🤎🧡💕💖💗💓💔💘💝💟😍🥰]️?', '', 'g')), '')
 where title ~ '[❤♥💞💙💛💚💜🖤🤍🤎🧡💕💖💗💓💔💘💝💟😍🥰]️?' or coalesce(body,'') ~ '[❤♥💞💙💛💚💜🖤🤍🤎🧡💕💖💗💓💔💘💝💟😍🥰]️?';
select set_config('app.notif_trusted','off',false);

COMMIT;
