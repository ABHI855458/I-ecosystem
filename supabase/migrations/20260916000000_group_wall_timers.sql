-- Group wall visibility timers — explicit spec: "3 hr after everyone
-- replies, and 12 hrs to open once ping is sent and once opened, they can
-- send [a reply] in a 6 hr window."
--
-- Replaces my_group_walls()'s previous flat `created_at > now() - 7 days`
-- filter, which ignored the `window_hours` column entirely and left every
-- wall visible for a full week regardless of member activity — reported
-- live as "I can see the group wall... even though I haven't used the app
-- from past 24 hrs".
--
-- Two independent expiry clocks, both real requirements, not one:
--   * THREAD-level close — once EVERY member's ping has replied_at set,
--     the whole wall vanishes for everyone 3h after the last reply. This
--     is a hard close: nobody sees it again after that, answered or not.
--   * PER-MEMBER expiry — a member who hasn't answered YET loses their own
--     view of the wall if they miss their personal window: 12h to open it
--     (seen_at still null) from when the ping was sent, or 6h to reply
--     (replied_at still null) from when they opened it (seen_at). A member
--     who already answered keeps seeing the wall regardless of their own
--     window — only the thread-level close removes it for them.
--
-- ping_threads/pings' created_at/seen_at/replied_at are all `timestamp
-- without time zone` storing UTC wall-clock (same as ping_replies.created_at
-- — see ping_streak_between's own `AT TIME ZONE 'UTC'` reinterpretation,
-- the established idiom in this codebase for this exact column family).
-- The 7-day filter stays too, as an outer safety bound in case a thread
-- somehow never accrues full replies (e.g. a member leaves the group) —
-- without it that thread would otherwise never expire for members who
-- already answered.
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
           max(p3.replied_at) AS last_reply_at
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
    AND (
      -- Thread-level close: not yet everyone-replied, OR still within 3h
      -- of the last reply that completed it.
      ts.total_pings IS NULL
      OR ts.replied_pings < ts.total_pings
      OR now() < (ts.last_reply_at AT TIME ZONE 'UTC') + interval '3 hours'
    )
    AND (
      -- Per-member expiry: only bites an UNANSWERED member's own row.
      m.id IS NULL                          -- sender w/ no receiver row of their own
      OR m.replied_at IS NOT NULL           -- already answered — keeps seeing it
      OR (m.seen_at IS NULL
          AND now() < (m.ping_created_at AT TIME ZONE 'UTC') + interval '12 hours')
      OR (m.seen_at IS NOT NULL
          AND now() < (m.seen_at AT TIME ZONE 'UTC') + interval '6 hours')
    )
  ORDER BY t.id, t.created_at DESC;
$$;
