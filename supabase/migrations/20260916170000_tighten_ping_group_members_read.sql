-- `ping_group_members` was world-readable: its only SELECT policy was
-- USING (true), so any authenticated user could read every
-- (group_id, user_id) row and reconstruct who had grouped whom — including
-- for groups they neither own nor belong to.
--
-- Found during an audit of "can anyone learn who pinned/grouped who". The
-- table is currently EMPTY and nothing in the app reads it (the live ping
-- grouping is `groups`/`group_members`), so this is latent rather than an
-- active breach — but a policy that leaks the moment the feature ships is
-- worth closing now.
--
-- BOTH sides of the check go through SECURITY DEFINER helpers, and that is
-- load-bearing. An inline `EXISTS (SELECT 1 FROM ping_group_members ...)`
-- recurses into this same policy; and an inline read of `ping_groups`
-- recurses too, because ping_groups' own pg_read policy contains an EXISTS
-- over ping_group_members. A definer function runs as the table owner and
-- so does not re-trigger RLS, which breaks both cycles. Verified: a
-- stranger sees 0 of a planted row, the group's owner sees it.
CREATE OR REPLACE FUNCTION public.is_ping_group_member(p_group_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.ping_group_members
     WHERE group_id = p_group_id AND user_id = p_user_id
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_ping_group_owner(p_group_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.ping_groups
     WHERE id = p_group_id AND owner_id = p_user_id
  );
$function$;

DROP POLICY IF EXISTS pgm_read ON public.ping_group_members;
CREATE POLICY pgm_read ON public.ping_group_members
  FOR SELECT USING (
    user_id = auth.uid()
    OR public.is_ping_group_owner(ping_group_members.group_id, auth.uid())
    OR public.is_ping_group_member(ping_group_members.group_id, auth.uid())
  );
