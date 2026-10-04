-- NOTIFICATION SYSTEM — PHASE 6: lifecycle segmentation (spec §6.6).
--
--   NEW      activation incomplete (no Group / Us album / Circle yet)
--   MID      activation done, opened within the last 2 days
--   COOLING  3-6 days since last open, still holds a live streak
--   LAPSED   7-13 days
--   DORMANT  14+ days  -> ONE final notification, then nothing, ever
--
-- The open signal is users.last_open_at, already written by
-- record_daily_open() which main_shell.dart calls on every app open. No new
-- client plumbing: the signal this needs was already being recorded.

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
    'lifecycle_cooling','lifecycle_lapsed','lifecycle_dormant'   -- Phase 6
  ])
);

CREATE TABLE IF NOT EXISTS public.user_lifecycle (
  user_id             uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  segment             text NOT NULL,
  last_open_on        date,
  computed_at         timestamptz NOT NULL DEFAULT now(),
  -- THE LATCH. Non-NULL means the single dormant notification has been sent.
  -- Cleared only by recalc_lifecycle when the user actually comes back.
  dormant_notified_at timestamptz,
  -- LAPSED cadence: "at most every 2-3 days, not daily".
  last_winback_on     date
);
ALTER TABLE public.user_lifecycle ENABLE ROW LEVEL SECURITY;

COMMENT ON COLUMN public.user_lifecycle.dormant_notified_at IS
  'Set once, when the single §6.6E dormant notification is sent. While it is '
  'non-NULL and the segment is still dormant, set_notification_push_slot() '
  'forces push_after to NULL on EVERY notification for this user, so no '
  'producer — present or future — can push to them. Cleared by '
  'recalc_lifecycle() the moment they open the app again.';

-- ========================= THE SEGMENTER =============================
-- Runs on app open (via record_daily_open) and in a daily batch.
-- p_user NULL = recompute everyone.
CREATE OR REPLACE FUNCTION public.recalc_lifecycle(p_user uuid DEFAULT NULL,
                                                   p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date; n int;
BEGIN
  INSERT INTO public.user_lifecycle (user_id, segment, last_open_on, computed_at)
  SELECT u.id,
         CASE
           WHEN u.last_open_at IS NULL THEN 'new'
           WHEN (v_today - u.last_open_at) >= 14 THEN 'dormant'
           WHEN (v_today - u.last_open_at) >= 7  THEN 'lapsed'
           WHEN (v_today - u.last_open_at) >= 3  THEN
             -- COOLING requires something live to lose; without that they are
             -- simply quiet, and a "you'll lose your streak" hook would be a
             -- lie. Such users stay MID until they cross into LAPSED.
             CASE WHEN COALESCE(u.daily_streak,0) > 0
                       OR EXISTS (SELECT 1 FROM public.friendships f
                                   WHERE f.status='accepted'
                                     AND (f.requester_id=u.id OR f.addressee_id=u.id)
                                     AND public.ping_streak_between(f.requester_id, f.addressee_id) > 0)
                  THEN 'cooling' ELSE 'mid' END
           -- Opened within 2 days: NEW until all three activation artefacts
           -- exist, MID afterwards (§6.6A/B).
           WHEN EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.user_id = u.id)
            AND EXISTS (SELECT 1 FROM public.us_albums a
                         WHERE (a.user_a = u.id OR a.user_b = u.id) AND a.status='accepted')
            AND EXISTS (SELECT 1 FROM public.circles c WHERE c.creator_id = u.id)
             THEN 'mid'
           ELSE 'new'
         END,
         u.last_open_at, p_at
    FROM public.users u
   WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
     AND (p_user IS NULL OR u.id = p_user)
  ON CONFLICT (user_id) DO UPDATE SET
    segment      = EXCLUDED.segment,
    last_open_on = EXCLUDED.last_open_on,
    computed_at  = EXCLUDED.computed_at,
    -- THE RETURN PATH. Leaving dormant for any other segment means they came
    -- back, so the latch is released and pushes resume. This is the only
    -- thing that ever clears it.
    dormant_notified_at = CASE WHEN EXCLUDED.segment = 'dormant'
                               THEN public.user_lifecycle.dormant_notified_at
                               ELSE NULL END;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;

-- ============= STRUCTURAL SUPPRESSION — the load-bearing part ==========
-- Every one of the 36 notification producers routes through this BEFORE
-- INSERT hook; the dispatcher's due-query requires `push_after IS NOT NULL`.
-- Forcing push_after to NULL here therefore makes a push to a notified-dormant
-- user impossible at the only chokepoint that matters, rather than asking
-- each producer to remember a rule.
--
-- Deliberately placed BEFORE the "IF push_after IS NULL" branch, so it also
-- overrides the three producers that set push_after explicitly (the
-- staggered senders). That ordering is the whole point — a suppression that
-- only applied to producers which left the column NULL would have exactly
-- the same blind spot as the stagger bug it is modelled on.
--
-- The row is still WRITTEN. A returning user's notification history is
-- intact; only delivery is withheld.
CREATE OR REPLACE FUNCTION public.set_notification_push_slot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_lifecycle ul
              WHERE ul.user_id = NEW.recipient_id
                AND ul.segment = 'dormant'
                AND ul.dormant_notified_at IS NOT NULL) THEN
    NEW.push_after := NULL;
    RETURN NEW;
  END IF;

  IF NEW.push_after IS NULL AND NEW.push_sent_at IS NULL THEN
    NEW.push_after := public.next_push_slot(NEW.tier, NEW.type, COALESCE(NEW.created_at, now()));
  END IF;
  RETURN NEW;
END;
$function$;

