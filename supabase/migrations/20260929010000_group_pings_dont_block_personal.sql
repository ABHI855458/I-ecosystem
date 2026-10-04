-- A GROUP ping no longer blocks pinging its members personally (bug found
-- 2026-09-29: a 7-person "Ping many" sent to only 2 — three recipients were
-- skipped as "already had an open ping" purely because they were in the
-- sender's group ping from the day before). The one-open-ping-per-person
-- rule is for 1:1 pings only, so both checks now require group_id IS NULL.
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

  if public.is_blocked_user(auth.uid(), p_receiver_id) then
    raise exception 'Cannot ping this user.';
  end if;

  select max(expires_at) into v_open_until
    from public.pings
   where sender_id = v_me
     and receiver_id = p_receiver_id
     and status = 'pending'
     and group_id is null
     and expires_at > now();

  if v_open_until is not null then
    raise exception 'PING_ALREADY_OPEN:%',
      to_char(v_open_until at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  end if;

  if p_anonymous then
    v_label := public.my_ping_anon_label(v_me);
  end if;

  insert into public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours, photo_url)
  values (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
  returning id into v_thread;

  insert into public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours, photo_url)
  values (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours, p_photo_url);

  return v_thread;
end;
$function$;

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
    'blocked', v_blocked
  );
END;
$$;

