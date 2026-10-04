-- Product-facing rename: "Us Album" -> "Duo" (explicit instruction: "the us
-- album rename it is as duo as such"). Client-side strings already updated
-- in my_profile_screen.dart / their_profile_screen.dart.
--
-- These three server-side notification titles are the only LIVE (not
-- migration-file-stale) places that still said "Us album" to an actual
-- user. notify_us_album_mutual's live title was already "Someone made a
-- photo visible to both of you" (the migration file's older wording never
-- made it live) -- nothing to change there.
--
-- Every function reproduced VERBATIM from its live pg_get_functiondef,
-- with ONLY the notification title text changed. Column/table/type names
-- (us_albums, us_album_invite, screen: 'us_album') are left exactly as-is
-- -- this is a display-text rename, not a schema rename.
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
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  VALUES (v_recipient, 'us_album_invite', NEW.created_by, 'major',
          v_name || ' started a Duo with you',
          jsonb_build_object('screen','us_album','album_id', NEW.id),
          'us_album_invite:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

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
    WHEN 'album'  THEN 'Your first Duo, with ' || COALESCE(p_label,'them') || ' 💙'
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

CREATE OR REPLACE FUNCTION public.notify_activation_drip(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_win   text := public.notification_window(p_at);
  v_dips  int;
  r record; st record; v_missing text[]; v_pick text; v_title text; v_age int;
  n int := 0;
BEGIN
  SELECT count(*)::int INTO v_dips FROM public.posts p
   WHERE p.visibility='anonymous' AND p.deleted_at IS NULL
     AND ((p.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date = v_today;

  PERFORM set_config('app.notif_trusted', 'on', true);

  FOR r IN
    SELECT u.id, u.created_at,
           EXTRACT(EPOCH FROM (p_at - (u.created_at AT TIME ZONE 'UTC')))/3600.0 AS hours_old
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  LOOP
    SELECT * INTO st FROM public.activation_state(r.id);
    CONTINUE WHEN st.complete;          -- §6.5: stops entirely. Graduated.

    -- Stage 1 — welcome, first hour.
    IF r.hours_old <= 1 THEN
      INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
      VALUES (r.id, 'activation_nudge', 'standard',
              'Drop your first Dip — takes 10 seconds.',
              jsonb_build_object('screen','composer','feed_scope','anon'),
              'activation_nudge:' || r.id::text || ':install')
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
      n := n + 1;
      CONTINUE;
    END IF;

    -- Stage 2 — +3h, only if they still have not dipped.
    IF r.hours_old >= 3
       AND NOT EXISTS (SELECT 1 FROM public.posts p
                        WHERE p.user_id = r.id AND p.visibility='anonymous'
                          AND p.deleted_at IS NULL) THEN
      INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
      VALUES (r.id, 'activation_nudge', 'standard',
              CASE WHEN v_dips > 0
                   THEN 'Still haven''t dipped? ' || v_dips || ' people already have today.'
                   ELSE 'Still haven''t dipped? Be the first today.' END,
              jsonb_build_object('screen','composer','feed_scope','anon'),
              'activation_nudge:' || r.id::text || ':plus3h')
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
      n := n + 1;
      CONTINUE;
    END IF;

    -- Stage 3 — daily rotating nudge, evening or last call only, once a day.
    CONTINUE WHEN v_win NOT IN ('evening','last_call');
    CONTINUE WHEN r.hours_old < 3;

    v_missing := ARRAY[]::text[];
    -- THE FIX (see header): array_append, not `|| 'literal'`.
    IF NOT st.has_group  THEN v_missing := array_append(v_missing, 'group');  END IF;
    IF NOT st.has_album  THEN v_missing := array_append(v_missing, 'album');  END IF;
    IF NOT st.has_circle THEN v_missing := array_append(v_missing, 'circle'); END IF;
    CONTINUE WHEN cardinality(v_missing) = 0;

    v_age  := GREATEST(0, (v_today - (r.created_at AT TIME ZONE 'UTC')::date));
    v_pick := v_missing[(v_age % cardinality(v_missing)) + 1];

    v_title := CASE v_pick
      WHEN 'group'  THEN 'You haven''t joined or made a group yet — that''s where your people actually are.'
      WHEN 'album'  THEN 'Got someone you''re close with? Start a Duo — it''s just the two of you.'
      ELSE               'Make a Circle — pick exactly who sees your next post.'
    END;

    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.id, 'activation_nudge', 'standard', v_title,
            jsonb_build_object('screen',
              CASE v_pick WHEN 'group' THEN 'groups'
                          WHEN 'album' THEN 'profile'
                          ELSE 'circles' END),
            'activation_nudge:' || r.id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
