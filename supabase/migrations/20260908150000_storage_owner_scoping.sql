-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  SECURITY: scope storage writes to the uploader's own folder         ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- THE PROBLEM
-- Every write policy was `bucket_id = X AND auth.role() = 'authenticated'`
-- — any signed-in user could upload to ANY path in these buckets. Combined
-- with upsert:true (which the app uses everywhere), that means one student
-- can overwrite another student's profile photo, anon persona, or post
-- image by guessing the path. Paths are predictable: they contain the
-- target's users.id, which is visible on their own posts.
--
-- THE FIX
-- Compare the owning path segment against the caller's users.id.
--
-- KEYSPACE NOTE, and this is the whole difficulty: these paths contain
-- `users.id`, NOT `auth.uid()`. Writing the obvious
-- `(storage.foldername(name))[2] = auth.uid()::text` would match nothing
-- and break every upload silently. The helper below bridges the two id
-- spaces the same way every RLS policy in this schema does.

CREATE OR REPLACE FUNCTION public.my_users_id_text()
 RETURNS text
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT id::text FROM public.users WHERE auth_id = auth.uid() LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.my_users_id_text() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_users_id_text() TO authenticated;

-- ── posts: {anonymous|everyone}/{users.id}/{postId}.jpg ────────────────
DROP POLICY IF EXISTS "authenticated_upload_posts" ON storage.objects;
CREATE POLICY "authenticated_upload_posts" ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'posts' AND (storage.foldername(name))[2] = public.my_users_id_text()
);

DROP POLICY IF EXISTS "authenticated_update_posts" ON storage.objects;
CREATE POLICY "authenticated_update_posts" ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'posts' AND (storage.foldername(name))[2] = public.my_users_id_text()
) WITH CHECK (
  bucket_id = 'posts' AND (storage.foldername(name))[2] = public.my_users_id_text()
);

-- ── personas: {users.id}.jpg — the anon persona photo, single segment ──
-- Highest-value target in the app: overwriting someone's persona photo is a
-- direct attack on the anonymity system.
DROP POLICY IF EXISTS "authenticated_upload_personas" ON storage.objects;
CREATE POLICY "authenticated_upload_personas" ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'personas' AND name = public.my_users_id_text() || '.jpg'
);

DROP POLICY IF EXISTS "authenticated_update_personas" ON storage.objects;
CREATE POLICY "authenticated_update_personas" ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'personas' AND name = public.my_users_id_text() || '.jpg'
) WITH CHECK (
  bucket_id = 'personas' AND name = public.my_users_id_text() || '.jpg'
);

-- ── profiles: avatars/{users.id}.jpg | banners/{users.id}.jpg ──────────
DROP POLICY IF EXISTS "authenticated_upload_profiles" ON storage.objects;
CREATE POLICY "authenticated_upload_profiles" ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'profiles'
  AND (storage.foldername(name))[1] IN ('avatars','banners')
  AND split_part((storage.filename(name)), '.', 1) = public.my_users_id_text()
);

DROP POLICY IF EXISTS "authenticated_update_profiles" ON storage.objects;
CREATE POLICY "authenticated_update_profiles" ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'profiles'
  AND split_part((storage.filename(name)), '.', 1) = public.my_users_id_text()
) WITH CHECK (
  bucket_id = 'profiles'
  AND split_part((storage.filename(name)), '.', 1) = public.my_users_id_text()
);

-- ── reaction-photos: presets/{users.id}/… | realmoji/{users.id}/… ──────
DROP POLICY IF EXISTS "authenticated_upload_reaction_photos" ON storage.objects;
CREATE POLICY "authenticated_upload_reaction_photos" ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'reaction-photos' AND (storage.foldername(name))[2] = public.my_users_id_text()
);

DROP POLICY IF EXISTS "authenticated_update_reaction_photos" ON storage.objects;
CREATE POLICY "authenticated_update_reaction_photos" ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'reaction-photos' AND (storage.foldername(name))[2] = public.my_users_id_text()
) WITH CHECK (
  bucket_id = 'reaction-photos' AND (storage.foldername(name))[2] = public.my_users_id_text()
);

-- NOT scoped, deliberately, because their paths carry no owner segment:
--   group-icons / group-photos  — keyed by groupId; group membership is the
--                                 real boundary and lives in group_members
--   community-photos / -docs    — keyed by communityId/postId
--   us-album-photos             — keyed by albumId
--   ping-photos                 — keyed by pingId
--   bucket-photos               — dormant feature
-- Scoping those needs a membership lookup per path, which is a larger change
-- than this migration; they are listed in the launch report as remaining work.
