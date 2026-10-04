-- ============================================================================
-- Group posts from groups you're a MEMBER of show in your feed again
-- (regression from 20260926060000: group_post_feed_access() answers
-- 'member' first, and the feed kept only 'open'/'locked', so e.g. a Ping QA
-- Group post shared with you vanished). Members get it unlocked, one row per
-- post, same as every other path. Your own posts stay out, as before.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
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
  where r.access in ('member', 'open', 'locked')
  order by r.created_at desc
  limit p_limit offset p_offset;
$function$;

COMMIT;
