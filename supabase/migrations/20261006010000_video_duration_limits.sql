-- ============================================================================
-- Server-side video length caps (2026-10-06: "15s pings, 60s posts").
--
-- The recorder enforces 15s (pings) / 60s (posts) on the device; these CHECKs
-- stop a patched client from posting a ten-minute file. A little headroom
-- over the recorder cap (65s) so a clip that finishes a beat late is never
-- rejected. ping_replies already carries a 20s CHECK (20261006000000).
-- NOT VALID: existing rows are untouched, only new writes are checked.
-- A video PING (a new ping carrying a clip) rides in pings.photo_url and is
-- recognised by its .mp4/.mov/.m4v extension, so it needs no schema change.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

-- posts already had an older, stricter rule capping a video at 6 SECONDS
-- (posts_video_duration_check). Posts may now be up to 60s, so it is replaced
-- by the 65s rule below. posts_video_needs_poster (a video post must carry a
-- still image_url) is KEPT — the app generates a poster frame from the clip.
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_video_duration_check;
ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_video_duration_ck;
ALTER TABLE public.posts ADD CONSTRAINT posts_video_duration_ck
  CHECK (video_duration_ms IS NULL OR video_duration_ms <= 65000) NOT VALID;

ALTER TABLE public.group_posts DROP CONSTRAINT IF EXISTS group_posts_video_duration_ck;
ALTER TABLE public.group_posts ADD CONSTRAINT group_posts_video_duration_ck
  CHECK (video_duration_ms IS NULL OR video_duration_ms <= 65000) NOT VALID;

ALTER TABLE public.us_album_photos DROP CONSTRAINT IF EXISTS us_album_photos_video_duration_ck;
ALTER TABLE public.us_album_photos ADD CONSTRAINT us_album_photos_video_duration_ck
  CHECK (video_duration_ms IS NULL OR video_duration_ms <= 65000) NOT VALID;

COMMIT;
