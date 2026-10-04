-- ============================================================================
-- PING — 5h reply window (was 3h).
--
-- CREATE OR REPLACE only — no ALTER on existing rows. A ping already in
-- flight keeps whatever window_hours it was sent with; only pings sent
-- after this migration get 5h. Both functions are otherwise byte-identical
-- to 20260906000000's originals, just the default changed.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_ping(
  p_receiver_id  UUID,
  p_prompt       TEXT,
  p_anonymous    BOOLEAN DEFAULT false,
  p_window_hours INT DEFAULT 5
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_me UUID;
  v_thread UUID;
  v_label TEXT;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_receiver_id = v_me THEN RAISE EXCEPTION 'Cannot ping yourself.'; END IF;

  IF p_anonymous THEN
    v_label := public.gen_handle();
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours)
  VALUES (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours)
  VALUES (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours);

  RETURN v_thread;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_group_ping(
  p_group_id     UUID,
  p_prompt       TEXT,
  p_anonymous    BOOLEAN DEFAULT false,
  p_window_hours INT DEFAULT 5
) RETURNS TABLE(thread_id UUID, recipients INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
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

  RETURN QUERY SELECT v_thread, v_n;
END;
$$;
