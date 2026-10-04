-- ============================================================================
-- Us albums — pairwise shared photo albums, per the original spec:
--   us_albums: id, user_a, user_b, created_at, status (pending/accepted)
--   us_album_photos: id, album_id, uploaded_by, photo_url, created_at,
--     visibility ('private'|'mutual', default 'private')
--
-- NOT RUN YET — draft for review. Manual-run block, same convention as the
-- friendships migration.
-- ============================================================================
--
-- ALBUM LIFECYCLE — mirrors friendships' pending/accepted shape, with one
-- addition: created_by, because "the other must accept before it's visible
-- to anyone but the creator" needs to know who "the creator" is. Symmetric
-- to friendships otherwise: both parties can always see their OWN album row
-- regardless of status (the non-creator needs to see the pending invite to
-- act on it) — it's only THIRD PARTIES who are gated on status='accepted'.
--
-- PHOTO-ADD TIMING — reconciling two lines from the original spec that
-- read as slightly in tension ("created when either user adds the first
-- photo" vs "either party can add photos to an accepted album"): the
-- CREATOR can add photos (including the first one, which creates the
-- pending row) before the other side accepts; the NON-creator can only add
-- once accepted. Flag if this isn't the intended reading — it's my
-- resolution of an ambiguity, not something you stated outright.
--
-- PER-PHOTO VISIBILITY — 'private' default, either party's own uploads,
-- toggle is OWN uploads only (per your later clarification: "a per-photo
-- lock/globe toggle each party can flip on their own uploads (not the
-- other party's)"). 'mutual' = visible to both owners AND any viewer who
-- is an ACCEPTED friend of BOTH — computed via a SECURITY DEFINER helper
-- (is_mutual_friend_of_both), per TICKET 3 in TODO_TICKETS.md: plain table
-- SELECT access can't compute this, since friendships' own RLS only lets a
-- user see rows they're a party to.
--
-- LIVE, NOT PRECOMPUTED — per the question you asked me to answer before
-- wiring the DB: is_mutual_friend_of_both() below computes live off
-- friendships(requester_id)/friendships(addressee_id) (already indexed,
-- from that migration). Recommending live for now given this is a new app
-- with small expected friend-counts per user — the EXISTS-based query
-- short-circuits and stays cheap. Revisit (precompute into a lookup table)
-- if/when friend-counts grow large enough that this shows up in slow-query
-- logs — not a decision to make speculatively now.
--
-- STORAGE — photo_url is just a TEXT column here, same shape as
-- group_posts.photo_url / users.profile_photo_url. Actual upload mechanics
-- (bucket, path convention) reuse the existing StorageService/BucketService
-- already in this app — no new schema needed for that part.
--
-- SCOPE NOTE — this schema fully implements 'mutual' visibility (SELECT
-- RLS on us_album_photos includes the third-party mutual-friend path), but
-- per your earlier answer, TheirProfileScreen's UI for v1 only shows "my
-- own album with this person" — it does NOT yet surface a third party's
-- OTHER mutual-visible albums. The backend supports that already; only the
-- UI for it is deferred, so nothing here needs to change when that ships.
--
-- DELETING AN ACCEPTED ALBUM REQUIRES MUTUAL CONSENT — NOT symmetric with
-- unfriend, per explicit correction. Real shared photos are a genuine joint
-- artifact; one party unilaterally destroying content the other
-- contributed is worse than anything unfriend risks (an empty relationship
-- row). Two-step handshake via delete_requested_by: party A sets it to
-- themselves (an UPDATE — us_albums_request_delete below), then only party
-- B (NOT A) can issue the actual DELETE (us_albums_delete_confirmed) —
-- either side can be the one who first requests, but the deletion only
-- executes once the OTHER side independently confirms it. Either party can
-- also clear delete_requested_by back to null to cancel/decline a pending
-- request they don't agree with.
--
-- PENDING (not yet accepted) albums are the one exception, kept simple —
-- see us_albums_delete_pending: at that stage only the CREATOR has been
-- able to upload anything (per the photo-add-timing note above), so
-- declining/canceling a pending invite is the same shape as declining a
-- friend request, not "destroying the other party's contribution." Mutual
-- consent only gates ACCEPTED albums, where both sides may have added
-- real content.
--
-- INDIVIDUAL PHOTO DELETION IS UNAFFECTED — us_album_photos_delete_own
-- (below, on the us_album_photos table) lets a party delete their OWN
-- uploaded photo unilaterally, same as it always did. That's a genuinely
-- separate action from destroying the whole shared album and was never
-- bundled with the consent requirement above.
--
-- NOT BUILT (noted as a possible future addition, not scope-crept in now):
-- a per-user "hide from my own view without deleting" option, floated as
-- "if that's useful" rather than a firm requirement — would need its own
-- hidden_by_a/hidden_by_b-shaped column pair. Left out of this pass.
-- ============================================================================

CREATE TABLE us_albums (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  user_a UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
  created_at TIMESTAMP DEFAULT NOW(),
  responded_at TIMESTAMP,
  -- Mutual-consent delete handshake — see this file's own note above.
  -- Null = no pending delete request. Set to one party's id = that party
  -- has requested deletion; only the OTHER party's DELETE call actually
  -- removes the row (us_albums_delete_confirmed).
  delete_requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
  delete_requested_at TIMESTAMP,
  CONSTRAINT us_albums_no_self CHECK (user_a <> user_b),
  CONSTRAINT us_albums_creator_is_party CHECK (created_by IN (user_a, user_b)),
  CONSTRAINT us_albums_delete_requester_is_party CHECK (delete_requested_by IS NULL OR delete_requested_by IN (user_a, user_b))
);

CREATE UNIQUE INDEX us_albums_pair_unique ON us_albums (
  LEAST(user_a, user_b),
  GREATEST(user_a, user_b)
);

CREATE INDEX us_albums_user_a_idx ON us_albums(user_a);
CREATE INDEX us_albums_user_b_idx ON us_albums(user_b);

CREATE TABLE us_album_photos (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  album_id UUID NOT NULL REFERENCES us_albums(id) ON DELETE CASCADE,
  uploaded_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL,
  visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'mutual')),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX us_album_photos_album_idx ON us_album_photos(album_id);

-- ============================================================================
-- SECURITY DEFINER helper — see TICKET 3. Bypasses the caller's own RLS on
-- friendships to check THIRD-PARTY rows (target_a's and target_b's
-- friendships, not the caller's own) — that's the whole reason this can't
-- be a plain view/query.
-- ============================================================================

CREATE OR REPLACE FUNCTION is_mutual_friend_of_both(target_a UUID, target_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM users viewer
    WHERE viewer.auth_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM friendships f
      WHERE f.status = 'accepted'
      AND ((f.requester_id = viewer.id AND f.addressee_id = target_a)
        OR (f.addressee_id = viewer.id AND f.requester_id = target_a))
    )
    AND EXISTS (
      SELECT 1 FROM friendships f
      WHERE f.status = 'accepted'
      AND ((f.requester_id = viewer.id AND f.addressee_id = target_b)
        OR (f.addressee_id = viewer.id AND f.requester_id = target_b))
    )
  );
$$;

-- ============================================================================
-- RLS — us_albums
-- ============================================================================

ALTER TABLE us_albums ENABLE ROW LEVEL SECURITY;

-- Both parties always see their own row (any status) — third parties only
-- once accepted, and only if mutual-friends-of-both.
CREATE POLICY "us_albums_select" ON us_albums FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id IN (user_a, user_b))
  OR (status = 'accepted' AND is_mutual_friend_of_both(user_a, user_b))
);