-- ===================== WIN-BACK NOTIFICATIONS =========================
CREATE OR REPLACE FUNCTION public.notify_lifecycle(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  r record; v_title text; v_count int; n int := 0;
BEGIN
  PERFORM public.recalc_lifecycle(NULL, p_at);
  PERFORM set_config('app.notif_trusted', 'on', true);

  -- ---------------- COOLING: once/day, what they stand to lose ----------
  FOR r IN SELECT ul.user_id, u.daily_streak
             FROM public.user_lifecycle ul JOIN public.users u ON u.id = ul.user_id
            WHERE ul.segment = 'cooling'
  LOOP
    SELECT g.name, s.current_streak INTO v_title, v_count
      FROM public.group_members gm
      JOIN public.groups g ON g.id = gm.group_id
      CROSS JOIN LATERAL public.group_ping_streak(g.id) s
     WHERE gm.user_id = r.user_id AND COALESCE(s.current_streak,0) > 0
     ORDER BY s.current_streak DESC LIMIT 1;

    IF v_title IS NOT NULL THEN
      v_title := v_title || '''s streak needs you today, or it resets to zero.';
    ELSIF COALESCE(r.daily_streak,0) > 0 THEN
      v_title := 'Your ' || r.daily_streak || '-day streak is about to break — that''s real time invested.';
    ELSE
      CONTINUE;   -- nothing genuine to point at
    END IF;

    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.user_id, 'lifecycle_cooling', 'standard', v_title,
            jsonb_build_object('screen','composer','feed_scope','anon'),
            'lifecycle_cooling:' || r.user_id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1; v_title := NULL; v_count := NULL;
  END LOOP;

  -- ---------------- LAPSED: real events only, every 2-3 days -------------
  FOR r IN SELECT ul.user_id, ul.last_open_on
             FROM public.user_lifecycle ul
            WHERE ul.segment = 'lapsed'
              AND (ul.last_winback_on IS NULL OR (v_today - ul.last_winback_on) >= 2)
  LOOP
    v_title := NULL;
    SELECT count(*)::int INTO v_count FROM public.pings p
     WHERE p.receiver_id = r.user_id
       AND ((p.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date > r.last_open_on;
    IF v_count > 0 THEN
      v_title := v_count || ' ' || CASE WHEN v_count=1 THEN 'person' ELSE 'people' END
                 || ' pinged you while you were gone.';
    ELSE
      SELECT u2.name, count(*)::int INTO v_title, v_count
        FROM public.pinned_people pp
        JOIN public.users u2 ON u2.id = pp.pinned_user_id
        JOIN public.posts po ON po.user_id = pp.pinned_user_id
       WHERE pp.user_id = r.user_id AND po.deleted_at IS NULL
         AND po.visibility <> 'anonymous'
         AND ((po.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date > r.last_open_on
       GROUP BY u2.name ORDER BY count(*) DESC LIMIT 1;
      IF v_title IS NOT NULL THEN
        v_title := v_title || ' posted ' || v_count || ' time'
                   || CASE WHEN v_count=1 THEN '' ELSE 's' END
                   || ' since you last opened this.';
      END IF;
    END IF;

    -- §6.6: nothing real to say means nothing gets sent. No "we miss you".
    CONTINUE WHEN v_title IS NULL;

    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.user_id, 'lifecycle_lapsed', 'standard', v_title,
            jsonb_build_object('screen','feed'),
            'lifecycle_lapsed:' || r.user_id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    UPDATE public.user_lifecycle SET last_winback_on = v_today WHERE user_id = r.user_id;
    n := n + 1;
  END LOOP;

  -- ---------------- DORMANT: exactly one, then never again --------------
  -- Three independent guards, any one of which is sufficient:
  --   (a) this query only selects dormant_notified_at IS NULL;
  --   (b) the dedupe_key carries NO date, so the partial unique index on
  --       (type, dedupe_key) rejects a second insert for this user forever;
  --   (c) the latch set immediately below makes
  --       set_notification_push_slot() strip push_after from every future
  --       notification of any type until they return.
  -- The INSERT happens BEFORE the latch is set, which is the only order in
  -- which this one notification can itself be delivered.
  FOR r IN SELECT ul.user_id, ul.last_open_on
             FROM public.user_lifecycle ul
            WHERE ul.segment = 'dormant' AND ul.dormant_notified_at IS NULL
  LOOP
    SELECT c.name, count(*)::int INTO v_title, v_count
      FROM public.circles c
      JOIN public.circle_members cm ON cm.circle_id = c.id
      JOIN public.posts po ON po.user_id = cm.member_id
     WHERE c.creator_id = r.user_id AND po.deleted_at IS NULL
       AND ((po.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date > COALESCE(r.last_open_on, v_today)
     GROUP BY c.name ORDER BY count(*) DESC LIMIT 1;

    IF v_title IS NOT NULL AND v_count > 0 THEN
      v_title := 'Your Circle members have posted ' || v_count || ' time'
                 || CASE WHEN v_count=1 THEN '' ELSE 's' END
                 || ' since you left — ' || v_title || ' is still there.';
      INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
      VALUES (r.user_id, 'lifecycle_dormant', 'standard', v_title,
              jsonb_build_object('screen','feed'),
              'lifecycle_dormant:' || r.user_id::text)   -- NO DATE: once, ever
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
      n := n + 1;
    END IF;

    -- Latched whether or not copy was found. A dormant user with nothing
    -- real to say gets silence AND is still marked done — "we had nothing
    -- honest to send" must not become a reason to try again tomorrow.
    UPDATE public.user_lifecycle SET dormant_notified_at = p_at WHERE user_id = r.user_id;
    v_title := NULL; v_count := NULL;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
