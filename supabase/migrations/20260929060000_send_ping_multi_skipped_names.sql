-- send_ping_multi also returns WHO was skipped for already holding an open
-- ping from me (user report 2026-09-29: "pinged several people, showing
-- only two" — the app only said "5 already had an open ping"). Names only,
-- of people I chose to ping myself; no new information is exposed.
CREATE OR REPLACE FUNCTION public.send_ping_multi(
  p_receiver_ids uuid[],
  p_prompt text,
  p_anonymous boolean DEFAULT false,
  p_window_hours integer DEFAULT 5,
  p_photo_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_me uuid;
  v_thread uuid;
  v_label text;
  v_eligible uuid[] := '{}';
  v_open int := 0;
  v_blocked int := 0;
  v_open_names text[] := '{}';
  r uuid;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;

  FOR r IN SELECT DISTINCT x FROM unnest(p_receiver_ids) x WHERE x IS NOT NULL LOOP
    IF r = v_me THEN
      CONTINUE;
    ELSIF public.is_blocked_user(auth.uid(), r) THEN
      v_blocked := v_blocked + 1;
    ELSIF EXISTS (
      SELECT 1 FROM public.pings
       WHERE sender_id = v_me AND receiver_id = r
         AND status = 'pending' AND group_id IS NULL AND expires_at > now()
    ) THEN
      v_open := v_open + 1;
      v_open_names := v_open_names
        || COALESCE((SELECT NULLIF(btrim(name), '') FROM public.users WHERE id = r), 'someone');
    ELSE
      v_eligible := v_eligible || r;
    END IF;
  END LOOP;

  IF cardinality(v_eligible) > 0 THEN
    IF p_anonymous THEN
      v_label := public.my_ping_anon_label(v_me);
    END IF;

    INSERT INTO public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours, photo_url)
    VALUES (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
    RETURNING id INTO v_thread;

    INSERT INTO public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours, photo_url)
    SELECT v_thread, v_me, x, p_prompt, p_anonymous, p_window_hours, p_photo_url
      FROM unnest(v_eligible) x;
  END IF;

  RETURN jsonb_build_object(
    'thread_id', v_thread,
    'sent', cardinality(v_eligible),
    'already_open', v_open,
    'already_open_names', to_jsonb(v_open_names),
    'blocked', v_blocked
  );
END;
$$;
