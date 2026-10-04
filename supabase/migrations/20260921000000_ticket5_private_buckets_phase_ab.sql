-- TICKET 5 — Phase A + B: make us-album-photos and ping-photos genuinely
-- private. DO NOT RUN THIS WITHOUT READING THE "ORDER OF OPERATIONS" NOTE
-- AT THE BOTTOM — the client must ship the signed-URL change too, or every
-- affected image 404s.
--
-- ---------------------------------------------------------------------
-- WHY
-- ---------------------------------------------------------------------
-- Verified exploitable on the live project: an unauthenticated GET (no
-- apikey, no JWT, no cookies) against a `visibility='private'` Us-album
-- photo returned HTTP 200, 390KB, image/jpeg.
--
-- us_album_photos and ping_replies both carry correct row-level policies,
-- but Storage serves bytes over a separate route that never consults them.
-- The privacy rule was enforced on the ROW and ignored on the FILE. For
-- ping photos this also defeats hold-to-reveal outright: the raw URL
-- returns the photo regardless of whether the viewer ever held to reveal.
--
-- The UUID object paths added earlier are obscurity, not access control.
--
-- ---------------------------------------------------------------------
-- THE DESIGN CHOICE THAT MATTERS
-- ---------------------------------------------------------------------
-- The SELECT policies below deliberately do NOT re-implement either
-- table's visibility rule. They just ask whether the caller can SELECT the
-- owning row:
--
--   EXISTS (SELECT 1 FROM public.us_album_photos p WHERE p.photo_url = name)
--
-- That subquery is itself subject to us_album_photos' own RLS, so if the
-- caller cannot see the row, the EXISTS is false and the object is
-- unreadable. The storage rule therefore CANNOT drift from the row rule —
-- it has no independent copy of it to drift from. Re-stating the
-- mutual/private logic here would have created exactly the kind of
-- duplicated predicate that caused the earlier anon-identity leak.
--
-- Requires: photo_url / selfie_url stored as BARE OBJECT PATHS, which
-- step 3 below migrates them to.

-- ---------------------------------------------------------------------
-- 1. SELECT policies — replace the blanket public-read policies
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "public_read_us_album_photos" ON storage.objects;
DROP POLICY IF EXISTS "ping_photos_public_read" ON storage.objects;

CREATE POLICY "us_album_photos_read_if_row_visible" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'us-album-photos'
  AND EXISTS (
    SELECT 1 FROM public.us_album_photos p
     WHERE p.photo_url = storage.objects.name
  )
);

-- Both halves of a camera reply live in this bucket; either column may
-- name the object, so both are checked. can_see_ping_reply() (via
-- ping_replies' own RLS) is what actually gates it.
CREATE POLICY "ping_photos_read_if_reply_visible" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'ping-photos'
  AND EXISTS (
    SELECT 1 FROM public.ping_replies r
     WHERE r.photo_url  = storage.objects.name
        OR r.selfie_url = storage.objects.name
  )
);

-- ---------------------------------------------------------------------
-- 2. Flip the buckets private
-- ---------------------------------------------------------------------
-- After this, /object/public/<bucket>/... stops serving. Only
-- createSignedUrl() (and the service role) can read.
UPDATE storage.buckets SET public = false
 WHERE id IN ('us-album-photos', 'ping-photos');

-- ---------------------------------------------------------------------
-- 3. Rewrite stored absolute URLs -> bare object paths
-- ---------------------------------------------------------------------
-- The DB currently stores fully-qualified public URLs, e.g.
--   https://<ref>.supabase.co/storage/v1/object/public/us-album-photos/<uuid>.jpg
-- Everything up to and including the bucket segment is stripped, leaving
-- the object path the signed-URL API expects.
--
-- Idempotent: only rows still holding an absolute URL are touched, so
-- re-running is a no-op. split_part on the bucket marker is used rather
-- than a fixed offset so it does not depend on the project ref's length.
UPDATE us_album_photos
   SET photo_url = split_part(photo_url, '/object/public/us-album-photos/', 2)
 WHERE photo_url LIKE '%/object/public/us-album-photos/%';

UPDATE ping_replies
   SET photo_url = split_part(photo_url, '/object/public/ping-photos/', 2)
 WHERE photo_url LIKE '%/object/public/ping-photos/%';

UPDATE ping_replies
   SET selfie_url = split_part(selfie_url, '/object/public/ping-photos/', 2)
 WHERE selfie_url LIKE '%/object/public/ping-photos/%';

-- ---------------------------------------------------------------------
-- VERIFY (run these after, and actually read the numbers)
-- ---------------------------------------------------------------------
-- a) Buckets are private — expect both false:
--      SELECT id, public FROM storage.buckets
--       WHERE id IN ('us-album-photos','ping-photos');
--
-- b) No absolute URLs left — expect 0, 0, 0:
--      SELECT
--        (SELECT count(*) FROM us_album_photos WHERE photo_url LIKE 'http%'),
--        (SELECT count(*) FROM ping_replies   WHERE photo_url LIKE 'http%'),
--        (SELECT count(*) FROM ping_replies   WHERE selfie_url LIKE 'http%');
--
-- c) Exactly one SELECT policy per bucket, and it is the new one:
--      SELECT policyname, cmd FROM pg_policies
--       WHERE schemaname='storage' AND tablename='objects'
--         AND policyname IN ('us_album_photos_read_if_row_visible',
--                            'ping_photos_read_if_reply_visible');
--
-- d) THE REAL TEST — the one that actually proves the ticket is closed.
--    Take any us_album_photos.photo_url, rebuild the OLD public URL by
--    hand, and curl it unauthenticated. Expect 400/404, NOT 200:
--      curl -s -o /dev/null -w '%{http_code}\n' \
--        "https://<ref>.supabase.co/storage/v1/object/public/us-album-photos/<path>"
--    A 200 here means the bucket flip did not take. Do not accept
--    "the migration ran without error" as proof.
--
-- ---------------------------------------------------------------------
-- ORDER OF OPERATIONS — read before running
-- ---------------------------------------------------------------------
-- This migration and the client change in storage_service.dart are ONE
-- unit. Running the SQL against a build that still calls getPublicUrl()
-- turns every Us-album photo and every ping reply photo into a broken
-- image, for everyone, immediately.
--
-- Ship in this order:
--   1. Deploy the client build containing signedUrlFor() (that code reads
--      BOTH shapes — it passes an absolute URL straight through — so it is
--      safe to ship BEFORE this SQL runs).
--   2. Run this migration.
--   3. Verify (a)-(d) above, then open the app and confirm Us-album
--      photos and revealed ping replies actually render. A migration that
--      "succeeded" while every image 404s is the expected failure mode
--      here, and it is highly visible.
--
-- Rollback, if images break and the cause is not obvious:
--   UPDATE storage.buckets SET public = true
--    WHERE id IN ('us-album-photos','ping-photos');
-- That restores serving immediately (re-opening the hole) without needing
-- to un-rewrite the stored paths, because signed URLs keep working on a
-- public bucket. Fix forward from there.
