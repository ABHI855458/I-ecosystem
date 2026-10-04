-- ============================================================================
-- Fix reactions_post_user_type_uniq / reactions_group_post_user_type_uniq:
-- 20260902020000_group_post_reactions created these as PARTIAL unique
-- indexes (WHERE post_id IS NOT NULL / WHERE group_post_id IS NOT NULL).
-- reaction_service.dart's upsert(..., onConflict: 'post_id,user_id,type')
-- (and the group_post_id variant) sends a plain column-list ON CONFLICT
-- target with no WHERE clause — Postgres only infers a NON-PARTIAL unique
-- index for that form, so every reaction upsert (personal AND group posts)
-- has been throwing 42P10 ("no unique or exclusion constraint matching the
-- ON CONFLICT specification") since that migration landed, surfaced in the
-- app as "Couldn't save your reaction."
--
-- Fix: drop the WHERE predicate. Still correct — Postgres treats NULL <>
-- NULL for uniqueness, so a non-partial index on (post_id, user_id, type)
-- still lets unlimited group-post rows (post_id IS NULL) coexist; it only
-- enforces uniqueness among rows sharing the same non-null post_id. Same
-- reasoning symmetric for the group_post_id index.
-- ============================================================================

DROP INDEX IF EXISTS reactions_post_user_type_uniq;
DROP INDEX IF EXISTS reactions_group_post_user_type_uniq;

CREATE UNIQUE INDEX reactions_post_user_type_uniq
  ON reactions(post_id, user_id, type);

CREATE UNIQUE INDEX reactions_group_post_user_type_uniq
  ON reactions(group_post_id, user_id, type);
