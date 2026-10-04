-- ============================================================================
-- Member-authored community feed: community_posts + community_post_documents,
-- a community-docs Storage bucket, and a community_post_id column on reports.
--
-- CONFIRMED against the live database on 2026-09-04 via the Supabase MCP
-- (schema.sql is stale — do not trust it):
--   * `communities` (7 cols, 2 live rows) and `community_members`
--     (community_id, user_id, joined_at) both exist. community_members has
--     NO CREATE TABLE anywhere in version control; its live policies are
--     mem_read USING(true), mem_join WITH CHECK (user_id = auth.uid()),
--     mem_leave FOR DELETE USING (user_id = auth.uid()).
--   * `reports` exists live with (id, post_id, comment_id, ping_id,
--     reporter_id, reason, created_at) and exactly ONE policy — rep_ins,
--     INSERT TO authenticated WITH CHECK (reporter_id = auth.uid()). It has
--     no CREATE TABLE in version control either. No SELECT policy: reporters
--     must not be able to read the moderation queue. That stays true here.
--   * `is_blocked_user(viewer_auth uuid, target_user_id uuid)` exists
--     (20260903000000) and is reused below rather than duplicated.
--   * No community_posts / community_post_documents / community-docs bucket.
--
-- KEYSPACE — the one thing to get right in this file. This app has two
-- parallel identity spaces and they meet in this table:
--   * community_members.user_id  IS a raw auth.uid()  (profiles keyspace)
--   * community_posts.user_id    IS a users.id        (content keyspace)
-- That is deliberate: authoring tables (posts, group_posts) all FK to
-- users.id, and is_blocked_user() expects a users.id as its target. So
-- is_community_member() below takes an AUTH UID, while the post's author
-- column stores a users.id. Writing a users.id into community_members (or
-- vice versa) is the exact bug block_service.dart:11-22 warns about — it
-- fails silently as an empty list, never as an error.
--
-- Every statement is idempotent, safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. is_community_member — mirrors is_group_member's role, but keyed on the
-- auth uid because that is what community_members stores. SECURITY DEFINER
-- so RLS on community_members can't recurse into the policies that call it.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_community_member(p_community UUID, p_auth UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM community_members
     WHERE community_id = p_community AND user_id = p_auth
  );
$$;

REVOKE ALL ON FUNCTION public.is_community_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_community_member(UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. community_posts — a NEW table rather than a reuse of `posts`.
--
-- `posts` already has community_id and visibility='community', so reuse was
-- the obvious first idea. It was rejected because posts carries a large
-- amount of unrelated baggage that would silently apply to community posts:
-- music_id/music_url/music_title/music_artist, post_type/moment_color,
-- photo_fit, aspect_ratio, prompt, the posts_feed masking view, and
-- FeedService.anonVisibleWindow's 24h anon cutoff. Most decisively: the
-- streak trigger (20260904010000) fires on anonymous `posts` and must NOT
-- fire on community-feed posts, so one table would mean a WHEN clause
-- separating two different kinds of anonymity inside one row shape.
--
-- Anonymity here is a real boolean, unlike posts (where it is
-- visibility='anonymous' plus a masking view). Nothing else about a
-- community post changes with anonymity, so a column is honest and cheap.
-- NOTE the masking is currently CLIENT-side — see the follow-up comment on
-- the block filter below.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.community_posts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES public.users(id)       ON DELETE CASCADE,
  body         TEXT,
  photo_urls   TEXT[],
  is_anonymous BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at   TIMESTAMPTZ,
  CONSTRAINT community_posts_body_len  CHECK (body IS NULL OR char_length(body) <= 1000),
  CONSTRAINT community_posts_photo_cap CHECK (photo_urls IS NULL OR array_length(photo_urls, 1) <= 4),
  CONSTRAINT community_posts_not_empty CHECK (body IS NOT NULL OR photo_urls IS NOT NULL)
);

COMMENT ON COLUMN public.community_posts.user_id IS
  'users.id (NOT auth.uid()) — matches posts/group_posts so is_blocked_user() works unchanged.';
COMMENT ON COLUMN public.community_posts.photo_urls IS
  'Ordered; index 0 is the cover. Capped at 4 by community_posts_photo_cap.';

