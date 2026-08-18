-- ========================================
-- I APP SCHEMA (Supabase)
-- ========================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ========================================
-- USERS TABLE
-- ========================================

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  anon_name TEXT UNIQUE NOT NULL,
  department TEXT,
  bio TEXT,
  profile_photo_url TEXT,
  banner_url TEXT,
  glow_score INT DEFAULT 0,
  ping_score INT DEFAULT 0,
  streak INT DEFAULT 0,
  posted_today BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX users_email_idx ON users(email);
CREATE INDEX users_auth_id_idx ON users(auth_id);

-- ========================================
-- COMMUNITIES TABLE
-- ========================================

CREATE TABLE communities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT UNIQUE NOT NULL,
  description TEXT,
  icon_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX communities_deleted_idx ON communities(deleted_at);

-- ========================================
-- USER COMMUNITIES (join table)
-- ========================================

CREATE TABLE user_communities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  community_id UUID REFERENCES communities(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, community_id)
);

CREATE INDEX user_communities_user_idx ON user_communities(user_id);
CREATE INDEX user_communities_community_idx ON user_communities(community_id);

-- ========================================
-- POSTS TABLE
-- ========================================

CREATE TABLE posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  content TEXT,
  image_url TEXT,
  visibility TEXT CHECK (visibility IN ('anonymous', 'everyone', 'community')),
  community_id UUID REFERENCES communities(id) ON DELETE SET NULL,
  music_id TEXT,
  music_url TEXT,
  music_title TEXT,
  music_artist TEXT,
  prompt TEXT,
  photo_fit TEXT DEFAULT 'fill',
  aspect_ratio TEXT DEFAULT '4:5',
  post_type TEXT DEFAULT 'moment',
  view_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX posts_user_idx ON posts(user_id);
CREATE INDEX posts_visibility_idx ON posts(visibility);
CREATE INDEX posts_community_idx ON posts(community_id);
CREATE INDEX posts_deleted_idx ON posts(deleted_at);
CREATE INDEX posts_created_idx ON posts(created_at DESC);

-- ========================================
-- COMMENTS TABLE
-- ========================================

CREATE TABLE comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX comments_post_idx ON comments(post_id);
CREATE INDEX comments_user_idx ON comments(user_id);
CREATE INDEX comments_deleted_idx ON comments(deleted_at);

-- ========================================
-- REACTIONS TABLE
-- ========================================

CREATE TABLE reactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(post_id, user_id, emoji)
);

CREATE INDEX reactions_post_idx ON reactions(post_id);
CREATE INDEX reactions_user_idx ON reactions(user_id);
CREATE INDEX reactions_emoji_idx ON reactions(emoji);

-- ========================================
-- PINGS TABLE
-- ========================================

CREATE TABLE pings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
  receiver_id UUID REFERENCES users(id) ON DELETE CASCADE,
  group_id UUID REFERENCES communities(id) ON DELETE SET NULL,
  prompt TEXT NOT NULL,
  status TEXT DEFAULT 'pending',
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX pings_receiver_idx ON pings(receiver_id);
CREATE INDEX pings_sender_idx ON pings(sender_id);
CREATE INDEX pings_status_idx ON pings(status);

-- ========================================
-- PING REPLIES TABLE
-- ========================================

CREATE TABLE ping_replies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ping_id UUID REFERENCES pings(id) ON DELETE CASCADE,
  replier_id UUID REFERENCES users(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL,
  viewed BOOLEAN DEFAULT FALSE,
  viewed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX ping_replies_ping_idx ON ping_replies(ping_id);
CREATE INDEX ping_replies_replier_idx ON ping_replies(replier_id);

-- ========================================
-- COLLAGES TABLE
-- ========================================

CREATE TABLE collages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title TEXT,
  photos TEXT[],
  layout TEXT DEFAULT 'grid',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX collages_user_idx ON collages(user_id);

-- ========================================
-- HIGHLIGHTS TABLE
-- ========================================

CREATE TABLE highlights (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  photos TEXT[] NOT NULL,
  icon_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX highlights_user_idx ON highlights(user_id);

-- ========================================
-- PROFILE VIEWS TABLE
-- ========================================

CREATE TABLE profile_views (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  viewer_id UUID REFERENCES users(id) ON DELETE CASCADE,
  viewed_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  is_anonymous BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX profile_views_viewer_idx ON profile_views(viewer_id);
CREATE INDEX profile_views_viewed_idx ON profile_views(viewed_user_id);

-- ========================================
-- PINNED PEOPLE TABLE
-- ========================================

CREATE TABLE pinned_people (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  pinned_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, pinned_user_id)
);

CREATE INDEX pinned_people_user_idx ON pinned_people(user_id);

-- ========================================
-- MODERATORS TABLE
-- ========================================

CREATE TABLE moderators (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  role TEXT DEFAULT 'moderator',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX moderators_email_idx ON moderators(email);

-- ========================================
-- FEATURE FLAGS TABLE
-- ========================================

CREATE TABLE feature_flags (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  flag_name TEXT UNIQUE NOT NULL,
  is_enabled BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO feature_flags (flag_name, is_enabled) VALUES
  ('anonymous_posts', TRUE),
  ('pings', TRUE),
  ('collage', TRUE),
  ('highlights', TRUE),
  ('groups', TRUE),
  ('music', TRUE)
ON CONFLICT (flag_name) DO NOTHING;

-- ========================================
-- ROW LEVEL SECURITY (RLS)
-- ========================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE pings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ping_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE communities ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_communities ENABLE ROW LEVEL SECURITY;
ALTER TABLE collages ENABLE ROW LEVEL SECURITY;
ALTER TABLE highlights ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE pinned_people ENABLE ROW LEVEL SECURITY;
ALTER TABLE moderators ENABLE ROW LEVEL SECURITY;

-- ========================================
-- USERS RLS POLICIES
-- ========================================

CREATE POLICY "users_select" ON users FOR SELECT USING (true);
CREATE POLICY "users_update_own" ON users FOR UPDATE USING (auth.uid() = auth_id);

-- ========================================
-- POSTS RLS POLICIES
-- ========================================

CREATE POLICY "posts_select" ON posts FOR SELECT USING (deleted_at IS NULL);
CREATE POLICY "posts_insert" ON posts FOR INSERT WITH CHECK (auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id));
CREATE POLICY "posts_update_own" ON posts FOR UPDATE USING (auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id));
CREATE POLICY "posts_delete_own" ON posts FOR DELETE USING (auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id));
CREATE POLICY "posts_delete_moderator" ON posts FOR DELETE USING (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email())
);

