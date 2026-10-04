-- ============================================================================
-- Add `group_post_id` to `comments` — the column CommentService
-- (lib/services/comment_service.dart) has assumed existed since it was
-- written ("see the group_post_id migration on comments"), but which was
-- never actually migrated. Same drift class as reactions/
-- post_realmoji_reactions before 20260902020000_group_post_reactions.sql.
--
-- CONFIRMED against the live database on 2026-09-03: `comments.
-- group_post_id` does NOT exist (PostgrestException 42703 on
-- `select=group_post_id`). Until this runs, every comment on a GROUP post
-- fails to read (fetchRecent/fetchCount filter on the missing column and
-- fail closed to []/0) and fails to write. A personal-post comment insert
-- was ALSO failing — CommentService always sent the key, null or not, and
-- PostgREST validates every payload key against the schema regardless of
-- its value — but that half is already fixed client-side (comment_service
-- .dart's post() now omits the key entirely when unset) so it does not
-- depend on this migration.
--
-- Every statement below is idempotent, safe to re-run.
-- ============================================================================

ALTER TABLE comments
  ADD COLUMN IF NOT EXISTS group_post_id UUID REFERENCES group_posts(id) ON DELETE CASCADE;

-- Added NOT VALID then validated separately: if a stray row somehow already
-- has both/neither id set, that surfaces as an explicit VALIDATE failure
-- naming the row, rather than aborting the ADD COLUMN + constraint as one
-- atomic failure with a less useful error.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'comments_post_xor_group_post'
  ) THEN
    ALTER TABLE comments ADD CONSTRAINT comments_post_xor_group_post
      CHECK ((post_id IS NOT NULL) <> (group_post_id IS NOT NULL)) NOT VALID;
  END IF;
END $$;

ALTER TABLE comments VALIDATE CONSTRAINT comments_post_xor_group_post;

CREATE INDEX IF NOT EXISTS comments_group_post_idx ON comments(group_post_id);

-- No RLS change needed, unlike reactions/post_realmoji_reactions before
-- them: comments_select is `USING (deleted_at IS NULL)` (schema.sql) — it
-- never branched on post_id, so a group-post comment row is already visible
-- once it exists. The one policy that DOES read comments.post_id,
-- comments_block_filter (20260903000000_blocks_formalize_and_account_soft_
-- delete.sql — RESTRICTIVE, anon-post carve-out), degrades correctly for a
-- group row: its `p.id = comments.post_id` EXISTS check is simply false
-- when post_id is NULL, which falls through to its own
-- `OR NOT is_blocked_user(...)` branch — the same block-filtering a group
-- comment should get. comments_insert only ever checked author ownership.
