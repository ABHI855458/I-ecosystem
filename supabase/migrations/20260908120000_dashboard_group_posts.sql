-- Group posts for the dashboard's Home feed.
--
-- `group_posts` is a separate table from `posts`, so dashboard_feed cannot
-- reach it — group content was invisible in the dashboard entirely.
-- Same auth gate and the same community scoping as the other feeds.
--
-- Community moderators get nothing here: groups have no community_id in this
-- schema (see GroupService's own note), so there is no honest way to scope
-- them to one community. Returning everything to a community moderator would
-- be a leak; returning a filtered-by-nothing set would be a lie.

DROP FUNCTION IF EXISTS public.dashboard_group_posts(integer,integer);

CREATE FUNCTION public.dashboard_group_posts(
  p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(
   id uuid, group_id uuid, group_name text,
   author_name text, author_avatar text,
   caption text, photo_url text, photo_urls text[],
   created_at timestamptz)
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.is_admin_or_global_mod() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;

  RETURN QUERY
  SELECT gp.id, gp.group_id, g.name,
         u.name, u.profile_photo_url,
         gp.caption, gp.photo_url, gp.photo_urls, gp.created_at
    FROM group_posts gp
    JOIN groups g ON g.id = gp.group_id
    LEFT JOIN users u ON u.id = gp.user_id
   ORDER BY gp.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_group_posts(integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dashboard_group_posts(integer,integer) TO authenticated;
