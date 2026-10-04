-- TICKET 5 — us-album-photos slice only.
--
-- 20260921000000_ticket5_private_buckets_phase_ab.sql already contains the
-- SQL for this, but bundles it with ping-photos in one migration. Applying
-- that file as written would ALSO flip ping-photos private — a completely
-- separate feature (ping replies / hold-to-reveal) whose client side was
-- NOT touched by this pass (TODO_TICKETS.md itself notes that slice as a
-- separate remaining item, and this session's own approved plan explicitly
-- left it out of scope). Verified live: StorageService.uploadPingPhoto still
-- calls getPublicUrl and signedPingPhotoUrl has zero read call sites, so
-- flipping that bucket now would 404 every ping reply photo in the app.
--
-- This migration applies ONLY the us-album-photos half of that file's logic
-- — same SELECT policy, same bucket flip, same bare-path backfill — now that
-- the client-side signed-URL read path for THIS bucket is confirmed shipped
-- (StorageService.uploadUsAlbumPhoto returns a bare path; every render site
-- — my_profile_screen.dart, their_profile_screen.dart, and the feed/profile
-- pipeline via FeedService._attachAuthors — resolves through
-- StorageService.signedUsAlbumPhotoUrl).
--
-- Applied via `supabase db query --linked -f` per this project's own
-- drifted-ledger convention.

DROP POLICY IF EXISTS "public_read_us_album_photos" ON storage.objects;

CREATE POLICY "us_album_photos_read_if_row_visible" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'us-album-photos'
  AND EXISTS (
    SELECT 1 FROM public.us_album_photos p
     WHERE p.photo_url = storage.objects.name
  )
);

UPDATE storage.buckets SET public = false WHERE id = 'us-album-photos';

UPDATE us_album_photos
   SET photo_url = split_part(photo_url, '/object/public/us-album-photos/', 2)
 WHERE photo_url LIKE '%/object/public/us-album-photos/%';

-- VERIFY:
--   SELECT id, public FROM storage.buckets WHERE id = 'us-album-photos'; -- expect false
--   SELECT count(*) FROM us_album_photos WHERE photo_url LIKE 'http%';   -- expect 0
--   curl the OLD-style public URL for any stored photo_url -> expect 400/404, not 200.
