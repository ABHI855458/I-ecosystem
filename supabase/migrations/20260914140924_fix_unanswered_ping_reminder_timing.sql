-- CORRECTION to the previous migration's timing.
--
-- pings.expires_at is a GENERATED column and does NOT use window_hours:
--   seen_at IS NOT NULL -> seen_at   + 6 hours
--   otherwise           -> created_at + 24 hours
-- window_hours (3-5 in live data) is carried on the row but does not drive
-- expiry at all, so the first version would have nudged an unseen ping at
-- ~22h — hours after it stopped mattering.
--
-- Halfway is therefore computed from whichever clock actually applies:
--   seen   -> seen_at    + 3h   (half of 6h)
--   unseen -> created_at + 12h  (half of 24h)
-- created_at is `timestamp without time zone` holding UTC (verified: db TZ
-- is UTC and expires_at - created_at AT TIME ZONE 'UTC' = exactly 1 day),
-- so it is lifted with AT TIME ZONE 'UTC' rather than left to an implicit
-- session-dependent cast.

CREATE OR REPLACE FUNCTION public.ping_nudge_due_at(p_created timestamp, p_seen timestamp)
RETURNS timestamptz LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_seen IS NOT NULL THEN (p_seen    AT TIME ZONE 'UTC') + INTERVAL '3 hours'
    ELSE                         (p_created AT TIME ZONE 'UTC') + INTERVAL '12 hours'
  END;
$$;

CREATE OR REPLACE FUNCTION public.notify_unanswered_pings()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  -- Personal ping, unanswered, past halfway, not yet expired.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'ping_unanswered', NULL, 'major',
         'Someone is still waiting on you 👀',
         p.prompt,
         jsonb_build_object('screen','ping','ping_id', p.id),
         'ping_unanswered:' || p.id::text
  FROM public.pings p
  WHERE p.group_id IS NULL
    AND p.receiver_id IS NOT NULL
    AND p.receiver_id <> p.sender_id
    AND p.replied_at IS NULL
    AND p.expires_at > now()
    AND now() >= public.ping_nudge_due_at(p.created_at, p.seen_at)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  -- Group thread with at least one member still silent. Goes to EVERY
  -- member of the thread, repliers included, and carries a count only.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT mem.receiver_id, 'group_ping_waiting', NULL, 'major',
         CASE WHEN t.waiting = 1
              THEN 'Someone in ' || COALESCE(g.name,'your group') || ' still hasn''t replied 👀'
              ELSE t.waiting || ' people in ' || COALESCE(g.name,'your group') || ' still haven''t replied 👀'
         END,
         t.prompt,
         jsonb_build_object('screen','group','group_id', t.group_id, 'thread_id', t.thread_id),
         'group_ping_waiting:' || t.thread_id::text || ':' || mem.receiver_id::text
  FROM (
    SELECT p.thread_id, p.group_id, min(p.prompt) AS prompt,
           count(*) FILTER (WHERE p.replied_at IS NULL) AS waiting,
           max(p.expires_at) AS expires_at,
           min(public.ping_nudge_due_at(p.created_at, p.seen_at)) AS nudge_at
    FROM public.pings p
    WHERE p.group_id IS NOT NULL AND p.thread_id IS NOT NULL
    GROUP BY p.thread_id, p.group_id
    HAVING count(*) FILTER (WHERE p.replied_at IS NULL) > 0
  ) t
  JOIN public.groups g ON g.id = t.group_id
  JOIN public.pings mem ON mem.thread_id = t.thread_id AND mem.receiver_id IS NOT NULL
  WHERE t.expires_at > now()
    AND now() >= t.nudge_at
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
END;
$$;
