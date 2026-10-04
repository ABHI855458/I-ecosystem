-- Add aspect_ratio to the shared-audience feed RPC's return shape — the
-- poster's own per-post size choice (group_posts.aspect_ratio) must reach
-- this path the same as the direct-membership one (fetchGroupFeed's plain
-- select already gets it for free).
DROP FUNCTION IF EXISTS public.group_post_audience_feed(integer, integer);

CREATE OR REPLACE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone, aspect_ratio text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid())
  select gp.id, gp.group_id, g.name, g.icon_url, gp.user_id, u.username, u.name,
         u.profile_photo_url, gp.caption, gp.photo_url, gp.photo_urls,
         gp.created_at, gp.aspect_ratio
  from public.group_posts gp
  join public.groups g on g.id = gp.group_id
  join public.users u on u.id = gp.user_id
  where gp.user_id <> (select id from me)
    and gp.deleted_at is null
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
$function$;

GRANT EXECUTE ON FUNCTION public.group_post_audience_feed(integer, integer) TO authenticated;
