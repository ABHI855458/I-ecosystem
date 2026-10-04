-- Notifications: emotional copy, fewer pushes, two missing events.
--
-- User ask (2026-09-27): notifications shouldn't read like dry English; ping
-- and group streaks should be about emotion ("2 have answered, only you
-- left", "X is waiting for you — reply fast"); Duo invites should feel
-- unique; and it must NOT turn into addictive spam.
--
-- 1. Copy rewritten (light Hinglish) for pings, ping reminders, group pings,
--    streak alerts, streak milestones/breaks, Duo invites, prompts.
-- 2. Anti-spam, enforced in ONE place (set_notification_push_slot, BEFORE
--    INSERT). A capped row is still written — it shows in the in-app list —
--    it just never pushes (push_after NULL; claim_due_notifications skips
--    those):
--      * window_prompt pushes only in the lunch + evening windows (was 8/day)
--      * "promo" nudges (prompts, ranks, digests, levels…): max 3 pushes/day
--      * streak alerts (red/blue/group): max 3 pushes/day
--      * unanswered-ping reminders: max 4 pushes/day
--    Direct human events (a ping, a comment, an invite, a Duo) are never
--    capped.
-- 3. Streak escalation: 2 stages (18:00 + 21:00 IST) instead of 4, and the
--    group alert goes ONLY to members who haven't replied.
-- 4. BUG FIX: the group branch of notify_streak_escalation read counts via
--    group_ping_streak(), which returns nothing without a signed-in user —
--    i.e. always, from cron. Zero group_streak_risk rows had ever been sent.
--    Counts are now computed directly.
-- 5. New: "X said yes" to the creator when a Duo is accepted, and "X
--    accepted your invite" to the inviter when a group invite is accepted.
-- 6. Plural fix ("1 days") via days_label().

-- ---------------------------------------------------------------------------
create or replace function public.days_label(n int)
returns text language sql immutable
set search_path to 'public', 'pg_temp'
as $$ select n || ' day' || case when n = 1 then '' else 's' end $$;

-- ---------------------------------------------------------------------------
-- Push caps
-- ---------------------------------------------------------------------------
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
    -- Prompts push only at lunch + evening; the other windows are in-app only.
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
      ELSE NULL END;

    IF v_group IS NOT NULL THEN
      v_cap := CASE v_group WHEN 'promo' THEN 3 WHEN 'streak' THEN 3 ELSE 4 END;
      v_types := CASE v_group
        WHEN 'promo' THEN ARRAY['window_prompt','streak_standing','leaderboard_movement',
                                'rank_overtaken','rank_regained','streak_rank_overtaken',
                                'level_progress','day_digest','midday_report',
                                'start_streak_nudge','activation_nudge','lifecycle_cooling',
                                'break_live_count','moment_reply_nudge']
        WHEN 'streak' THEN ARRAY['streak_risk_red','streak_risk_blue','group_streak_risk']
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

-- ---------------------------------------------------------------------------
-- Pings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_ping()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_name text;
BEGIN
  IF NEW.receiver_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sender_id = NEW.receiver_id THEN RETURN NEW; END IF;

  -- Named ONLY when the sender chose not to be anonymous.
  IF NEW.anonymous IS NOT TRUE THEN
    SELECT COALESCE(NULLIF(btrim(name), ''), anon_name) INTO v_name
      FROM public.users WHERE id = NEW.sender_id;
  END IF;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
  VALUES (NEW.receiver_id, 'ping',
          CASE WHEN NEW.anonymous IS TRUE THEN NULL ELSE NEW.sender_id END,
          'major',
          CASE WHEN v_name IS NULL THEN 'Someone''s thinking about you 👀'
               ELSE v_name || ' pinged you 💭' END,
          NEW.prompt, 'ping:' || NEW.id::text)
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
DECLARE v_sender uuid;
BEGIN
  SELECT sender_id INTO v_sender FROM public.pings WHERE id = NEW.ping_id;
  IF v_sender IS NULL OR v_sender = NEW.replier_id THEN RETURN NEW; END IF;

  -- Replier stays unnamed on purpose: the reveal happens on ping_reveal.
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (v_sender, 'ping_answered', NEW.replier_id, 'major',
          'Your ping got an answer 🔥', 'Dekho kya bola 👀',
          jsonb_build_object('screen','ping_reveal','ping_id', NEW.ping_id, 'ping_reply_id', NEW.id),
          'ping_answered:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_unanswered_pings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int := 0; m int;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  -- 1:1, stages at +3h and +8h. Named only for non-anonymous pings.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'ping_unanswered', NULL, 'major',
         CASE
           WHEN st.stage = 1 AND nm.name IS NOT NULL
             THEN nm.name || ' is waiting for your reply 🥺'
           WHEN st.stage = 1
             THEN 'Someone''s been waiting 3 hours for you 🥺'
           WHEN nm.name IS NOT NULL
             THEN 'Still no reply? ' || nm.name || ' keeps checking 👀'
           ELSE 'They''re still waiting… 8 hours now 😶'
         END,
         p.prompt,
         jsonb_build_object('screen','ping','ping_id', p.id),
         'ping_unanswered:' || p.id::text || ':s' || st.stage
    FROM public.pings p
    CROSS JOIN LATERAL (VALUES (1, INTERVAL '3 hours'), (2, INTERVAL '8 hours')) AS st(stage, after)
    LEFT JOIN LATERAL (
      SELECT COALESCE(NULLIF(btrim(u.name), ''), u.anon_name) AS name
        FROM public.users u
       WHERE u.id = p.sender_id AND p.anonymous IS NOT TRUE
    ) nm ON true
   WHERE p.group_id IS NULL
     AND p.receiver_id IS NOT NULL
     AND p.receiver_id <> p.sender_id
     AND p.replied_at IS NULL
     AND p.expires_at > now()
     AND now() >= (p.created_at AT TIME ZONE 'UTC') + st.after
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  -- Group, stages at +3h and +5h, non-repliers only, with the thread's real
  -- standing counted at send time.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'group_ping_waiting', NULL, 'major',
         CASE
           WHEN st.stage = 1 AND tc.replied > 0 AND tc.total - tc.replied = 1
             THEN 'Everyone in ' || COALESCE(g.name,'your group') || ' answered… except you 🥺'
           WHEN st.stage = 1 AND tc.replied > 0
             THEN tc.replied || '/' || tc.total || ' answered in '
                  || COALESCE(g.name,'your group') || ' — tu kab? 👀'
           WHEN st.stage = 1
             THEN COALESCE(g.name,'Your group') || ' is waiting for you 🫣'
           ELSE 'Still waiting on you in ' || COALESCE(g.name,'your group')
                || ' 👀 don''t leave them hanging'
         END,
         p.prompt,
         jsonb_build_object('screen','group','group_id', p.group_id, 'thread_id', p.thread_id),
         'group_ping_waiting:' || p.id::text || ':s' || st.stage
    FROM public.pings p
    JOIN public.groups g ON g.id = p.group_id
    CROSS JOIN LATERAL (VALUES (1, INTERVAL '3 hours'), (2, INTERVAL '5 hours')) AS st(stage, after)
    CROSS JOIN LATERAL (
      SELECT count(*)::int AS total,
             count(*) FILTER (WHERE t.replied_at IS NOT NULL)::int AS replied
        FROM public.pings t
       WHERE t.thread_id = p.thread_id AND t.receiver_id IS NOT NULL
    ) tc
   WHERE p.group_id IS NOT NULL
     AND p.thread_id IS NOT NULL
     AND p.receiver_id IS NOT NULL
     AND p.replied_at IS NULL
     AND p.expires_at > now()
     AND now() >= (p.created_at AT TIME ZONE 'UTC') + st.after
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Group pings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_group_ping_opened()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_group text; v_streak int; v_title text; r record;
        v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;

  -- Read directly: group_ping_streak() needs a signed-in member and returns
  -- nothing otherwise. Same freshness rule it applies.
  SELECT CASE WHEN gs.last_complete_on >= (v_today - 1) THEN COALESCE(gs.current_streak, 0) ELSE 0 END
    INTO v_streak
    FROM public.group_ping_streaks gs WHERE gs.group_id = NEW.group_id;
  v_streak := COALESCE(v_streak, 0);

  v_title := CASE WHEN v_streak > 0
                  THEN '🔥 ' || v_group || ' — ' || v_streak || '-day streak on the line. Reply now!'
                  ELSE '👋 ' || v_group || ' just pinged — reply & start a streak together' END;

  FOR r IN SELECT unnest(NEW.member_ids) AS uid LOOP
    IF r.uid <> NEW.started_by THEN
      INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
      VALUES (r.uid, 'group_streak_ping', NEW.started_by, 'major', v_title,
              jsonb_build_object('screen','group','group_id', NEW.group_id, 'thread_id', NEW.thread_id),
              'group_streak_ping:' || NEW.group_id::text || ':' || NEW.on_date::text || ':' || r.uid::text)
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_group_ping_first_reply()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_thread uuid; v_group uuid; v_name text; v_created timestamp;
BEGIN
  SELECT p.thread_id, p.group_id, p.created_at
    INTO v_thread, v_group, v_created
  FROM public.pings p WHERE p.id = NEW.ping_id;

  IF v_thread IS NULL OR v_group IS NULL THEN
    RETURN NEW;
  END IF;

  -- EARLY-ONLY. Inside the last 45 minutes before the T+3h checkpoint this
  -- would collide with, invert against, or duplicate that checkpoint.
  IF now() >= (v_created AT TIME ZONE 'UTC') + INTERVAL '2 hours 15 minutes' THEN
    RETURN NEW;
  END IF;

  SELECT name INTO v_name FROM public.groups WHERE id = v_group;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  SELECT mem.receiver_id, 'group_ping_replied', NULL, 'major',
         'First reply is in 👀 ' || COALESCE(v_name,'your group') || ' — your turn',
         jsonb_build_object('screen','group','group_id', v_group, 'thread_id', v_thread),
         'group_ping_replied:' || v_thread::text || ':' || mem.receiver_id::text
  FROM public.pings mem
  WHERE mem.thread_id = v_thread
    AND mem.receiver_id IS NOT NULL
    AND mem.receiver_id <> NEW.replier_id
    -- "your turn" only to people who haven't replied yet.
    AND NOT EXISTS (
      SELECT 1 FROM public.ping_replies rp JOIN public.pings p2 ON p2.id = rp.ping_id
       WHERE p2.thread_id = v_thread AND rp.replier_id = mem.receiver_id)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Streaks
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_streak_escalation(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_win   text := public.notification_window(p_at);
  v_stage int;
  v_tier  text;
  v_hours int := GREATEST(1, CEIL(EXTRACT(EPOCH FROM
                   ((v_today + 1)::timestamp - (p_at AT TIME ZONE 'Asia/Kolkata'))) / 3600.0)::int);
  n int := 0; r record;
BEGIN
  -- Two stages only (was four): a gentle one in the evening, a last call.
  -- The day_end / wind_down cron jobs still fire and now no-op here.
  v_stage := CASE v_win
               WHEN 'evening'   THEN 2
               WHEN 'last_call' THEN 3
               ELSE 0 END;
  IF v_stage = 0 THEN RETURN 0; END IF;
  v_tier := CASE WHEN v_stage = 3 THEN 'major' ELSE 'standard' END;

  PERFORM set_config('app.notif_trusted', 'on', true);

  -- ---------------- RED: personal anon streak ----------------
  FOR r IN SELECT id, daily_streak FROM public.users
            WHERE COALESCE(daily_streak,0) > 0
              AND (daily_streak_last IS NULL OR daily_streak_last < v_today)
              AND deleted_at IS NULL
  LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.id, 'streak_risk_red', v_tier,
      CASE v_stage
        WHEN 2 THEN 'Your 🔴 ' || r.daily_streak || '-day streak misses you 🥺 one anon post keeps it alive'
        ELSE        '⏳ ' || v_hours || 'h left — your 🔴 ' || r.daily_streak || '-day streak is about to break 💔'
      END,
      jsonb_build_object('screen','composer','feed_scope','anon'),
      'streak_risk_red:' || r.id::text || ':' || v_today::text || ':s' || v_stage)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- ---------------- BLUE: per friend pair ----------------
  FOR r IN SELECT f.a, f.b,
                  public.ping_streak_between(f.a, f.b) AS streak
             FROM public.friend_pairs f
  LOOP
    CONTINUE WHEN COALESCE(r.streak,0) = 0;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.ping_replies rp JOIN public.pings p ON p.id = rp.ping_id
       WHERE rp.deleted_at IS NULL
         AND ((p.sender_id = r.a AND p.receiver_id = r.b) OR (p.sender_id = r.b AND p.receiver_id = r.a))
         AND ((rp.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date = v_today);

    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    SELECT s.me, 'streak_risk_blue', s.other, v_tier,
      CASE v_stage
        WHEN 2 THEN 'You + ' || COALESCE(u.name, u.anon_name, 'them') || ' = '
                    || public.days_label(r.streak) || ' 🔵 don''t let it end tonight 🥺'
        ELSE        '⏳ ' || v_hours || 'h left — ' || public.days_label(r.streak) || ' with '
                    || COALESCE(u.name, u.anon_name, 'them') || ' ends at midnight 💔'
      END,
      jsonb_build_object('screen','ping','user_id', s.other),
      'streak_risk_blue:' || s.me::text || ':' || s.other::text || ':' || v_today::text || ':s' || v_stage
      FROM (VALUES (r.a, r.b), (r.b, r.a)) AS s(me, other)
      JOIN public.users u ON u.id = s.other
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 2;
  END LOOP;

  -- ---------------- GROUP: shared all-or-nothing streak ----------------
  -- Counts computed here (group_ping_streak() returns nothing from cron),
  -- and only members who HAVEN'T replied are told.
  FOR r IN SELECT d.group_id, d.thread_id, d.member_ids, g.name AS gname,
                  CASE WHEN gs.last_complete_on >= (v_today - 1)
                       THEN COALESCE(gs.current_streak, 0) ELSE 0 END AS streak,
                  array_length(d.member_ids, 1) AS total,
                  (SELECT count(DISTINCT rp.replier_id)::int
                     FROM public.ping_replies rp JOIN public.pings p ON p.id = rp.ping_id
                    WHERE p.thread_id = d.thread_id AND rp.replier_id = ANY(d.member_ids)) AS replied
             FROM public.group_ping_days d
             JOIN public.groups g ON g.id = d.group_id
             LEFT JOIN public.group_ping_streaks gs ON gs.group_id = d.group_id
            WHERE d.on_date = v_today AND NOT d.resolved
  LOOP
    CONTINUE WHEN r.replied >= r.total;

    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    SELECT m.uid, 'group_streak_risk', v_tier,
      CASE
        WHEN v_stage = 2 AND r.total - r.replied = 1
          THEN 'Everyone in ' || r.gname || ' showed up… except you 🥺'
               || CASE WHEN r.streak > 0 THEN ' ' || r.streak || '-day streak 🔥' ELSE '' END
        WHEN v_stage = 2 AND r.streak > 0
          THEN r.gname || '''s ' || r.streak || '-day streak needs you — '
               || (r.total - r.replied) || ' still silent 😬'
        WHEN v_stage = 2
          THEN r.replied || '/' || r.total || ' answered in ' || r.gname || ' — tu kab? 👀'
        WHEN r.total - r.replied = 1
          THEN '⏳ ' || v_hours || 'h left — ' || r.gname || ' is only waiting on YOU 😭'
        ELSE '⏳ ' || v_hours || 'h left — ' || r.gname || ' needs '
               || (r.total - r.replied) || ' more replies before midnight'
      END,
      jsonb_build_object('screen','group','group_id', r.group_id, 'thread_id', r.thread_id),
      'group_streak_risk:' || r.group_id::text || ':' || v_today::text || ':' || m.uid::text || ':s' || v_stage
      FROM unnest(r.member_ids) AS m(uid)
     WHERE NOT EXISTS (
       SELECT 1 FROM public.ping_replies rp JOIN public.pings p ON p.id = rp.ping_id
        WHERE p.thread_id = r.thread_id AND rp.replier_id = m.uid)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_group_streak_broken()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_group text; v_day record; v_title text; r record;
BEGIN
  IF NOT (COALESCE(OLD.current_streak,0) > 0 AND NEW.current_streak = 0) THEN RETURN NEW; END IF;
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_day FROM public.group_ping_days WHERE group_id = NEW.group_id AND resolved ORDER BY on_date DESC LIMIT 1;
  IF v_day IS NULL THEN RETURN NEW; END IF;
  v_title := '💔 ' || v_group || '''s ' || OLD.current_streak
             || '-day streak just ended. Kal se phir shuru?';
  FOR r IN SELECT unnest(v_day.member_ids) AS uid LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.uid, 'group_streak_broken', 'standard', v_title,
            jsonb_build_object('screen','group','group_id', NEW.group_id),
            'group_streak_broken:' || NEW.group_id::text || ':' || v_day.on_date::text || ':' || r.uid::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END LOOP;
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.notify_pair_streak_milestone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
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

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  VALUES (v_sender, 'streak_milestone_blue', NEW.replier_id, 'major',
          'You + ' || v_b_name || ' = ' || public.days_label(v_streak) || ' 🔵🎉 unstoppable',
          jsonb_build_object('screen','ping','user_id', NEW.replier_id),
          'streak_milestone_blue:' || v_sender::text || ':' || NEW.replier_id::text || ':' || v_streak)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  VALUES (NEW.replier_id, 'streak_milestone_blue', v_sender, 'major',
          'You + ' || v_a_name || ' = ' || public.days_label(v_streak) || ' 🔵🎉 unstoppable',
          jsonb_build_object('screen','ping','user_id', v_sender),
          'streak_milestone_blue:' || NEW.replier_id::text || ':' || v_sender::text || ':' || v_streak)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

-- ---------------------------------------------------------------------------
-- Duo
-- ---------------------------------------------------------------------------
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
          v_name || ' picked you for a Duo 💞',
          'One album. Just you two. Say yes?',
          jsonb_build_object('screen','us_album','album_id', NEW.id),
          'us_album_invite:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

-- New: tell the person who asked when their Duo is accepted.
CREATE OR REPLACE FUNCTION public.notify_us_album_accepted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_accepter uuid; v_name text;
BEGIN
  IF NOT (NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted') THEN RETURN NEW; END IF;
  v_accepter := CASE WHEN NEW.created_by = NEW.user_a THEN NEW.user_b ELSE NEW.user_a END;
  IF v_accepter IS NULL OR v_accepter = NEW.created_by THEN RETURN NEW; END IF;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_name FROM public.users WHERE id = v_accepter;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.created_by, 'us_album_accepted', v_accepter, 'major',
          v_name || ' said yes 💞',
          'Your Duo is live — drop the first photo',
          jsonb_build_object('screen','us_album','album_id', NEW.id),
          'us_album_accepted:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

-- notifications.type is a CHECK-constrained whitelist; without this the
-- trigger below raises and aborts every Duo accept.
ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['reaction'::text, 'ping'::text, 'branch_view'::text, 'us_album_mutual'::text, 'report_resolved'::text, 'report_filed'::text, 'announcement'::text, 'ping_answered'::text, 'us_album_invite'::text, 'comment'::text, 'moment_contribution'::text, 'group_added'::text, 'group_invite'::text, 'group_post'::text, 'group_dip'::text, 'community_post'::text, 'friend_post'::text, 'streak_risk_red'::text, 'streak_risk_blue'::text, 'streak_milestone_blue'::text, 'group_streak_ping'::text, 'group_streak_risk'::text, 'group_streak_broken'::text, 'level_up'::text, 'level_progress'::text, 'leaderboard_movement'::text, 'ping_unanswered'::text, 'group_ping_waiting'::text, 'group_ping_replied'::text, 'pinned_post_view'::text, 'pinned_group_post_view'::text, 'moment_new_post'::text, 'moment_reply_nudge'::text, 'pinned_profile_view'::text, 'rank_overtaken'::text, 'rank_regained'::text, 'streak_rank_overtaken'::text, 'start_streak_nudge'::text, 'streak_standing'::text, 'window_prompt'::text, 'break_live_count'::text, 'midday_report'::text, 'day_digest'::text, 'lifecycle_cooling'::text, 'lifecycle_lapsed'::text, 'lifecycle_dormant'::text, 'activation_nudge'::text, 'graduation'::text, 'ping_reply_liked'::text, 'us_album_accepted'::text])));

DROP TRIGGER IF EXISTS trg_notify_us_album_accepted ON public.us_albums;
CREATE TRIGGER trg_notify_us_album_accepted
  AFTER UPDATE OF status ON public.us_albums
  FOR EACH ROW EXECUTE FUNCTION public.notify_us_album_accepted();

-- ---------------------------------------------------------------------------
-- Groups: the inviter hears "X accepted your invite"; everyone else "X joined"
-- ---------------------------------------------------------------------------
-- respond_group_invite inserts the member BEFORE deleting the invite, so the
-- invite row (and its invited_by) is still readable here.
CREATE OR REPLACE FUNCTION public.notify_group_added()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_group text; v_name text; v_inviter uuid;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(NULLIF(btrim(u.name), ''), 'Someone') INTO v_name
    FROM public.users u WHERE u.id = NEW.user_id;
  SELECT gi.invited_by INTO v_inviter FROM public.group_invites gi
   WHERE gi.group_id = NEW.group_id AND gi.invitee_id = NEW.user_id
   ORDER BY gi.created_at DESC LIMIT 1;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  SELECT gm.user_id, 'group_added', NEW.user_id,
         CASE WHEN gm.user_id = v_inviter THEN 'major' ELSE 'standard' END,
         CASE WHEN gm.user_id = v_inviter
              THEN v_name || ' accepted your invite to ' || v_group || ' 🎉'
              ELSE v_name || ' joined ' || v_group || ' 🎉' END,
         jsonb_build_object('screen','group','group_id', NEW.group_id),
         'group_added:' || NEW.group_id::text || ':' || NEW.user_id::text || ':' || gm.user_id::text
    FROM public.group_members gm
   WHERE gm.group_id = NEW.group_id AND gm.user_id <> NEW.user_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END $function$;

-- ---------------------------------------------------------------------------
-- Prompts: the question itself is the hook
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_window_change(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_window text; v_day date; v_dips int;
  c_batch constant int := 50;
  c_stagger constant interval := INTERVAL '1 minute';
  n int := 0;
BEGIN
  SELECT w.window_key, w.for_day INTO v_window, v_day
    FROM public.current_prompt_window((p_at AT TIME ZONE 'Asia/Kolkata')) w;
  IF v_window IS NULL THEN RETURN 0; END IF;

  SELECT count(*)::int INTO v_dips FROM public.posts p
   WHERE p.visibility = 'anonymous' AND p.deleted_at IS NULL
     AND ((p.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date = v_day;

  PERFORM set_config('app.notif_trusted', 'on', true);
  WITH mine AS (
    SELECT u.id AS user_id, c.id AS community_id,
           row_number() OVER (PARTITION BY u.id
             ORDER BY public.window_affinity_for(c.id, v_window) DESC, cm.joined_at) AS pick
      FROM public.users u
      JOIN public.community_members cm ON cm.user_id = u.auth_id
      JOIN public.communities c ON c.id = cm.community_id AND c.deleted_at IS NULL
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  ),
  chosen AS (SELECT user_id, community_id FROM mine WHERE pick = 1),
  resolved AS (
    SELECT ch.user_id, ch.community_id,
           public.pick_window_prompt(ch.community_id, v_window, v_day, 'anon') AS pid
      FROM chosen ch
  ),
  final AS (
    SELECT r.user_id, r.community_id, dp.prompt_text,
           (row_number() OVER (ORDER BY r.user_id) - 1) AS seq
      FROM resolved r JOIN public.daily_prompts dp ON dp.id = r.pid
  )
  INSERT INTO public.notifications
    (recipient_id, type, tier, title, body, data, dedupe_key, push_after)
  SELECT f.user_id, 'window_prompt', 'minor',
         '💭 ' || CASE WHEN length(f.prompt_text) > 70
                THEN left(f.prompt_text, 69) || '…' ELSE f.prompt_text END,
         CASE WHEN v_dips > 0 THEN v_dips || ' dips already today — nobody will know it''s you 🤫'
              ELSE 'Be the first — nobody will know it''s you 🤫' END,
         jsonb_build_object('screen','anon_feed','community_id', f.community_id),
         'window_prompt:' || f.user_id::text || ':' || v_day::text || ':' || v_window,
         public.next_push_slot('minor', 'window_prompt',
                               p_at + ((f.seq / c_batch) * c_stagger))
    FROM final f
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END; $function$;

-- New definer function: not callable by clients (Postgres grants EXECUTE to
-- PUBLIC by default).
REVOKE EXECUTE ON FUNCTION public.notify_us_album_accepted() FROM PUBLIC, anon, authenticated;
