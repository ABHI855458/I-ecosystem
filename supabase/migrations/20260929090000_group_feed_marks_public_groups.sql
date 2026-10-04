-- Lets the client tell a PUBLIC group's post apart from a PRIVATE group's
-- post that simply became open to a community (both currently read as
-- `locked = false`, i.e. "open" — group_post_feed_access's own doc). User
-- request 2026-09-29: "the accept button remove it public groups as they
-- cannot join public groups like that from feed" — a public group is
-- already self-joinable (self_join_public_group / its own profile screen),
-- so a per-post "Accept" pill in the feed is the wrong join door for it;
-- it stays exactly as it was for a private group's post that a member
-- shared, which really is an invitation.
DROP FUNCTION IF EXISTS public.group_post_audience_feed(integer, integer);

CREATE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone, aspect_ratio text, locked boolean, shared_via uuid, group_is_public boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  with rows as (
    select gp.*, g.name as gname, g.icon_url as gicon,
           coalesce(g.visibility, 'private') = 'public' as gpublic,
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
         r.created_at, r.aspect_ratio, (r.access = 'locked') as locked,
         case when r.access = 'open' then (
           select s.via
             from (select distinct coalesce(a.shared_by, r.user_id) as via
                     from public.group_post_audiences a
                    where a.group_post_id = r.id) s
            where public.group_post_shared_via_admits(r.id, s.via)
            order by (s.via = r.user_id) desc, s.via
            limit 1
         ) end,
         r.gpublic
  from rows r
  join public.users u on u.id = r.user_id
  where r.access in ('member', 'open', 'locked')
  order by r.created_at desc
  limit p_limit offset p_offset;
$$;

REVOKE ALL ON FUNCTION public.group_post_audience_feed(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_post_audience_feed(integer, integer) TO authenticated;
