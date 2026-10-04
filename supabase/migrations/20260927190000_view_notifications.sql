-- View notifications + ping-like copy (2026-09-27).
--
-- User ask: "if someone unpinned views their profile it shall go like
-- 'someone from X department viewed your profile', and if they opened their
-- group profile then to all the members 'someone in X department opened
-- your group profile'".
--
-- 1. notify_branch_view: previously gated on 100+ students in the viewer's
--    branch, a threshold far above this campus's size, so it had NEVER fired
--    (0 rows ever). The gate now follows the app's existing convention: the
--    in-app "Viewed by" list already shows unpinned viewers as "someone in
--    CV" with no threshold (profile_view_service.dart _anonLabel), and branch
--    is on public profiles. The show_branch_signal opt-out is kept. Pinned
--    viewers are skipped (notify_pinned_profile_view covers them). At most one
--    per branch per day, and the dedupe key never carries the viewer id.
--    Viewers with no branch on file read "Someone viewed your profile".
-- 2. New notify_group_profile_view on group_profile_views (122 rows, no
--    trigger until now): every member hears that someone from X opened their
--    group's profile. Members viewing their own group are skipped. One per
--    group per member per day.
-- 3. A 'views' push cap: branch_view + group_profile_view push at most 3/day
--    per person (the rest stay in-app).
-- 4. toggle_ping_reply_reaction: "Your photo got a ❤️" was wrong for text
--    replies, which can now be liked too (ping_page.dart).

UPDATE public.app_config SET value = '1'::jsonb WHERE key = 'visitor_branch_min_students';

ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['reaction'::text, 'ping'::text, 'branch_view'::text, 'us_album_mutual'::text, 'report_resolved'::text, 'report_filed'::text, 'announcement'::text, 'ping_answered'::text, 'us_album_invite'::text, 'comment'::text, 'moment_contribution'::text, 'group_added'::text, 'group_invite'::text, 'group_post'::text, 'group_dip'::text, 'community_post'::text, 'friend_post'::text, 'streak_risk_red'::text, 'streak_risk_blue'::text, 'streak_milestone_blue'::text, 'group_streak_ping'::text, 'group_streak_risk'::text, 'group_streak_broken'::text, 'level_up'::text, 'level_progress'::text, 'leaderboard_movement'::text, 'ping_unanswered'::text, 'group_ping_waiting'::text, 'group_ping_replied'::text, 'pinned_post_view'::text, 'pinned_group_post_view'::text, 'moment_new_post'::text, 'moment_reply_nudge'::text, 'pinned_profile_view'::text, 'rank_overtaken'::text, 'rank_regained'::text, 'streak_rank_overtaken'::text, 'start_streak_nudge'::text, 'streak_standing'::text, 'window_prompt'::text, 'break_live_count'::text, 'midday_report'::text, 'day_digest'::text, 'lifecycle_cooling'::text, 'lifecycle_lapsed'::text, 'lifecycle_dormant'::text, 'activation_nudge'::text, 'graduation'::text, 'ping_reply_liked'::text, 'us_album_accepted'::text, 'group_profile_view'::text])));

