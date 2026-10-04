-- NOTIFICATION SYSTEM — PHASE 5: rhythm (spec §6.7C / D / E).
--
--   5a  window-change push, prompt + Dip count MERGED into ONE, all 8 windows
--   5b  break-time live counts (snack + lunch), real presence only
--   5c  midday 6-hour report + end-of-day personal digest, zero lines OMITTED
--
-- Every number below is queried at send time from real rows. Nothing is
-- padded, rounded up, or estimated, and a count that comes back zero removes
-- its line rather than printing "0".
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
    'window_prompt','break_live_count','midday_report','day_digest'  -- Phase 5
  ])
);

-- ============ 5a: window turnover — ONE notification, not two ==========
-- §6.7C wants the new prompt and §6.5 wants the day's Dip count, and both
-- say explicitly: one notification per turnover, never two. So the prompt is
-- the title and the count is the body of the SAME row.
--
-- The prompt is resolved PER USER, not campus-wide: pick_window_prompt is
-- per community, and a user's bar is driven by the communities they joined.
-- The community chosen is the one with the highest window_affinity_for —
-- the same signal prompt_bar_for_user ranks by — so the prompt quoted is one
-- they would actually have seen on opening the app.
--
-- STAGGERED, same 50-per-slot / 3-minute structure as the start-streak
-- nudge. This one matters most: it is the only notification aimed at the
-- WHOLE campus at a single instant, eight times a day. Without the stagger
-- every device on campus would be pushed inside the same second at 11:00,
-- which is both an FCM burst and a very visible "everyone's phone buzzed at
-- once" moment.
--
-- Zero Dips is not an error and is never printed as "0": §6.5 says frame
-- small numbers with momentum, so the body becomes an invitation instead.
CREATE OR REPLACE FUNCTION public.notify_window_change(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_window text; v_day date; v_dips int;
  c_batch   constant int := 50;
  c_stagger constant interval := INTERVAL '3 minutes';
  n int := 0;
BEGIN
  SELECT w.window_key, w.for_day INTO v_window, v_day
    FROM public.current_prompt_window((p_at AT TIME ZONE 'Asia/Kolkata')) w;
  IF v_window IS NULL THEN RETURN 0; END IF;

  SELECT count(*)::int INTO v_dips
    FROM public.posts p
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
      FROM resolved r
      JOIN public.daily_prompts dp ON dp.id = r.pid
  )
  INSERT INTO public.notifications
    (recipient_id, type, tier, title, body, data, dedupe_key, push_after)
  SELECT f.user_id, 'window_prompt', 'minor',
         'New prompt: ' ||
           CASE WHEN length(f.prompt_text) > 60
                THEN left(f.prompt_text, 59) || '…' ELSE f.prompt_text END,
         CASE WHEN v_dips > 0
              THEN v_dips || ' Dips posted today 🔥'
              ELSE 'Be the first to dip today' END,
         jsonb_build_object('screen','anon_feed','community_id', f.community_id),
         'window_prompt:' || f.user_id::text || ':' || v_day::text || ':' || v_window,
         p_at + ((f.seq / c_batch) * c_stagger)
    FROM final f
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

-- ============== 5b: break-time live counts (real presence) =============
-- "{real live count} people are here right now" — post_presence heartbeats
-- inside the last 5 minutes, which is the only genuine liveness signal in
-- the schema. No padding, no floor, no "at least N".
--
-- Two guards keep it honest:
--   * a live count of 0 or 1 sends NOTHING. One "live" person during a break
--     is usually the reader themselves, and "1 person is here right now" is
--     a worse advertisement than silence.
--   * people currently live are excluded as recipients — they can see the
--     room; the notification exists to pull in everyone who cannot.
CREATE OR REPLACE FUNCTION public.notify_break_live_count(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_day date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_win text := public.notification_window(p_at);
  v_live int;
  c_batch constant int := 50;
  c_stagger constant interval := INTERVAL '3 minutes';
  n int := 0;
BEGIN
  SELECT count(DISTINCT pp.user_id)::int INTO v_live
    FROM public.post_presence pp
   WHERE pp.last_seen_at > p_at - INTERVAL '5 minutes';

  IF v_live < 2 THEN RETURN 0; END IF;

  PERFORM set_config('app.notif_trusted', 'on', true);

  WITH audience AS (
    SELECT u.id AS user_id, (row_number() OVER (ORDER BY u.id) - 1) AS seq
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.post_presence pp
                        WHERE pp.user_id = u.id
                          AND pp.last_seen_at > p_at - INTERVAL '5 minutes')
  )
  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key, push_after)
  SELECT a.user_id, 'break_live_count', 'minor',
         v_live || ' people are here right now',
         jsonb_build_object('screen','anon_feed'),
         'break_live_count:' || a.user_id::text || ':' || v_day::text || ':' || v_win,
         p_at + ((a.seq / c_batch) * c_stagger)
    FROM audience a
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

