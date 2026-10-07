-- The "seen N" eye-count on a Duo album's photo tiles is for the Duo's own
-- two people only (explicit request, 2026-10-07: "others shall not see who
-- have viewed ... seen also only the sender").
--
-- duo_photo_seen_counts answered anyone who could see the photo's post, so
-- a friend opening a shared Duo album got the view count of every photo in
-- it. It now answers only the album's two members; everyone else gets no
-- rows (the app also stops drawing the count for them).
--
-- Patched in place from the LIVE definition; the fragment must be found
-- exactly once or nothing changes. Companion to
-- 20261007040000_viewer_lists_owner_only.sql.
DO $$
DECLARE
  v_def text;
  v_old text := E'   WHERE ph.album_id = p_album\n     AND public.current_user_id() IS NOT NULL\n';
  v_rep text := E'   WHERE ph.album_id = p_album\n     AND public.current_user_id() IS NOT NULL\n'
             || E'     -- the Duo''s own two people only\n'
             || E'     AND EXISTS (SELECT 1 FROM public.us_albums a\n'
             || E'                  WHERE a.id = p_album\n'
             || E'                    AND public.current_user_id() IN (a.user_a, a.user_b))\n';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'duo_photo_seen_counts' AND p.pronamespace = 'public'::regnamespace;
  IF v_def IS NULL THEN RAISE EXCEPTION 'duo_photo_seen_counts not found'; END IF;
  IF v_def LIKE '%IN (a.user_a, a.user_b)%' THEN
    RAISE NOTICE 'duo_photo_seen_counts already patched';
    RETURN;
  END IF;
  IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'duo_photo_seen_counts: WHERE clause not found exactly once';
  END IF;
  EXECUTE replace(v_def, v_old, v_rep);
END $$;
