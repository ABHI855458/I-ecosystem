-- Public buckets were LISTABLE by anyone, signed out included.
--
-- Each public bucket carried a SELECT policy on storage.objects for role
-- PUBLIC with only `bucket_id = '<bucket>'` as its condition. Serving a file
-- by its public URL needs no SELECT policy (that is what buckets.public is
-- for), so all these policies added was the storage list/search API: with
-- only the public anon key, anyone could enumerate every object path —
-- private ping photos (ping-photos), friends-only post images (posts),
-- private-group photos (group-photos, including the photos 2+ a locked
-- group post withholds — see 20260927140000), RealMoji selfies
-- (reaction-photos), avatars — and then open each one by URL.
-- Probe 2026-09-27 as role anon: 46 group-photos and 40 ping-photos objects
-- listable.
--
-- The app still needs SELECT on its OWN objects: every upload in
-- StorageService uses `upsert: true`, which Storage only allows when the
-- caller can see the object it would overwrite. So SELECT narrows to
-- "authenticated AND the object's owner". Public URLs, image loading and
-- re-uploads are unchanged.
--
-- group-icons keeps a signed-in (not owner-only) read: a group's icon sits at
-- a per-group path that any member may re-upload over, so the uploader is
-- often not the object's owner. Icons are shown to everyone who sees the
-- group anyway.

drop policy if exists ping_photos_public_read on storage.objects;
drop policy if exists "public_read_[bucketname]" on storage.objects;
drop policy if exists public_read_bucket_photos on storage.objects;
drop policy if exists public_read_community_docs on storage.objects;
drop policy if exists public_read_community_photos on storage.objects;
drop policy if exists public_read_group_icons on storage.objects;
drop policy if exists public_read_group_photos on storage.objects;
drop policy if exists public_read_personas on storage.objects;
drop policy if exists public_read_posts on storage.objects;
drop policy if exists public_read_profiles on storage.objects;
drop policy if exists public_read_reaction_photos on storage.objects;

drop policy if exists owner_read_public_buckets on storage.objects;
create policy owner_read_public_buckets on storage.objects
  for select to authenticated
  using (
    bucket_id in (
      'bucket-photos', 'community-docs', 'community-photos', 'group-photos',
      'personas', 'ping-photos', 'posts', 'profiles', 'reaction-photos'
    )
    and owner_id = (select auth.uid())::text
  );

drop policy if exists member_read_group_icons on storage.objects;
create policy member_read_group_icons on storage.objects
  for select to authenticated
  using (bucket_id = 'group-icons');
