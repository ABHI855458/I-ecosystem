-- Admin-only group management. Explicit request: "in group profiles give
-- option to rename the group and as well remove members, by the admin
-- only". Neither existed — a group's name was fixed at creation and the
-- only way out of a group was for the member to leave themselves.
--
-- Both gate on group_members.role = 'admin' via the existing
-- is_group_member(group, user, role) overload, so the check lives
-- server-side rather than in whatever UI happens to call it.

CREATE OR REPLACE FUNCTION public.rename_group(p_group_id uuid, p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid;
  v_name text;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.is_group_member(p_group_id, v_me, 'admin') THEN
    RAISE EXCEPTION 'Only an admin can rename this group.';
  END IF;

  v_name := btrim(coalesce(p_name, ''));
  IF length(v_name) = 0 THEN
    RAISE EXCEPTION 'A group needs a name.';
  END IF;
  IF length(v_name) > 60 THEN
    RAISE EXCEPTION 'That name is too long (60 characters max).';
  END IF;

  UPDATE public.groups SET name = v_name WHERE id = p_group_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_group_member(p_group_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid;
  v_admins int;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.is_group_member(p_group_id, v_me, 'admin') THEN
    RAISE EXCEPTION 'Only an admin can remove members.';
  END IF;
  IF p_user_id = v_me THEN
    -- Leaving is a different action with different consequences (it can
    -- empty the group); refuse rather than silently doing something else.
    RAISE EXCEPTION 'Use Leave group to remove yourself.';
  END IF;

  -- Never strand a group with no admin.
  SELECT count(*) INTO v_admins
    FROM public.group_members
   WHERE group_id = p_group_id AND role = 'admin' AND user_id <> p_user_id;
  IF v_admins = 0 THEN
    RAISE EXCEPTION 'That would leave the group without an admin.';
  END IF;

  DELETE FROM public.group_members
   WHERE group_id = p_group_id AND user_id = p_user_id;
END;
$function$;
