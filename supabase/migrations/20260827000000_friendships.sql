-- ============================================================================
-- Friendships — prerequisite for Us-album 'mutual' visibility (Phase 3) and
-- the Add Friend button on TheirProfileScreen (Phase 2).
--
-- NOT RUN YET — draft for review. Manual-run block, same convention as
-- 2026-08-22_three_tier_roles.sql.
-- ============================================================================
--
-- STATE MODEL — deliberately just two real states, no permanent history:
--   'pending'  — requester_id has asked, addressee_id hasn't responded yet
--   'accepted' — both sides are friends
-- There is no 'declined' status and no 'unfriended' status. Declining a
-- pending request, or unfriending an accepted one, both just DELETE the row
-- — "no relationship" IS "no row", full stop. This means either side can
-- freely re-request after a decline (no cooldown, no permanent block) —
-- flag if you want a cooldown/rate-limit instead; that would need a new
-- column (e.g. last_declined_at) and is a bigger change than this draft.
--
-- DIRECTIONALITY — requester_id/addressee_id (not a symmetric pair) so the
-- UI can tell "I sent this" from "they sent this" (your 4 states: not-
-- friends / pending-sent / incoming-request / friends all fall out of who's
-- who on the one row that can exist between two users).
--
-- ONE ROW PER PAIR, REGARDLESS OF DIRECTION — friendships_pair_unique below
-- is a unique index on the NORMALIZED (LEAST, GREATEST) pair, not on
-- (requester_id, addressee_id) directly. Without this, nothing would stop
-- both "A requested B" AND "B requested A" existing as two separate rows
-- simultaneously.
-- ============================================================================

-- Schema-qualified: extensions.uuid_generate_v4(), not the bare name.
-- uuid-ossp lives in the `extensions` schema on this project, and the
-- migration-runner's session search_path doesn't include it (confirmed via
-- `pg_proc`/`SHOW search_path` — differs from an ad-hoc `db query` session,
-- which does), so the bare call resolves fine interactively but fails
-- during an actual migration run. Qualifying sidesteps that entirely.
CREATE TABLE friendships (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
  created_at TIMESTAMP DEFAULT NOW(),
  responded_at TIMESTAMP,
  CONSTRAINT friendships_no_self CHECK (requester_id <> addressee_id)
);

-- Enforces "at most one relationship row per pair" regardless of who
-- requested whom. expression index, not a column, so it can't drift out of
-- sync with requester_id/addressee_id.
CREATE UNIQUE INDEX friendships_pair_unique ON friendships (
  LEAST(requester_id, addressee_id),
  GREATEST(requester_id, addressee_id)
);

CREATE INDEX friendships_requester_idx ON friendships(requester_id);
CREATE INDEX friendships_addressee_idx ON friendships(addressee_id);

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

-- SELECT — only the two people IN the relationship can see the row. (Phase
-- 3's "mutual friends of both A and B" computation for Us-album visibility
-- will need a SECURITY DEFINER helper function to compute that across rows
-- neither viewer is a party to — plain table SELECT access intentionally
-- does NOT expose that; flagging now so Phase 3's proposal isn't a surprise.)
CREATE POLICY "friendships_select_own" ON friendships FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = requester_id)
  OR auth.uid() IN (SELECT auth_id FROM users WHERE id = addressee_id)
);

-- INSERT — only as yourself, only as the requester, only starting 'pending'
-- (can't insert a pre-accepted row to skip the other side's consent).
CREATE POLICY "friendships_insert_own" ON friendships FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = requester_id)
  AND status = 'pending'
);

-- UPDATE — only the addressee, only pending -> accepted (accepting a
-- request). Nothing else is a legal update (no status other than accepted
-- is settable this way; canceling/declining/unfriending are all DELETE).
CREATE POLICY "friendships_accept" ON friendships FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = addressee_id)
  AND status = 'pending'
) WITH CHECK (
  status = 'accepted'
);

-- DELETE — either party, any state. Covers: requester cancels a pending
-- request, addressee declines a pending request, either side unfriends an
-- accepted one.
CREATE POLICY "friendships_delete_own" ON friendships FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = requester_id)
  OR auth.uid() IN (SELECT auth_id FROM users WHERE id = addressee_id)
);
