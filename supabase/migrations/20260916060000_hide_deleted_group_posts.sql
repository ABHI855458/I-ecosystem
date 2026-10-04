-- Deleted group posts were still being served and counted.
--
-- group_post_audience_feed had no deleted_at filter at all, while
-- friends_feed (the personal half of the same feed) has always had one. A
-- deleted group post therefore kept arriving in the Friends feed forever,
-- while the group profile page — which does filter — showed it as gone.
-- Reported as "the ping qa group has only one post, then why is [it]
-- appearing twice in the feed": the second card was a post deleted on
-- 2026-09-08 that only this function still returned.
--
-- groups_with_counts_for_user had the same gap in its post_count subquery,
-- so the group list showed an inflated number that disagreed with the
-- group profile's own POSTS stat.

CREATE OR REPLACE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid())
  select gp.id, gp.group_id, g.name, g.icon_url, gp.user_id, u.username, u.name,
         u.profile_photo_url, gp.caption, gp.photo_url, gp.photo_urls,
         gp.created_at
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
$function$
;

CREATE OR REPLACE FUNCTION public.groups_with_counts_for_user(p_user_id uuid)
 RETURNS TABLE(id uuid, name text, icon_url text, banner_url text, created_at timestamp with time zone, member_count bigint, post_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
begin
  v_me := public.current_user_id();
  if v_me is null then
    return;
  end if;

  -- Same authorization group_members_select_friend/groups_select_friend_member
  -- already grant: your own groups always, anyone else's only if you're a
  -- friend of theirs (migration 20260904180000_group_visibility_for_friends).
  -- Re-checked here explicitly since SECURITY DEFINER bypasses RLS.
  if p_user_id <> v_me and not public.is_friend_of(p_user_id) then
    return;
  end if;

  return query
  select
    g.id,
    g.name,
    g.icon_url,
    g.banner_url,
    g.created_at,
    (select count(*) from public.group_members gm2 where gm2.group_id = g.id) as member_count,
    (select count(*) from public.group_posts gp2
      where gp2.group_id = g.id and gp2.deleted_at is null) as post_count
  from public.groups g
  join public.group_members gm on gm.group_id = g.id
  where gm.user_id = p_user_id
  order by g.created_at desc;
end;
$function$
;
