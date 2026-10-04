-- Community moderators see only THEIR community's content.
--
-- The dashboard feeds were gated on is_admin_or_global_mod(), so a
-- community moderator could open them and get nothing at all — an empty
-- page rather than their community's posts. These admit them and scope the
-- rows to the community they were appointed to.
--
-- Anon posts stay masked for them exactly as for everyone else: appointing
-- someone to moderate a community must not hand them the identities behind
-- its anonymous posts.

DROP FUNCTION IF EXISTS public.dashboard_feed(text,integer,integer);

CREATE FUNCTION public.dashboard_feed(
  p_scope text DEFAULT 'all', p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(
   id uuid, user_id uuid, author_name text, author_avatar text,
   is_anonymous boolean, anon_name text,
   content text, image_url text, visibility text, post_type text,
   prompt text, community_id uuid, community_name text,
   comment_count integer, reaction_count integer, view_count integer,
   created_at timestamp)
 LANGUAGE plpgsql STABLE SECURITY DEFINER
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
     -- Community moderator: only posts tagged to their community, whether
     -- anonymous or a community-tagged friends post.
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

REVOKE ALL ON FUNCTION public.dashboard_feed(text,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dashboard_feed(text,integer,integer) TO authenticated;


DROP FUNCTION IF EXISTS public.dashboard_community_feed(uuid,integer,integer);

CREATE FUNCTION public.dashboard_community_feed(
  p_community uuid DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(
   id uuid, community_id uuid, community_name text,
   author_name text, is_anonymous boolean,
   body text, photo_urls text[], created_at timestamptz)
 LANGUAGE plpgsql STABLE SECURITY DEFINER
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
     AND (v_scoped IS NULL OR cp.community_id = v_scoped)
     AND (p_community IS NULL OR cp.community_id = p_community)
   ORDER BY cp.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_community_feed(uuid,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dashboard_community_feed(uuid,integer,integer) TO authenticated;
