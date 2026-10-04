-- A ping can carry a photo, not just a prompt — "when a person pings he
-- shall also send a photo, not only [text]... the photo sending in ping for
-- groups". Replies already supported photos; the OUTBOUND ping did not, so
-- the asker could only ever send words.
--
-- Stored on both tables on purpose: ping_threads is the one row per ping
-- EVENT (what the sender composed), pings is the per-receiver copy the inbox
-- and wall read from. Denormalising the url onto the receiver rows keeps
-- ping_inbox a single-join read, exactly as it is today.
--
-- my_group_walls also carries it (the group wall shows the asker photo), and
-- keeps the receiver-derived expiry rules introduced in
-- 20260916040000_group_wall_sender_expiry.sql.
ALTER TABLE public.ping_threads ADD COLUMN IF NOT EXISTS photo_url text;
ALTER TABLE public.pings        ADD COLUMN IF NOT EXISTS photo_url text;

DROP FUNCTION IF EXISTS public.send_ping(uuid, text, boolean, integer);
DROP FUNCTION IF EXISTS public.send_group_ping(uuid, text, boolean, integer);
DROP FUNCTION IF EXISTS public.ping_inbox();
DROP FUNCTION IF EXISTS public.my_group_walls();

CREATE OR REPLACE FUNCTION public.my_group_walls()
 RETURNS TABLE(thread_id uuid, group_id uuid, group_name text, prompt text, created_at timestamp without time zone, window_hours integer, anonymous boolean, asked_by text, my_ping_id uuid, unlocked boolean, answered integer, total integer, photo_url text)
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
    (t.sender_id = (SELECT id FROM me)) OR public.has_answered_thread(t.id, (SELECT id FROM me)),
    COALESCE(ts.replied_pings, 0),
    COALESCE(ts.total_pings, 0),
    t.photo_url
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
$function$
;

CREATE OR REPLACE FUNCTION public.ping_inbox()
 RETURNS TABLE(ping_id uuid, thread_id uuid, kind text, prompt text, created_at timestamp without time zone, window_hours integer, status text, anonymous boolean, group_id uuid, group_name text, group_size integer, sender_id uuid, sender_name text, sender_avatar text, expires_at timestamp with time zone, photo_url text)
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
    p.photo_url
  from public.pings p
  join public.ping_threads t on t.id = p.thread_id
  left join public.users u on u.id = p.sender_id
  left join public.groups g on g.id = p.group_id
  where p.receiver_id = public.current_user_id()
    and p.sender_id <> p.receiver_id
    and p.expires_at > now()
  order by p.created_at desc;
$function$
;

CREATE OR REPLACE FUNCTION public.send_group_ping(p_group_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5, p_photo_url text DEFAULT NULL::text)
 RETURNS TABLE(thread_id uuid, recipients integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me UUID;
  v_thread UUID;
  v_label TEXT;
  v_n INT;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.is_group_member(p_group_id, v_me) THEN
    RAISE EXCEPTION 'Not a member of that group.';
  END IF;

  IF p_anonymous THEN
    v_label := public.gen_handle();
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, group_id, prompt, anonymous, anon_display_name, window_hours, photo_url)
  VALUES (v_me, 'group', p_group_id, p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, group_id, prompt, anonymous, window_hours, photo_url)
  SELECT v_thread, v_me, gm.user_id, p_group_id, p_prompt, p_anonymous, p_window_hours, p_photo_url
    FROM public.group_members gm
   WHERE gm.group_id = p_group_id
     AND (p_anonymous OR gm.user_id <> v_me);

  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n = 0 THEN
    DELETE FROM public.ping_threads WHERE id = v_thread;
    RETURN QUERY SELECT NULL::UUID, 0;
    RETURN;
  END IF;

  UPDATE public.users SET ping_score = ping_score + 25 WHERE id = v_me;
  PERFORM public.open_group_ping_day(p_group_id, v_thread);

  RETURN QUERY SELECT v_thread, v_n;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.send_ping(p_receiver_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5, p_photo_url text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
  v_thread uuid;
  v_label text;
  v_open_until timestamptz;
begin
  v_me := public.current_user_id();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if p_receiver_id = v_me then raise exception 'Cannot ping yourself.'; end if;

  select max(expires_at) into v_open_until
    from public.pings
   where sender_id = v_me
     and receiver_id = p_receiver_id
     and status = 'pending'
     and expires_at > now();

  if v_open_until is not null then
    raise exception 'PING_ALREADY_OPEN:%',
      to_char(v_open_until at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  end if;

  if p_anonymous then
    v_label := public.gen_handle();
  end if;

  insert into public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours, photo_url)
  values (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
  returning id into v_thread;

  insert into public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours, photo_url)
  values (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours, p_photo_url);

  update public.users set ping_score = ping_score + 25 where id = v_me;
  perform public.bump_daily_streak(v_me);

  return v_thread;
end;
$function$
;

REVOKE ALL ON FUNCTION public.send_ping(uuid, text, boolean, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_ping(uuid, text, boolean, integer, text) TO authenticated;
REVOKE ALL ON FUNCTION public.send_group_ping(uuid, text, boolean, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_group_ping(uuid, text, boolean, integer, text) TO authenticated;
REVOKE ALL ON FUNCTION public.ping_inbox() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ping_inbox() TO authenticated;
REVOKE ALL ON FUNCTION public.my_group_walls() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_group_walls() TO authenticated;
