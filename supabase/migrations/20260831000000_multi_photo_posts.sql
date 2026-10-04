-- ============================================================================
-- Multi-photo posts — swipeable carousel support for BOTH personal posts
-- (`posts`) and group posts (`group_posts`), replacing the collage-layout
-- treatment on group posts.
--
-- NOT RUN YET — for review. You run this manually in the SQL Editor, same
-- as the last two migrations.
-- ============================================================================
--
-- ADDITIVE ONLY — `photo_urls TEXT[]` is added ALONGSIDE the existing
-- single-value columns (`posts.image_url`, `group_posts.photo_url`), which
-- are left completely untouched:
--
--   * No backfill. No NOT NULL change. No column drops.
--   * Every existing read path (FeedService, PostService, GroupService,
--     posts_feed view, every card widget) keeps working byte-for-byte
--     unchanged — they all still read the single column, which still holds
--     the first/cover photo exactly as before.
--   * New multi-photo code prefers `photo_urls` when it's non-empty and
--     falls back to the single column otherwise, so old rows (every row
--     currently in the DB) render as a 1-photo carousel with no migration
--     of their data at all.
--   * Trivially reversible: DROP COLUMN, nothing else to undo.
--
-- This is deliberately the lowest-risk of the three options considered —
-- notably it does NOT require touching `posts_feed`, which is the
-- security-sensitive anon-masking view (see TICKET 2 in TODO_TICKETS.md,
-- and the RLS leak fixed in 20260829020000). Adding a column to the base
-- table does not change that view's shape or its masking behavior.
--
-- WHY TEXT[] AND NOT A post_photos TABLE: a normalized child table would
-- need its own RLS policies duplicating the exact anon-visibility rules
-- just fixed in 20260829020000 — a new table is a new place for that same
-- leak to reappear. An array column inherits its parent row's RLS
-- automatically, with no new policy surface to get wrong.
--
-- NO RLS CHANGES NEEDED: `photo_urls` lives on rows already covered by
-- each table's existing policies. A caller who can SELECT the row can
-- already see `image_url`/`photo_url`; the array is the same class of data
-- on the same row, so it inherits the same (already-correct) visibility.
--
-- ORDERING: array order IS display order — index 0 is the cover/first
-- photo shown before any swipe, and is expected to match the existing
-- single column's value for rows written by the new code path.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- posts (personal posts)
-- ---------------------------------------------------------------------------

ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS photo_urls TEXT[];

COMMENT ON COLUMN posts.photo_urls IS
  'Ordered photo URLs for a swipeable multi-photo post; index 0 is the cover. '
  'NULL/empty means single-photo — read image_url instead. image_url remains '
  'the first/cover photo for backward compatibility with existing readers.';

-- ---------------------------------------------------------------------------
-- group_posts
-- ---------------------------------------------------------------------------

ALTER TABLE group_posts
  ADD COLUMN IF NOT EXISTS photo_urls TEXT[];

COMMENT ON COLUMN group_posts.photo_urls IS
  'Ordered photo URLs for a swipeable multi-photo group post; index 0 is the '
  'cover. NULL/empty means single-photo — read photo_url instead. photo_url '
  'stays NOT NULL and holds the first/cover photo, so no existing reader or '
  'constraint is affected.';
