-- PHASE 4a — 4-STAGE STREAK ESCALATION.
--
-- Spec: Day-end -> Evening -> Last Call -> Wind-down, self-cancelling on the
-- qualifying action, each streak escalating independently.
--
-- Before: all three risk notifications (red / blue / group) fired ONCE, from
-- notify_last_call at 21:00. One warning, and if it was missed the streak
-- died silently.
--
-- ===================== HOW SELF-CANCELLING WORKS =====================
-- There is no cancel step and no state to clear. Each stage re-evaluates
-- the SAME "is this streak still at risk today" predicate at send time:
--
--   red   — users.daily_streak_last < today  (an anon post sets it to today)
--   blue  — no ping reply between the pair today
--   group — the day's group_ping_day still has non-repliers
--
-- The moment the user acts, they stop matching, so every LATER stage simply
-- produces no row for them. A cancel flag would be a second source of truth
-- that could disagree with the streak itself; this cannot.
--
-- ==================== PER-STREAK INDEPENDENCE ========================
-- Dedupe keys are scoped to the streak, not the user: red is per user, blue
-- per friend PAIR, group per group. Someone can be at stage 4 on a blue
-- streak they are ignoring and stage 1 on the red one they are about to
-- save, and the two never interfere.
--
-- ========================== TIERS ====================================
-- Stages 1-3 are STANDARD. Stage 4 is MAJOR — not for drama, but because
-- push_allowed() admits STANDARD only in
-- wake_digest/pre_class/snack_peak/lunch_peak/day_end/evening/last_call.
-- Stage 4 fires in wind_down (22:30), which is MAJOR-only per §1, so a
-- STANDARD stage-4 would queue to the next morning and arrive after the
-- streak it was warning about had already broken.
-- p_at exists so the stage can be exercised deterministically: the whole
-- function keys off which WINDOW the moment falls in, and a test that had to
-- wait until 22:30 real time to check stage 4 would never be run. Cron calls
-- it with no argument.
CREATE OR REPLACE FUNCTION public.notify_streak_escalation(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
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
  v_stage := CASE v_win
               WHEN 'day_end'   THEN 1
               WHEN 'evening'   THEN 2
               WHEN 'last_call' THEN 3
               WHEN 'wind_down' THEN 4
               ELSE 0 END;
  IF v_stage = 0 THEN RETURN 0; END IF;   -- not an escalation window
  v_tier := CASE WHEN v_stage = 4 THEN 'major' ELSE 'standard' END;

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
        WHEN 1 THEN 'Your 🔴 ' || r.daily_streak || '-day streak needs a post today'
        WHEN 2 THEN 'Still time — your 🔴 ' || r.daily_streak || '-day streak ends at midnight'
        WHEN 3 THEN 'Last call: your 🔴 ' || r.daily_streak || '-day streak ends in ' || v_hours || 'h'
        ELSE        r.daily_streak || ' days about to end — one anon post saves it'
      END,
      -- Phase 7 actionability: straight into the composer that fixes it.
      jsonb_build_object('screen','composer','feed_scope','anon'),
      'streak_risk_red:' || r.id::text || ':' || v_today::text || ':s' || v_stage)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- ---------------- BLUE: per friend pair ----------------
  FOR r IN SELECT f.requester_id AS a, f.addressee_id AS b,
                  public.ping_streak_between(f.requester_id, f.addressee_id) AS streak
             FROM public.friendships f WHERE f.status = 'accepted'
  LOOP
    CONTINUE WHEN COALESCE(r.streak,0) = 0;
    -- Self-cancel: a reply between these two today removes the risk.
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.ping_replies rp JOIN public.pings p ON p.id = rp.ping_id
       WHERE rp.deleted_at IS NULL
         AND ((p.sender_id = r.a AND p.receiver_id = r.b) OR (p.sender_id = r.b AND p.receiver_id = r.a))
         AND ((rp.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date = v_today);

    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    SELECT s.me, 'streak_risk_blue', s.other, v_tier,
      CASE v_stage
        WHEN 1 THEN 'Your 🔵 ' || r.streak || '-day streak with ' || COALESCE(u.name, u.anon_name, 'them') || ' needs a reply'
        WHEN 2 THEN COALESCE(u.name, u.anon_name, 'They') || ' is still waiting — ' || r.streak || ' days 🔵'
        WHEN 3 THEN 'Your streak with ' || COALESCE(u.name, u.anon_name, 'them') || ' ends tonight — ' || r.streak || ' days 🔵'
        ELSE        r.streak || ' days with ' || COALESCE(u.name, u.anon_name, 'them') || ' about to end 🔵'
      END,
      jsonb_build_object('screen','ping','user_id', s.other),
      'streak_risk_blue:' || s.me::text || ':' || s.other::text || ':' || v_today::text || ':s' || v_stage
      FROM (VALUES (r.a, r.b), (r.b, r.a)) AS s(me, other)
      JOIN public.users u ON u.id = s.other
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 2;
  END LOOP;

  -- ---------------- GROUP: shared all-or-nothing streak ----------------
  FOR r IN SELECT d.group_id, d.thread_id, g.name AS gname,
                  s.current_streak, s.today_replied, s.today_total
             FROM public.group_ping_days d
             JOIN public.groups g ON g.id = d.group_id
             CROSS JOIN LATERAL public.group_ping_streak(d.group_id) s
            WHERE d.on_date = v_today AND NOT d.resolved
              AND s.today_open AND s.today_replied < s.today_total
  LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    SELECT m.user_id, 'group_streak_risk', v_tier,
      CASE v_stage
        WHEN 1 THEN r.gname || ' needs everyone today — ' || (r.today_total - r.today_replied) || ' still to reply'
        WHEN 2 THEN r.gname || '''s ' || COALESCE(r.current_streak,0) || '-day streak needs ' || (r.today_total - r.today_replied) || ' more'
        WHEN 3 THEN r.gname || '''s ' || COALESCE(r.current_streak,0) || '-day streak is at risk — ' || (r.today_total - r.today_replied) || ' members haven''t replied yet'
        ELSE        r.gname || '''s streak ends at midnight — ' || (r.today_total - r.today_replied) || ' still silent'
      END,
      jsonb_build_object('screen','group','group_id', r.group_id, 'thread_id', r.thread_id),
      'group_streak_risk:' || r.group_id::text || ':' || v_today::text || ':' || m.user_id::text || ':s' || v_stage
      FROM public.group_members m WHERE m.group_id = r.group_id
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
