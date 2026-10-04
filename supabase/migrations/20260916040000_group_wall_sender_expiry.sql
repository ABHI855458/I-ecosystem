-- The group wall outlived its own timers for the person who SENT it.
--
-- my_group_walls() gated the 12h-to-open / 6h-to-reply windows on the
-- viewer's own `pings` row (alias m). The sender has no such row — they are
-- the asker, not a receiver — so `m.id IS NULL` short-circuited every window
-- and their wall simply sat there until the 7-day floor. Reported against a
-- thread 3 days old with 0 of 2 answered and 0 opened: both receivers' 12h
-- windows had long expired, nobody could still answer it, and it was still
-- on the sender's Ping page.
--
-- The thread's life is now derived from the RECEIVERS, which is where the
-- rules actually live:
--   * a ping is still live while its owner can act on it — unopened inside
--     12h, or opened inside 6h;
--   * once every ping has been replied to, the thread stays 3 more hours so
--     the answers can be read;
--   * a thread nobody can act on any more is over, for everyone, sender
--     included.
CREATE OR REPLACE FUNCTION public.my_group_walls()
RETURNS TABLE(thread_id uuid, group_id uuid, group_name text, prompt text, created_at timestamp without time zone, window_hours integer, anonymous boolean, asked_by text, my_ping_id uuid, unlocked boolean, answered integer, total integer)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH me AS (SELECT public.current_user_id() AS id),
  mine AS (
    SELECT p.thread_id, p.id, p.created_at AS ping_created_at, p.seen_at, p.replied_at
      FROM public.pings p, me
     WHERE p.receiver_id = me.id
  ),
  thread_stats AS (
    SELECT p3.thread_id,
           count(*)::int AS total_pings,
           count(*) FILTER (WHERE p3.replied_at IS NOT NULL)::int AS replied_pings,
           max(p3.replied_at) AS last_reply_at,
           -- Any receiver who can still act on this thread at all.
           count(*) FILTER (
             WHERE p3.replied_at IS NULL
               AND (
                 (p3.seen_at IS NULL
                   AND now() < (p3.created_at AT TIME ZONE 'UTC') + interval '12 hours')
                 OR (p3.seen_at IS NOT NULL
                   AND now() < (p3.seen_at AT TIME ZONE 'UTC') + interval '6 hours')
               )
           )::int AS still_open_pings
      FROM public.pings p3
     GROUP BY p3.thread_id
  )
  SELECT DISTINCT ON (t.id)
    t.id, t.group_id, g.name, t.prompt, t.created_at, t.window_hours,
    t.anonymous,
    CASE WHEN t.anonymous THEN t.anon_display_name ELSE su.name END,
    m.id,
    (t.sender_id = (SELECT id FROM me)) OR public.has_answered_thread(t.id, (SELECT id FROM me)),
    COALESCE(ts.replied_pings, 0),
    COALESCE(ts.total_pings, 0)
  FROM public.ping_threads t
  JOIN public.groups g ON g.id = t.group_id
  LEFT JOIN public.users su ON su.id = t.sender_id
  LEFT JOIN mine m ON m.thread_id = t.id
  LEFT JOIN thread_stats ts ON ts.thread_id = t.id
  , me
  WHERE t.kind = 'group'
    AND public.is_group_member(t.group_id, me.id)
    AND t.created_at > now() - interval '7 days'
    -- Thread-level life: somebody can still answer, or everyone has and the
    -- 3h reading window is still open. Applies to sender and receiver alike.
    AND (
      ts.total_pings IS NULL
      OR ts.still_open_pings > 0
      OR (ts.replied_pings = ts.total_pings
          AND now() < (ts.last_reply_at AT TIME ZONE 'UTC') + interval '3 hours')
    )
    -- Viewer-level life: a receiver additionally drops out once their own
    -- window shuts, even while others are still open. The sender has no
    -- ping row and so rides the thread-level rule alone.
    AND (
      m.id IS NULL
      OR m.replied_at IS NOT NULL
      OR (m.seen_at IS NULL
          AND now() < (m.ping_created_at AT TIME ZONE 'UTC') + interval '12 hours')
      OR (m.seen_at IS NOT NULL
          AND now() < (m.seen_at AT TIME ZONE 'UTC') + interval '6 hours')
    )
  ORDER BY t.id, t.created_at DESC;
$$;
