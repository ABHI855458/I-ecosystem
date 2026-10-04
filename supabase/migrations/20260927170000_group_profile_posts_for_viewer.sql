-- A non-member opening a group's profile saw NO posts at all (the public
-- tier, group_public_profile, never reads group_posts), even when the group
-- had shared posts with them. Explicit request: tapping a group from the
-- friends feed opens its profile, and "if they are included in the list to
-- see their post then [they] shall see all their posts which [they are]
-- permitted to".
--
-- "Permitted" is exactly what the friends feed already uses,
-- group_post_feed_access():
--   'open'   -> the post's audience admits you (shared to you by a member)
--               or it's a PUBLIC group in one of your communities: full post.
--   'locked' -> a PRIVATE group in one of your communities: first photo
--               only — every slot carries photo 1, same withholding as
--               group_post_audience_feed (20260927140000), so photos 2+
--               never leave the database.
--   'member' -> not returned here; members read group_posts directly.
-- Blocked authors are already excluded inside group_post_feed_access.
--
-- Row shape mirrors GroupService.fetchPosts (group_posts.* plus
-- `users` {name, profile_photo_url}) so GroupProfilePostCard renders it
-- unchanged, plus a `locked` flag.

create or replace function public.group_profile_posts_for_viewer(p_group_id uuid)
returns table(
  id uuid, group_id uuid, user_id uuid,
  photo_url text, photo_urls text[], photo_url_secondary text, inset_on_right boolean,
  caption text, note text, place text, taken_at timestamptz,
  created_at timestamptz, aspect_ratio text,
  users jsonb, locked boolean
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with v as (
    select gp.*, public.group_post_feed_access(gp.id) as access
      from public.group_posts gp
     where gp.group_id = p_group_id
       and gp.deleted_at is null
  )
  select v.id, v.group_id, v.user_id,
         case when v.access = 'locked'
              then coalesce(v.photo_urls[1], v.photo_url) else v.photo_url end,
         case when v.access = 'locked'
              then array_fill(coalesce(v.photo_urls[1], v.photo_url),
                              array[greatest(coalesce(array_length(v.photo_urls, 1), 0), 1)])
              else v.photo_urls end,
         -- The dual-photo inset is a second photo too: withheld when locked.
         case when v.access = 'locked' then null else v.photo_url_secondary end,
         v.inset_on_right,
         v.caption, v.note, v.place, v.taken_at, v.created_at, v.aspect_ratio,
         jsonb_build_object('name', u.name, 'profile_photo_url', u.profile_photo_url),
         (v.access = 'locked')
    from v
    join public.users u on u.id = v.user_id
   where v.access in ('open', 'locked')
   order by v.created_at desc;
$$;

revoke execute on function public.group_profile_posts_for_viewer(uuid) from public, anon;
grant execute on function public.group_profile_posts_for_viewer(uuid) to authenticated, service_role;
