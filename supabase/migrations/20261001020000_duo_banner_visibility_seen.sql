-- Duo album page (2026-10-01): a shared banner, a privacy badge either
-- person can tap, and a "seen by N" count on each photo.

ALTER TABLE public.us_albums ADD COLUMN IF NOT EXISTS banner_url text;

-- Either person in the Duo sets the banner. Only a public group-icons
-- object under duo-banners/ is accepted.
CREATE OR REPLACE FUNCTION public.set_duo_banner(p_album uuid, p_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_me uuid := public.current_user_id();
BEGIN
  IF v_me IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.us_albums a
     WHERE a.id = p_album AND v_me IN (a.user_a, a.user_b)) THEN
    RAISE EXCEPTION 'Only the two people in this Duo can change its banner';
  END IF;
  IF p_url IS NOT NULL
     AND position('/storage/v1/object/public/group-icons/duo-banners/' IN p_url) = 0 THEN
    RAISE EXCEPTION 'Invalid banner';
  END IF;
  UPDATE public.us_albums SET banner_url = p_url WHERE id = p_album;
END $$;

-- Either person can flip a photo public/private. Making a partner's photo
-- public IS their approval (default audience: their Friends circle). The
-- uploader making their own photo public still waits for the partner's
-- approval unless it was approved before.
CREATE OR REPLACE FUNCTION public.set_duo_photo_visibility(p_photo uuid, p_mutual boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_me uuid := public.current_user_id();
        v_photo public.us_album_photos%ROWTYPE;
        v_album public.us_albums%ROWTYPE;
BEGIN
  SELECT * INTO v_photo FROM public.us_album_photos WHERE id = p_photo;
  SELECT * INTO v_album FROM public.us_albums WHERE id = v_photo.album_id;
  IF v_photo.id IS NULL OR v_me IS NULL OR v_me NOT IN (v_album.user_a, v_album.user_b) THEN
    RAISE EXCEPTION 'Only the two people in this Duo can change this';
  END IF;
  IF NOT p_mutual THEN
    UPDATE public.us_album_photos SET visibility = 'private' WHERE id = p_photo;
    RETURN 'private';
  END IF;
  IF v_me = v_photo.uploaded_by THEN
    UPDATE public.us_album_photos SET visibility = 'mutual' WHERE id = p_photo;
    RETURN CASE WHEN v_photo.partner_approved_at IS NULL THEN 'awaiting' ELSE 'live' END;
  END IF;
  PERFORM set_config('app.duo_approving', 'on', true);
  UPDATE public.us_album_photos
     SET visibility = 'mutual',
         partner_approved_at = COALESCE(partner_approved_at, now())
   WHERE id = p_photo;
  PERFORM set_config('app.duo_approving', 'off', true);
  RETURN 'live';
END $$;

-- How many distinct people opened each live photo's post, for photos whose
-- post the caller can see.
CREATE OR REPLACE FUNCTION public.duo_photo_seen_counts(p_album uuid)
RETURNS TABLE(photo_id uuid, seen integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT ph.id, count(DISTINCT pv.viewer_id)::int
    FROM public.us_album_photos ph
    JOIN public.posts p ON p.us_album_photo_id = ph.id AND p.deleted_at IS NULL
    LEFT JOIN public.post_views pv ON pv.post_id = p.id
   WHERE ph.album_id = p_album
     AND public.current_user_id() IS NOT NULL
     AND public.post_engagement_visible(p.id)
   GROUP BY ph.id;
$$;

REVOKE ALL ON FUNCTION public.set_duo_banner(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_duo_photo_visibility(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.duo_photo_seen_counts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_duo_banner(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_duo_photo_visibility(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.duo_photo_seen_counts(uuid) TO authenticated;
