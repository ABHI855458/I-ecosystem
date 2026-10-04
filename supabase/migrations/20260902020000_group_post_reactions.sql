-- ============================================================================
-- Add real group_post_id support to `reactions` and `post_realmoji_reactions`
-- — the column both tables' client code (reaction_service.dart,
-- realmoji_service.dart) already assumes exists (group_post_id filters,
-- and reactions' upsert already targets onConflict: 'group_post_id,user_id,
-- type' for a group reaction) but which was never actually migrated.
--
-- CONFIRMED against the live database on 2026-09-02: `reactions.
-- group_post_id` and `post_realmoji_reactions.group_post_id` both do NOT
-- exist (PostgrestException 42703 on every group-post reaction/realmoji
-- call). 20260829030000's own header comment asserting the latter was
-- "CONFIRMED NOT to exist" was accurate as of 2026-08-29 and still is —
-- this migration is what finally closes that gap. Until this runs, every
-- group-post reaction/RealMoji call in the app fails closed (caught,
-- logged, shows an unreacted state) rather than crashing, which is why the
-- gap went unnoticed.
--
-- Every statement below is idempotent, safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- reactions — post_id was already nullable, so only the new column/index/
-- RLS work is needed here.
-- ---------------------------------------------------------------------------

ALTER TABLE reactions
  ADD COLUMN IF NOT EXISTS group_post_id UUID REFERENCES group_posts(id) ON DELETE CASCADE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reactions_post_xor_group_post'
  ) THEN
    ALTER TABLE reactions ADD CONSTRAINT reactions_post_xor_group_post
      CHECK ((post_id IS NOT NULL) <> (group_post_id IS NOT NULL));
  END IF;
END $$;

-- Replaces the old single UNIQUE(post_id, user_id, type): a plain unique
-- constraint spanning both id columns wouldn't work here, since Postgres
-- treats NULL <> NULL for uniqueness purposes — two group-post rows sharing
-- the same group_post_id would both have post_id NULL and never collide.
-- Two partial indexes, one per post kind, is what actually enforces "one
-- reaction per (user, type) per post" in both cases, and each name matches
-- the exact onConflict target reaction_service.dart already sends.
ALTER TABLE reactions DROP CONSTRAINT IF EXISTS reactions_post_id_user_id_type_key;

CREATE UNIQUE INDEX IF NOT EXISTS reactions_post_user_type_uniq
  ON reactions(post_id, user_id, type) WHERE post_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS reactions_group_post_user_type_uniq
  ON reactions(group_post_id, user_id, type) WHERE group_post_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS reactions_group_post_idx ON reactions(group_post_id);

-- reactions_select is currently `EXISTS (SELECT 1 FROM posts p WHERE p.id =
-- post_id)` — always false for a group-post row (post_id is NULL there), so
-- every group reaction would be invisible even once the column exists.
-- Adding the group_posts/group_members branch alongside it, same shape
-- group_posts_select itself uses for group-post visibility. NOTE: unlike
-- `posts`, live `group_posts` has no deleted_at column (confirmed via
-- information_schema — schema.sql's CREATE TABLE claiming one is stale), so
-- no soft-delete guard here, matching group_posts_select's own shape.
DROP POLICY IF EXISTS "reactions_select" ON reactions;
CREATE POLICY "reactions_select" ON reactions FOR SELECT USING (
  EXISTS (SELECT 1 FROM posts p WHERE p.id = reactions.post_id)
  OR EXISTS (
    SELECT 1 FROM group_posts gp
    JOIN group_members gm ON gm.group_id = gp.group_id
    JOIN users u ON u.id = gm.user_id
    WHERE gp.id = reactions.group_post_id
    AND u.auth_id = auth.uid()
  )
);
-- insert/update/delete policies only ever checked reaction ownership (never
-- post visibility), so no group-post branch is needed there — unchanged.

-- ---------------------------------------------------------------------------
-- post_realmoji_reactions — post_id is currently NOT NULL (20260829030000),
-- which would reject every group-post insert (postId: null) even after the
-- column below is added, so that constraint has to go first.
-- ---------------------------------------------------------------------------

ALTER TABLE post_realmoji_reactions ALTER COLUMN post_id DROP NOT NULL;

ALTER TABLE post_realmoji_reactions
  ADD COLUMN IF NOT EXISTS group_post_id UUID REFERENCES group_posts(id) ON DELETE CASCADE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'post_realmoji_reactions_post_xor_group_post'
  ) THEN
    ALTER TABLE post_realmoji_reactions ADD CONSTRAINT post_realmoji_reactions_post_xor_group_post
      CHECK ((post_id IS NOT NULL) <> (group_post_id IS NOT NULL));
  END IF;
END $$;

-- realmoji_service.dart does a plain .insert() here, never .upsert() — no
-- unique constraint was required before, so none is added now either. Same
-- name/shape 20260825000000_feed_rules.sql's own guarded block already
-- wanted to create but skipped (the column didn't exist yet when it ran).
CREATE INDEX IF NOT EXISTS post_realmoji_reactions_user_group_post_idx
  ON post_realmoji_reactions(user_id, group_post_id);

-- Same fix as reactions_select above: the existing SELECT policy only
-- resolves posts.id = post_id, always false for a group-post row.
DROP POLICY IF EXISTS "post_realmoji_reactions_select" ON post_realmoji_reactions;
CREATE POLICY "post_realmoji_reactions_select" ON post_realmoji_reactions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = post_realmoji_reactions.post_id
    AND p.deleted_at IS NULL
    AND (
      p.visibility IS DISTINCT FROM 'anonymous'
      OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
    )
  )
  OR EXISTS (
    SELECT 1 FROM group_posts gp
    JOIN group_members gm ON gm.group_id = gp.group_id
    JOIN users u ON u.id = gm.user_id
    WHERE gp.id = post_realmoji_reactions.group_post_id
    AND u.auth_id = auth.uid()
  )
);
-- insert/update/delete policies only ever checked reaction-row ownership
-- (never post visibility), so no group-post branch is needed there either.
