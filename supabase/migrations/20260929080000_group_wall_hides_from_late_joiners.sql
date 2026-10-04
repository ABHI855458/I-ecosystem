-- A group ping sent before someone joined the group was still showing up on
-- their Ping page the moment they joined (user report 2026-09-29: "after
-- pinging the group if the person joins then the ping shall not be seen to
-- him — the pinging group pings shall be seen in the next future pings to
-- him"). They should only ever see group pings sent from the point they
-- joined onward.
--
-- Root cause: my_group_walls()'s viewer-level life clause treats "I have no
-- `pings` row for this thread" (`m.id IS NULL`) as "still open to me" — a
-- rule written specifically for the SENDER of a non-anonymous group ping
-- (send_group_ping excludes the asker from their own non-anonymous send, so
-- they genuinely have no row — see 20260916040000_group_wall_sender_expiry
-- .sql's own doc). It never distinguished that case from ANY OTHER member
-- with no row, which is exactly what a late joiner looks like too (their
-- membership didn't exist yet when send_group_ping's INSERT ran, so no row
-- was ever created for them). Both were let through identically.
--
-- Fix: only the actual sender gets the "no row, still counts" exception.
-- Anyone else with no row (a late joiner, or someone send_group_ping
-- skipped as blocked) is excluded, same as it already excludes ping_inbox()
-- — that function was never affected, since it selects `pings` directly
-- and a missing row there already meant "nothing to show".
CREATE OR REPLACE FUNCTION public.my_group_walls()
RETURNS TABLE(thread_id uuid, group_id uuid, group_name text, prompt text, created_at timestamp without time zone, window_hours integer, anonymous boolean, asked_by text, my_ping_id uuid, unlocked boolean, answered integer, total integer, photo_url text, group_icon_url text)
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
    public.has_answered_thread(t.id, (SELECT id FROM me)),
    COALESCE(ts.replied_pings, 0),
    COALESCE(ts.total_pings, 0),
    t.photo_url,
    g.icon_url
  FROM public.ping_threads t
  JOIN public.groups g ON g.id = t.group_id
  LEFT JOIN public.users su ON su.id = t.sender_id
  LEFT JOIN mine m ON m.thread_id = t.id
  LEFT JOIN thread_stats ts ON ts.thread_id = t.id
  , me
  WHERE t.kind = 'group'
    AND public.is_group_member(t.group_id, me.id)
    AND t.created_at > now() - interval '7 days'
    AND (
      ts.total_pings IS NULL
      OR ts.still_open_pings > 0
      OR (ts.replied_pings = ts.total_pings
          AND now() < (ts.last_reply_at AT TIME ZONE 'UTC') + interval '3 hours')
    )
    AND (
      -- Only the SENDER rides the thread-level rule with no row of their
      -- own. Anyone else with no row (a late joiner; someone
      -- send_group_ping skipped as blocked) never sees this thread.
      (m.id IS NULL AND t.sender_id = (SELECT id FROM me))
      OR m.replied_at IS NOT NULL
      OR (m.seen_at IS NULL
          AND now() < (m.ping_created_at AT TIME ZONE 'UTC') + interval '12 hours')
      OR (m.seen_at IS NOT NULL
          AND now() < (m.seen_at AT TIME ZONE 'UTC') + interval '6 hours')
    )
  ORDER BY t.id, t.created_at DESC;
$$;
