-- GROUP PING OVERLAP RESOLUTION.
--
-- group_ping_replied (trigger, fires on the first reply) and
-- group_ping_waiting (cron, T+3h and T+5h) were nudging the SAME silent
-- members about the SAME thread, independently. Modelled deterministically
-- against push_allowed(), that produced three distinct defects:
--
--   1. ORDERING INVERSION. 'replied' was STANDARD and 'waiting' MAJOR.
--      STANDARD is deferred out of class blocks, MAJOR is not, so a reply at
--      11:55 surfaced at 14:00 while the "you're holding this up" push it
--      contradicts landed at 12:00 — the user was chased about a thread that
--      had already moved, and told so two hours later.
--   2. SAME-SLOT COLLISION. In that same case 'replied' and waiting-s2 both
--      resolved to 14:00: two pushes about one thread in one minute.
--   3. NEAR-SIMULTANEOUS. A reply at T+4h58m landed 13:58 against waiting-s2
--      at 14:00.
--
-- Resolution, three parts:
--   (1) the s1 checkpoint now CARRIES the social proof, so no separate push
--       is needed at that point;
--   (2) group_ping_replied survives only while it is genuinely EARLY —
--       suppressed once the thread is within 45 minutes of the T+3h
--       checkpoint, which is precisely the window all three defects live in;
--   (3) tiers aligned to MAJOR so ordering can follow causality.

-- ============ (1) + s1 folds in the real reply count ==================
CREATE OR REPLACE FUNCTION public.notify_unanswered_pings()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int := 0; m int;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  -- 1:1, stages at +3h and +8h (unchanged).
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'ping_unanswered', NULL, 'major',
         CASE WHEN st.stage = 1
              THEN 'Someone is still waiting on you 👀'
              ELSE 'Still unanswered — they pinged you 8 hours ago 👀' END,
         p.prompt,
         jsonb_build_object('screen','ping','ping_id', p.id),
         'ping_unanswered:' || p.id::text || ':s' || st.stage
    FROM public.pings p
    CROSS JOIN LATERAL (VALUES (1, INTERVAL '3 hours'), (2, INTERVAL '8 hours')) AS st(stage, after)
   WHERE p.group_id IS NULL
     AND p.receiver_id IS NOT NULL
     AND p.receiver_id <> p.sender_id
     AND p.replied_at IS NULL
     AND p.expires_at > now()
     AND now() >= (p.created_at AT TIME ZONE 'UTC') + st.after
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  -- Group, stages at +3h and +5h, non-repliers only.
  --
  -- Stage 1 now carries the thread's REAL standing — "2 of 4 have replied" —
  -- which is the signal group_ping_replied used to deliver as its own push.
  -- Both numbers are counted at send time off the thread's own ping rows, so
  -- neither is cached or estimated. With nobody yet replied the count would
  -- read "0 of 4", which states the opposite of social proof, so that case
  -- falls back to the plain wording instead.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'group_ping_waiting', NULL, 'major',
         CASE
           WHEN st.stage = 1 AND tc.replied > 0
             THEN tc.replied || ' of ' || tc.total || ' have replied — '
                  || COALESCE(g.name,'your group') || ' is waiting on you 👀'
           WHEN st.stage = 1
             THEN COALESCE(g.name,'Your group') || ' is waiting on you 👀'
           ELSE 'Still waiting on you in ' || COALESCE(g.name,'your group') || ' 👀'
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

-- ====== (2) early-only window  +  (3) tier aligned to MAJOR ===========
-- The 45-minute guard is expressed as "thread younger than 2h15m", which is
-- the same boundary from the other side and is what the trigger can actually
-- evaluate at insert time.
--
-- Past that point this notification is strictly redundant: the s1 checkpoint
-- 45 minutes later now says everything it said, plus who is still missing.
-- Below it, it is doing real work — an early "something is happening here"
-- pull long before any nudge is due.
--
-- MAJOR matches group_ping_waiting so the two share one push-window policy.
-- While they had different tiers a later event could overtake an earlier one
-- purely because STANDARD was held back out of a class block and MAJOR was
-- not; with both MAJOR, delivery order can only follow event order.
CREATE OR REPLACE FUNCTION public.notify_group_ping_first_reply()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
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
         'Someone in ' || COALESCE(v_name,'your group') || ' replied 👀',
         jsonb_build_object('screen','group','group_id', v_group, 'thread_id', v_thread),
         'group_ping_replied:' || v_thread::text || ':' || mem.receiver_id::text
  FROM public.pings mem
  WHERE mem.thread_id = v_thread
    AND mem.receiver_id IS NOT NULL
    AND mem.receiver_id <> NEW.replier_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;
