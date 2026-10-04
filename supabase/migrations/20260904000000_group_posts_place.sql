-- ============================================================================
-- group_posts.place — the third piece of a Memory's context, alongside the
-- taken_at/note pair added in 20260903020000_dips_and_group_streaks.sql.
--
-- Free-typed text, not a geocoded reference: there is no places/venues table
-- anywhere in this schema and the composer offers a plain TextField, so
-- storing anything richer would be storing a shape nothing produces.
--
-- CONFIRMED against the live database on 2026-09-02: group_posts is
-- id, group_id, user_id, photo_url, caption, created_at, photo_urls,
-- taken_at, note — no place column, and (still) no deleted_at. schema.sql
-- is stale and does not list photo_urls/taken_at/note either; do not trust
-- it here.
--
-- Idempotent, safe to re-run.
-- ============================================================================

ALTER TABLE public.group_posts
  ADD COLUMN IF NOT EXISTS place TEXT;

-- ---------------------------------------------------------------------------
-- groups.updated_at — discovered while wiring the profile plan's banner
-- upload (GroupService.updateGroupInfo already unconditionally sets
-- updates['updated_at'] on every call, unlike every other field there,
-- which is conditional). CONFIRMED against the live DB: groups is id,
-- name, icon_url, banner_url, community_id, created_by, created_at — no
-- updated_at, so that update has been failing outright (PGRST204, same
-- failure class as the comments.group_post_id/group_posts.deleted_at
-- drifts already logged) for every existing call site, including the
-- legacy group icon-change flow (group_profile_screen.dart's _changeIcon).
-- Nothing in the app reads groups.updated_at (grepped), so this is a pure
-- addition, safe to backfill via DEFAULT now().
-- ---------------------------------------------------------------------------

ALTER TABLE public.groups
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
