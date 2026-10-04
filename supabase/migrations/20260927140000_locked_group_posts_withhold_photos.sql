-- Locked group posts: photos 2+ must not be accessible, not just blurred.
--
-- A private group's post reaches its communities as a "locked" card: first
-- photo clear, the rest blurred (PostPhotoCarousel.blurFromIndex: 1). The
-- blur was client-side only — group_post_audience_feed returned the full
-- photo_urls array to the locked viewer, and group-photos is a public
-- bucket, so the real URLs of photos 2+ sat on the viewer's phone and
-- opened for anyone holding them. Explicit request: "the blurred photos of
-- group posts, they shall not be able to access them".
--
-- For locked rows every slot now carries the FIRST photo's URL. The array
-- keeps its length, so the card still shows "1/3" and its blurred slides
-- (now a blur of photo 1), and no client change is needed. The real URLs
-- of photos 2+ never leave the database for a non-member. Members and
-- 'open' rows are unchanged. Same signature, so CREATE OR REPLACE.

create or replace function public.group_post_audience_feed(p_limit integer default 20, p_offset integer default 0)
returns table(
  id uuid, group_id uuid, group_name text, group_icon_url text,
  user_id uuid, username text, name text, avatar_url text,
  caption text, photo_url text, photo_urls text[],
  created_at timestamp with time zone, aspect_ratio text, locked boolean
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with me as (select id from public.users where auth_id = auth.uid()),
  rows as (
    select gp.*, g.name as gname, g.icon_url as gicon,
           public.group_post_feed_access(gp.id) as access
    from public.group_posts gp
    join public.groups g on g.id = gp.group_id
    where gp.user_id <> (select id from me)
      and gp.deleted_at is null
  )
  select r.id, r.group_id, r.gname, r.gicon, r.user_id, u.username, u.name,
         u.profile_photo_url, r.caption,
         case when r.access = 'locked'
              then coalesce(r.photo_urls[1], r.photo_url)
              else r.photo_url end,
         case when r.access = 'locked'
              then array_fill(coalesce(r.photo_urls[1], r.photo_url),
                              array[greatest(coalesce(array_length(r.photo_urls, 1), 0), 1)])
              else r.photo_urls end,
         r.created_at, r.aspect_ratio, (r.access = 'locked') as locked
  from rows r
  join public.users u on u.id = r.user_id
  where r.access in ('member', 'open', 'locked')
  order by r.created_at desc
  limit p_limit offset p_offset;
$$;
