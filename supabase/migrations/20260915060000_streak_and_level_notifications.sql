-- notification_system_spec.md §4 — the three streak systems and score/level
-- progress, wired to the streak machinery that STREAK SYSTEM v4 actually
-- built (migrations 20260914030000..20260914060000).
--
-- Naming note: §4 calls the per-pair blue streak "Us album", but the live
-- system's BLUE 1 is the one-to-one PING streak per friend pair
-- (ping_streak_with / my_ping_streaks, derived not stored). That is the
-- thing that exists and has a day boundary, so that is what these hook.

-- ── level names — the ladder level_for_score() already encodes in comments
CREATE OR REPLACE FUNCTION public.level_name(p_level int)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_level
    WHEN 7 THEN 'Legend'    WHEN 6 THEN 'Dominator' WHEN 5 THEN 'Ace'
    WHEN 4 THEN 'Elite'     WHEN 3 THEN 'Contender' WHEN 2 THEN 'Rookie'
    ELSE 'Ghost' END;
$$;

-- Score at which each level starts — mirrors level_for_score()'s thresholds.
CREATE OR REPLACE FUNCTION public.level_floor(p_level int)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_level
    WHEN 7 THEN 6000 WHEN 6 THEN 3000 WHEN 5 THEN 1500
    WHEN 4 THEN 700  WHEN 3 THEN 300  WHEN 2 THEN 100 ELSE 0 END;
$$;

