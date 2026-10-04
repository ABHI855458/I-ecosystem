-- Fixes infinite recursion introduced by the previous migration
-- (20260904170000): us_albums_select's third-party clause queried
-- us_album_photos directly, which (being itself RLS-protected) had to
-- evaluate us_album_photos_select, whose own third-party clause queried
-- us_albums right back — a genuine circular RLS dependency between the
-- two tables' policies, caught live via 42P17 "infinite recursion
-- detected in policy for relation us_albums" while verifying the
-- previous migration.
--
-- Fix: two SECURITY DEFINER helpers that read the OTHER table directly.
-- Functions created here are owned by the migration role (which, same as
-- posts_feed/anon_reaction_counts elsewhere in this project, has
-- BYPASSRLS), so their internal queries never re-invoke either table's
-- own RLS policy — breaking the cycle at both ends instead of just
-- moving it.

create or replace function public.album_has_mutual_photo(p_album_id uuid)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from us_album_photos
    where album_id = p_album_id and visibility = 'mutual'
  );
$$;

create or replace function public.album_is_accepted_and_friend_of_either(p_album_id uuid)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from us_albums a
    where a.id = p_album_id
    and a.status = 'accepted'
    and is_friend_of_either(a.user_a, a.user_b)
  );
$$;

drop policy us_albums_select on us_albums;
create policy us_albums_select on us_albums
  for select
  using (
    auth.uid() in (select users.auth_id from users where users.id = any (array[user_a, user_b]))
    or (
      status = 'accepted'
      and is_friend_of_either(user_a, user_b)
      and album_has_mutual_photo(id)
    )
  );

drop policy us_album_photos_select on us_album_photos;
create policy us_album_photos_select on us_album_photos
  for select
  using (
    exists (
      select 1 from us_albums a
      where a.id = us_album_photos.album_id
      and auth.uid() in (select users.auth_id from users where users.id = any (array[a.user_a, a.user_b]))
    )
    or (
      visibility = 'mutual'
      and album_is_accepted_and_friend_of_either(album_id)
    )
  );
