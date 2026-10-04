-- Profile post visibility = community overlap, gated by friendship-or-overlap.
--
-- Rule implemented (stated explicitly because the request is compact):
--   * your own profile              -> every post
--   * friend OR shares >=1 community -> posts whose community YOU are also
--                                       in, plus posts with no community
--   * neither                       -> nothing; the client blurs and shows
--                                       "Be friends to view"
--
-- So friendship is the KEY that unlocks the profile; community overlap is
-- the FILTER that decides which posts appear once unlocked. A friend does
-- not see communities they aren't in.

CREATE OR REPLACE FUNCTION public.profile_access_state(p_profile uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_me uuid; v_friend boolean;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN RETURN 'locked'; END IF;
  IF v_me = p_profile THEN RETURN 'self'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.friendships f
     WHERE f.status = 'accepted'
       AND ((f.requester_id = v_me AND f.addressee_id = p_profile)
         OR (f.addressee_id = v_me AND f.requester_id = p_profile))
  ) INTO v_friend;

  IF COALESCE(v_friend, false) THEN RETURN 'friend'; END IF;
  IF COALESCE(public.shares_community(v_me, p_profile), false) THEN RETURN 'community'; END IF;
  RETURN 'locked';
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_posts_for_viewer(p_profile uuid)
RETURNS TABLE(
  id uuid, content text, image_url text, photo_urls text[],
  photo_url_secondary text, inset_on_right boolean,
  visibility text, community_id uuid, community_name text,
  prompt text, post_type text, aspect_ratio text, photo_fit text,
  created_at timestamptz
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_me uuid; v_state text;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  v_state := public.profile_access_state(p_profile);

  IF v_state = 'locked' THEN
    RETURN;  -- zero rows; the client renders the blurred "be friends" state
  END IF;

  RETURN QUERY
  SELECT p.id, p.content, p.image_url, p.photo_urls,
         p.photo_url_secondary, p.inset_on_right,
         p.visibility, p.community_id, c.name,
         p.prompt, p.post_type, p.aspect_ratio, p.photo_fit,
         (p.created_at AT TIME ZONE 'UTC')::timestamptz
  FROM public.posts p
  LEFT JOIN public.communities c ON c.id = p.community_id
  WHERE p.user_id = p_profile
    AND p.deleted_at IS NULL
    AND (
      v_state = 'self'
      OR p.community_id IS NULL                       -- general / everyone
      OR EXISTS (                                     -- viewer is in it too
        SELECT 1 FROM public.community_members cm
         WHERE cm.community_id = p.community_id AND cm.user_id = v_me
      )
    )
  ORDER BY p.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_access_state(uuid)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.profile_posts_for_viewer(uuid) TO authenticated;
