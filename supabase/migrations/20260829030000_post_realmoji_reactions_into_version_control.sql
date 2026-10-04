-- ============================================================================
-- Bring post_realmoji_reactions fully into version control — the original,
-- narrower Phase 5 scope (TICKET 2 in TODO_TICKETS.md), resumed after the
-- higher-priority RLS-leak fix (20260829020000) that was discovered while
-- starting this same investigation.
--
-- post_realmoji_reactions has existed live since before this migrations
-- directory started (see 20260825000000_feed_rules.sql's own note: "exists
-- in the live database... its CREATE TABLE lives outside version control")
-- — this migration captures its CONFIRMED CURRENT LIVE SHAPE (introspected
-- directly against the linked project on 2026-08-29, not assumed) so a
-- fresh environment bootstrapping from this migrations directory ends up
-- with the same table, including the SAME (just-fixed, secure) RLS — not
-- just the same columns. Omitting RLS here would mean a fresh environment
-- silently regrows the exact vulnerability 20260829020000 just closed.
--
-- CONFIRMED NOT to exist on this environment, so NOT included below:
-- `group_post_id`. 20260825000000_feed_rules.sql's own guarded index block
-- already handles this column's presence/absence correctly (checks
-- information_schema.columns before indexing it) — nothing more needed
-- here. Inventing that column's shape for environments where it might
-- exist would be guessing, not capturing a confirmed fact.
--
-- Every statement below is idempotent (IF NOT EXISTS / guarded DO blocks)
-- specifically so this is safe to run against the CURRENT database, where
-- everything already exists exactly as captured — this migration should
-- produce zero actual changes here, only formalize what's already live.
--
-- MINOR OBSERVATION, not acted on: `delete own reaction` /
-- `post_realmoji_reactions_delete_own` are functionally duplicate DELETE
-- policies (same ownership check, different join formulation), same for
-- `insert own reaction` / `post_realmoji_reactions_insert_own` on INSERT.
-- Unlike the SELECT redundancy fixed in 20260829020000, neither pair is a
-- security issue (both sides of each pair are equally, correctly scoped) —
-- just policy-sprawl housekeeping. Left alone; a consolidation decision
-- for you to make separately, not bundled into this migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Enum type — also not in version control anywhere (confirmed: no CREATE
-- TYPE for emoji_type_enum exists in schema.sql or any prior migration).
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'emoji_type_enum') THEN
    CREATE TYPE emoji_type_enum AS ENUM ('like', 'joy', 'surprise', 'love', 'laughter', 'instant');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS post_realmoji_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji_type emoji_type_enum NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Same index 20260825000000_feed_rules.sql's own guarded block creates —
-- duplicated here (IF NOT EXISTS-safe) because on a FRESH environment that
-- earlier migration runs first, finds no post_realmoji_reactions table yet,
-- and skips its own guarded block entirely; without this, a fresh
-- environment would end up missing this index.
CREATE INDEX IF NOT EXISTS post_realmoji_reactions_user_post_idx
  ON post_realmoji_reactions(user_id, post_id);

-- ---------------------------------------------------------------------------
-- RLS — captures the table's CURRENT state (post-20260829020000 fix), so a
-- fresh environment gets the corrected policy, never the vulnerable one.
-- ---------------------------------------------------------------------------

ALTER TABLE post_realmoji_reactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_realmoji_reactions' AND policyname = 'post_realmoji_reactions_select') THEN
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
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_realmoji_reactions' AND policyname = 'insert own reaction') THEN
    CREATE POLICY "insert own reaction" ON post_realmoji_reactions FOR INSERT WITH CHECK (
      user_id = (SELECT users.id FROM users WHERE users.auth_id = auth.uid())
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_realmoji_reactions' AND policyname = 'post_realmoji_reactions_insert_own') THEN
    CREATE POLICY "post_realmoji_reactions_insert_own" ON post_realmoji_reactions FOR INSERT WITH CHECK (
      auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = post_realmoji_reactions.user_id)
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_realmoji_reactions' AND policyname = 'delete own reaction') THEN
    CREATE POLICY "delete own reaction" ON post_realmoji_reactions FOR DELETE USING (
      user_id = (SELECT users.id FROM users WHERE users.auth_id = auth.uid())
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_realmoji_reactions' AND policyname = 'post_realmoji_reactions_delete_own') THEN
    CREATE POLICY "post_realmoji_reactions_delete_own" ON post_realmoji_reactions FOR DELETE USING (
      auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = post_realmoji_reactions.user_id)
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_realmoji_reactions' AND policyname = 'post_realmoji_reactions_delete_moderator') THEN
    CREATE POLICY "post_realmoji_reactions_delete_moderator" ON post_realmoji_reactions FOR DELETE USING (
      is_admin_or_global_mod() OR EXISTS (
        SELECT 1 FROM posts
        WHERE posts.id = post_realmoji_reactions.post_id
        AND is_community_moderator_for(posts.community_id)
      )
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_realmoji_reactions' AND policyname = 'post_realmoji_reactions_update_own') THEN
    CREATE POLICY "post_realmoji_reactions_update_own" ON post_realmoji_reactions FOR UPDATE USING (
      auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = post_realmoji_reactions.user_id)
    );
  END IF;
END $$;
