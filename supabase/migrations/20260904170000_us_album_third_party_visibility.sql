-- Us Album third-party visibility correction (explicit spec from the
-- product owner): a third person may view an accepted album's MUTUAL
-- photos if they're an accepted friend of EITHER party (not both) — the
-- live policies (us_albums_select, us_album_photos_select) used
-- is_mutual_friend_of_both, a stricter rule than asked for. Also: if an
-- album has no mutual-visibility photos at all (every photo still
-- private, or no photos yet), its very EXISTENCE must stay invisible to
-- everyone except the two parties — a qualifying third party seeing the
-- ALBUM ROW (id/status/parties) with nothing to actually view was itself
-- a smaller leak the old policy allowed (it gated only on `status =
-- 'accepted'`, never on whether any photo was actually shared).

create or replace function public.is_friend_of_either(target_a uuid, target_b uuid)
returns boolean
language sql
security definer
set search_path to 'public', 'extensions'
as $$
  select exists (
    select 1 from users viewer
    where viewer.auth_id = auth.uid()
    and (
      exists (
        select 1 from friendships f
        where f.status = 'accepted'
        and ((f.requester_id = viewer.id and f.addressee_id = target_a)
          or (f.addressee_id = viewer.id and f.requester_id = target_a))
      )
      or exists (
        select 1 from friendships f
        where f.status = 'accepted'
        and ((f.requester_id = viewer.id and f.addressee_id = target_b)
          or (f.addressee_id = viewer.id and f.requester_id = target_b))
      )
    )
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
      and exists (
        select 1 from us_album_photos p
        where p.album_id = us_albums.id and p.visibility = 'mutual'
      )
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
      and exists (
        select 1 from us_albums a
        where a.id = us_album_photos.album_id
        and a.status = 'accepted'
        and is_friend_of_either(a.user_a, a.user_b)
      )
    )
  );
