-- ============================================================================
-- Video in group posts, Duo albums and ping replies (explicit request,
-- 2026-10-06: "allow to upload videos as well to duo and group posts just
-- like normal posts ... and holding to record a video, set a limit just like
-- Snap, and sending it to pinged people").
--
-- `posts` already had video_url/video_duration_ms (unused by the app until
-- now); these three tables did not. Columns are nullable and additive, so
-- every existing row and query is unaffected: a row with video_url NULL is
-- exactly the photo it was.
--
-- duration_ms is stored so a card can show "0:08" without downloading the
-- file, and so the Snap-style recording cap can be enforced on read as well
-- as in the recorder.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

ALTER TABLE public.group_posts
  ADD COLUMN IF NOT EXISTS video_url text,
  ADD COLUMN IF NOT EXISTS video_duration_ms int;

ALTER TABLE public.us_album_photos
  ADD COLUMN IF NOT EXISTS video_url text,
  ADD COLUMN IF NOT EXISTS video_duration_ms int;

ALTER TABLE public.ping_replies
  ADD COLUMN IF NOT EXISTS video_url text,
  ADD COLUMN IF NOT EXISTS video_duration_ms int;

-- A ping video is capped at 15s in the recorder; the database refuses
-- anything wildly longer so a patched client can't post a 10-minute file.
ALTER TABLE public.ping_replies
  DROP CONSTRAINT IF EXISTS ping_replies_video_duration_ck;
ALTER TABLE public.ping_replies
  ADD CONSTRAINT ping_replies_video_duration_ck
  CHECK (video_duration_ms IS NULL OR video_duration_ms <= 20000);

COMMIT;
