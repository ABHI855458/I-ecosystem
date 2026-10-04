-- Adds the dual-capture selfie to a ping reply's photo. Restores the
-- front-lens second shot in PingCameraScreen (ping_reveal_screen.dart) —
-- previously removed, leaving the top-left "selfie inset" on every reply
-- photo render site as a permanently empty placeholder Container. Nullable:
-- a text-only reply has neither photo nor selfie, and an ALBUM pick (single
-- image, no dual capture) has a photo but no selfie — the null is exactly
-- what tells the client not to show the inset at all for an album reply.
--
-- NOTE: this project's live DB migration ledger is drifted from what
-- `supabase migration list` believes is applied (see the project's own
-- notes on ping_post_author/send_ping/send_group_ping already existing
-- live with no tracked migration row) — this file is applied directly via
-- `supabase db query --linked -f`, not `db push`, and will not gain a
-- remote ledger row either.

ALTER TABLE public.ping_replies
  ADD COLUMN IF NOT EXISTS selfie_url TEXT;

-- get_group_wall needs to surface the selfie too, so a revealed wall tile
-- can show it the same way _photoView does for a person-ping reply. The
-- return row shape is changing (one column added), which Postgres won't
-- let CREATE OR REPLACE do in place — drop and recreate instead.
DROP FUNCTION IF EXISTS public.get_group_wall(uuid);

CREATE FUNCTION public.get_group_wall(p_thread_id uuid)
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

  v_unlocked := (v_me = v_sender) OR public.has_answered_thread(p_thread_id, v_me);

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
$function$;