-- ========================================
-- COMMENTS RLS POLICIES
-- ========================================

CREATE POLICY "comments_select" ON comments FOR SELECT USING (deleted_at IS NULL);
CREATE POLICY "comments_insert" ON comments FOR INSERT WITH CHECK (auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id));
CREATE POLICY "comments_delete_own" ON comments FOR DELETE USING (auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id));
CREATE POLICY "comments_delete_moderator" ON comments FOR DELETE USING (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email())
);

-- ========================================
-- REACTIONS RLS POLICIES
-- ========================================

CREATE POLICY "reactions_select" ON reactions FOR SELECT USING (true);
CREATE POLICY "reactions_insert" ON reactions FOR INSERT WITH CHECK (auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id));
CREATE POLICY "reactions_delete_own" ON reactions FOR DELETE USING (auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id));

-- ========================================
-- PINGS RLS POLICIES
-- ========================================

CREATE POLICY "pings_select" ON pings FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = sender_id) OR
  auth.uid() IN (SELECT auth_id FROM users WHERE id = receiver_id)
);
CREATE POLICY "pings_insert" ON pings FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = sender_id)
);

-- ========================================
-- PING REPLIES RLS POLICIES
-- ========================================

CREATE POLICY "ping_replies_select" ON ping_replies FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM pings
    WHERE id = ping_id AND (
      auth.uid() IN (SELECT auth_id FROM users WHERE id = sender_id) OR
      auth.uid() IN (SELECT auth_id FROM users WHERE id = receiver_id)
    )
  )
);
CREATE POLICY "ping_replies_insert" ON ping_replies FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM pings
    WHERE id = ping_id AND auth.uid() IN (SELECT auth_id FROM users WHERE id = receiver_id)
  )
);

-- ========================================
-- COMMUNITIES RLS POLICIES
-- ========================================

CREATE POLICY "communities_select" ON communities FOR SELECT USING (deleted_at IS NULL);
CREATE POLICY "communities_insert_moderator" ON communities FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email() AND role = 'admin')
);
CREATE POLICY "communities_update_moderator" ON communities FOR UPDATE USING (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email() AND role = 'admin')
);
CREATE POLICY "communities_delete_moderator" ON communities FOR DELETE USING (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email() AND role = 'admin')
);

-- ========================================
-- USER COMMUNITIES RLS POLICIES
-- ========================================

CREATE POLICY "user_communities_select" ON user_communities FOR SELECT USING (true);
CREATE POLICY "user_communities_insert" ON user_communities FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "user_communities_delete" ON user_communities FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ========================================
-- PROFILE VIEWS RLS POLICIES
-- ========================================

CREATE POLICY "profile_views_select" ON profile_views FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = viewed_user_id)
);
CREATE POLICY "profile_views_insert" ON profile_views FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = viewer_id)
);

-- ========================================
-- MODERATORS RLS POLICIES
-- ========================================

CREATE POLICY "moderators_select" ON moderators FOR SELECT USING (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email() AND role = 'admin')
);
CREATE POLICY "moderators_insert" ON moderators FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email() AND role = 'admin')
);
CREATE POLICY "moderators_delete" ON moderators FOR DELETE USING (
  EXISTS (SELECT 1 FROM moderators WHERE email = auth.email() AND role = 'admin')
);

-- ========================================
-- USERS RLS — SELF-PROVISIONING
-- ========================================
-- No signup flow currently inserts a `users` row for a new auth user, so
-- CurrentUserService (Flutter) lazily creates one on first use. That insert
-- runs as the signed-in user, so it needs an explicit CHECK — there was no
-- INSERT policy on `users` before this.
--
-- auth_id had no uniqueness constraint before this, which the lazy-create
-- path (and every "SELECT id FROM users WHERE auth_id = ..." lookup used
-- throughout the RLS policies above) depends on to stay a 1:1 mapping. If
-- this ALTER fails, it means duplicate `users` rows for the same auth_id
-- already exist and need manual cleanup first.

ALTER TABLE users ADD CONSTRAINT users_auth_id_unique UNIQUE (auth_id);

CREATE POLICY "users_insert_own" ON users FOR INSERT WITH CHECK (auth.uid() = auth_id);

-- ========================================
-- POSTS RLS — ANONYMOUS IDENTITY PROTECTION
-- ========================================
-- Original posts_select had no visibility check at all: any authenticated
-- (or anon) caller could read every row of `posts`, including `user_id` on
-- 'anonymous'-visibility rows — i.e. anonymous posts were fully deanonymized
-- to anyone who queried the table directly (app UI, REST API, anything).
--
-- Fix is two parts:
--  1. Tighten posts_select so an 'anonymous' row is only visible, at the
--     base-table level, to its own author. This is the actual security
--     boundary — it holds regardless of what any client/API call does.
--  2. Add posts_feed, a view that re-exposes anonymous content to everyone
--     with user_id nulled out for non-authors. Views in Postgres run with
--     the privileges of their OWNER (not the querying role) unless created
--     with security_invoker — since this view is created by the migration
--     role (which bypasses RLS), it can see the real rows and selectively
--     mask user_id, while still being subject to the same result-set logic
--     for every caller. This is the standard "security-definer view"
--     pattern for column-level masking, which plain RLS can't express
--     (RLS is row-level: it can hide a whole row, not one column of it).
--
-- Any future "Anonymous feed" read should query posts_feed, not posts
-- directly — non-authors get zero rows for anonymous content from the base
-- table now.

DROP POLICY IF EXISTS "posts_select" ON posts;
CREATE POLICY "posts_select" ON posts FOR SELECT USING (
  deleted_at IS NULL
  AND (
    visibility IS DISTINCT FROM 'anonymous'
    OR auth.uid() IN (SELECT auth_id FROM users WHERE id = posts.user_id)
  )
);

