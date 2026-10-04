-- unpin_person must return boolean (row actually deleted or not) — the
-- existing client (post_author_pin_service.dart's unpin()) already casts
-- the RPC result `as bool`. Folded into 20260907000000 on disk; this file
-- exists so the migration history matches exactly what ran live (the
-- return-type change required a DROP, which CREATE OR REPLACE can't do).
DROP FUNCTION IF EXISTS public.unpin_person(uuid);

CREATE FUNCTION public.unpin_person(p_pinned_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
BEGIN
  DELETE FROM pinned_people WHERE user_id = v_me AND pinned_user_id = p_pinned_user_id;
  RETURN FOUND;
END;
$function$;

REVOKE ALL ON FUNCTION public.unpin_person(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unpin_person(uuid) TO authenticated;
