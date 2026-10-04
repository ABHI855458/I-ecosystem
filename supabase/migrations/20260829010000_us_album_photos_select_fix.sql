-- ============================================================================
-- Fix us_album_photos_select — own-party branch incorrectly required
-- status = 'accepted', found during Phase 3 UI wiring (2026-08-29) while
-- building the "creator uploads first photo to a pending album" flow: the
-- creator could INSERT (us_album_photos_insert already correctly allows
-- this for a pending album's creator) but could never SELECT it back,
-- since the read policy gated ALL access — including the uploader's own —
-- on the album already being accepted. That directly broke the approved
-- reading of the spec ("creator can add photos pre-acceptance").
--
-- Fix: the OWN-party branch no longer requires status='accepted' — a party
-- can always see photos in their own album, pending or accepted, mirroring
-- us_albums_select's own "both parties always see their own row regardless
-- of status" symmetry. The THIRD-PARTY mutual-friend branch is untouched —
-- it still correctly requires status='accepted' (a third party should
-- never see into a not-yet-agreed-to pairing).
-- ============================================================================

DROP POLICY "us_album_photos_select" ON us_album_photos;

CREATE POLICY "us_album_photos_select" ON us_album_photos FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM us_albums a
    WHERE a.id = album_id
    AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (a.user_a, a.user_b))
  )
  OR (
    visibility = 'mutual'
    AND EXISTS (
      SELECT 1 FROM us_albums a
      WHERE a.id = album_id AND a.status = 'accepted'
      AND is_mutual_friend_of_both(a.user_a, a.user_b)
    )
  )
);