CREATE OR REPLACE VIEW posts_feed AS
SELECT
  p.id,
  CASE
    WHEN p.visibility = 'anonymous'
     AND NOT EXISTS (
       SELECT 1 FROM users u WHERE u.id = p.user_id AND u.auth_id = auth.uid()
     )
    THEN NULL
    ELSE p.user_id
  END AS user_id,
  p.content,
  p.image_url,
  p.visibility,
  p.community_id,
  p.music_id,
  p.music_url,
  p.music_title,
  p.music_artist,
  p.prompt,
  p.photo_fit,
  p.aspect_ratio,
  p.post_type,
  p.view_count,
  p.created_at,
  p.updated_at
FROM posts p
WHERE p.deleted_at IS NULL;

GRANT SELECT ON posts_feed TO authenticated, anon;

-- ========================================
-- BUCKETS TABLE
-- ========================================
-- v1 scope: community buckets only. bucket_type is carried now (instead of
-- being added later) so 'feed' and 'ping' types can be introduced without a
-- migration — nothing in this v1 reads or writes it beyond the default.
--
-- REQUIRES a manual step this file does not do: create a storage bucket
-- named `bucket-photos` in the Supabase dashboard (Storage → New bucket),
-- same as how the existing `posts`/`profiles`/`memories` buckets were made —
-- this schema file has never scripted storage bucket creation, only tables.

CREATE TABLE buckets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  creator_id UUID REFERENCES users(id) ON DELETE CASCADE,
  bucket_type TEXT NOT NULL DEFAULT 'community' CHECK (bucket_type IN ('community', 'feed', 'ping')),
  title TEXT NOT NULL,
  community_id UUID REFERENCES communities(id) ON DELETE SET NULL,
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX buckets_creator_idx ON buckets(creator_id);
CREATE INDEX buckets_community_idx ON buckets(community_id);
CREATE INDEX buckets_expires_idx ON buckets(expires_at);

-- ========================================
-- BUCKET CONTRIBUTIONS TABLE
-- ========================================

CREATE TABLE bucket_contributions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bucket_id UUID REFERENCES buckets(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX bucket_contributions_bucket_idx ON bucket_contributions(bucket_id);
CREATE INDEX bucket_contributions_user_idx ON bucket_contributions(user_id);

-- ========================================
-- BUCKETS / BUCKET CONTRIBUTIONS RLS
-- ========================================

ALTER TABLE buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE bucket_contributions ENABLE ROW LEVEL SECURITY;

-- Visible if still active, OR to its creator, OR to anyone who contributed —
-- the latter two so a bucket doesn't disappear from someone's profile the
-- moment it expires.
CREATE POLICY "buckets_select_active" ON buckets FOR SELECT USING (
  expires_at IS NULL OR expires_at > NOW()
);
CREATE POLICY "buckets_select_own_created" ON buckets FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = creator_id)
);
CREATE POLICY "buckets_select_own_contributed" ON buckets FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM bucket_contributions bc
    JOIN users u ON u.id = bc.user_id
    WHERE bc.bucket_id = buckets.id AND u.auth_id = auth.uid()
  )
);
CREATE POLICY "buckets_insert" ON buckets FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = creator_id)
);

-- Any authenticated user can see every contribution in a still-active
-- bucket (that's the shared grid); contributors can always see their own
-- past submissions even after the bucket expires.
CREATE POLICY "bucket_contributions_select_active" ON bucket_contributions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM buckets b
    WHERE b.id = bucket_id AND (b.expires_at IS NULL OR b.expires_at > NOW())
  )
);
CREATE POLICY "bucket_contributions_select_own" ON bucket_contributions FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "bucket_contributions_insert" ON bucket_contributions FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  AND EXISTS (
    SELECT 1 FROM buckets b
    WHERE b.id = bucket_id AND (b.expires_at IS NULL OR b.expires_at > NOW())
  )
);

-- ========================================
-- REACTIONS REDESIGN — emoji + face reactions coexist
-- ========================================
-- DESTRUCTIVE: drops and recreates `reactions`. The old shape
-- (post_id, user_id, emoji, UNIQUE(post_id,user_id,emoji)) can't represent
-- "one active emoji reaction AND one active face reaction per user per
-- post, independently" — that needs a `type` column with
-- UNIQUE(post_id,user_id,type) instead, which is a different uniqueness
-- shape, not an additive change. reaction_service.dart's original comment
-- said "nothing in the app writes to it yet," and nothing else in the
-- codebase reads from it — confirm that's still true against the live DB
-- before running this against a database with real data; if it isn't, this
-- needs a backfill migration instead of a drop.
--
-- REQUIRES a manual step this file does not do: create a storage bucket
-- named `reaction-photos` in the Supabase dashboard, same as
-- `bucket-photos` above.

DROP TABLE IF EXISTS reactions CASCADE;

CREATE TABLE reactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('emoji', 'face')),
  emoji TEXT NOT NULL,
  photo_url TEXT, -- null for 'emoji' reactions, set for 'face' reactions
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(post_id, user_id, type)
);

CREATE INDEX reactions_post_idx ON reactions(post_id);
CREATE INDEX reactions_user_idx ON reactions(user_id);
CREATE INDEX reactions_post_type_idx ON reactions(post_id, type);

ALTER TABLE reactions ENABLE ROW LEVEL SECURITY;

