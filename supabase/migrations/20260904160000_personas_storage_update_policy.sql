-- The personas bucket (anon persona photo — users.anon_photo_url) only had
-- an INSERT storage policy. StorageService.uploadPersonaPhoto always
-- uploads with upsert:true so a person can CHANGE their anon photo later,
-- not just set it once — but Supabase Storage's upsert path requires an
-- UPDATE policy to overwrite an object that already exists. Without one,
-- the very first upload for any given user succeeds (a real INSERT), and
-- every subsequent re-upload silently fails (caught into a StorageException
-- -> null -> "Couldn't update your anon photo" toast) — confirmed live: the
-- bucket carries exactly one INSERT policy and no UPDATE policy, and the
-- one real anon_photo_url set so far only ever went through the
-- first-upload path.
create policy authenticated_update_personas on storage.objects
  for update
  using (bucket_id = 'personas' and auth.role() = 'authenticated')
  with check (bucket_id = 'personas' and auth.role() = 'authenticated');
