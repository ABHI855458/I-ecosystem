-- ============================================================================
-- us-album-photos Storage bucket + RLS — ALREADY APPLIED live via `supabase
-- db query` on 2026-08-29 (bucket creation + storage.objects policies).
-- Recorded here for version-control parity with every other bucket in this
-- project, none of which have their bucket-creation SQL in migrations
-- either (confirmed: no CREATE for storage.buckets anywhere in schema.sql
-- or prior migrations — same pre-existing drift, not something this file
-- introduces). This migration is written idempotent (ON CONFLICT / IF NOT
-- EXISTS) specifically so re-running it against the already-applied state
-- above is a safe no-op.
--
-- SEE TICKET 5 in TODO_TICKETS.md — this bucket is `public: true`, same as
-- every other bucket in this app, which means `us_album_photos.visibility
-- = 'private'`'s guarantee is NOT actually enforced at the storage layer,
-- only at the database-row-query layer. Flagged as a launch blocker
-- specifically for this feature, not fixed in this migration — see that
-- ticket for the real fix (private bucket + signed URLs).
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('us-album-photos', 'us-album-photos', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "authenticated_upload_us_album_photos" ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'us-album-photos' AND auth.role() = 'authenticated');

CREATE POLICY "public_read_us_album_photos" ON storage.objects FOR SELECT
USING (bucket_id = 'us-album-photos');
