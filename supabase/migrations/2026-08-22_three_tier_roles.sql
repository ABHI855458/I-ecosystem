-- ============================================================================
-- 3-TIER ROLE/PERMISSIONS SYSTEM — admin / global_moderator / community_moderator
-- ============================================================================
-- MANUAL RUN ONLY — paste into Supabase SQL Editor and run yourself.
-- Not executed by any tooling. Builds on the existing `moderators` table
-- (keyed by email, RLS-enforced) — does not create a parallel system.
--
-- Ground truth this was written against (live schema, verified via
-- PostgREST introspection, NOT the stale supabase/schema.sql):
--   - moderators: id, email (unique), role ('admin'|'moderator' today),
--     created_at, updated_at. 2 live rows.
--   - profiles: real identity table, id = auth.uid(). 4 live rows.
--   - users: near-dead stopgap, 1 demo row — posts/comments/reactions/
--     post_realmoji_reactions/group_posts still FK to users.id (verified
--     live, not assumed). Out of scope for this migration per explicit
--     instruction — flagged as a separate follow-up.
--   - community_members: (community_id, user_id -> profiles.id, joined_at).
--     0 rows, no role column (never existed — "rolled back" was literal).
--   - posts.community_id exists but is NULL on every live row (community
--     content actually flows through the separate group_posts table).
--   - daily_prompts.community_id exists, nullable, unused. ping_prompts has
--     no link to daily_prompts at all today.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- PART A — extend `moderators` for 3-tier + community scoping
-- ----------------------------------------------------------------------------

