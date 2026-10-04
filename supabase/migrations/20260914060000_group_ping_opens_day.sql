-- ---------------------------------------------------------------------------
-- STREAK SYSTEM v4 — send_group_ping() opens the day.
--
-- BLUE 2 is judged off group_ping_days: one row per (group, IST day),
-- carrying the roster snapshot the resolver checks replies against. Something
-- has to CREATE that row when the daily group ping goes out.
--
-- Done here, server-side inside send_group_ping itself, rather than as a
-- second call from the client: every existing group-ping entry point (the
-- ping page, the group profile, any future one) starts here, so the day
-- gets opened no matter which path sent it and no client can forget. It
-- also keeps the two writes in one transaction — a ping that exists with no
-- day row would be invisible to the resolver and silently un-streakable.
--
-- open_group_ping_day is idempotent per (group, day), so the 2nd..Nth ping
-- of the same day is a no-op and "the daily group ping" stays exactly one
-- judged event per day.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_group_ping(p_group_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5)
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

  INSERT INTO public.ping_threads (sender_id, kind, group_id, prompt, anonymous, anon_display_name, window_hours)
  VALUES (v_me, 'group', p_group_id, p_prompt, p_anonymous, v_label, p_window_hours)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, group_id, prompt, anonymous, window_hours)
  SELECT v_thread, v_me, gm.user_id, p_group_id, p_prompt, p_anonymous, p_window_hours
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

  -- Opens today's streak day for this group (no-op if already open).
  PERFORM public.open_group_ping_day(p_group_id, v_thread);

  RETURN QUERY SELECT v_thread, v_n;
END;
$function$;
