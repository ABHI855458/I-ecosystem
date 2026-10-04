-- PHASE 6A — the NEW segment's own content (spec §6.5 drip + §6.6A graduations).
--
-- Phase 6 built the segmenter that classifies a user as NEW; this is what NEW
-- actually receives. A user is NEW until all three activation artefacts exist
-- (a Group, an accepted Us album, a Circle), and the drip stops permanently
-- at that point — §6.5: "Stops entirely once the user has all three."
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY[
    'reaction','ping','friend_request','friend_accepted','branch_view',
    'us_album_mutual','report_resolved','report_filed','announcement',
    'ping_answered','us_album_invite','comment','moment_contribution',
    'group_added','group_post','group_dip','community_post','friend_post',
    'streak_risk_red','streak_risk_blue','streak_milestone_blue',
    'group_streak_ping','group_streak_risk','group_streak_broken',
    'level_up','level_progress','leaderboard_movement','ping_unanswered',
    'group_ping_waiting','group_ping_replied','pinned_post_view',
    'moment_new_post','moment_reply_nudge','pinned_profile_view',
    'rank_overtaken','rank_regained','streak_rank_overtaken',
    'start_streak_nudge','streak_standing',
    'window_prompt','break_live_count','midday_report','day_digest',
    'lifecycle_cooling','lifecycle_lapsed','lifecycle_dormant',
    'activation_nudge','graduation'                              -- Phase 6A
  ])
);

-- A single reusable predicate for "has this person finished activating".
-- Used by the drip (to stop), by the graduation triggers (to detect the
-- LAST one), and it mirrors recalc_lifecycle's own NEW/MID boundary.
CREATE OR REPLACE FUNCTION public.activation_state(p_user uuid)
RETURNS TABLE(has_group boolean, has_album boolean, has_circle boolean, complete boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT g, a, c, (g AND a AND c)
    FROM (SELECT
      EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.user_id = p_user) AS g,
      EXISTS (SELECT 1 FROM public.us_albums al
               WHERE (al.user_a = p_user OR al.user_b = p_user) AND al.status='accepted') AS a,
      EXISTS (SELECT 1 FROM public.circles ci WHERE ci.creator_id = p_user) AS c
    ) s;
$function$;

-- ========================= §6.5 ACTIVATION DRIP ========================
-- Three stages, all keyed off REAL state:
--   1. within the first hour of the account existing
--   2. +3h, only if they still have not posted anonymously
--   3. daily thereafter, ONE rotating nudge for whichever artefact is still
--      missing — never all three stacked into one notification
--
-- Stage 2 quotes the day's real Dip count. §6.5 forbids padding it and says
-- to frame a small number with momentum instead of size, so a zero count
-- changes the sentence rather than printing "0 people".
--
-- Rotation uses the account's age in days modulo the number of still-missing
-- artefacts, so a user missing two of them alternates instead of hearing
-- about the same one every evening.
CREATE OR REPLACE FUNCTION public.notify_activation_drip(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
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
    IF NOT st.has_group  THEN v_missing := v_missing || 'group';  END IF;
    IF NOT st.has_album  THEN v_missing := v_missing || 'album';  END IF;
    IF NOT st.has_circle THEN v_missing := v_missing || 'circle'; END IF;
    CONTINUE WHEN cardinality(v_missing) = 0;

    v_age  := GREATEST(0, (v_today - (r.created_at AT TIME ZONE 'UTC')::date));
    v_pick := v_missing[(v_age % cardinality(v_missing)) + 1];

    v_title := CASE v_pick
      WHEN 'group'  THEN 'You haven''t joined or made a group yet — that''s where your people actually are.'
      WHEN 'album'  THEN 'Got someone you''re close with? Start a Us album — it''s just the two of you.'
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

-- ====================== §6.6A GRADUATION CELEBRATIONS ==================
-- "fires the moment each of the three is completed for the FIRST time —
--  real, immediate, positive reinforcement, separate from the nudge that
--  led to it."
--
-- MAJOR so it lands immediately rather than queueing behind a window: the
-- whole value is that it arrives while the user is still looking at the
-- thing they just made.
--
-- "First time" is enforced by the dedupe key, which carries the user and the
-- artefact kind but NO id and NO date — so a second group, or leaving and
-- rejoining, can never re-fire it.
CREATE OR REPLACE FUNCTION public.notify_graduation(p_user uuid, p_kind text, p_label text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_title text;
BEGIN
  IF p_user IS NULL THEN RETURN; END IF;
  v_title := CASE p_kind
    WHEN 'group'  THEN 'You just made your first Group 🎉 — ' || COALESCE(p_label,'it') || ' is live.'
    WHEN 'album'  THEN 'Your first Us album, with ' || COALESCE(p_label,'them') || ' 💙'
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

CREATE OR REPLACE FUNCTION public.trg_graduation_group()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_name text;
BEGIN
  SELECT name INTO v_name FROM public.groups WHERE id = NEW.group_id;
  PERFORM public.notify_graduation(NEW.user_id, 'group', v_name);
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.trg_graduation_circle()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
BEGIN
  PERFORM public.notify_graduation(NEW.creator_id, 'circle', NEW.name);
  RETURN NEW;
END; $function$;

-- Album graduation fires on ACCEPTANCE, not on invite: an album that the
-- other person never accepted is not an album, and celebrating it would be
-- the kind of fabricated milestone §6.6 exists to prevent. Both people
-- graduate, since it becomes each of their first album at the same moment.
CREATE OR REPLACE FUNCTION public.trg_graduation_album()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_a text; v_b text;
BEGIN
  IF NEW.status <> 'accepted' OR COALESCE(OLD.status,'') = 'accepted' THEN RETURN NEW; END IF;
  SELECT name INTO v_a FROM public.users WHERE id = NEW.user_a;
  SELECT name INTO v_b FROM public.users WHERE id = NEW.user_b;
  PERFORM public.notify_graduation(NEW.user_a, 'album', v_b);
  PERFORM public.notify_graduation(NEW.user_b, 'album', v_a);
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_notify_graduation_group ON public.group_members;
CREATE TRIGGER trg_notify_graduation_group AFTER INSERT ON public.group_members
FOR EACH ROW EXECUTE FUNCTION public.trg_graduation_group();

DROP TRIGGER IF EXISTS trg_notify_graduation_circle ON public.circles;
CREATE TRIGGER trg_notify_graduation_circle AFTER INSERT ON public.circles
FOR EACH ROW EXECUTE FUNCTION public.trg_graduation_circle();

DROP TRIGGER IF EXISTS trg_notify_graduation_album ON public.us_albums;
CREATE TRIGGER trg_notify_graduation_album AFTER UPDATE ON public.us_albums
FOR EACH ROW EXECUTE FUNCTION public.trg_graduation_album();