-- Only as yourself, only as a party, only starting pending, and created_by
-- must be you (can't create an album crediting the other person as creator).
CREATE POLICY "us_albums_insert" ON us_albums FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id IN (user_a, user_b))
  AND auth.uid() IN (SELECT auth_id FROM users WHERE id = created_by)
  AND status = 'pending'
);

-- Only the NON-creator can accept (pending -> accepted) — mirrors
-- friendships_accept: the person who didn't initiate is the one consenting.
-- WITH CHECK also pins delete_requested_by to null on accept — otherwise
-- this policy's own WITH CHECK (which is OR'd against
-- us_albums_request_delete's below, since Postgres combines permissive
-- policies with OR) wouldn't itself constrain that column, and a caller
-- could smuggle an arbitrary delete_requested_by value through an accept
-- call. A freshly-accepted album should never start with a stale request.
CREATE POLICY "us_albums_accept" ON us_albums FOR UPDATE USING (
  status = 'pending'
  AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (user_a, user_b))
  AND auth.uid() NOT IN (SELECT auth_id FROM users WHERE id = created_by)
) WITH CHECK (
  status = 'accepted' AND delete_requested_by IS NULL
);

-- Either party can request deletion (set delete_requested_by = self) or
-- cancel/decline a pending request (clear it back to null) on an accepted
-- album. This alone does NOT delete anything — see us_albums_delete_
-- confirmed below, which requires the OTHER party to act.
CREATE POLICY "us_albums_request_delete" ON us_albums FOR UPDATE USING (
  status = 'accepted'
  AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (user_a, user_b))
) WITH CHECK (
  status = 'accepted'
);

