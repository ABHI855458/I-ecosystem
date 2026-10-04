-- Your OWN group posts never appeared in your friends feed.
--
-- group_post_audience_feed carried `where gp.user_id <> me`, so the poster
-- was the one person guaranteed not to see their group post there — while
-- their personal and Duo posts do show in the same feed. Reported as "I
-- posted a group post but it isn't visible in the friends feed". Nothing
-- else merges own group posts back in client-side (FeedService.
-- fetchFriendsGroupFeed is the only reader), so the condition is simply
-- dropped; the author resolves to 'member' access and gets the full post.
-- Body otherwise identical to 20260927140000 (locked-photo withholding kept).
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
    where gp.deleted_at is null
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
