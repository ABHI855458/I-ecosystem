-- Returns the group's DP alongside each wall thread.
--
-- The Group Wall card drew generated initial+tint circles for the group
-- and every member, even where real photos existed. Member DPs were
-- purely a client bug (get_group_wall has always returned
-- memberAvatarUrl; ping_page.dart just ignored it). The GROUP dp is the
-- half that genuinely could not be fixed client-side: my_group_walls
-- never returned groups.icon_url, so the client had nothing to render.
--
-- Purely additive: `group_icon_url` is appended as the LAST column, so
-- any caller reading by name or by existing position is unaffected. The
-- `groups g` join it reads from was already in the query for g.name.
--
-- Everything else is reproduced VERBATIM from the live
-- pg_get_functiondef output — this is a faithful CREATE OR REPLACE, not
-- a rewrite. Diffed to confirm only the two intended lines differ.
--
-- Note: DROP first. Postgres will not CREATE OR REPLACE a function whose
-- RETURNS TABLE signature changed ("cannot change return type of
-- existing function"), and adding a column counts.

DROP FUNCTION IF EXISTS public.my_group_walls();

CREATE OR REPLACE FUNCTION public.my_group_walls()
 RETURNS TABLE(thread_id uuid, group_id uuid, group_name text, prompt text, created_at timestamp without time zone, window_hours integer, anonymous boolean, asked_by text, my_ping_id uuid, unlocked boolean, answered integer, total integer, photo_url text, group_icon_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      m.id IS NULL
      OR m.replied_at IS NOT NULL
      OR (m.seen_at IS NULL
          AND now() < (m.ping_created_at AT TIME ZONE 'UTC') + interval '12 hours')
      OR (m.seen_at IS NOT NULL
          AND now() < (m.seen_at AT TIME ZONE 'UTC') + interval '6 hours')
    )
  ORDER BY t.id, t.created_at DESC;
$function$;
