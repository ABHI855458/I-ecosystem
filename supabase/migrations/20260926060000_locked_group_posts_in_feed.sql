-- ============================================================================
-- Private-group posts reach the group's community as NORMAL group-post cards
-- (same layout, header, caption, members, reactions) — first photo clear,
-- every other photo blurred. Replaces the separate "Blurred Group Teaser"
-- cards entirely (explicit correction: "remove all the teasers").
--
-- group_post_audience_feed now returns, one row per post:
--   locked = false  -> shared with me by a member (group_post_audience_admits)
--                      or a PUBLIC group in my community: everything visible;
--   locked = true   -> a PRIVATE group in a community I'm in, I'm not a
--                      member and nobody has shared it with me: the client
--                      blurs photo 2..n and taps say "Be a friend to see it".
-- The instant any member shares it with me, the same row flips to
-- locked = false — still one card.
--
-- Also: group_card_members(), so a locked card can show the group's roster
-- (group_members RLS hides it from non-members), and the teaser RPC is
-- dropped.
--
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================

BEGIN;

-- Can the caller see this group post in the feed at all, and is it locked?
-- NULL = not visible.
CREATE OR REPLACE FUNCTION public.group_post_feed_access(p_group_post uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT CASE
    WHEN public.is_group_member(gp.group_id, public.current_user_id()) THEN 'member'
    WHEN public.group_post_audience_admits(gp.id, gp.user_id)
      OR public.is_public_group_in_my_community(gp.group_id) THEN 'open'
    WHEN g.community_id IS NOT NULL
      AND COALESCE(g.visibility, 'private') <> 'public'
      AND public.is_community_member(g.community_id, auth.uid()) THEN 'locked'
    ELSE NULL END
  FROM public.group_posts gp
  JOIN public.groups g ON g.id = gp.group_id
  WHERE gp.id = p_group_post AND gp.deleted_at IS NULL
    AND NOT public.is_blocked_user(auth.uid(), gp.user_id);
$$;
REVOKE ALL ON FUNCTION public.group_post_feed_access(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_post_feed_access(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.group_post_audience_feed(integer, integer);
CREATE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone, aspect_ratio text, locked boolean)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
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
         u.profile_photo_url, r.caption, r.photo_url, r.photo_urls,
         r.created_at, r.aspect_ratio, (r.access = 'locked') as locked
  from rows r
  join public.users u on u.id = r.user_id
  -- 'member' rows stay out, as before: members see their group's posts in
  -- the group itself, not duplicated here.
  where r.access in ('open', 'locked')
  order by r.created_at desc
  limit p_limit offset p_offset;
$function$;
REVOKE ALL ON FUNCTION public.group_post_audience_feed(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_post_audience_feed(integer, integer) TO authenticated;

-- The roster for a group-post card, for anyone the post is shown to.
CREATE OR REPLACE FUNCTION public.group_card_members(p_group_post uuid)
RETURNS TABLE(user_id uuid, name text, profile_photo_url text, role text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT gm.user_id, u.name, u.profile_photo_url, gm.role
    FROM public.group_posts gp
    JOIN public.group_members gm ON gm.group_id = gp.group_id
    JOIN public.users u ON u.id = gm.user_id
   WHERE gp.id = p_group_post
     AND public.group_post_feed_access(p_group_post) IS NOT NULL
     AND u.deleted_at IS NULL
   ORDER BY gm.role, u.name;
$$;
REVOKE ALL ON FUNCTION public.group_card_members(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_card_members(uuid) TO authenticated;

-- No more separate teaser cards.
DROP FUNCTION IF EXISTS public.group_posts_teaser_for_community(uuid);

COMMIT;