-- ── cron-safe pair streak. ping_streak_with() resolves "me" from
--    current_user_id() (auth.uid()), which is NULL in a cron session, so it
--    cannot be used from a scheduled job. Same logic, both ids explicit.
CREATE OR REPLACE FUNCTION public.ping_streak_between(p_a uuid, p_b uuid)
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
  WITH days AS (
    SELECT DISTINCT ((r.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date AS d
      FROM ping_replies r JOIN pings p ON p.id = r.ping_id
     WHERE r.deleted_at IS NULL
       AND ((p.sender_id = p_a AND p.receiver_id = p_b)
         OR (p.sender_id = p_b AND p.receiver_id = p_a))
  ),
  ranked AS (SELECT d, (row_number() OVER (ORDER BY d DESC))::int AS rn FROM days),
  anchor AS (SELECT max(d) AS last_day FROM days)
  SELECT COALESCE((
    SELECT count(*)::int FROM ranked, anchor
     WHERE anchor.last_day >= ((now() AT TIME ZONE 'Asia/Kolkata')::date - 1)
       AND ranked.d = anchor.last_day - (ranked.rn - 1)), 0);
$$;

-- ═══ GROUP BLUE STREAK — the daily ping opens the day ═══════════════════
-- "{sender} pinged {group name} — reply to keep the {n}-day streak alive"
-- Fires off group_ping_days, the row send_group_ping() creates exactly once
-- per (group, IST day), so the 2nd..Nth ping of a day does not re-notify.
CREATE OR REPLACE FUNCTION public.notify_group_ping_opened()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_group text; v_sender text; v_streak int; v_title text; r record;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_sender
    FROM public.users WHERE id = NEW.started_by;
  SELECT current_streak INTO v_streak FROM public.group_ping_streak(NEW.group_id);
  v_streak := COALESCE(v_streak, 0);

  v_title := v_sender || ' pinged ' || v_group ||
             CASE WHEN v_streak > 0
                  THEN ' — reply to keep the ' || v_streak || '-day streak alive'
                  ELSE ' — reply to start a streak' END;

  FOR r IN SELECT unnest(NEW.member_ids) AS uid LOOP
    IF r.uid <> NEW.started_by THEN
      INSERT INTO public.notifications
        (recipient_id, type, actor_id, tier, title, data, dedupe_key)
      VALUES (r.uid, 'group_streak_ping', NEW.started_by, 'major', v_title,
              jsonb_build_object('screen','group','group_id', NEW.group_id,
                                 'thread_id', NEW.thread_id),
              'group_streak_ping:' || NEW.group_id::text || ':' || NEW.on_date::text
                || ':' || r.uid::text)
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    END IF;
  END LOOP;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_group_ping_opened ON public.group_ping_days;
CREATE TRIGGER trg_notify_group_ping_opened AFTER INSERT ON public.group_ping_days
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_ping_opened();

-- ═══ GROUP BLUE STREAK — broken ═════════════════════════════════════════
-- "{group}'s streak ended — {name} didn't reply in time". STANDARD and
-- factual per §4: it names who, with no blame language beyond the name.
-- Fires when resolve_group_ping_day() knocks current_streak down to 0.
CREATE OR REPLACE FUNCTION public.notify_group_streak_broken()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_group text; v_day record; v_missing text; v_title text; r record;
BEGIN
  IF NOT (COALESCE(OLD.current_streak,0) > 0 AND NEW.current_streak = 0) THEN
    RETURN NEW;
  END IF;
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_day FROM public.group_ping_days
   WHERE group_id = NEW.group_id AND resolved ORDER BY on_date DESC LIMIT 1;
  IF v_day IS NULL THEN RETURN NEW; END IF;

  SELECT string_agg(COALESCE(u.name, u.anon_name, 'someone'), ', ')
    INTO v_missing
    FROM unnest(v_day.member_ids) m
    JOIN public.users u ON u.id = m
   WHERE m NOT IN (
     SELECT r2.replier_id FROM public.ping_replies r2
      JOIN public.pings p ON p.id = r2.ping_id
     WHERE p.thread_id = v_day.thread_id);

  v_title := v_group || '''s streak ended' ||
             CASE WHEN v_missing IS NOT NULL
                  THEN ' — ' || v_missing || ' didn''t reply in time' ELSE '' END;

  FOR r IN SELECT unnest(v_day.member_ids) AS uid LOOP
    INSERT INTO public.notifications
      (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.uid, 'group_streak_broken', 'standard', v_title,
            jsonb_build_object('screen','group','group_id', NEW.group_id),
            'group_streak_broken:' || NEW.group_id::text || ':'
              || v_day.on_date::text || ':' || r.uid::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END LOOP;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_group_streak_broken ON public.group_ping_streaks;
CREATE TRIGGER trg_notify_group_streak_broken AFTER UPDATE ON public.group_ping_streaks
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_streak_broken();

-- ═══ LEVEL UP (MAJOR, immediate) ════════════════════════════════════════
-- §4: "fires immediately regardless of window". push_allowed() already lets
-- MAJOR through everywhere but deep quiet hours, which is the one boundary
-- §7 keeps closed for everything except a ping reply.
CREATE OR REPLACE FUNCTION public.notify_level_up()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
BEGIN
  IF COALESCE(NEW.level,1) <= COALESCE(OLD.level,1) THEN RETURN NEW; END IF;
  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key)
  VALUES (NEW.id, 'level_up', 'major',
          'You''re now ' || public.level_name(NEW.level) || ' 🎉',
          jsonb_build_object('screen','profile','level', NEW.level),
          'level_up:' || NEW.id::text || ':' || NEW.level::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;

-- Fires on glow_score/ping_score, NOT on level. users.level and
-- users.total_score are both GENERATED ALWAYS columns derived from
-- (glow_score + ping_score), so they can never appear in an UPDATE
-- statement's column list — `AFTER UPDATE OF level` would compile fine and
-- then silently never fire. OLD.level/NEW.level still read correctly inside
-- the trigger; only the firing condition has to name the base columns.
DROP TRIGGER IF EXISTS trg_notify_level_up ON public.users;
CREATE TRIGGER trg_notify_level_up
  AFTER UPDATE OF glow_score, ping_score ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.notify_level_up();

-- ═══ BLUE PAIR STREAK — milestone ═══════════════════════════════════════
-- "You + {name} hit {n} days 🔵🎉" at the 7 / 30 / 100 day thresholds.
CREATE OR REPLACE FUNCTION public.notify_pair_streak_milestone()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_sender uuid; v_streak int; v_a_name text; v_b_name text; v_day text;
BEGIN
  SELECT sender_id INTO v_sender FROM public.pings WHERE id = NEW.ping_id;
  IF v_sender IS NULL OR v_sender = NEW.replier_id THEN RETURN NEW; END IF;

  v_streak := public.ping_streak_between(v_sender, NEW.replier_id);
  IF v_streak NOT IN (7, 30, 100) THEN RETURN NEW; END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_a_name FROM public.users WHERE id = v_sender;
  SELECT COALESCE(name, anon_name, 'someone') INTO v_b_name FROM public.users WHERE id = NEW.replier_id;
  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, dedupe_key)
  VALUES (v_sender, 'streak_milestone_blue', NEW.replier_id, 'major',
          'You + ' || v_b_name || ' hit ' || v_streak || ' days 🔵🎉',
          'streak_milestone_blue:' || v_sender::text || ':' || NEW.replier_id::text || ':' || v_streak)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, dedupe_key)
  VALUES (NEW.replier_id, 'streak_milestone_blue', v_sender, 'major',
          'You + ' || v_a_name || ' hit ' || v_streak || ' days 🔵🎉',
          'streak_milestone_blue:' || NEW.replier_id::text || ':' || v_sender::text || ':' || v_streak)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_pair_streak_milestone ON public.ping_replies;
CREATE TRIGGER trg_notify_pair_streak_milestone AFTER INSERT ON public.ping_replies
  FOR EACH ROW EXECUTE FUNCTION public.notify_pair_streak_milestone();
