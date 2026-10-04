-- One ping to several people = ONE thread (user request 2026-09-29: "sending
-- ping to multiple people ... everybody's replies come in the same box").
--
-- Before this, the client looped send_ping per person, so each recipient got
-- their own thread: replies arrived as unrelated cards, and a 4-person send
-- burned 4 of the 5-per-24h quota. Now every recipient's ping shares one
-- ping_threads row (kind 'person', group_id NULL):
--   * enforce_ping_limit counts DISTINCT thread_id, so the send costs 1.
--   * Privacy is unchanged: every "see other replies" path
--     (can_see_ping_reply, toggle_ping_reply_reaction, has_answered_thread
--     callers) is gated on group_id IS NOT NULL, so each reply stays between
--     the sender and that one recipient. Only the SENDER sees the grid.
--
-- Recipients who are blocked, are me, or already hold an open ping from me
-- are skipped (counted), not fatal. The thread is only created if at least
-- one recipient is eligible.
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
         AND status = 'pending' AND expires_at > now()
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

REVOKE ALL ON FUNCTION public.send_ping_multi(uuid[], text, boolean, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_ping_multi(uuid[], text, boolean, integer, text) TO authenticated;
