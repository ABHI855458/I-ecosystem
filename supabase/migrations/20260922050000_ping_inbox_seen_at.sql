-- ping_inbox() did not return pings.seen_at, so the client had no way to know
-- which inbound pings the user had already held-to-reveal. PingPage kept that
-- purely in an in-memory map, which meant every relaunch re-blurred a ping the
-- user had already opened and forced the hold-to-reveal again.
--
-- seen_at is already written by mark_ping_seen() at the instant of the reveal,
-- so the durable record existed all along — it just never reached the client.
-- Appended LAST so every existing column keeps its position.
--
-- Body is otherwise byte-identical to the live definition; the return type
-- changes, so this has to DROP before CREATE.
DROP FUNCTION IF EXISTS public.ping_inbox();

CREATE FUNCTION public.ping_inbox()
RETURNS TABLE(
  ping_id uuid, thread_id uuid, kind text, prompt text,
  created_at timestamp without time zone, window_hours integer, status text,
  anonymous boolean, group_id uuid, group_name text, group_size integer,
  sender_id uuid, sender_name text, sender_avatar text,
  expires_at timestamp with time zone, photo_url text,
  seen_at timestamp without time zone
)
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
    p.seen_at
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

GRANT EXECUTE ON FUNCTION public.ping_inbox() TO authenticated;
