-- Communities a moderator may act on.
--
-- The Prompts page listed EVERY community as a pill, including ones a
-- community moderator has no jurisdiction over — they could see the names
-- and click them, only to be refused by RLS on the first write. Showing a
-- control that cannot work is worse than not showing it.
--
-- Reads still go through `communities_select` (deleted_at IS NULL) for
-- everyone; this is specifically "what may I MANAGE".
DROP FUNCTION IF EXISTS public.my_manageable_communities();

CREATE FUNCTION public.my_manageable_communities()
 RETURNS TABLE(id uuid, name text)
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_scoped uuid;
BEGIN
  IF public.is_admin_or_global_mod() THEN
    RETURN QUERY
      SELECT c.id, c.name FROM public.communities c
       WHERE c.deleted_at IS NULL ORDER BY c.name;
    RETURN;
  END IF;

  IF public.current_moderator_role() = 'community_moderator' THEN
    v_scoped := public.current_moderator_community_id();
    RETURN QUERY
      SELECT c.id, c.name FROM public.communities c
       WHERE c.deleted_at IS NULL AND c.id = v_scoped;
    RETURN;
  END IF;

  RETURN;  -- not a moderator: nothing to manage
END;
$function$;

REVOKE ALL ON FUNCTION public.my_manageable_communities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_manageable_communities() TO authenticated;
