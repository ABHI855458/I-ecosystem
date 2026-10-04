-- ============================================================================
-- Either member of a Duo can LOCK a currently-live photo back to private.
--
-- "if either one of the 2 people in us album does lock the post then the
-- post gone live would be deleted as such and it would be private as such"
--
-- Today, flipping a photo's visibility is us_album_photos_update_own's own
-- rule: uploader only (see 20260828000000_us_albums.sql). That was a
-- deliberate call — 20260907190000_us_album_either_member_delete.sql
-- explicitly declined to extend UPDATE to both members, reasoning that
-- "publishing someone else's photo more widely than they chose... should
-- not be reachable from the other side."
--
-- This does not reopen that decision. It adds the ONE direction that
-- reasoning doesn't cover: taking a shared photo DOWN, not publishing it
-- wider. Locking is self-defence, same as that migration's own DELETE
-- grant (either party can already remove the photo outright) — this is
-- the softer, reversible version of the same right: hide it from the
-- Friends feed without destroying it, so un-locking still restores the
-- same post (see sync_us_album_post's own ON CONFLICT ... DO UPDATE,
-- 20260926020000_shared_album_audiences.sql) rather than losing its
-- comments/reactions.
--
-- No new trigger logic needed for the "post gone live gets deleted"
-- half of the ask — sync_us_album_post already soft-deletes the mirrored
-- `posts` row the instant visibility stops being 'mutual' (its ELSE
-- branch). This migration only widens WHO is allowed to flip that column
-- away from 'mutual', not what happens when it flips.
--
-- One-directional by construction: WITH CHECK admits ONLY visibility =
-- 'private'. A partner cannot use this policy to PUBLISH a private photo
-- (visibility = 'mutual') — that still requires uploaded_by = self, via
-- us_album_photos_update_own, unchanged. Multiple permissive policies for
-- the same command OR together on both USING and WITH CHECK (Postgres
-- RLS semantics, same pattern this app already relies on for SELECT) —
-- so the uploader's own full read-write policy is untouched, and this
-- policy only ever ADDS the one-way "either party may lock" path.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push
-- unused — see project convention in every prior us_album_* migration).
-- ============================================================================

CREATE POLICY "us_album_photos_lock_partner" ON public.us_album_photos
FOR UPDATE USING (
  visibility = 'mutual'
  AND EXISTS (
    SELECT 1 FROM public.us_albums a
     WHERE a.id = us_album_photos.album_id
       AND auth.uid() IN (
         SELECT u.auth_id FROM public.users u
          WHERE u.id = ANY (ARRAY[a.user_a, a.user_b])
       )
  )
) WITH CHECK (
  visibility = 'private'
);
