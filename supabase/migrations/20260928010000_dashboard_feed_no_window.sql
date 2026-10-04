-- dashboard_feed: drop the 48h window so moderators see every live post.
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
     -- Moderators see every live post (the app's Dip feed resurfaces older
     -- Dips, so a 48h window hid posts students can still see). Moments
     -- still end at 24h, same as in the app.
     AND (p.post_type IS DISTINCT FROM 'moment'
          OR p.created_at > (now() AT TIME ZONE 'utc') - interval '24 hours')
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
$function$
;
