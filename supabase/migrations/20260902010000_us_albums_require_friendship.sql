-- ============================================================================
-- Us albums — require an ACCEPTED friendship to START one (INSERT), closing a
-- gap left open since 20260828000000_us_albums.sql: that migration correctly
-- gates THIRD-PARTY 'mutual'-photo visibility on friendship
-- (is_mutual_friend_of_both), but never gated CREATING an album at all — any
-- two signed-in users, friends or total strangers, could start a pending Us
-- album together. Discovered during the friend-request UI wiring (2026-09-02)
-- once "friends" became a real, checkable relationship in the UI, not just a
-- backend table nothing referenced yet.
--
-- Manual-run block, same convention as the rest of this schema's migrations.
-- ============================================================================
--
-- NEW HELPER, not a reuse of is_mutual_friend_of_both — that function checks
-- "is V friends with BOTH A and B" (a third-party viewer's relationship to two
-- OTHER people). What's needed here is different: "ARE A and B friends with
-- EACH OTHER" — the two parties of the album, not a viewer. SECURITY DEFINER
-- for the same reason as its sibling: this evaluates `friendships` rows that
-- may belong to neither the caller nor a plain SELECT-visible pair, and
-- friendships_select_own's own RLS only lets a user see rows they're a party
-- to — the INSERT-time check here is being run as one of the two prospective
-- album parties, so in practice they ARE a party to the row being tested, but
-- defining it as SECURITY DEFINER keeps it symmetric with is_mutual_friend_of_
-- both and safe to reuse elsewhere later without re-deriving this reasoning.
CREATE OR REPLACE FUNCTION are_accepted_friends(a UUID, b UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM friendships f
    WHERE f.status = 'accepted'
    AND ((f.requester_id = a AND f.addressee_id = b)
      OR (f.requester_id = b AND f.addressee_id = a))
  );
$$;

-- SCOPE — ONLY the two INSERT policies change. Deliberately untouched:
-- us_albums_select, us_album_photos_select, us_albums_accept, and every
-- DELETE policy. Consequence, stated plainly: an album created while two
-- people were friends SURVIVES an unfriend — both parties keep reading it,
-- and the existing mutual-consent delete handshake still governs removing
-- it — but neither side can add new photos to it until they are friends
-- again. That mirrors this schema's own established position that one party
-- must never be able to unilaterally destroy content the other contributed
-- (see 20260828000000_us_albums.sql's note on why unfriend and Us-album
-- deletion are NOT symmetric operations).

DROP POLICY "us_albums_insert" ON us_albums;

CREATE POLICY "us_albums_insert" ON us_albums FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id IN (user_a, user_b))
  AND auth.uid() IN (SELECT auth_id FROM users WHERE id = created_by)
  AND status = 'pending'
  AND are_accepted_friends(user_a, user_b)
);

DROP POLICY "us_album_photos_insert" ON us_album_photos;

CREATE POLICY "us_album_photos_insert" ON us_album_photos FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = uploaded_by)
  AND EXISTS (
    SELECT 1 FROM us_albums a
    WHERE a.id = album_id
    AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (a.user_a, a.user_b))
    AND (a.status = 'accepted' OR auth.uid() IN (SELECT auth_id FROM users WHERE id = a.created_by))
    AND are_accepted_friends(a.user_a, a.user_b)
  )
);
