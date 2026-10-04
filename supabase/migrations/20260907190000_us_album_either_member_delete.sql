-- ============================================================================
-- Either member of an Us Album can remove any photo in it.
--
-- "anyone of the us album can remove the photos in us album."
--
-- us_album_photos_delete_own scoped DELETE to the uploader, so a photo of the
-- two of you could only ever be taken down by whoever happened to upload it —
-- the other person, who is equally in the picture, had no way to remove it.
-- An Us Album is jointly owned by construction (mutual-consent to create,
-- mutual-consent to delete, see 20260828000000), and this is the one place
-- that did not follow the same rule.
--
-- Deliberately NOT extended to UPDATE: flipping a photo private/mutual stays
-- with the uploader. Removing a photo of yourself is self-defence; publishing
-- someone else's photo more widely than they chose is not the same act, and
-- should not be reachable from the other side.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

DROP POLICY IF EXISTS "us_album_photos_delete_own" ON public.us_album_photos;

CREATE POLICY "us_album_photos_delete_member" ON public.us_album_photos
FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM public.us_albums a
     WHERE a.id = us_album_photos.album_id
       AND auth.uid() IN (
         SELECT u.auth_id FROM public.users u
          WHERE u.id = ANY (ARRAY[a.user_a, a.user_b])
       )
  )
);
