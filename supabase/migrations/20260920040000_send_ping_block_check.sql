-- send_ping / send_group_ping had no block check at all — a blocked user
-- could still ping (or be pinged by) someone who blocked them, and a
-- blocker in a shared group still received group pings from someone
-- they'd blocked. Flagged twice, never applied until now.
--
-- TWO near-miss functions existed and neither is a drop-in call here:
--   is_blocked(a, b)             — both args must be `blocks`' own id
--                                   space, which turned out to be AUTH
--                                   uids (blocks_blocker_id_fkey ->
--                                   profiles(id), and profiles.id ==
--                                   users.auth_id, verified live — 0 of 11
--                                   users.id values exist in profiles.id
--                                   at all). Calling it with v_me/
--                                   p_receiver_id (both users.id) would
--                                   have compiled cleanly and silently
--                                   matched nothing, ever.
--   is_blocked_user(viewer_auth,
--                    target_user_id)  — the actually-correct one: takes
--                                   the CALLER's auth uid plus the
--                                   target's ordinary users.id and joins
--                                   through users.auth_id itself,
--                                   symmetric in both directions. This is
--                                   what block_service.dart's own RLS
--                                   checks use elsewhere, and what's
--                                   called below. Verified against a real
--                                   inserted block row before relying on
--                                   it (rolled back): returned true.
--
-- viewer_auth is auth.uid() directly, not a second lookup of v_me's own
-- auth_id — both SECURITY DEFINER functions already run inside the
-- caller's session, so auth.uid() IS the caller, no extra query needed.
--
-- Every other line below is byte-for-byte the live function as of this
-- migration — pulled fresh via pg_get_functiondef immediately before
-- writing this file, not reconstructed from memory.
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

  -- THE FIX.
  if public.is_blocked_user(auth.uid(), p_receiver_id) then
    raise exception 'Cannot ping this user.';
  end if;

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
$function$;

-- THE FIX for the group path: a blocked/blocking member is filtered
-- straight out of the fan-out INSERT's own WHERE, so they are never
-- inserted as a recipient in the first place — not inserted then hidden.
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
     -- gm.user_id is users.id (verified live — matches users.id, not
     -- auth_id), which is exactly is_blocked_user's target_user_id shape.
     AND NOT public.is_blocked_user(auth.uid(), gm.user_id);

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
$function$;
