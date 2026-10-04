-- ping_inbox() — expose pings.photo_opened_at (added in
-- 20260924010000_ping_photo_one_time_view.sql) so the client can tell a
-- still-viewable attached photo from one whose one-time view was already
-- spent. Reproduced verbatim from the live definition; only the new column
-- is added, at the end of the SELECT list, so it's additive to the existing
-- shape rather than reordering anything callers already positionally index
-- into (this file's own client mapping reads by key, not position, but no
-- reason to disturb the rest).
--
-- DROP first: this adds a column to the RETURNS TABLE, and a bare CREATE OR
-- REPLACE fails with "cannot change return type of existing function" (hit
-- this for real on score_leaderboard earlier — same shape of change).
DROP FUNCTION IF EXISTS public.ping_inbox();

CREATE OR REPLACE FUNCTION public.ping_inbox()
RETURNS TABLE(ping_id uuid, thread_id uuid, kind text, prompt text, created_at timestamp without time zone, window_hours integer, status text, anonymous boolean, group_id uuid, group_name text, group_size integer, sender_id uuid, sender_name text, sender_avatar text, expires_at timestamp with time zone, photo_url text, seen_at timestamp without time zone, photo_opened_at timestamp with time zone)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  select
    p.id, p.thread_id, t.kind, p.prompt, p.created_at, p.window_hours,
    p.status, p.anonymous,
    p.group_id,
    g.name,
    (select count(*)::int from public.group_members gm where gm.group_id = p.group_id),
    case when p.anonymous then null else p.sender_id end,
    case when p.anonymous then t.anon_display_name else u.name end,
    case when p.anonymous then null else u.profile_photo_url end,
    p.expires_at,
    p.photo_url,
    p.seen_at,
    p.photo_opened_at
  from public.pings p
  join public.ping_threads t on t.id = p.thread_id
  left join public.users u on u.id = p.sender_id
  left join public.groups g on g.id = p.group_id
  where p.receiver_id = public.current_user_id()
    and p.sender_id <> p.receiver_id
    and p.expires_at > now()
    and (p.group_id is not null or not public.is_blocked_user(auth.uid(), p.sender_id))
  order by p.created_at desc;
$function$;
