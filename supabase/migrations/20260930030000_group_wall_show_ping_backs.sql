-- A one-tap ping back ('👋' text reply) on a group ping carries no content,
-- so every member sees "X pinged back" in that slot even before they have
-- answered themselves. Photos and typed replies stay gated exactly as before.
CREATE OR REPLACE FUNCTION public.get_group_wall(p_thread_id uuid)
 RETURNS TABLE(member_id uuid, member_name text, member_avatar text, is_me boolean, answered boolean, reply_id uuid, reply_kind text, reply_body text, reply_photo text, reply_selfie text, replied_at timestamp without time zone, opened boolean, reaction_count integer, my_reaction boolean)
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
    CASE WHEN v_unlocked OR r.is_ping_back THEN r.id END,
    CASE WHEN v_unlocked OR r.is_ping_back THEN r.kind END,
    CASE WHEN v_unlocked OR r.is_ping_back THEN r.body END,
    CASE WHEN v_unlocked THEN r.photo_url END,
    CASE WHEN v_unlocked THEN r.selfie_url END,
    CASE WHEN v_unlocked OR r.is_ping_back THEN r.created_at END,
    COALESCE(v.viewer_id IS NOT NULL, false),
    CASE WHEN v_unlocked THEN COALESCE(rx.c, 0) ELSE 0 END,
    CASE WHEN v_unlocked THEN COALESCE(rx.mine, false) ELSE false END
  FROM public.pings p
  JOIN public.users u ON u.id = p.receiver_id
  LEFT JOIN LATERAL (
    SELECT rr.*,
           (rr.kind = 'text' AND rr.photo_url IS NULL
            AND btrim(rr.body) = '👋') AS is_ping_back
      FROM public.ping_replies rr
     WHERE rr.ping_id = p.id AND rr.deleted_at IS NULL
     ORDER BY rr.created_at DESC LIMIT 1
  ) r ON true
  LEFT JOIN public.ping_reply_views v ON v.reply_id = r.id AND v.viewer_id = v_me
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS c, bool_or(x.reactor_id = v_me) AS mine
    FROM public.ping_reply_reactions x
    WHERE x.reply_id = r.id
  ) rx ON true
  WHERE p.thread_id = p_thread_id
  ORDER BY (u.id = v_me) DESC, r.created_at NULLS LAST;
END;
$function$;