CREATE INDEX IF NOT EXISTS community_posts_community_created_idx
  ON public.community_posts (community_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS community_posts_user_idx
  ON public.community_posts (user_id);

ALTER TABLE public.community_posts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_posts' AND policyname = 'community_posts_select') THEN
    CREATE POLICY "community_posts_select" ON public.community_posts FOR SELECT USING (
      deleted_at IS NULL AND is_community_member(community_id, auth.uid())
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_posts' AND policyname = 'community_posts_insert') THEN
    CREATE POLICY "community_posts_insert" ON public.community_posts FOR INSERT WITH CHECK (
      is_community_member(community_id, auth.uid())
      AND user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_posts' AND policyname = 'community_posts_update_own') THEN
    CREATE POLICY "community_posts_update_own" ON public.community_posts FOR UPDATE
      USING (user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()))
      WITH CHECK (user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()));
  END IF;

  -- Moderator soft-delete. Mirrors posts_update_moderator from
  -- 2026-08-22_three_tier_roles.sql; can_moderate_community() already exists.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_posts' AND policyname = 'community_posts_update_moderator') THEN
    CREATE POLICY "community_posts_update_moderator" ON public.community_posts FOR UPDATE
      USING (can_moderate_community(community_id))
      WITH CHECK (can_moderate_community(community_id));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_posts' AND policyname = 'community_posts_delete_own') THEN
    CREATE POLICY "community_posts_delete_own" ON public.community_posts FOR DELETE USING (
      user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
    );
  END IF;
END $$;

-- Block filter, RESTRICTIVE — permissive policies are OR'd, so a plain
-- policy could not remove a row another policy already granted. Same shape
-- as posts_block_filter (20260903000000:114-152).
--
-- The `is_anonymous OR` carve-out is deliberate, not an oversight: if
-- blocking made anonymous posts disappear instantly, the blocker could
-- diff before/after and learn which anonymous posts a given person wrote.
-- That is exactly the leak 20260829020000 was written to close.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_posts' AND policyname = 'community_posts_block_filter') THEN
    CREATE POLICY "community_posts_block_filter" ON public.community_posts
      AS RESTRICTIVE FOR SELECT USING (
        is_anonymous OR NOT public.is_blocked_user(auth.uid(), user_id)
      );
  END IF;
END $$;

-- FOLLOW-UP (not fixed here): community_posts_select returns the author's
-- users.id even when is_anonymous, and the Dart layer masks it. A determined
-- client reading the raw row can therefore de-anonymise. The real fix is a
-- posts_feed-style SECURITY DEFINER view that nulls user_id for non-authors.
-- Tracked deliberately rather than half-built: doing it properly means
-- moving every read path onto the view at once.

-- ---------------------------------------------------------------------------
-- 3. community_post_documents — PDF attachments. Mirrors the shape of
-- community_feed_documents (the dashboard-side table, file_url + file_name)
-- and adds file_size for the UI chip and position for ordering.
--
-- The 2-PDF-per-post cap is enforced client-side only. A trigger would be
-- the airtight version; deferred because the cap is a product limit, not a
-- data-integrity invariant, and a bad value costs nothing.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.community_post_documents (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_post_id UUID NOT NULL REFERENCES public.community_posts(id) ON DELETE CASCADE,
  file_url   TEXT   NOT NULL,
  file_name  TEXT   NOT NULL,
  file_size  BIGINT,
  position   INT    NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS community_post_documents_post_idx
  ON public.community_post_documents (community_post_id, position);

ALTER TABLE public.community_post_documents ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Visible exactly when the parent post is visible. The EXISTS re-enters
  -- community_posts, so the parent's own SELECT policies (membership +
  -- block filter) apply — no rule is duplicated here.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_post_documents' AND policyname = 'community_post_documents_select') THEN
    CREATE POLICY "community_post_documents_select" ON public.community_post_documents FOR SELECT USING (
      EXISTS (SELECT 1 FROM public.community_posts p WHERE p.id = community_post_id)
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_post_documents' AND policyname = 'community_post_documents_insert') THEN
    CREATE POLICY "community_post_documents_insert" ON public.community_post_documents FOR INSERT WITH CHECK (
      EXISTS (
        SELECT 1 FROM public.community_posts p
         WHERE p.id = community_post_id
           AND p.user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
      )
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'community_post_documents' AND policyname = 'community_post_documents_delete') THEN
    CREATE POLICY "community_post_documents_delete" ON public.community_post_documents FOR DELETE USING (
      EXISTS (
        SELECT 1 FROM public.community_posts p
         WHERE p.id = community_post_id
           AND (p.user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
                OR can_moderate_community(p.community_id))
      )
    );
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. reports.community_post_id — extend the existing table rather than
-- creating a parallel community_post_reports. reports already has the
-- post_id / comment_id / ping_id shape; this is a fourth nullable target.
--
-- The partial unique index is load-bearing for the UI: reports has no
-- SELECT policy (correctly — reporters must not read the queue), so the
-- client cannot check "did I already report this?". It instead inserts and
-- reads 23505 as "already reported".
-- ---------------------------------------------------------------------------

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS community_post_id UUID REFERENCES public.community_posts(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS reports_community_post_idx
  ON public.reports (community_post_id) WHERE community_post_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS reports_one_per_reporter_community_post
  ON public.reports (reporter_id, community_post_id) WHERE community_post_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. community-docs Storage bucket. Follows 20260829000000, the only other
-- bucket created in SQL rather than by hand in the dashboard.
--
-- PRIVACY CAVEAT, carried forward verbatim from that migration because it
-- applies harder here: every bucket in this project is public:true. A
-- community post's row is member-gated by RLS, but its PDF is readable by
-- anyone who has the URL. For an ANONYMOUS post that also means the object
-- path must not identify the author — hence <community>/<post>/<n>_<name>,
-- with no user id anywhere in it. (Contrast the `posts` bucket, whose paths
-- literally read anonymous/$userId/... — do not copy that convention.)
-- ---------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public)
VALUES ('community-docs', 'community-docs', true)
ON CONFLICT (id) DO NOTHING;

-- Sibling bucket for community_posts.photo_urls, kept separate from both
-- `posts` (whose path convention encodes anonymous/$userId — exactly the
-- identity leak this table's paths must avoid) and `group-photos` (a
-- different table's content). Same public:true + privacy caveat as above.
INSERT INTO storage.buckets (id, name, public)
VALUES ('community-photos', 'community-photos', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'authenticated_upload_community_docs') THEN
    CREATE POLICY "authenticated_upload_community_docs" ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'community-docs');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'public_read_community_docs') THEN
    CREATE POLICY "public_read_community_docs" ON storage.objects FOR SELECT
      USING (bucket_id = 'community-docs');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'authenticated_upload_community_photos') THEN
    CREATE POLICY "authenticated_upload_community_photos" ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'community-photos');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'public_read_community_photos') THEN
    CREATE POLICY "public_read_community_photos" ON storage.objects FOR SELECT
      USING (bucket_id = 'community-photos');
  END IF;
END $$;