-- Readable iff the underlying post is readable — this EXISTS subquery is
-- itself subject to `posts`' own RLS, so it automatically inherits the
-- anonymous-post protection above with no duplication: a reaction on an
-- anonymous post you're not the author of is invisible not because of a
-- reactions-specific rule, but because the posts_select policy already
-- hides that row from you.
CREATE POLICY "reactions_select" ON reactions FOR SELECT USING (
  EXISTS (SELECT 1 FROM posts p WHERE p.id = post_id)
);
CREATE POLICY "reactions_insert_own" ON reactions FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
-- Needed for upsert (INSERT ... ON CONFLICT DO UPDATE) on the
-- UNIQUE(post_id, user_id, type) constraint to succeed on a second call.
CREATE POLICY "reactions_update_own" ON reactions FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "reactions_delete_own" ON reactions FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ========================================
-- GROUPS — user-created named groups with admin/member roles
-- ========================================
-- Distinct from `communities` (moderator-created, no per-member roles) and
-- from `buckets` (ephemeral, expiring, no membership list at all). A user
-- creates a group, becomes its admin, and can add/remove members; members
-- can post to the group's shared album and leave. See group_service.dart —
-- this replaces the old GroupService placeholder that repurposed
-- community-scoped posts (moved to community_photos_service.dart /
-- CommunityPhotosService, since that's a genuinely different, still-real
-- feature that shouldn't be silently dropped).
--
-- REQUIRES a manual step this file does not do: create storage buckets
-- named `group-icons` and `group-photos` in the Supabase dashboard, same as
-- `bucket-photos` above.

CREATE TABLE groups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  icon_url TEXT,
  banner_url TEXT,
  creator_id UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX groups_creator_idx ON groups(creator_id);
CREATE INDEX groups_deleted_idx ON groups(deleted_at);

-- ========================================
-- GROUP MEMBERS (join table + role)
-- ========================================

CREATE TABLE group_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(group_id, user_id)
);

CREATE INDEX group_members_group_idx ON group_members(group_id);
CREATE INDEX group_members_user_idx ON group_members(user_id);

-- ========================================
-- GROUP POSTS (photos posted to a group's shared album)
-- ========================================

CREATE TABLE group_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL,
  caption TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP
);

CREATE INDEX group_posts_group_idx ON group_posts(group_id);
CREATE INDEX group_posts_deleted_idx ON group_posts(deleted_at);

-- ========================================
-- GROUPS / GROUP MEMBERS / GROUP POSTS RLS
-- ========================================

ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_posts ENABLE ROW LEVEL SECURITY;

-- Visible only to its members (a group has no public feed) — creation is
-- open to any signed-in user (they become admin via the group_members
-- insert that immediately follows, done client-side in two calls since
-- Postgres can't do "insert into two tables atomically" without a
-- function; see GroupService.createGroup for why the insert order matters).
CREATE POLICY "groups_select" ON groups FOR SELECT USING (
  deleted_at IS NULL AND EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = groups.id AND u.auth_id = auth.uid()
  )
);
CREATE POLICY "groups_insert" ON groups FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = creator_id)
);
CREATE POLICY "groups_update_admin" ON groups FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = groups.id AND gm.role = 'admin' AND u.auth_id = auth.uid()
  )
);
CREATE POLICY "groups_delete_admin" ON groups FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = groups.id AND gm.role = 'admin' AND u.auth_id = auth.uid()
  )
);

-- Membership rows are visible to fellow members (so the member list/avatar
-- row can render). Inserting a member requires either being the group's
-- admin, or being the very first row for that group (the creator's own
-- self-as-admin insert, which by definition has no admin row yet to check
-- against). Removing a row is allowed for the group's admin, or for the
-- row's own user (leaving).
CREATE POLICY "group_members_select" ON group_members FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = group_members.group_id AND u.auth_id = auth.uid()
  )
);
CREATE POLICY "group_members_insert_admin" ON group_members FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = group_members.group_id AND gm.role = 'admin' AND u.auth_id = auth.uid()
  )
);
CREATE POLICY "group_members_insert_first_admin" ON group_members FOR INSERT WITH CHECK (
  role = 'admin'
  AND auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  AND NOT EXISTS (SELECT 1 FROM group_members gm WHERE gm.group_id = group_members.group_id)
);
CREATE POLICY "group_members_delete_self" ON group_members FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "group_members_delete_admin" ON group_members FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = group_members.group_id AND gm.role = 'admin' AND u.auth_id = auth.uid()
  )
);

-- Posts are visible to group members only. Any member can post; deleting is
-- allowed for the post's own author or the group's admin (matches "members
-- can delete their own posts, admin can delete any post").
CREATE POLICY "group_posts_select" ON group_posts FOR SELECT USING (
  deleted_at IS NULL AND EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = group_posts.group_id AND u.auth_id = auth.uid()
  )
);
CREATE POLICY "group_posts_insert" ON group_posts FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  AND EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = group_posts.group_id AND u.auth_id = auth.uid()
  )
);
CREATE POLICY "group_posts_delete_own" ON group_posts FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "group_posts_delete_admin" ON group_posts FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM group_members gm
    JOIN users u ON u.id = gm.user_id
    WHERE gm.group_id = group_posts.group_id AND gm.role = 'admin' AND u.auth_id = auth.uid()
  )
);

-- ========================================
-- NOTIFICATION SYSTEM
-- ========================================
-- Backend for: ping received/replied, pinned-vs-anonymous profile views,
-- pinned-vs-anonymous reactions/comments, per-community prompt rotation
-- (3h), per-community live-activity nudges (6h). See
-- supabase/functions/README.md for the Edge Functions this schema feeds and
-- the manual setup (GUCs, secrets, `supabase functions deploy`) required
-- before any of this actually sends a push.
--
-- Architecture: AFTER INSERT triggers on the source-of-truth tables
-- (pings, ping_replies, profile_views, reactions, comments) call
-- notify_webhook(), which POSTs a Database-Webhook-shaped payload to the
-- matching Edge Function via pg_net. Two pg_cron jobs hit the
-- prompt-rotation and live-activity-nudge functions directly on a
-- schedule. Every function that decides whether to reveal a name calls
-- is_pinned_by() below — that's the single enforcement point.

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ----------------------------------------
-- DEVICE TOKENS — push targets per user
-- ----------------------------------------

CREATE TABLE device_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, token)
);