-- ================== 5c(i): midday 6-hour report ========================
-- "{real count} posts in the last 6 hours — catch up".
--
-- Counted PER USER over what that user can actually reach — friends' posts
-- plus posts in their communities — not a campus total. A campus number
-- would be real but would not be the thing being offered: there is no point
-- telling someone to catch up on 40 posts when 3 of them are visible to them.
--
-- Zero sends nothing.
CREATE OR REPLACE FUNCTION public.notify_midday_report(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_day date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_since timestamp := (p_at AT TIME ZONE 'UTC') - INTERVAL '6 hours';
  n int := 0;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  WITH counted AS (
    SELECT u.id AS user_id,
           (SELECT count(*) FROM public.posts p
             WHERE p.deleted_at IS NULL
               AND p.created_at > v_since
               AND p.user_id <> u.id
               AND (
                 EXISTS (SELECT 1 FROM public.friendships f
                          WHERE f.status='accepted'
                            AND ((f.requester_id=u.id AND f.addressee_id=p.user_id)
                              OR (f.addressee_id=u.id AND f.requester_id=p.user_id)))
                 OR (p.community_id IS NOT NULL AND EXISTS (
                       SELECT 1 FROM public.community_members cm
                        WHERE cm.community_id = p.community_id AND cm.user_id = u.auth_id))
               ))::int AS posts
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  )
  INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
  SELECT c.user_id, 'midday_report', 'minor',
         c.posts || ' post' || CASE WHEN c.posts = 1 THEN '' ELSE 's' END
           || ' in the last 6 hours — catch up',
         jsonb_build_object('screen','feed'),
         'midday_report:' || c.user_id::text || ':' || v_day::text
    FROM counted c
   WHERE c.posts > 0                         -- zero sends nothing at all
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

-- ============== 5c(ii): end-of-day personal digest =====================
-- "Today: {n} reactions, {n} comments, {n} views on your posts. Streak: …"
--
-- §6.7E: "If a count is zero, omit that line entirely rather than sending
-- '0 reactions.'" The copy is therefore ASSEMBLED, not templated — each
-- clause is appended only when its count is non-zero, and if every count is
-- zero and there is no streak to report, no notification is produced at all.
-- A digest that says "Today: nothing happened" is worse than no digest.
CREATE OR REPLACE FUNCTION public.notify_day_digest(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_day date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_since timestamp := ((v_day::timestamp) AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'UTC';
  r record; parts text[]; v_title text; n int := 0;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  FOR r IN
    SELECT u.id AS user_id, COALESCE(u.daily_streak,0) AS streak,
           (u.daily_streak_last = v_day) AS kept_today,
           (SELECT count(*) FROM public.reactions x JOIN public.posts p ON p.id=x.post_id
             WHERE p.user_id=u.id AND x.created_at > v_since)
         + (SELECT count(*) FROM public.post_realmoji_reactions x JOIN public.posts p ON p.id=x.post_id
             WHERE p.user_id=u.id AND x.created_at > v_since) AS reactions,
           (SELECT count(*) FROM public.comments x JOIN public.posts p ON p.id=x.post_id
             WHERE p.user_id=u.id AND x.deleted_at IS NULL AND x.created_at > v_since) AS comments,
           (SELECT count(*) FROM public.post_views x JOIN public.posts p ON p.id=x.post_id
             WHERE p.user_id=u.id AND x.created_at > v_since) AS views
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  LOOP
    parts := ARRAY[]::text[];
    IF r.reactions > 0 THEN
      parts := parts || (r.reactions || ' reaction' || CASE WHEN r.reactions=1 THEN '' ELSE 's' END);
    END IF;
    IF r.comments > 0 THEN
      parts := parts || (r.comments || ' comment' || CASE WHEN r.comments=1 THEN '' ELSE 's' END);
    END IF;
    IF r.views > 0 THEN
      parts := parts || (r.views || ' view' || CASE WHEN r.views=1 THEN '' ELSE 's' END);
    END IF;

    -- Nothing happened AND no streak to speak of: send nothing.
    CONTINUE WHEN cardinality(parts) = 0 AND r.streak = 0;

    IF cardinality(parts) > 0 THEN
      v_title := 'Today: ' || array_to_string(parts, ', ') || ' on your posts';
      IF r.streak > 0 THEN
        v_title := v_title || '. Streak: ' || r.streak || ' day'
          || CASE WHEN r.streak=1 THEN '' ELSE 's' END
          || CASE WHEN r.kept_today THEN ' 🔴' ELSE ' — at risk' END;
      END IF;
    ELSE
      v_title := 'Streak: ' || r.streak || ' day' || CASE WHEN r.streak=1 THEN '' ELSE 's' END
        || CASE WHEN r.kept_today THEN ' 🔴 kept today' ELSE ' — at risk tonight' END;
    END IF;

    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.user_id, 'day_digest', 'standard', v_title,
            jsonb_build_object('screen','notifications'),
            'day_digest:' || r.user_id::text || ':' || v_day::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
