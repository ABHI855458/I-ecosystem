-- ============================================================================
-- Fix: the named (non-anonymous) sender of a group ping never gets their own
-- row in the fan-out (send_group_ping deliberately excludes them — see the
-- previous migration's doc, "everyone already knows they asked"). That means
-- has_answered_thread(thread, sender) is always false for them, since they
-- have no ping row of their own to attach a ping_replies row to.
--
-- get_group_wall()/my_group_walls() both gated their reply-payload/unlocked
-- flag purely on has_answered_thread(), which as a result would lock the
-- sender out of the wall they themselves started — the one person who has
-- no reciprocity obligation in the first place. Fixed: unlocked also when
-- the caller IS the thread's sender.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_group_wall(p_thread_id UUID)
RETURNS TABLE(
  member_id     UUID,
  member_name   TEXT,
  member_avatar TEXT,
  is_me         BOOLEAN,
  answered      BOOLEAN,
  reply_id      UUID,
  reply_kind    TEXT,
  reply_body    TEXT,
  reply_photo   TEXT,
  replied_at    TIMESTAMP,
  opened        BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.my_group_walls()
RETURNS TABLE(
  thread_id    UUID,
  group_id     UUID,
  group_name   TEXT,
  prompt       TEXT,
  created_at   TIMESTAMP,
  window_hours INT,
  anonymous    BOOLEAN,
  asked_by     TEXT,
  my_ping_id   UUID,
  unlocked     BOOLEAN,
  answered     INT,
  total        INT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
  WITH me AS (SELECT public.current_user_id() AS id)
  SELECT DISTINCT ON (t.id)
    t.id, t.group_id, g.name, t.prompt, t.created_at, t.window_hours,
    t.anonymous,
    CASE WHEN t.anonymous THEN t.anon_display_name ELSE su.name END,
    (SELECT p.id FROM public.pings p, me WHERE p.thread_id = t.id AND p.receiver_id = me.id),
    (t.sender_id = (SELECT id FROM me))
      OR public.has_answered_thread(t.id, (SELECT id FROM me)),
    (SELECT count(DISTINCT r.ping_id)::INT
       FROM public.ping_replies r JOIN public.pings p2 ON p2.id = r.ping_id
      WHERE p2.thread_id = t.id AND r.deleted_at IS NULL),
    (SELECT count(*)::INT FROM public.pings p3 WHERE p3.thread_id = t.id)
  FROM public.ping_threads t
  JOIN public.groups g ON g.id = t.group_id
  LEFT JOIN public.users su ON su.id = t.sender_id
  , me
  WHERE t.kind = 'group'
    AND public.is_group_member(t.group_id, me.id)
    AND t.created_at > now() - interval '7 days'
  ORDER BY t.id, t.created_at DESC;
$$;
