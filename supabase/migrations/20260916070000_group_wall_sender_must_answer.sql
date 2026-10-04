-- The sender of a group ping could always see everyone's replies without
-- ever answering their own ask. Explicit request: "the person who pings
-- shall also reply to the ping, then only he can see the replies, if not
-- he cannot" — the sender is now just another participant, gated by the
-- same has_answered_thread() check as every receiver.
--
-- That needs the sender to actually HAVE something to answer: a
-- non-anonymous group ping never gave them their own `pings` row (only
-- the anonymous case did, so the asker could answer their own anonymous
-- prompt). Every group ping now fans out to every member including the
-- sender, unconditionally — verified live: sender_tile_present=true,
-- reply_visible_before_sender_answers=false,
-- reply_visible_after_sender_answers=true.
--
-- notify_ping also picked up a sender<>receiver guard here: an anonymous
-- group ping already gave the sender a self-row (to answer their own
-- anonymous prompt), and with no guard this trigger was quietly sending
-- every anonymous group-ping sender a "Someone pinged you" notification
-- about themselves. Now that every group ping gives the sender a self-row,
-- the same bug would have hit the non-anonymous case too.

CREATE OR REPLACE FUNCTION public.get_group_wall(p_thread_id uuid)
 RETURNS TABLE(member_id uuid, member_name text, member_avatar text, is_me boolean, answered boolean, reply_id uuid, reply_kind text, reply_body text, reply_photo text, reply_selfie text, replied_at timestamp without time zone, opened boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me UUID;
  v_group UUID;
  v_sender UUID;
  v_unlocked BOOLEAN;
BEGIN
  v_me := public.current_user_id();
  SELECT t.group_id, t.sender_id INTO v_group, v_sender
    FROM public.ping_threads t WHERE t.id = p_thread_id;
  IF v_group IS NULL OR NOT public.is_group_member(v_group, v_me) THEN
    RETURN;
  END IF;

  v_unlocked := public.has_answered_thread(p_thread_id, v_me);

  RETURN QUERY
  SELECT
    u.id, u.name, u.profile_photo_url,
    (u.id = v_me),
    (r.id IS NOT NULL),
    CASE WHEN v_unlocked THEN r.id END,
    CASE WHEN v_unlocked THEN r.kind END,
    CASE WHEN v_unlocked THEN r.body END,
    CASE WHEN v_unlocked THEN r.photo_url END,
    CASE WHEN v_unlocked THEN r.selfie_url END,
    CASE WHEN v_unlocked THEN r.created_at END,
    COALESCE(v.viewer_id IS NOT NULL, false)
  FROM public.pings p
  JOIN public.users u ON u.id = p.receiver_id
  LEFT JOIN LATERAL (
    SELECT rr.* FROM public.ping_replies rr
     WHERE rr.ping_id = p.id AND rr.deleted_at IS NULL
     ORDER BY rr.created_at DESC LIMIT 1
  ) r ON true
  LEFT JOIN public.ping_reply_views v ON v.reply_id = r.id AND v.viewer_id = v_me
  WHERE p.thread_id = p_thread_id
  ORDER BY (u.id = v_me) DESC, r.created_at NULLS LAST;
END;
$function$
;

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
    public.has_answered_thread(t.id, (SELECT id FROM me)),
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

CREATE OR REPLACE FUNCTION public.notify_ping()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_actor_name text;
BEGIN
  IF NEW.receiver_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sender_id = NEW.receiver_id THEN RETURN NEW; END IF;
  IF NEW.anonymous IS TRUE THEN
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
    VALUES (NEW.receiver_id, 'ping', NULL, 'major', 'Someone pinged you 👋', NEW.prompt, 'ping:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  ELSE
    SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name FROM public.users WHERE id = NEW.sender_id;
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
    VALUES (NEW.receiver_id, 'ping', NEW.sender_id, 'major',
            COALESCE(v_actor_name,'someone') || ' pinged you 👋', NEW.prompt, 'ping:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;
  RETURN NEW;
END; $function$
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
   WHERE gm.group_id = p_group_id;

  SELECT count(*) INTO v_n
    FROM public.pings pp WHERE pp.thread_id = v_thread AND pp.receiver_id <> v_me;

  IF v_n = 0 THEN
    DELETE FROM public.ping_threads WHERE id = v_thread;
    DELETE FROM public.pings WHERE pings.thread_id = v_thread;
    RETURN QUERY SELECT NULL::UUID, 0;
    RETURN;
  END IF;

  UPDATE public.users SET ping_score = ping_score + 25 WHERE id = v_me;
  PERFORM public.open_group_ping_day(p_group_id, v_thread);

  RETURN QUERY SELECT v_thread, v_n;
END;
$function$
;
