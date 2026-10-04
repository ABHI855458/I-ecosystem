-- STAGGER FIX — two defects in the batching introduced in 4d / 5a / 5b.
--
-- 1. THE STAGGER BYPASSED THE TIER RULES.
--    set_notification_push_slot() is a BEFORE INSERT hook that reads:
--        IF NEW.push_after IS NULL AND NEW.push_sent_at IS NULL THEN
--            NEW.push_after := next_push_slot(tier, type, created_at);
--    Every other notification in the system leaves push_after NULL and gets
--    its window enforced there. The staggered senders SET push_after
--    explicitly, so the hook skipped them and push_allowed() never ran:
--    a MINOR window_prompt staggered past 11:30 would have pushed during
--    class block 2, which §1 forbids outright ("MINOR-tier notifications
--    never interrupt outside the two peak windows and the wake digest").
--
--    Fix: keep the stagger, then snap it through next_push_slot() — the same
--    function the hook uses. The stagger decides the ORDER and spacing; the
--    window rules still decide what is allowed to leave.
--
-- 2. THE INTERVAL DID NOT FIT THE WINDOW IT SENDS IN.
--    50 per slot / 3 minutes spreads 1200 students over 72 minutes. The
--    snack peak is 30 minutes long (11:00-11:30), so past batch ~10 every
--    remaining student fell outside the peak and (once fix 1 landed) got
--    deferred to lunch — receiving the SNACK prompt two hours late.
--
--    Fix: 50 per slot / 1 minute. That is 3000 students inside a 60-minute
--    window and 1500 inside the 30-minute snack peak, while staying far
--    under the dispatcher's own ceiling (it sweeps every 5 minutes and
--    takes 500 rows, so 50/min is 250 per sweep).

CREATE OR REPLACE FUNCTION public.notify_start_streak_nudge(p_at timestamptz DEFAULT now())
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  c_batch constant int := 50;
  c_stagger constant interval := INTERVAL '1 minute';
  n int := 0;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);
  WITH eligible AS (
    SELECT u.id, (row_number() OVER (ORDER BY u.id) - 1) AS seq
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
       AND COALESCE(u.daily_streak, 0) = 0
  )
  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key, push_after)
  SELECT e.id, 'start_streak_nudge', 'minor',
         'Start a 🔴 streak today — one anon post is all it takes',
         jsonb_build_object('screen','composer','feed_scope','anon'),
         'start_streak_nudge:' || e.id::text || ':' || v_today::text,
         public.next_push_slot('minor', 'start_streak_nudge',
                               p_at + ((e.seq / c_batch) * c_stagger))
    FROM eligible e
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END; $function$;

CREATE OR REPLACE FUNCTION public.notify_window_change(p_at timestamptz DEFAULT now())
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
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
         'New prompt: ' || CASE WHEN length(f.prompt_text) > 60
                THEN left(f.prompt_text, 59) || '…' ELSE f.prompt_text END,
         CASE WHEN v_dips > 0 THEN v_dips || ' Dips posted today 🔥'
              ELSE 'Be the first to dip today' END,
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

CREATE OR REPLACE FUNCTION public.notify_break_live_count(p_at timestamptz DEFAULT now())
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_day date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_win text := public.notification_window(p_at);
  v_live int;
  c_batch constant int := 50;
  c_stagger constant interval := INTERVAL '1 minute';
  n int := 0;
BEGIN
  SELECT count(DISTINCT pp.user_id)::int INTO v_live FROM public.post_presence pp
   WHERE pp.last_seen_at > p_at - INTERVAL '5 minutes';
  IF v_live < 2 THEN RETURN 0; END IF;

  PERFORM set_config('app.notif_trusted', 'on', true);
  WITH audience AS (
    SELECT u.id AS user_id, (row_number() OVER (ORDER BY u.id) - 1) AS seq
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.post_presence pp
                        WHERE pp.user_id = u.id AND pp.last_seen_at > p_at - INTERVAL '5 minutes')
  )
  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key, push_after)
  SELECT a.user_id, 'break_live_count', 'minor',
         v_live || ' people are here right now',
         jsonb_build_object('screen','anon_feed'),
         'break_live_count:' || a.user_id::text || ':' || v_day::text || ':' || v_win,
         public.next_push_slot('minor', 'break_live_count',
                               p_at + ((a.seq / c_batch) * c_stagger))
    FROM audience a
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END; $function$;
