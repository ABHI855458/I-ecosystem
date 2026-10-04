-- GROUP PING SEND — log the score event that already exists as a real award.
--
-- THE BUG: send_group_ping already does `UPDATE users SET ping_score =
-- ping_score + 25` for the sender (once per SEND, not once per fan-out
-- row — verified live: the UPDATE sits outside the per-member INSERT, so
-- pinging a 5-person group still only pays 25, not 125). The points ARE
-- real. But it never calls log_score_event, unlike every other award path
-- in this codebase (award_ping_sent_score's own trigger for 1:1 does; so
-- does award_ping_reply_score). ScoreGainService.since() — what drives the
-- reward dropdown — reads score_events, not users.ping_score directly, so
-- it always saw gained=0 for a group send despite the real +25 having
-- landed. Reported as "for group pings in the dropdown isn't giving any
-- points" — the score was never missing, only the RECEIPT of it was.
--
-- FIX: log the event. Same 'ping_sent' type and same 25 amount already used
-- for 1:1 — this is the same reward for the same action (sending a ping),
-- not a new point value; only the audience differs. No new event_type
-- needed, so ScoreGainService's existing 'ping_sent' -> 'Ping sent' label
-- mapping already covers it with no client-side label change.
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
     AND NOT public.is_blocked_user(auth.uid(), gm.user_id)
  -- Everyone in the group is pinged, including people invited but not yet
  -- accepted (group_invites). They can open and answer their own ping
  -- (pings_select / ping_replies_insert key on receiver_id); the group
  -- wall's other answers stay members-only until they accept.
  UNION
  SELECT v_thread, v_me, gi.invitee_id, p_group_id, p_prompt, p_anonymous, p_window_hours, p_photo_url
    FROM public.group_invites gi
   WHERE gi.group_id = p_group_id
     AND NOT public.is_blocked_user(auth.uid(), gi.invitee_id);

  SELECT count(*) INTO v_n
    FROM public.pings pp WHERE pp.thread_id = v_thread AND pp.receiver_id <> v_me;

  IF v_n = 0 THEN
    DELETE FROM public.ping_threads WHERE id = v_thread;
    DELETE FROM public.pings WHERE pings.thread_id = v_thread;
    RETURN QUERY SELECT NULL::UUID, 0;
    RETURN;
  END IF;

  UPDATE public.users SET ping_score = ping_score + 25 WHERE id = v_me;
  -- THE FIX: the one line this migration adds. Same call, same event_type,
  -- same amount as the 1:1 trigger — this is the receipt for an award that
  -- was already happening, not a new award.
  PERFORM public.log_score_event(v_me, 'ping_sent', 25);
  PERFORM public.open_group_ping_day(p_group_id, v_thread);

  RETURN QUERY SELECT v_thread, v_n;
END;
$function$;