-- PENDING albums stay simply deletable by either party (declining/
-- canceling an invite) — see this file's own note on why mutual consent
-- doesn't apply at this stage.
CREATE POLICY "us_albums_delete_pending" ON us_albums FOR DELETE USING (
  status = 'pending'
  AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (user_a, user_b))
);

-- ACCEPTED albums require the two-step mutual-consent handshake: a pending
-- delete_requested_by must already be set, AND the party issuing THIS
-- DELETE must be the OTHER one (not who set it) — so the same person can
-- never both request and execute the deletion alone.
CREATE POLICY "us_albums_delete_confirmed" ON us_albums FOR DELETE USING (
  status = 'accepted'
  AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (user_a, user_b))
  AND delete_requested_by IS NOT NULL
  AND auth.uid() NOT IN (SELECT auth_id FROM users WHERE id = delete_requested_by)
);

-- ============================================================================
-- RLS — us_album_photos
-- ============================================================================

ALTER TABLE us_album_photos ENABLE ROW LEVEL SECURITY;

-- A party sees ALL photos (private + mutual) in their own accepted album.
-- A third party sees ONLY 'mutual' photos, only in an accepted album, only
-- if mutual-friends-of-both.
CREATE POLICY "us_album_photos_select" ON us_album_photos FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM us_albums a
    WHERE a.id = album_id AND a.status = 'accepted'
    AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (a.user_a, a.user_b))
  )
  OR (
    visibility = 'mutual'
    AND EXISTS (
      SELECT 1 FROM us_albums a
      WHERE a.id = album_id AND a.status = 'accepted'
      AND is_mutual_friend_of_both(a.user_a, a.user_b)
    )
  )
);

-- Uploader must be a party of the album, and either the album is already
-- accepted, or the uploader is the album's own creator (covers the
-- first-photo-creates-the-album flow — see this file's own note on that
-- above). The non-creator can't upload until they've accepted.
CREATE POLICY "us_album_photos_insert" ON us_album_photos FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = uploaded_by)
  AND EXISTS (
    SELECT 1 FROM us_albums a
    WHERE a.id = album_id
    AND auth.uid() IN (SELECT auth_id FROM users WHERE id IN (a.user_a, a.user_b))
    AND (a.status = 'accepted' OR auth.uid() IN (SELECT auth_id FROM users WHERE id = a.created_by))
  )
);

-- Visibility toggle — own uploads only, per your explicit clarification.
CREATE POLICY "us_album_photos_update_own" ON us_album_photos FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = uploaded_by)
) WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = uploaded_by)
);

-- Not explicitly specified in the original ask — added for consistency
-- with this app's existing "delete your own content" convention
-- (posts_delete_own, comments_delete_own). Flag if photo deletion should
-- work differently (e.g. disallowed once 'mutual', or requiring the other
-- party's consent).
CREATE POLICY "us_album_photos_delete_own" ON us_album_photos FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = uploaded_by)
);
