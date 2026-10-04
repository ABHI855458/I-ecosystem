-- US (Duo) photos live in the PRIVATE us-album-photos bucket and posts.image_url
-- holds a bare object path, so the admin dashboard rendered broken images.
-- Let admins / global moderators sign them (read-only) for moderation.
drop policy if exists us_album_photos_read_moderators on storage.objects;
create policy us_album_photos_read_moderators on storage.objects
  for select to authenticated
  using (bucket_id = 'us-album-photos'
         and public.current_moderator_role() in ('admin', 'global_moderator'));
