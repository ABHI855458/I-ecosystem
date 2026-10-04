-- Duo photos only after the invite is accepted (2026-09-27).
--
-- User ask: starting a Duo sends an INVITATION, "and after accepting only the
-- photo uploading process can start". The insert policy used to let the
-- Duo's creator upload into a still-pending album. Now every upload requires
-- status = 'accepted'. The one photo already sitting in a pending album is
-- left alone; it goes live if that Duo is ever accepted, as before.

ALTER POLICY us_album_photos_insert ON public.us_album_photos
  WITH CHECK (
    (auth.uid() IN (SELECT users.auth_id FROM public.users WHERE users.id = us_album_photos.uploaded_by))
    AND EXISTS (
      SELECT 1 FROM public.us_albums a
       WHERE a.id = us_album_photos.album_id
         AND auth.uid() IN (SELECT users.auth_id FROM public.users WHERE users.id = ANY (ARRAY[a.user_a, a.user_b]))
         AND a.status = 'accepted'
    )
  );
