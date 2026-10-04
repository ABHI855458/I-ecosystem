-- Comprehensive sweep for the same bug class just found and fixed on
-- `personas` (20260904160000): every bucket whose upload path is written
-- with `upsert: true` (StorageService, dart) needs an UPDATE storage
-- policy, or only the FIRST-EVER upload to any given deterministic path
-- succeeds (a real INSERT) — every subsequent re-upload (changing an
-- existing photo) silently fails, caught into a StorageException -> null
-- by every upload function's own try/catch. Confirmed live: `profiles`
-- (uploadAvatar/uploadUserBanner) had exactly this shape — the one real
-- account with a profile photo already set could never change it.
--
-- Buckets using upsert:false (us-album-photos, community-photos,
-- community-docs, ping-photos) are NOT touched here — each of those
-- writes a fresh UUID-named object every time, never overwriting, so no
-- UPDATE policy is needed for them.
create policy authenticated_update_posts on storage.objects
  for update
  using (bucket_id = 'posts' and auth.role() = 'authenticated')
  with check (bucket_id = 'posts' and auth.role() = 'authenticated');

create policy authenticated_update_profiles on storage.objects
  for update
  using (bucket_id = 'profiles' and auth.role() = 'authenticated')
  with check (bucket_id = 'profiles' and auth.role() = 'authenticated');

create policy authenticated_update_bucket_photos on storage.objects
  for update
  using (bucket_id = 'bucket-photos' and auth.role() = 'authenticated')
  with check (bucket_id = 'bucket-photos' and auth.role() = 'authenticated');

create policy authenticated_update_group_icons on storage.objects
  for update
  using (bucket_id = 'group-icons' and auth.role() = 'authenticated')
  with check (bucket_id = 'group-icons' and auth.role() = 'authenticated');

create policy authenticated_update_group_photos on storage.objects
  for update
  using (bucket_id = 'group-photos' and auth.role() = 'authenticated')
  with check (bucket_id = 'group-photos' and auth.role() = 'authenticated');

-- reaction-photos already has a narrow UPDATE policy
-- (realmoji_selfie_update_own, scoped to the realmoji/ path prefix only)
-- — this adds bucket-wide coverage (permissive, ORs with the existing
-- one) for the two OTHER paths that bucket's own upload functions write
-- to: uploadReactionPhoto's `$postId/$userId.jpg` and
-- uploadReactionPresetPhoto's `presets/$userId/$presetId.jpg`, neither of
-- which the realmoji-scoped policy's folder check ever matched.
create policy authenticated_update_reaction_photos on storage.objects
  for update
  using (bucket_id = 'reaction-photos' and auth.role() = 'authenticated')
  with check (bucket_id = 'reaction-photos' and auth.role() = 'authenticated');
