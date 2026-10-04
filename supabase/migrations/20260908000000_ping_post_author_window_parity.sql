-- ============================================================================
-- ping_post_author — reply-window parity with send_ping.
--
-- Plan item 3, divergence #1: ping_post_author hardcoded a 3h reply window
-- (20260906000000_ping_threads_group_wall_and_anonymity.sql:679) while
-- send_ping's own default is 5h as of 20260906040000_ping_window_5h.sql.
-- The anon feed's "ping the post author" flow (PingService.pingPostAuthor,
-- lib/services/ping_service.dart:592-609, called from
-- lib/features/home/anon_feed_v2/anon_feed_screen.dart:298-321) should give
-- the anonymous author the same reply window a named person-to-person ping
-- gets, not a shorter one just because it's anonymous.
--
-- Adds p_window_hours as a new trailing DEFAULT arg. A plain CREATE OR
-- REPLACE with a new defaulted parameter creates a SECOND overload
-- alongside the existing 3-arg signature (Postgres overloads on argument
-- list, not on defaults), which would make the client's existing 3-arg
-- call `ping_post_author(p_post_id, p_prompt, p_anonymous)` ambiguous
-- between the two. DROP the old signature first so there is exactly one
-- version live.
-- ============================================================================

DROP FUNCTION IF EXISTS public.ping_post_author(UUID, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.ping_post_author(
  p_post_id      UUID,
  p_prompt       TEXT,
  p_anonymous    BOOLEAN DEFAULT true,
  p_window_hours INT DEFAULT 5
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_target UUID;
BEGIN
  SELECT p.user_id INTO v_target FROM public.posts p
   WHERE p.id = p_post_id AND p.deleted_at IS NULL;
  IF v_target IS NULL THEN
    RAISE EXCEPTION 'Post not found.';
  END IF;
  RETURN public.send_ping(v_target, p_prompt, p_anonymous, p_window_hours);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ping_post_author(UUID, TEXT, BOOLEAN, INT) TO authenticated;
