-- The dashboard was showing posts the APP had already expired.
--
-- Every feed in the app hides a post past its window as a query filter
-- rather than deleting it (FeedService.anonVisibleWindow /
-- postVisibleWindow / momentVisibleWindow, kCommunityPostVisibleWindow) —
-- 48h for an ordinary, anon or community post, 24h for a Moment. The three
-- dashboard RPCs filtered on deleted_at alone, so a moderator kept seeing
-- rows no user could still see (80 posts listed vs 10 actually live), and
-- Overview's counts disagreed with the app.
-- Explicit request: "in dashboard as posts expire, anon posts expire and
-- community posts expire they shall also go away from the dashboard".
--
-- Deliberately the SAME query-filter approach, not a delete: the row and
-- any report/moderation trail on it still exist, they just stop being
-- listed. Reports is not time-filtered, so an expired post is still
-- reachable there.
CREATE OR REPLACE FUNCTION public.dashboard_feed(p_scope text DEFAULT 'all'::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, user_id uuid, author_name text, author_avatar text, is_anonymous boolean, anon_name text, content text, image_url text, visibility text, post_type text, prompt text, community_id uuid, community_name text, comment_count integer, reaction_count integer, view_count integer, created_at timestamp without time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_scoped uuid;   -- non-null => a community moderator, limited to this one
BEGIN
  IF public.is_admin_or_global_mod() THEN
    v_scoped := NULL;
  ELSIF public.current_moderator_role() = 'community_moderator' THEN
    v_scoped := public.current_moderator_community_id();
    IF v_scoped IS NULL THEN
      RAISE EXCEPTION 'no community assigned';
    END IF;
  ELSE
    RAISE EXCEPTION 'not authorised';
  END IF;

  RETURN QUERY
  SELECT p.id,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::uuid ELSE p.user_id END,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::text ELSE u.name END,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::text ELSE u.profile_photo_url END,
         (p.visibility = 'anonymous'),
         CASE WHEN p.visibility = 'anonymous'
              THEN COALESCE(NULLIF(btrim(u.anon_name),''),'anonymous') END,
         p.content, p.image_url, p.visibility, p.post_type, p.prompt,
         p.community_id, c.name,
         (SELECT COUNT(*)::int FROM comments cm WHERE cm.post_id = p.id AND cm.deleted_at IS NULL),
         (SELECT COUNT(*)::int FROM post_realmoji_reactions r WHERE r.post_id = p.id),
         COALESCE(p.view_count,0),
         p.created_at
    FROM posts p
    JOIN users u ON u.id = p.user_id
    LEFT JOIN communities c ON c.id = p.community_id
   WHERE p.deleted_at IS NULL
     AND p.post_type IS DISTINCT FROM 'memory'
     -- App parity: a Moment lives 24h, everything else 48h.
     AND p.created_at > (now() AT TIME ZONE 'utc')
         - CASE WHEN p.post_type = 'moment' THEN interval '24 hours'
                ELSE interval '48 hours' END
     AND (v_scoped IS NULL OR p.community_id = v_scoped)
     AND (p_scope = 'all'
       OR (p_scope = 'anon'     AND p.visibility = 'anonymous')
       OR (p_scope = 'friends'  AND p.visibility = 'friends')
       OR (p_scope = 'everyone' AND p.visibility = 'everyone')
       OR (p_scope = 'moment'   AND p.post_type  = 'moment')
       OR (p_scope = 'us'       AND p.post_type  = 'us'))
   ORDER BY p.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dashboard_community_feed(p_community uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, community_id uuid, community_name text, author_name text, is_anonymous boolean, body text, photo_urls text[], created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_scoped uuid;
BEGIN
  IF public.is_admin_or_global_mod() THEN
    v_scoped := NULL;
  ELSIF public.current_moderator_role() = 'community_moderator' THEN
    v_scoped := public.current_moderator_community_id();
    IF v_scoped IS NULL THEN
      RAISE EXCEPTION 'no community assigned';
    END IF;
  ELSE
    RAISE EXCEPTION 'not authorised';
  END IF;

  RETURN QUERY
  SELECT cp.id, cp.community_id, c.name,
         CASE WHEN cp.is_anonymous THEN NULL::text ELSE u.name END,
         cp.is_anonymous, cp.body, cp.photo_urls, cp.created_at
    FROM community_posts cp
    JOIN communities c ON c.id = cp.community_id
    LEFT JOIN users u ON u.id = cp.user_id
   WHERE cp.deleted_at IS NULL
     -- App parity: kCommunityPostVisibleWindow.
     AND cp.created_at > now() - interval '48 hours'
     AND (v_scoped IS NULL OR cp.community_id = v_scoped)
     AND (p_community IS NULL OR cp.community_id = p_community)
   ORDER BY cp.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dashboard_group_posts(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, group_id uuid, group_name text, author_name text, author_avatar text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.is_admin_or_global_mod() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;
  RETURN QUERY
  SELECT gp.id, gp.group_id, g.name, u.name, u.profile_photo_url,
         gp.caption, gp.photo_url, gp.photo_urls, gp.created_at
    FROM group_posts gp
    JOIN groups g ON g.id = gp.group_id
    LEFT JOIN users u ON u.id = gp.user_id
   WHERE gp.deleted_at IS NULL
     AND gp.created_at > now() - interval '48 hours'
   ORDER BY gp.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$;

-- Priority notices were permanent. Explicit request: "the priority
-- notifications shall go after 14 days". Same filter-don't-delete rule, so
-- the item and its poll votes survive for the record. Both clients apply
-- the same window (CommunityFeedService.kPriorityItemVisibleWindow and the
-- dashboard's PRIORITY_ITEM_VISIBLE_DAYS).
CREATE OR REPLACE FUNCTION public.community_priority_items(p_community_id uuid)
 RETURNS SETOF public.community_feed_items
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT * FROM public.community_feed_items
   WHERE community_id = p_community_id
     AND deleted_at IS NULL
     AND created_at > now() - interval '14 days'
   ORDER BY created_at DESC;
$function$;
