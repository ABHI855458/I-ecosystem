-- Group icon (DP) update, opened to ANY group member — explicit follow-up:
-- "anyone can change the dp". groups_update_admin (RLS) restricts UPDATE on
-- the `groups` table to admins/creator, which is right for renaming a
-- group but was also the only path uploadGroupIcon's caller had for
-- writing icon_url, so a non-admin member's upload silently failed
-- ("Only a group admin can change this group").
--
-- A narrow SECURITY DEFINER RPC touching ONLY icon_url, gated on plain
-- membership (any role) rather than widening groups_update_admin itself —
-- widening that policy would also open name/banner/created_by-adjacent
-- fields to every member, which was never asked for and changes who can
-- rename a group, a separate decision from who can change its photo.
CREATE OR REPLACE FUNCTION public.update_group_icon(p_group_id uuid, p_icon_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_me uuid;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;
  IF NOT public.is_group_member(p_group_id, v_me) THEN
    RAISE EXCEPTION 'Not a member of that group.';
  END IF;
  UPDATE public.groups
     SET icon_url = p_icon_url, updated_at = now()
   WHERE id = p_group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_group_icon(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_group_icon(uuid, text) TO authenticated;