CREATE INDEX device_tokens_user_idx ON device_tokens(user_id);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "device_tokens_select_own" ON device_tokens FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "device_tokens_insert_own" ON device_tokens FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "device_tokens_update_own" ON device_tokens FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "device_tokens_delete_own" ON device_tokens FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ----------------------------------------
-- ACTIVE SESSIONS — presence heartbeat
-- ----------------------------------------
-- Client upserts its own row (user_id, community_id it's currently viewing)
-- roughly every 30s while foregrounded. Feeds two things:
--  1. live_count for LIVE ACTIVITY NUDGE (count of rows per community with
--     a recent last_seen_at — "recent" = live-activity-nudge's own
--     freshness window, not hardcoded here).
--  2. the live-vs-delivered-after-the-fact distinction on PROFILE VIEW —
--     PINNED PERSON (was the viewer's own session recent at view time?).
-- Nothing in the Flutter client writes to this table yet — this is schema
-- only, ready for a presence heartbeat to be wired in.

CREATE TABLE active_sessions (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  community_id UUID REFERENCES communities(id) ON DELETE SET NULL,
  last_seen_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX active_sessions_community_idx ON active_sessions(community_id, last_seen_at);

ALTER TABLE active_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "active_sessions_select_own" ON active_sessions FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "active_sessions_upsert_own" ON active_sessions FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "active_sessions_update_own" ON active_sessions FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ----------------------------------------
-- PER-COMMUNITY NOTIFICATION OPT-IN
-- ----------------------------------------
-- Governs PROMPT ROTATION and LIVE ACTIVITY NUDGE fan-out — a member with
-- notifications_enabled = false for a community is skipped by both.

ALTER TABLE user_communities ADD COLUMN notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- ----------------------------------------
-- PROMPTS — bank + per-community rotation state
-- ----------------------------------------
-- A small starter bank (mirrors the tone of lib/services/prompt_service.dart's
-- client-side list, which is unrelated and can stay as-is). Insert more
-- rows any time — prompt-rotation reads the table live, no redeploy needed.

CREATE TABLE prompts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  text TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO prompts (text) VALUES
  ('Post your view right now 👀'),
  ('Your current vibe ✨'),
  ('Show your workspace 💻'),
  ('Something blue 💙'),
  ('Your campus right now 🏫'),
  ('Unfiltered thoughts rn'),
  ('Hot take on campus life 🔥'),
  ('Your chill spot 🎧'),
  ('The sky right now ☁️'),
  ('Confession ⛪'),
  ('Rate your day 1–10'),
  ('Your go-to comfort food 🍲'),
  ('One word for your mood'),
  ('Show what relaxes you 🛁'),
  ('Your setup right now 🖥️');

-- One row per community: which prompt is live, when it rotated, and a
-- short ring buffer of recently-used prompt ids so rotation doesn't repeat
-- the same prompt back-to-back (mirrors PromptService's _seen set, but
-- persisted per-community instead of per-client-session).
CREATE TABLE community_prompt_state (
  community_id UUID PRIMARY KEY REFERENCES communities(id) ON DELETE CASCADE,
  current_prompt_id UUID REFERENCES prompts(id),
  rotated_at TIMESTAMP,
  recent_prompt_ids UUID[] NOT NULL DEFAULT '{}'
);

-- ----------------------------------------
-- NOTIFICATION EVENTS — idempotency + audit log
-- ----------------------------------------
-- Every Edge Function inserts a row here BEFORE sending. dedupe_key is the
-- source row's id (or, for the two cron jobs, `<community_id>:<hour
-- bucket>`) — a unique-index conflict means "already sent," so the
-- function skips the push. This is what makes pg_net's at-least-once
-- trigger delivery safe to retry, and what the client-side NotifState
-- throttle (_kMaxPerHour, per-key cooldowns) had no server equivalent for
-- until now. No client ever reads this table — service-role only.

CREATE TABLE notification_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipient_id UUID REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'ping_received', 'ping_replied', 'profile_view',
    'reaction', 'comment', 'prompt_rotation', 'live_nudge'
  )),
  tier TEXT NOT NULL CHECK (tier IN ('minor', 'standard', 'major')),
  dedupe_key TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE UNIQUE INDEX notification_events_dedupe_idx
  ON notification_events(event_type, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX notification_events_recipient_idx
  ON notification_events(recipient_id, created_at DESC);

ALTER TABLE notification_events ENABLE ROW LEVEL SECURITY;
-- No policies — RLS enabled with zero grants means default-deny for
-- anon/authenticated; only the service-role key (used by Edge Functions)
-- can read or write this table.

-- ----------------------------------------
-- is_pinned_by() — THE identity-reveal enforcement point
-- ----------------------------------------
-- Single source of truth for "does p_recipient_id have p_actor_id pinned,"
-- i.e. the only question that decides whether a name gets revealed
-- (PROFILE VIEW — PINNED PERSON) or masked (PROFILE VIEW — NON-PINNED,
-- REACTION/COMMENT). Every notify-* function calls this instead of
-- querying `pinned_people` inline, so the privacy rule lives in one place.
--
-- Execute is revoked from anon/authenticated on purpose: if a client could
-- call this directly, user A could probe "does user B have ME pinned?" for
-- arbitrary B — leaking pinning relationships that are otherwise private
-- (pinned_people has no SELECT policy for other users' rows either).
-- Only the service-role key (Edge Functions) can call it.

CREATE OR REPLACE FUNCTION is_pinned_by(p_recipient_id UUID, p_actor_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM pinned_people
    WHERE user_id = p_recipient_id AND pinned_user_id = p_actor_id
  );
$$;

REVOKE EXECUTE ON FUNCTION is_pinned_by(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_pinned_by(UUID, UUID) TO service_role;

-- ----------------------------------------
-- toggle_pin_post_author() / is_post_author_pinned() — client-facing pin
-- ----------------------------------------
-- Anonymous posts never expose the author's real user_id to the client (see
-- PingContext — ping is resolved the same way), so the PinPersonButton on
-- PhotoPostCard/TextPostCard (post_card_shared.dart) can't write to
-- pinned_people directly — that table has RLS enabled with NO client
-- policies, by design. These two SECURITY DEFINER RPCs, keyed by post_id,
-- are the only way in: they resolve auth.uid() -> users.id and the post's
-- author internally, same trust boundary as is_pinned_by() above.
--
-- NOTE: this project's public schema has a default ACL (pg_default_acl)
-- that auto-grants EXECUTE on every new function to anon at CREATE time.
-- REVOKE ... FROM PUBLIC does NOT undo that (it only revokes PUBLIC's
-- implicit grant, not a direct per-role grant) — anon must be revoked
-- explicitly, or it silently keeps access. Applies to any future function
-- added to this schema, not just these two.

CREATE OR REPLACE FUNCTION toggle_pin_post_author(p_post_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me UUID := (SELECT id FROM users WHERE auth_id = auth.uid());
  v_author UUID := (SELECT user_id FROM posts WHERE id = p_post_id);
BEGIN
  IF v_me IS NULL OR v_author IS NULL OR v_author = v_me THEN
    RAISE EXCEPTION 'invalid pin target';
  END IF;

  DELETE FROM pinned_people WHERE user_id = v_me AND pinned_user_id = v_author;
  IF FOUND THEN
    RETURN false;
  END IF;

  INSERT INTO pinned_people (user_id, pinned_user_id) VALUES (v_me, v_author);
  RETURN true;
END;
$$;
REVOKE EXECUTE ON FUNCTION toggle_pin_post_author(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION toggle_pin_post_author(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION toggle_pin_post_author(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION is_post_author_pinned(p_post_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM pinned_people
    WHERE user_id = (SELECT id FROM users WHERE auth_id = auth.uid())
      AND pinned_user_id = (SELECT user_id FROM posts WHERE id = p_post_id)
  );
$$;
REVOKE EXECUTE ON FUNCTION is_post_author_pinned(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION is_post_author_pinned(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION is_post_author_pinned(UUID) TO authenticated;

-- ----------------------------------------
-- list_pinned_people() / unpin_person() — Settings screen's Pinned People
-- section (settings_screen.dart). Same reason as the two RPCs above:
-- pinned_people has RLS enabled with NO client policies, so a plain
-- `.from('pinned_people').select()`/`.delete()` returns nothing / is
-- denied. These resolve auth.uid() -> users.id internally, same trust
-- boundary as toggle_pin_post_author()/is_pinned_by() above.
CREATE OR REPLACE FUNCTION list_pinned_people()
RETURNS TABLE (pinned_user_id UUID, name TEXT, profile_photo_url TEXT, pinned_at TIMESTAMP)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.id, u.name, u.profile_photo_url, p.created_at
  FROM pinned_people p
  JOIN users u ON u.id = p.pinned_user_id
  WHERE p.user_id = (SELECT id FROM users WHERE auth_id = auth.uid())
  ORDER BY p.created_at DESC;
$$;
REVOKE EXECUTE ON FUNCTION list_pinned_people() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION list_pinned_people() FROM anon;
GRANT EXECUTE ON FUNCTION list_pinned_people() TO authenticated;

CREATE OR REPLACE FUNCTION unpin_person(p_pinned_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me UUID := (SELECT id FROM users WHERE auth_id = auth.uid());
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'no signed-in user';
  END IF;

  DELETE FROM pinned_people WHERE user_id = v_me AND pinned_user_id = p_pinned_user_id;
  RETURN FOUND;
END;
$$;
REVOKE EXECUTE ON FUNCTION unpin_person(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION unpin_person(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION unpin_person(UUID) TO authenticated;

-- ----------------------------------------
-- anon EXECUTE audit (post-pin-feature sweep)
-- ----------------------------------------
-- Every pre-existing public function in this project had an implicit
-- EXECUTE grant to `anon` via this database's default ACL (pg_default_acl
-- grants EXECUTE on new functions to anon/authenticated/service_role at
-- CREATE time) — REVOKE ... FROM PUBLIC never stripped it, since that only
-- revokes the PUBLIC pseudo-role's grant, not a role's direct one. Audited
-- and fixed here:
--
--   - owns_anon_post/is_blocked/is_in_circle/is_member/get_thread_handle
--     were RPC-callable (real return types, not `trigger`) with NO auth
--     check on their own — anon could probe arbitrary UUID pairs.
--     owns_anon_post in particular is a direct anon-post deanonymization
--     oracle. All five now revoke anon explicitly, authenticated retained.
--   - The 8 RETURNS trigger functions (apply_score, enforce_anon_limit,
--     enforce_card_limit, enforce_ping_limit, handle_new_user,
--     set_anon_expiry, set_pin_expiry, set_ping_replied) were never
--     actually callable via RPC regardless of grant — Postgres refuses to
--     invoke a trigger-return function outside trigger context — but anon
--     + authenticated EXECUTE revoked from all of them anyway as hygiene;
--     confirmed this cannot break trigger firing (that doesn't require the
--     invoking role to hold EXECUTE on the trigger function itself).
--   - enforce_pin_max() was dropped entirely: dead code referencing a
--     nonexistent new.pinner_id column (pinned_people's real columns are
--     user_id/pinned_user_id), not attached as a trigger to any table.
--   - gen_handle()/gen_user_code() left with anon EXECUTE intentionally —
--     pure generators, no table access, no SECURITY DEFINER, no user data.
--
-- Any NEW function added to this schema needs the same explicit
-- `REVOKE ... FROM anon` (not just `FROM PUBLIC`) or it inherits anon
-- access silently via the same default ACL.

REVOKE EXECUTE ON FUNCTION owns_anon_post(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION owns_anon_post(UUID, UUID) FROM anon;

REVOKE EXECUTE ON FUNCTION is_blocked(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION is_blocked(UUID, UUID) FROM anon;

REVOKE EXECUTE ON FUNCTION is_in_circle(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION is_in_circle(UUID, UUID) FROM anon;

REVOKE EXECUTE ON FUNCTION is_member(UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION is_member(UUID, UUID) FROM anon;

REVOKE EXECUTE ON FUNCTION get_thread_handle(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_thread_handle(UUID) FROM anon;

REVOKE EXECUTE ON FUNCTION apply_score() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION enforce_anon_limit() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION enforce_card_limit() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION enforce_ping_limit() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION set_anon_expiry() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION set_pin_expiry() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION set_ping_replied() FROM PUBLIC, anon, authenticated;

-- enforce_pin_max() removed — see audit note above. Was:
--   CREATE FUNCTION enforce_pin_max() RETURNS trigger ... references
--   new.pinner_id, which was never a real column on pinned_people.

-- ----------------------------------------
-- Trigger → Edge Function wiring
-- ----------------------------------------
-- REQUIRES a manual step this file cannot do (it would mean committing a
-- secret): set these two GUCs once per database, as the postgres role —
--
--   ALTER DATABASE postgres SET app.settings.edge_function_base_url =
--     'https://uehqazxnodndutjvxemq.supabase.co/functions/v1';
--   ALTER DATABASE postgres SET app.settings.service_role_key =
--     '<service_role_key from Project Settings → API>';
--
-- then reconnect (GUCs set this way apply to new sessions). Until both are
-- set, notify_webhook() below silently POSTs to a blank URL and pg_net
-- logs a failed request — nothing crashes, nothing sends.

CREATE OR REPLACE FUNCTION notify_webhook() RETURNS TRIGGER AS $$
DECLARE
  base_url TEXT := current_setting('app.settings.edge_function_base_url', true);
  service_key TEXT := current_setting('app.settings.service_role_key', true);
BEGIN
  PERFORM net.http_post(
    url := base_url || '/' || TG_ARGV[0],
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW)
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER trg_notify_ping
  AFTER INSERT ON pings FOR EACH ROW
  EXECUTE FUNCTION notify_webhook('notify-ping');

CREATE TRIGGER trg_notify_ping_reply
  AFTER INSERT ON ping_replies FOR EACH ROW
  EXECUTE FUNCTION notify_webhook('notify-ping-reply');

CREATE TRIGGER trg_notify_profile_view
  AFTER INSERT ON profile_views FOR EACH ROW
  EXECUTE FUNCTION notify_webhook('notify-profile-view');

CREATE TRIGGER trg_notify_reaction
  AFTER INSERT ON reactions FOR EACH ROW
  EXECUTE FUNCTION notify_webhook('notify-engagement');

CREATE TRIGGER trg_notify_comment
  AFTER INSERT ON comments FOR EACH ROW
  EXECUTE FUNCTION notify_webhook('notify-engagement');

-- RealMoji reactions (user_realmojis / post_realmoji_reactions, both
-- already live — see the Flutter client's realmoji_service.dart) route
-- through the SAME notify-engagement function as `reactions`/`comments`
-- above; it discriminates on TG_TABLE_NAME via payload.table. No new Edge
-- Function needed, just this trigger.
CREATE TRIGGER trg_notify_realmoji_reaction
  AFTER INSERT ON post_realmoji_reactions FOR EACH ROW
  EXECUTE FUNCTION notify_webhook('notify-engagement');

-- ----------------------------------------
-- RealMoji RLS (post_realmoji_reactions / user_realmojis)
-- ----------------------------------------
-- Both tables are created directly in the live Supabase project, not by
-- this file (no CREATE TABLE for either exists here) — this block is
-- documentation-only, applied via the SQL Editor, kept here so this file
-- doesn't drift from the live DB the way it had for these two tables
-- until this fix (security review, 2026-08-17: no RLS existed on either
-- table at all — a client with any valid session, or the anon key
-- depending on grants, could insert post_realmoji_reactions rows under an
-- arbitrary user_id, or read raw rows/joins to deanonymize who reacted to
-- an anonymous post, defeating the Anon feed's entire "no identity, ever"
-- design). Mirrors the `reactions` table's own policy pattern above
-- (auth.uid() via users.auth_id, posts-visibility inheritance for SELECT).
ALTER TABLE post_realmoji_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_realmojis ENABLE ROW LEVEL SECURITY;

-- Readable iff the underlying post is readable — inherits posts_select's
-- own anonymous-post protection with no duplication, same trick
-- reactions_select uses.
CREATE POLICY "post_realmoji_reactions_select" ON post_realmoji_reactions
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM posts p WHERE p.id = post_id)
  );

CREATE POLICY "post_realmoji_reactions_insert_own" ON post_realmoji_reactions
  FOR INSERT WITH CHECK (
    auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  );

CREATE POLICY "post_realmoji_reactions_update_own" ON post_realmoji_reactions
  FOR UPDATE USING (
    auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  );

CREATE POLICY "post_realmoji_reactions_delete_own" ON post_realmoji_reactions
  FOR DELETE USING (
    auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  );

-- Own rows always readable (RealmojiService.savedSelfies/savedSelfieUrl).
-- Other users' rows readable ONLY when feed_scope='everyone' — required
-- for the Everyone-feed reactor stack (RealmojiService.fetchReactors,
-- which reads OTHER users' saved selfies to render their faces).
-- Anonymous-scoped rows stay owner-only — THIS is the actual identity
-- boundary: a client can no longer join user_realmojis to
-- post_realmoji_reactions to deanonymize an anon-post reactor.
CREATE POLICY "user_realmojis_select" ON user_realmojis
  FOR SELECT USING (
    auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
    OR feed_scope = 'everyone'
  );

CREATE POLICY "user_realmojis_insert_own" ON user_realmojis
  FOR INSERT WITH CHECK (
    auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  );

CREATE POLICY "user_realmojis_update_own" ON user_realmojis
  FOR UPDATE USING (
    auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  );

CREATE POLICY "user_realmojis_delete_own" ON user_realmojis
  FOR DELETE USING (
    auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
  );

-- ----------------------------------------
-- RealMoji storage policy (reaction-photos/realmoji/ prefix)
-- ----------------------------------------
-- Security review, 2026-08-17 (Vuln 2): no storage.objects policy existed
-- anywhere for any bucket in this app — not just this one — so this is
-- the first such policy on record here, not a mirror of an existing
-- pattern. Path convention: realmoji/$userId/$feedScope/$emojiType.jpg
-- (StorageService.uploadRealmojiSelfie, lib/services/storage_service.dart).
-- storage.foldername(name) splits that into ['realmoji', '$userId',
-- '$feedScope'] — segment [2] is the userId; writes are scoped so it must
-- match the caller's own users.id, closing the IDOR where any
-- authenticated client could overwrite another user's saved RealMoji
-- selfie by uploading to their userId's path.
--
-- Reads are intentionally NOT restricted: this bucket is public
-- (StorageService uses getPublicUrl), so GETs already bypass RLS by
-- bucket design — same tradeoff every other asset bucket in this app
-- already makes, unrelated to this fix.
--
-- storage.objects RLS is bucket-wide at the table level, not scoped per
-- bucket — this policy assumes RLS is already enabled on storage.objects
-- (Supabase's default for every project) rather than toggling it here,
-- since forcing it on blind could start enforcing (nonexistent) policies
-- against every other bucket (posts/profiles/personas/bucket-photos/
-- group-icons/group-photos) and lock out uploads that currently work.
CREATE POLICY "realmoji_selfie_insert_own" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'reaction-photos'
    AND (storage.foldername(name))[1] = 'realmoji'
    AND (storage.foldername(name))[2] IN (
      SELECT id::text FROM users WHERE auth_id = auth.uid()
    )
  );

CREATE POLICY "realmoji_selfie_update_own" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'reaction-photos'
    AND (storage.foldername(name))[1] = 'realmoji'
    AND (storage.foldername(name))[2] IN (
      SELECT id::text FROM users WHERE auth_id = auth.uid()
    )
  );

-- ----------------------------------------
-- Scheduled jobs — prompt rotation (3h) + live-activity nudge (6h)
-- ----------------------------------------
-- pg_cron calling an Edge Function via pg_net, rather than Supabase's
-- dashboard-configured Scheduled Functions — this repo has no
-- supabase/config.toml / linked CLI project to declare that in, and this
-- way the whole schedule is version-controlled SQL like everything else
-- here. Same base_url/service_role_key GUCs as notify_webhook() above.

SELECT cron.schedule(
  'prompt-rotation-job',
  '0 */3 * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.edge_function_base_url', true) || '/prompt-rotation',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := '{}'::jsonb
  );
  $$
);

SELECT cron.schedule(
  'live-activity-nudge-job',
  '0 */6 * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.edge_function_base_url', true) || '/live-activity-nudge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := '{}'::jsonb
  );
  $$
);

-- ========================================
-- REACTION PRESETS — personal reaction library ("preset reactions")
-- ========================================
-- Users record a face+emoji (or, on the Anonymous feed, emoji-only)
-- reaction ONCE and reuse it instantly on any post afterward, instead of
-- capturing a fresh selfie every time. Presets are a faster SOURCE for a
-- reaction, not a separate storage path: applying one still just writes a
-- row to the existing `reactions` table (type='face' with the preset's
-- photo_url + emoji, or type='emoji' with just emoji), same as today.
--
-- category is split ('anonymous' | 'everyone') because the two feeds have
-- fundamentally different rules: Anonymous is emoji-only (a real face
-- breaks anonymity there), Everyone is face+emoji. The CHECK constraint
-- below enforces that at the DB layer too, not just in the client UI — an
-- 'anonymous' row can never carry a photo_url.
--
-- Preset selfies reuse the existing `reaction-photos` storage bucket (see
-- the REACTIONS REDESIGN section above) under a `presets/$userId/` prefix,
-- separate from the per-post `$postId/$userId.jpg` objects live reactions
-- use — no manual bucket-creation step needed here, it already exists.

CREATE TABLE reaction_presets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('anonymous', 'everyone')),
  emoji TEXT NOT NULL,
  photo_url TEXT, -- null for 'anonymous' presets, set for 'everyone' presets
  created_at TIMESTAMP DEFAULT NOW(),
  CONSTRAINT reaction_presets_anonymous_has_no_photo CHECK (
    category <> 'anonymous' OR photo_url IS NULL
  )
);

CREATE INDEX reaction_presets_user_category_idx
  ON reaction_presets(user_id, category, created_at DESC);

ALTER TABLE reaction_presets ENABLE ROW LEVEL SECURITY;

-- A user's reaction library is theirs alone — unlike `reactions` (readable
-- by anyone who can read the post), nobody else ever needs to read,
-- write, or enumerate another user's saved presets.
CREATE POLICY "reaction_presets_select_own" ON reaction_presets FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "reaction_presets_insert_own" ON reaction_presets FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "reaction_presets_update_own" ON reaction_presets FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "reaction_presets_delete_own" ON reaction_presets FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ========================================
-- POST SUBSCRIPTIONS — per-post "bell" (mute/subscribe to a post's activity)
-- ========================================
-- Backs the bell icon in the post card's new top-left corner control
-- (post_subscriptions_service.dart / PostBellButton, screens/feed/widgets/
-- post_card_shared.dart). Presence of a row = subscribed (filled bell);
-- absence = not subscribed (outline bell) — this is an opt-IN, not an
-- opt-out/mute list, so the default (no row) is "not subscribed," matching
-- the bell-icon convention used elsewhere (YouTube, Twitter/X): tapping the
-- bell turns notifications ON for that specific post's future reactions/
-- comments, it isn't on by default just from viewing or posting.
--
-- Nothing yet fans these out as actual pushes — that would mean extending
-- the notify-engagement Edge Function (supabase/functions/notify-engagement)
-- to also notify every subscriber, not just the post's own author. This
-- table is the data model for that future step; it isn't wired to the
-- notification pipeline yet.

CREATE TABLE post_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

CREATE INDEX post_subscriptions_post_idx ON post_subscriptions(post_id);
CREATE INDEX post_subscriptions_user_idx ON post_subscriptions(user_id);

ALTER TABLE post_subscriptions ENABLE ROW LEVEL SECURITY;

-- A user's own subscriptions are theirs alone to read/write — same
-- reasoning as reaction_presets: nobody else needs to see who subscribed
-- to what (that's not a public "follower" list, just a personal
-- notification toggle).
CREATE POLICY "post_subscriptions_select_own" ON post_subscriptions FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "post_subscriptions_insert_own" ON post_subscriptions FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
CREATE POLICY "post_subscriptions_delete_own" ON post_subscriptions FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ========================================
-- ONBOARDING FLAG
-- ========================================
-- Backs the AuthGate's post-sign-in routing (lib/features/auth/auth_gate.dart):
-- false (the default, set on every lazily-created row — see
-- CurrentUserService.resolveId) routes a freshly-signed-in user to
-- OnboardingScreen; true routes straight to the home feed. Flipped once by
-- OnboardingScreen on completion (CurrentUserService.markOnboardingComplete),
-- never automatically.

ALTER TABLE users ADD COLUMN onboarding_completed BOOLEAN NOT NULL DEFAULT false;

-- ========================================
-- DONE
-- ========================================
