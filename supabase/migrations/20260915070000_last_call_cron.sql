-- notification_system_spec.md §4 — everything that is time-driven rather
-- than event-driven. All of it lives in the Last Call window (21:00–22:30
-- IST), which §1 describes as where "streak-risk escalation lives".
--
-- §4 is explicit that the red-streak warning must NEVER fire earlier:
-- "don't create anxiety early in the day, only when it's genuinely close to
-- lost." Scheduling this job at 21:00 IST is what enforces that — the
-- notifications are not created at all before then, so there is no queued
-- row that an earlier window could flush.

-- Daily global rank snapshot — leaderboard movement needs yesterday's
-- position to say "{n} people passed you today", and nothing was recording
-- it. Ranked on users.total_score, the same number the profile shows.
CREATE TABLE IF NOT EXISTS public.leaderboard_rank_snapshots (
  user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  on_date  DATE NOT NULL,
  rank     INTEGER NOT NULL,
  PRIMARY KEY (user_id, on_date)
);
ALTER TABLE public.leaderboard_rank_snapshots ENABLE ROW LEVEL SECURITY;
-- Service-role only, like notification_events: nothing client-side reads it.

CREATE OR REPLACE FUNCTION public.notify_last_call()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE
  v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_hours int  := GREATEST(1, CEIL(EXTRACT(EPOCH FROM
                    ((v_today + 1)::timestamp - (now() AT TIME ZONE 'Asia/Kolkata'))
                  ) / 3600.0)::int);
  n int := 0;
  r record;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  -- ── RED: personal anon streak at risk ────────────────────────────────
  FOR r IN
    SELECT id, daily_streak FROM public.users
     WHERE COALESCE(daily_streak,0) > 0
       AND (daily_streak_last IS NULL OR daily_streak_last < v_today)
       AND deleted_at IS NULL
  LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, dedupe_key)
    VALUES (r.id, 'streak_risk_red', 'standard',
            'Your 🔴 ' || r.daily_streak || '-day streak ends in ' || v_hours ||
            'h — one anon post keeps it alive',
            'streak_risk_red:' || r.id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- ── BLUE 1: per-pair ping streak ending tonight ──────────────────────
  -- Every accepted friendship whose pair streak is alive but has had no
  -- reply today. Evaluated both ways so each half gets their own line with
  -- the other person's name in it.
  FOR r IN
    SELECT f.requester_id AS a, f.addressee_id AS b,
           public.ping_streak_between(f.requester_id, f.addressee_id) AS streak
      FROM public.friendships f
     WHERE f.status = 'accepted'
  LOOP
    CONTINUE WHEN COALESCE(r.streak,0) = 0;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.ping_replies rp JOIN public.pings p ON p.id = rp.ping_id
       WHERE rp.deleted_at IS NULL
         AND ((p.sender_id = r.a AND p.receiver_id = r.b)
           OR (p.sender_id = r.b AND p.receiver_id = r.a))
         AND ((rp.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date = v_today);

    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, dedupe_key)
    SELECT me, 'streak_risk_blue', other, 'standard',
           'Your streak with ' || COALESCE(u.name, u.anon_name, 'them') ||
           ' ends tonight — ' || r.streak || ' days 🔵',
           'streak_risk_blue:' || me::text || ':' || other::text || ':' || v_today::text
      FROM (VALUES (r.a, r.b), (r.b, r.a)) AS s(me, other)
      JOIN public.users u ON u.id = s.other
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 2;
  END LOOP;

  -- ── BLUE 2: group shared streak at risk ──────────────────────────────
  FOR r IN
    SELECT d.group_id, g.name AS gname, s.current_streak, s.today_replied, s.today_total
      FROM public.group_ping_days d
      JOIN public.groups g ON g.id = d.group_id
      CROSS JOIN LATERAL public.group_ping_streak(d.group_id) s
     WHERE d.on_date = v_today AND NOT d.resolved
       AND s.today_open AND s.today_replied < s.today_total
  LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    SELECT m.user_id, 'group_streak_risk', 'standard',
           r.gname || '''s ' || COALESCE(r.current_streak,0) || '-day streak is at risk — ' ||
           (r.today_total - r.today_replied) || ' members haven''t replied yet',
           jsonb_build_object('screen','group','group_id', r.group_id),
           'group_streak_risk:' || r.group_id::text || ':' || v_today::text || ':' || m.user_id::text
      FROM public.group_members m WHERE m.group_id = r.group_id
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- ── SCORE: close to levelling ────────────────────────────────────────
  -- Within 50 points of the next level's floor, and not already maxed.
  FOR r IN
    SELECT id, total_score, level,
           public.level_floor(level + 1) - COALESCE(total_score,0) AS gap
      FROM public.users
     WHERE deleted_at IS NULL AND COALESCE(level,1) < 7
  LOOP
    CONTINUE WHEN r.gap IS NULL OR r.gap <= 0 OR r.gap > 50;
    INSERT INTO public.notifications (recipient_id, type, tier, title, dedupe_key)
    VALUES (r.id, 'level_progress', 'standard',
            r.gap || ' points from ' || public.level_name(r.level + 1) ||
            ' — one post gets you there',
            'level_progress:' || r.id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- ── LEADERBOARD: who passed you today ────────────────────────────────
  -- Snapshot first, then compare against yesterday's. On the very first run
  -- there is no yesterday, so nothing sends — correct, not a bug.
  INSERT INTO public.leaderboard_rank_snapshots (user_id, on_date, rank)
  SELECT id, v_today,
         rank() OVER (ORDER BY COALESCE(total_score,0) DESC, id)
    FROM public.users WHERE deleted_at IS NULL
  ON CONFLICT (user_id, on_date) DO UPDATE SET rank = EXCLUDED.rank;

  FOR r IN
    SELECT t.user_id, (t.rank - y.rank) AS dropped
      FROM public.leaderboard_rank_snapshots t
      JOIN public.leaderboard_rank_snapshots y
        ON y.user_id = t.user_id AND y.on_date = v_today - 1
     WHERE t.on_date = v_today AND t.rank > y.rank
  LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, dedupe_key)
    VALUES (r.user_id, 'leaderboard_movement', 'standard',
            r.dropped || ' people passed you today — climb back up',
            'leaderboard_movement:' || r.user_id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END; $$;

REVOKE EXECUTE ON FUNCTION public.notify_last_call() FROM PUBLIC, anon, authenticated;

-- 15:30 UTC == 21:00 IST, the top of the Last Call window.
SELECT cron.unschedule('notify-last-call')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-last-call');
SELECT cron.schedule('notify-last-call', '30 15 * * *',
                     $$SELECT public.notify_last_call();$$);