ALTER TABLE moderators
  ADD COLUMN IF NOT EXISTS community_id UUID REFERENCES communities(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_protected BOOLEAN NOT NULL DEFAULT FALSE;

-- Rename the existing 2-tier 'moderator' role to 'global_moderator' before
-- adding the CHECK constraint that would otherwise reject it.
UPDATE moderators SET role = 'global_moderator' WHERE role = 'moderator';

ALTER TABLE moderators
  ALTER COLUMN role DROP DEFAULT,
  ALTER COLUMN role SET DEFAULT 'community_moderator';

ALTER TABLE moderators
  ADD CONSTRAINT moderators_role_check
    CHECK (role IN ('admin', 'global_moderator', 'community_moderator'));

ALTER TABLE moderators
  ADD CONSTRAINT moderators_community_scope_check
    CHECK (
      (role = 'community_moderator' AND community_id IS NOT NULL) OR
      (role IN ('admin', 'global_moderator') AND community_id IS NULL)
    );

-- Pin the existing admin row as permanently unremovable/unmodifiable.
-- EDIT THE EMAIL BELOW if this isn't the right row before running.
UPDATE moderators SET is_protected = TRUE
  WHERE email = 'abhisheksdpatel.cs25@rvce.edu.in' AND role = 'admin';


-- ----------------------------------------------------------------------------
-- PART B — role-check helper functions (SECURITY DEFINER)
-- ----------------------------------------------------------------------------
-- Why SECURITY DEFINER: the ORIGINAL moderators RLS (moderators_select
-- required role='admin') meant a plain 'moderator' row could never see its
-- OWN row, so any OTHER table's policy that did
-- `EXISTS (SELECT 1 FROM moderators WHERE email = auth.email())` — e.g.
-- posts_delete_moderator — silently evaluated to FALSE for them, because
-- that subquery is itself subject to moderators' RLS (recursive). This was
-- a real, live bug, just never surfaced because the dashboard had no login
-- (service_role bypasses RLS entirely) until now. These helpers run as the
-- function owner (bypasses RLS internally, standard Supabase pattern) so
-- every moderator's OWN role/community always resolves correctly,
-- regardless of what moderators_select otherwise allows them to see.

CREATE OR REPLACE FUNCTION current_moderator_role()
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT role FROM moderators WHERE email = auth.email() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION current_moderator_community_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT community_id FROM moderators WHERE email = auth.email() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION current_moderator_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT id FROM moderators WHERE email = auth.email() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT current_moderator_role() = 'admin';
$$;

CREATE OR REPLACE FUNCTION is_global_moderator()
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT current_moderator_role() = 'global_moderator';
$$;

CREATE OR REPLACE FUNCTION is_admin_or_global_mod()
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT current_moderator_role() IN ('admin', 'global_moderator');
$$;

CREATE OR REPLACE FUNCTION is_community_moderator_for(target_community UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT current_moderator_role() = 'community_moderator'
     AND current_moderator_community_id() = target_community;
$$;

-- The one predicate almost every moderation policy below actually uses:
-- "can the caller moderate content belonging to this community" — true
-- unconditionally for admin/global_moderator, true for a community_moderator
-- only when it's THEIR community. NULL target_community (content with no
-- community assigned) never matches the community_moderator branch, which
-- is what makes the community-scoped policies correctly no-op on today's
-- data (posts.community_id is always NULL right now).
CREATE OR REPLACE FUNCTION can_moderate_community(target_community UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT is_admin_or_global_mod() OR is_community_moderator_for(target_community);
$$;

GRANT EXECUTE ON FUNCTION current_moderator_role() TO authenticated;
GRANT EXECUTE ON FUNCTION current_moderator_community_id() TO authenticated;
GRANT EXECUTE ON FUNCTION current_moderator_id() TO authenticated;
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION is_global_moderator() TO authenticated;
GRANT EXECUTE ON FUNCTION is_admin_or_global_mod() TO authenticated;
GRANT EXECUTE ON FUNCTION is_community_moderator_for(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION can_moderate_community(UUID) TO authenticated;


-- ----------------------------------------------------------------------------
-- PART C — one-time self-service profile linking (dashboard login flow)
-- ----------------------------------------------------------------------------
-- Called once by the dashboard right after a moderator's first successful
-- login, so `moderators.profile_id` gets populated without needing a
-- general-purpose UPDATE policy that a moderator could otherwise use to
-- edit OTHER columns (role, community_id) on their own row. This function
-- can only ever set profile_id = auth.uid() on the row matching the
-- caller's OWN email — no privilege-escalation surface.

CREATE OR REPLACE FUNCTION claim_moderator_profile()
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE moderators
     SET profile_id = auth.uid(), updated_at = now()
   WHERE email = auth.email() AND profile_id IS NULL;
$$;

GRANT EXECUTE ON FUNCTION claim_moderator_profile() TO authenticated;


-- ----------------------------------------------------------------------------
-- PART D — moderators RLS (replaces the old 2-tier policies)
-- ----------------------------------------------------------------------------
-- Appointment rule encoded here: INSERT allows admin (any role) OR
-- global_moderator inserting ONLY a community_moderator row — matches
-- "both admin and global mods can appoint community moderators" while
-- "only admin can add app users and grant dashboard permissions" (every
-- OTHER write — editing an existing moderator's role/community, or
-- deleting one — is admin-only). is_protected rows are immune to
-- UPDATE/DELETE for every role, including other admins.

DROP POLICY IF EXISTS "moderators_select" ON moderators;
CREATE POLICY "moderators_select" ON moderators FOR SELECT USING (
  is_admin_or_global_mod() OR email = auth.email()
);

DROP POLICY IF EXISTS "moderators_insert" ON moderators;
CREATE POLICY "moderators_insert" ON moderators FOR INSERT WITH CHECK (
  is_admin()
  OR (is_global_moderator() AND role = 'community_moderator')
);

DROP POLICY IF EXISTS "moderators_update" ON moderators;
CREATE POLICY "moderators_update" ON moderators FOR UPDATE USING (
  is_admin() AND is_protected = FALSE
) WITH CHECK (
  is_admin() AND is_protected = FALSE
);

DROP POLICY IF EXISTS "moderators_delete" ON moderators;
CREATE POLICY "moderators_delete" ON moderators FOR DELETE USING (
  is_admin() AND is_protected = FALSE
);


-- ----------------------------------------------------------------------------
-- PART E — extend existing moderation DELETE policies to 3-tier + scoping
-- ----------------------------------------------------------------------------
-- posts/comments already had a moderator-delete policy (schema.sql) — these
-- REPLACE those two. post_realmoji_reactions and profiles did not have one;
-- these ADD new policies without touching whatever SELECT/INSERT policies
-- already exist there (unknown to this audit — additive only, never DROP
-- anything I don't have the original definition of).

DROP POLICY IF EXISTS "posts_delete_moderator" ON posts;
CREATE POLICY "posts_delete_moderator" ON posts FOR DELETE USING (
  can_moderate_community(community_id)
);

-- The dashboard's actual "remove post" action (Posts.jsx) soft-deletes via
-- UPDATE (sets deleted_at), not a hard DELETE — posts had no moderator
-- UPDATE policy at all before this (only posts_update_own, which requires
-- being the post's own author). Discovered while auditing what the
-- anon-key client swap would newly block; without this, moderator soft-
-- delete silently no-ops (0 rows updated, no error) instead of working.
DROP POLICY IF EXISTS "posts_update_moderator" ON posts;
CREATE POLICY "posts_update_moderator" ON posts FOR UPDATE USING (
  can_moderate_community(community_id)
) WITH CHECK (
  can_moderate_community(community_id)
);

DROP POLICY IF EXISTS "comments_delete_moderator" ON comments;
CREATE POLICY "comments_delete_moderator" ON comments FOR DELETE USING (
  is_admin_or_global_mod()
  OR EXISTS (
    SELECT 1 FROM posts WHERE posts.id = comments.post_id
      AND is_community_moderator_for(posts.community_id)
  )
);

ALTER TABLE post_realmoji_reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "post_realmoji_reactions_delete_moderator" ON post_realmoji_reactions;
CREATE POLICY "post_realmoji_reactions_delete_moderator" ON post_realmoji_reactions FOR DELETE USING (
  is_admin_or_global_mod()
  OR EXISTS (
    SELECT 1 FROM posts WHERE posts.id = post_realmoji_reactions.post_id
      AND is_community_moderator_for(posts.community_id)
  )
);

-- "remove users from the app" (global moderator capability). Full removal
-- (deleting the auth.users row) is a service_role-only Admin API call — RLS
-- has no jurisdiction there, see the dashboard code comments. This policy
-- covers the profiles-table half of that action for defense in depth /
-- for any non-Admin-API removal path.
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profiles_delete_moderator" ON profiles;
CREATE POLICY "profiles_delete_moderator" ON profiles FOR DELETE USING (
  is_admin_or_global_mod()
);

-- Additive, not a replacement: the ORIGINAL pings_select (participant-only:
-- auth.uid() IN sender/receiver) stays exactly as-is for everyone else.
-- This just ALSO lets admin/global_moderator see every row — needed so
-- Overview.jsx's exact-count stat for `pings` reflects the real total
-- instead of silently reporting 0 (a moderator is never a ping's own
-- sender/receiver, so under RLS alone that count would just be filtered
-- to nothing — no error, just quietly wrong). Multiple permissive SELECT
-- policies on the same table OR together in Postgres, so this is safe to
-- add without touching the existing policy.
DROP POLICY IF EXISTS "pings_select_moderator" ON pings;
CREATE POLICY "pings_select_moderator" ON pings FOR SELECT USING (
  is_admin_or_global_mod()
);


-- ----------------------------------------------------------------------------
-- PART F — community feed content (news+docs, polls, daily prompts)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS community_feed_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  author_moderator_id UUID NOT NULL REFERENCES moderators(id),
  item_type TEXT NOT NULL CHECK (item_type IN ('news', 'poll', 'daily_prompt')),
  title TEXT NOT NULL,
  body TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS community_feed_items_community_idx ON community_feed_items(community_id);

CREATE TABLE IF NOT EXISTS community_feed_documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  feed_item_id UUID NOT NULL REFERENCES community_feed_items(id) ON DELETE CASCADE,
  file_url TEXT NOT NULL,
  file_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS community_feed_poll_options (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  feed_item_id UUID NOT NULL REFERENCES community_feed_items(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  position INT NOT NULL
);

CREATE TABLE IF NOT EXISTS community_feed_poll_votes (
  feed_item_id UUID NOT NULL REFERENCES community_feed_items(id) ON DELETE CASCADE,
  option_id UUID NOT NULL REFERENCES community_feed_poll_options(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (feed_item_id, profile_id)
);

-- Link the EXISTING daily_prompts/ping_prompts tables into the feed instead
-- of duplicating them.
ALTER TABLE daily_prompts
  ADD COLUMN IF NOT EXISTS feed_item_id UUID REFERENCES community_feed_items(id) ON DELETE CASCADE;

ALTER TABLE ping_prompts
  ADD COLUMN IF NOT EXISTS daily_prompt_id UUID REFERENCES daily_prompts(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION enforce_max_4_ping_prompts()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.daily_prompt_id IS NOT NULL THEN
    IF (SELECT count(*) FROM ping_prompts
          WHERE daily_prompt_id = NEW.daily_prompt_id
            AND id <> NEW.id) >= 4 THEN
      RAISE EXCEPTION 'A daily prompt can have at most 4 ping-prompts.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_max_4_ping_prompts ON ping_prompts;
CREATE TRIGGER trg_max_4_ping_prompts
  BEFORE INSERT OR UPDATE OF daily_prompt_id ON ping_prompts
  FOR EACH ROW EXECUTE FUNCTION enforce_max_4_ping_prompts();


-- ---- RLS: community_feed_items ---------------------------------------------

ALTER TABLE community_feed_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "community_feed_items_select" ON community_feed_items FOR SELECT USING (
  deleted_at IS NULL
);
CREATE POLICY "community_feed_items_insert" ON community_feed_items FOR INSERT WITH CHECK (
  can_moderate_community(community_id) AND author_moderator_id = current_moderator_id()
);
CREATE POLICY "community_feed_items_update" ON community_feed_items FOR UPDATE USING (
  can_moderate_community(community_id)
) WITH CHECK (
  can_moderate_community(community_id)
);
CREATE POLICY "community_feed_items_delete" ON community_feed_items FOR DELETE USING (
  can_moderate_community(community_id)
);

-- ---- RLS: community_feed_documents -----------------------------------------

ALTER TABLE community_feed_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "community_feed_documents_select" ON community_feed_documents FOR SELECT USING (true);
CREATE POLICY "community_feed_documents_insert" ON community_feed_documents FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM community_feed_items i WHERE i.id = feed_item_id AND can_moderate_community(i.community_id))
);
CREATE POLICY "community_feed_documents_delete" ON community_feed_documents FOR DELETE USING (
  EXISTS (SELECT 1 FROM community_feed_items i WHERE i.id = feed_item_id AND can_moderate_community(i.community_id))
);

-- ---- RLS: community_feed_poll_options --------------------------------------

ALTER TABLE community_feed_poll_options ENABLE ROW LEVEL SECURITY;

CREATE POLICY "community_feed_poll_options_select" ON community_feed_poll_options FOR SELECT USING (true);
CREATE POLICY "community_feed_poll_options_insert" ON community_feed_poll_options FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM community_feed_items i WHERE i.id = feed_item_id AND can_moderate_community(i.community_id))
);
CREATE POLICY "community_feed_poll_options_update" ON community_feed_poll_options FOR UPDATE USING (
  EXISTS (SELECT 1 FROM community_feed_items i WHERE i.id = feed_item_id AND can_moderate_community(i.community_id))
);
CREATE POLICY "community_feed_poll_options_delete" ON community_feed_poll_options FOR DELETE USING (
  EXISTS (SELECT 1 FROM community_feed_items i WHERE i.id = feed_item_id AND can_moderate_community(i.community_id))
);

-- ---- RLS: community_feed_poll_votes ----------------------------------------
-- App users vote, not moderators — ownership check only (matches the
-- existing app's permissive-read convention, e.g. reactions_select USING
-- (true)).

ALTER TABLE community_feed_poll_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "community_feed_poll_votes_select" ON community_feed_poll_votes FOR SELECT USING (true);
CREATE POLICY "community_feed_poll_votes_insert" ON community_feed_poll_votes FOR INSERT WITH CHECK (
  profile_id = auth.uid()
);
CREATE POLICY "community_feed_poll_votes_update" ON community_feed_poll_votes FOR UPDATE USING (
  profile_id = auth.uid()
) WITH CHECK (
  profile_id = auth.uid()
);
CREATE POLICY "community_feed_poll_votes_delete" ON community_feed_poll_votes FOR DELETE USING (
  profile_id = auth.uid()
);

-- ---- RLS: daily_prompts / ping_prompts write access ------------------------
-- Additive — these tables' existing SELECT (or other) policies, if any,
-- are untouched; only new moderator-write policies are added. Prompts with
-- no community (community_id / daily_prompt_id IS NULL) stay admin/global-
-- moderator-only, matching how they're app-wide today.

ALTER TABLE daily_prompts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "daily_prompts_insert_moderator" ON daily_prompts;
CREATE POLICY "daily_prompts_insert_moderator" ON daily_prompts FOR INSERT WITH CHECK (
  (community_id IS NULL AND is_admin_or_global_mod())
  OR (community_id IS NOT NULL AND can_moderate_community(community_id))
);
DROP POLICY IF EXISTS "daily_prompts_update_moderator" ON daily_prompts;
CREATE POLICY "daily_prompts_update_moderator" ON daily_prompts FOR UPDATE USING (
  (community_id IS NULL AND is_admin_or_global_mod())
  OR (community_id IS NOT NULL AND can_moderate_community(community_id))
);
DROP POLICY IF EXISTS "daily_prompts_delete_moderator" ON daily_prompts;
CREATE POLICY "daily_prompts_delete_moderator" ON daily_prompts FOR DELETE USING (
  (community_id IS NULL AND is_admin_or_global_mod())
  OR (community_id IS NOT NULL AND can_moderate_community(community_id))
);

ALTER TABLE ping_prompts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ping_prompts_insert_moderator" ON ping_prompts;
CREATE POLICY "ping_prompts_insert_moderator" ON ping_prompts FOR INSERT WITH CHECK (
  (daily_prompt_id IS NULL AND is_admin_or_global_mod())
  OR EXISTS (SELECT 1 FROM daily_prompts dp WHERE dp.id = daily_prompt_id AND can_moderate_community(dp.community_id))
);
DROP POLICY IF EXISTS "ping_prompts_update_moderator" ON ping_prompts;
CREATE POLICY "ping_prompts_update_moderator" ON ping_prompts FOR UPDATE USING (
  (daily_prompt_id IS NULL AND is_admin_or_global_mod())
  OR EXISTS (SELECT 1 FROM daily_prompts dp WHERE dp.id = daily_prompt_id AND can_moderate_community(dp.community_id))
);
DROP POLICY IF EXISTS "ping_prompts_delete_moderator" ON ping_prompts;
CREATE POLICY "ping_prompts_delete_moderator" ON ping_prompts FOR DELETE USING (
  (daily_prompt_id IS NULL AND is_admin_or_global_mod())
  OR EXISTS (SELECT 1 FROM daily_prompts dp WHERE dp.id = daily_prompt_id AND can_moderate_community(dp.community_id))
);

-- ============================================================================
-- END — verify after running:
--   select email, role, community_id, is_protected from moderators;
--   select proname from pg_proc where proname like 'is_%' or proname like 'current_moderator%';
-- ============================================================================
