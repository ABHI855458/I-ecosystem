-- Group visibility is per SHARER, not per group.
--
-- Explicit spec (2026-09-27): when X visits user U's profile,
--   * U's groups show only if X is a member, or U shared at least one of
--     that group's posts to X — otherwise X doesn't even learn the group
--     exists ("he shall not even see the existence of the albums");
--   * opening a group profile FROM U shows X only the posts U shared to X
--     ("if he goes through that man who had given access then he can see
--     the photo there") — a post someone ELSE shared to X does not appear
--     there; it appears when X goes through that other person;
--   * from the friends feed, the group opens via whoever's share put that
--     post in X's feed (group_post_audience_feed.shared_via).
-- Community-wide visibility (a PUBLIC group in X's community, or a private
-- group's first-photo "locked" preview) is not a personal share and is
-- unchanged. Members still see everything.

-- "Was p_post shared to ME by p_via?" — p_via's own share row
-- (shared_by = p_via, or the author's original audience when p_via wrote
-- it) admits the caller through p_via's Friends circle, a circle of
-- p_via's the caller is in, or a community of p_via's the caller is in.
create or replace function public.group_post_shared_via_admits(p_post uuid, p_via uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select exists (
    select 1
      from public.group_post_audiences a
      join public.group_posts gp on gp.id = a.group_post_id
     where a.group_post_id = p_post
       and gp.deleted_at is null
       and coalesce(a.shared_by, gp.user_id) = p_via
       and not public.is_blocked_user(auth.uid(), gp.user_id)
       and (
            (a.audience_kind = 'friends'
             and public.in_friends_circle(p_via, public.current_user_id()))
         or (a.audience_kind = 'circle'
             and exists (select 1 from public.circle_members cm
                          where cm.circle_id = a.circle_id
                            and cm.member_id = public.current_user_id()))
         or (a.audience_kind = 'community'
             and a.community_id is not null
             and public.is_community_member(a.community_id, auth.uid()))
       )
  );
$$;
revoke execute on function public.group_post_shared_via_admits(uuid, uuid) from public, anon;
grant execute on function public.group_post_shared_via_admits(uuid, uuid) to authenticated, service_role;

-- 1) U's groups on U's profile.
create or replace function public.groups_with_counts_for_user(p_user_id uuid)
returns table(id uuid, name text, icon_url text, banner_url text,
              created_at timestamptz, member_count bigint, post_count bigint)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid;
begin
  v_me := public.current_user_id();
  if v_me is null then
    return;
  end if;
  if p_user_id <> v_me and not public.is_friend_of(p_user_id) then
    return;
  end if;

  return query
  select g.id, g.name, g.icon_url, g.banner_url, g.created_at,
         (select count(*) from public.group_members gm2 where gm2.group_id = g.id),
         case
           when p_user_id = v_me or public.is_group_member(g.id, v_me) then
             (select count(*) from public.group_posts gp2
               where gp2.group_id = g.id and gp2.deleted_at is null)
           else
             (select count(*) from public.group_posts gp2
               where gp2.group_id = g.id and gp2.deleted_at is null
                 and public.group_post_shared_via_admits(gp2.id, p_user_id))
         end
    from public.groups g
    join public.group_members gm on gm.group_id = g.id
   where gm.user_id = p_user_id
     and (
          p_user_id = v_me
       or public.is_group_member(g.id, v_me)
       or exists (select 1 from public.group_posts gp
                   where gp.group_id = g.id and gp.deleted_at is null
                     and public.group_post_shared_via_admits(gp.id, p_user_id))
     )
   order by g.created_at desc;
end;
$function$;

-- 2) The group profile's non-member posts, scoped to who you came through.
drop function if exists public.group_profile_posts_for_viewer(uuid);
create or replace function public.group_profile_posts_for_viewer(
  p_group_id uuid,
  p_via_user uuid default null
)
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
         case when v.access = 'locked' then null else v.photo_url_secondary end,
         v.inset_on_right,
         v.caption, v.note, v.place, v.taken_at, v.created_at, v.aspect_ratio,
         jsonb_build_object('name', u.name, 'profile_photo_url', u.profile_photo_url),
         (v.access = 'locked')
    from v
    join public.users u on u.id = v.user_id
   where v.access in ('open', 'locked')
     and (
          -- community-wide, not a personal share: always shown
          v.access = 'locked'
       or public.is_public_group_in_my_community(v.group_id)
          -- a personal share: only through the person who shared it
       or (p_via_user is not null
           and public.group_post_shared_via_admits(v.id, p_via_user))
     )
   order by v.created_at desc;
$$;
revoke execute on function public.group_profile_posts_for_viewer(uuid, uuid) from public, anon;
grant execute on function public.group_profile_posts_for_viewer(uuid, uuid) to authenticated, service_role;

-- 3) Friends feed: say WHOSE share put each group post in my feed, so
--    tapping the group opens it via that person. Return type changes, so
--    drop + create (same body as 20260927180000 plus shared_via).
drop function if exists public.group_post_audience_feed(integer, integer);
create function public.group_post_audience_feed(p_limit integer default 20, p_offset integer default 0)
returns table(
  id uuid, group_id uuid, group_name text, group_icon_url text,
  user_id uuid, username text, name text, avatar_url text,
  caption text, photo_url text, photo_urls text[],
  created_at timestamp with time zone, aspect_ratio text, locked boolean,
  shared_via uuid
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with rows as (
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
         r.created_at, r.aspect_ratio, (r.access = 'locked') as locked,
         -- The author when their own audience admits me, else the first
         -- other member whose share does. Null for members and for
         -- community-wide (public / locked) rows.
         case when r.access = 'open' then (
           select s.via
             from (select distinct coalesce(a.shared_by, r.user_id) as via
                     from public.group_post_audiences a
                    where a.group_post_id = r.id) s
            where public.group_post_shared_via_admits(r.id, s.via)
            order by (s.via = r.user_id) desc, s.via
            limit 1
         ) end
  from rows r
  join public.users u on u.id = r.user_id
  where r.access in ('member', 'open', 'locked')
  order by r.created_at desc
  limit p_limit offset p_offset;
$$;
revoke execute on function public.group_post_audience_feed(integer, integer) from public, anon;
grant execute on function public.group_post_audience_feed(integer, integer) to authenticated, service_role;