-- Viewer's department phrase: 'Someone in CS' / 'Someone' (no branch, or
-- the viewer turned the branch signal off).
CREATE OR REPLACE FUNCTION public.viewer_branch_phrase(p_viewer uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (SELECT 'Someone in ' || upper(btrim(p.branch))
       FROM public.users u JOIN public.profiles p ON p.id = u.auth_id
      WHERE u.id = p_viewer
        AND NULLIF(btrim(p.branch), '') IS NOT NULL
        AND p.show_branch_signal IS TRUE
        AND (SELECT count(*) FROM public.branch_student_counts() b
              WHERE b.branch = p.branch AND b.student_count >=
                    COALESCE((SELECT (value #>> '{}')::int FROM public.app_config
                               WHERE key = 'visitor_branch_min_students'), 1)) > 0),
    'Someone');
$function$;

CREATE OR REPLACE FUNCTION public.notify_branch_view()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_who text; v_day text;
BEGIN
  IF NEW.viewer_id = NEW.viewed_user_id THEN RETURN NEW; END IF;
  -- Pinned viewers get their own notification (notify_pinned_profile_view).
  IF COALESCE(public.is_pinned_by(NEW.viewed_user_id, NEW.viewer_id), false) THEN
    RETURN NEW;
  END IF;
  v_who := public.viewer_branch_phrase(NEW.viewer_id);
  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  VALUES (NEW.viewed_user_id, 'branch_view', NULL, 'standard',
          v_who || ' viewed your profile 👀',
          jsonb_build_object('screen','profile'),
          -- No viewer id in the key: the recipient can read their own rows.
          'branch_view:' || NEW.viewed_user_id::text || ':' || v_who || ':' || v_day)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.notify_group_profile_view()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_group text; v_who text; v_day text;
BEGIN
  IF public.is_group_member(NEW.group_id, NEW.viewer_id) THEN RETURN NEW; END IF;
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  v_who := public.viewer_branch_phrase(NEW.viewer_id);
  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  SELECT gm.user_id, 'group_profile_view', NULL, 'standard',
         v_who || ' opened ' || v_group || '''s profile 👀',
         jsonb_build_object('screen','group','group_id', NEW.group_id),
         'group_profile_view:' || NEW.group_id::text || ':' || gm.user_id::text || ':' || v_day
    FROM public.group_members gm
   WHERE gm.group_id = NEW.group_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_notify_group_profile_view ON public.group_profile_views;
CREATE TRIGGER trg_notify_group_profile_view
  AFTER INSERT ON public.group_profile_views
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_profile_view();

REVOKE EXECUTE ON FUNCTION public.notify_group_profile_view() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.viewer_branch_phrase(uuid) FROM PUBLIC, anon, authenticated;

-- 'views' cap added to the push-slot trigger (see 20260927180000).
CREATE OR REPLACE FUNCTION public.set_notification_push_slot()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_group text;
  v_cap   int;
  v_types text[];
  v_day   date := (COALESCE(NEW.created_at, now()) AT TIME ZONE 'Asia/Kolkata')::date;
  v_used  int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_lifecycle ul
              WHERE ul.user_id = NEW.recipient_id
                AND ul.segment = 'dormant'
                AND ul.dormant_notified_at IS NOT NULL) THEN
    NEW.push_after := NULL;
    RETURN NEW;
  END IF;

  IF NEW.push_sent_at IS NULL THEN
    IF NEW.type = 'window_prompt'
       AND split_part(COALESCE(NEW.dedupe_key, ''), ':', 4) NOT IN ('lunch', 'evening') THEN
      NEW.push_after := NULL;
      RETURN NEW;
    END IF;

    v_group := CASE
      WHEN NEW.type IN ('window_prompt','streak_standing','leaderboard_movement',
                        'rank_overtaken','rank_regained','streak_rank_overtaken',
                        'level_progress','day_digest','midday_report',
                        'start_streak_nudge','activation_nudge','lifecycle_cooling',
                        'break_live_count','moment_reply_nudge') THEN 'promo'
      WHEN NEW.type IN ('streak_risk_red','streak_risk_blue','group_streak_risk') THEN 'streak'
      WHEN NEW.type IN ('ping_unanswered','group_ping_waiting') THEN 'reminder'
      WHEN NEW.type IN ('branch_view','group_profile_view') THEN 'views'
      ELSE NULL END;

    IF v_group IS NOT NULL THEN
      v_cap := CASE v_group WHEN 'reminder' THEN 4 ELSE 3 END;
      v_types := CASE v_group
        WHEN 'promo' THEN ARRAY['window_prompt','streak_standing','leaderboard_movement',
                                'rank_overtaken','rank_regained','streak_rank_overtaken',
                                'level_progress','day_digest','midday_report',
                                'start_streak_nudge','activation_nudge','lifecycle_cooling',
                                'break_live_count','moment_reply_nudge']
        WHEN 'streak' THEN ARRAY['streak_risk_red','streak_risk_blue','group_streak_risk']
        WHEN 'views'  THEN ARRAY['branch_view','group_profile_view']
        ELSE ARRAY['ping_unanswered','group_ping_waiting'] END;
      SELECT count(*) INTO v_used
        FROM public.notifications n
       WHERE n.recipient_id = NEW.recipient_id
         AND n.type = ANY(v_types)
         AND n.push_after IS NOT NULL
         AND n.created_at >= (v_day::timestamp AT TIME ZONE 'Asia/Kolkata');
      IF v_used >= v_cap THEN
        NEW.push_after := NULL;
        RETURN NEW;
      END IF;
    END IF;

    IF NEW.push_after IS NULL THEN
      NEW.push_after := public.next_push_slot(NEW.tier, NEW.type, COALESCE(NEW.created_at, now()));
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- Like notification copy: text replies can now be liked too.
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
  v_existed  boolean;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  SELECT p.sender_id, r.replier_id, r.ping_id, p.group_id, p.thread_id, r.photo_url
    INTO v_sender, v_replier, v_ping_id, v_group, v_thread, v_photo
  FROM public.ping_replies r
  JOIN public.pings p ON p.id = r.ping_id
  WHERE r.id = p_reply_id AND r.deleted_at IS NULL;

  IF v_ping_id IS NULL THEN
    RAISE EXCEPTION 'reply not found';
  END IF;

  -- Branch on group_id, NOT thread_id (1:1 pings carry a thread_id too).
  IF v_group IS NULL THEN
    -- 1:1 (anonymous or not): only the ping's sender may react.
    IF v_sender IS DISTINCT FROM v_me THEN
      RAISE EXCEPTION 'only the ping sender can react to this reply';
    END IF;
  ELSE
    -- Group wall: anyone who has answered may react, never to their own.
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
      INSERT INTO public.notifications
        (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
      VALUES (v_replier, 'ping_reply_liked', v_me, 'minor',
              CASE WHEN v_photo IS NULL THEN 'Your reply got a ❤️' ELSE 'Your photo got a ❤️' END,
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
