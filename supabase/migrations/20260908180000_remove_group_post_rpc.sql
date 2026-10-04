-- Group-post soft delete, as an RPC.
--
-- WHY NOT a plain UPDATE from the client: every SELECT policy on
-- `group_posts` requires `deleted_at IS NULL`, so the moment the update sets
-- it the new row is no longer visible — and PostgREST's `.select()` (which
-- compiles to UPDATE … RETURNING) is then refused with
-- "new row violates row-level security policy". Verified: updating any other
-- column succeeds, updating deleted_at does not.
--
-- Dropping the `.select()` would work but reintroduces this project's worst
-- failure mode — an RLS refusal returning zero rows and no error, so a
-- blocked removal looks like a success. This RPC does the check itself and
-- returns a real boolean.
--
-- Authorisation is re-derived here, not trusted from the caller: the author,
-- a group admin, or a global moderator.

DROP FUNCTION IF EXISTS public.remove_group_post(uuid);

CREATE FUNCTION public.remove_group_post(p_post_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me      uuid;
  v_author  uuid;
  v_group   uuid;
  v_allowed boolean := false;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  SELECT gp.user_id, gp.group_id INTO v_author, v_group
    FROM public.group_posts gp
   WHERE gp.id = p_post_id AND gp.deleted_at IS NULL;

  IF v_author IS NULL THEN
    RETURN false;   -- already gone, or never existed
  END IF;

  v_allowed := (v_author = v_me)
    OR COALESCE(public.is_admin_or_global_mod(), false)
    OR EXISTS (
      SELECT 1 FROM public.group_members gm
       WHERE gm.group_id = v_group AND gm.user_id = v_me AND gm.role = 'admin'
    );

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'not allowed to remove this post';
  END IF;

  UPDATE public.group_posts SET deleted_at = now() WHERE id = p_post_id;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.remove_group_post(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_group_post(uuid) TO authenticated;
