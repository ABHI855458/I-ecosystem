-- Group icon reaches the feed — explicit follow-up: the group's DP,
-- once set (any member can now set it, see 20260916020000), should
-- actually show on that group's posts, not just the group profile header.
-- Neither fetchGroupFeed's direct table read nor fetchFriendsGroupFeed's
-- RPC selected icon_url at all before this, so DesignGroupCard/
-- GroupPostCard always fell back to their letter-glyph initial regardless
-- of whether a real icon existed.
--
-- group_post_audience_feed's return TABLE gains group_icon_url — Postgres
-- requires DROP + CREATE (not CREATE OR REPLACE) to change a function's
-- return columns.
DROP FUNCTION IF EXISTS public.group_post_audience_feed(integer, integer);

CREATE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  with me as (select id from public.users where auth_id = auth.uid())
  select gp.id, gp.group_id, g.name, g.icon_url, gp.user_id, u.username, u.name,
         u.profile_photo_url, gp.caption, gp.photo_url, gp.photo_urls,
         gp.created_at
  from public.group_posts gp
  join public.groups g on g.id = gp.group_id
  join public.users u on u.id = gp.user_id
  where gp.user_id <> (select id from me)
    and (
      (
        exists (select 1 from public.group_post_audiences gpa
                where gpa.group_post_id = gp.id and gpa.audience_kind = 'friends')
        and exists (select 1 from public.friendships f
                where f.status = 'accepted'
                  and ((f.requester_id = (select id from me) and f.addressee_id = gp.user_id)
                    or (f.addressee_id = (select id from me) and f.requester_id = gp.user_id)))
      )
      or
      exists (select 1 from public.group_post_audiences gpa
              join public.community_members cm on cm.community_id = gpa.community_id
              where gpa.group_post_id = gp.id
                and gpa.audience_kind = 'community'
                and cm.user_id = auth.uid())
    )
  order by gp.created_at desc
  limit p_limit offset p_offset;
$$;

REVOKE ALL ON FUNCTION public.group_post_audience_feed(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_post_audience_feed(integer, integer) TO authenticated;
