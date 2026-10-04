-- Let someone who was SHOWN a group's post join that group from it.
-- Explicit request: "for group post as well give them option to accept to
-- the group, and wire it properly".
--
-- Needs a SECURITY DEFINER RPC: every INSERT policy on group_members
-- requires the caller to ALREADY be a member/admin/creator
-- (admin_add_members, member_add_members, group_members_insert_first_admin),
-- so a non-member has no self-join path at all today — members only ever
-- get added at creation time.
--
-- The gate is deliberately NOT "any group id you can name". It reuses
-- group_post_audience_feed's own visibility predicate: you may join a group
-- only if that group has actually shared a post into a surface you
-- qualified for — friends-of-the-poster, or a community you belong to.
-- Seeing the post is the invitation; nothing else is.
CREATE OR REPLACE FUNCTION public.join_group_from_shared_post(p_group_post_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_me    uuid;
  v_group uuid;
  v_ok    boolean;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;

  SELECT gp.group_id INTO v_group
    FROM public.group_posts gp
   WHERE gp.id = p_group_post_id AND gp.deleted_at IS NULL;

  IF v_group IS NULL THEN
    RAISE EXCEPTION 'That post is no longer available.';
  END IF;

  -- Already in it: succeed quietly rather than erroring, so a double tap
  -- (or a stale card) is a no-op instead of a scary failure toast.
  IF public.is_group_member(v_group, v_me) THEN
    RETURN false;
  END IF;

  -- Same two qualifying paths group_post_audience_feed uses.
  SELECT EXISTS (
    SELECT 1 FROM public.group_posts gp
    WHERE gp.id = p_group_post_id
      AND gp.deleted_at IS NULL
      AND (
        (
          EXISTS (SELECT 1 FROM public.group_post_audiences gpa
                   WHERE gpa.group_post_id = gp.id AND gpa.audience_kind = 'friends')
          AND EXISTS (SELECT 1 FROM public.friendships f
                       WHERE f.status = 'accepted'
                         AND ((f.requester_id = v_me AND f.addressee_id = gp.user_id)
                           OR (f.addressee_id = v_me AND f.requester_id = gp.user_id)))
        )
        OR EXISTS (
          SELECT 1 FROM public.group_post_audiences gpa
          JOIN public.community_members cm ON cm.community_id = gpa.community_id
          WHERE gpa.group_post_id = gp.id
            AND gpa.audience_kind = 'community'
            AND cm.user_id = auth.uid()
        )
      )
  ) INTO v_ok;

  IF NOT COALESCE(v_ok, false) THEN
    RAISE EXCEPTION 'This group post was not shared with you.';
  END IF;

  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group, v_me, 'member')
  ON CONFLICT DO NOTHING;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_group_from_shared_post(uuid) TO authenticated;
