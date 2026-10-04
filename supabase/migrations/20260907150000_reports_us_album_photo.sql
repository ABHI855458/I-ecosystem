-- ============================================================================
-- reports.us_album_photo_id — Us Album photos become reportable.
--
-- A third party can now see an album's 'mutual' photos (us_album_photos_select
-- + album_is_accepted_and_friend_of_either), but had no way to report one, and
-- no way to report the person who posted it: `reports` had no column that
-- could point at a us_album_photos row. Removing your own photo already worked
-- (us_album_photos_delete_own); reporting someone else's did not exist.
--
-- Additive and nullable, same shape as the group_post_id target added in
-- 20260907130000. No CHECK on this table to update.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS us_album_photo_id uuid
  REFERENCES public.us_album_photos(id) ON DELETE CASCADE;

COMMENT ON COLUMN public.reports.us_album_photo_id IS
  'Target for a report against a us_album_photos row.';

CREATE INDEX IF NOT EXISTS reports_us_album_photo_idx
  ON public.reports (us_album_photo_id) WHERE us_album_photo_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS reports_one_per_reporter_us_album_photo
  ON public.reports (reporter_id, us_album_photo_id)
  WHERE us_album_photo_id IS NOT NULL;
