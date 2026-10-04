-- ============================================================================
-- reports.group_post_id — group posts become reportable.
--
-- The Friends feed renders three row shapes: `posts` (solo), `group_posts`
-- (the collage cards) and Moments. Only the first and last could be reported;
-- the group card's menu popped a "Reported" toast and wrote nothing, because
-- `reports` had no column that could point at a group_posts row.
--
-- Additive only: the column is nullable, there is no exactly-one-target CHECK
-- on this table to update, and every existing query keeps working untouched.
--
-- NOTE: this does NOT make group posts removable. `group_posts` still has no
-- deleted_at and no moderator UPDATE policy, so the queue can record and
-- review a group-post report but not take the post down from it. That gap is
-- tracked separately; see the dashboard plan's Part 1 step 2.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS group_post_id uuid
  REFERENCES public.group_posts(id) ON DELETE CASCADE;

COMMENT ON COLUMN public.reports.group_post_id IS
  'Target for a report against a group_posts row. Mutually exclusive with the '
  'other *_id targets by convention (no CHECK enforces it on this table).';

CREATE INDEX IF NOT EXISTS reports_group_post_idx
  ON public.reports (group_post_id) WHERE group_post_id IS NOT NULL;

-- One report per person per group post, matching how the other targets are
-- de-duplicated (the client surfaces this as AlreadyReportedException).
CREATE UNIQUE INDEX IF NOT EXISTS reports_one_per_reporter_group_post
  ON public.reports (reporter_id, group_post_id) WHERE group_post_id IS NOT NULL;
