-- Profile visibility is a FILTER keyed on relationship, not a locked wall.
--   friend                      -> every post, unfiltered
--   shares a REAL community     -> only posts in the shared communities
--   neither                     -> nothing (the only empty state)
--
-- "Real" excludes General: every account is auto-joined to it (7/7 members
-- live), so counting it would make 'locked' unreachable and would hand every
-- stranger a community-scoped slice of every profile.

CREATE OR REPLACE FUNCTION public.is_general_community(p_community uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1 FROM communities c
     WHERE c.id = p_community AND lower(trim(c.name)) = 'general'
  );
$$;

-- Overlap test that ignores General. Mirrors shares_community()'s id space:
-- community_members.user_id holds auth_id, not users.id.
CREATE OR REPLACE FUNCTION public.shares_real_community(p_a uuid, p_b uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM users ua
    JOIN community_members ma ON ma.user_id = ua.auth_id
    JOIN community_members mb ON mb.community_id = ma.community_id
    JOIN users ub ON ub.auth_id = mb.user_id
    JOIN communities c ON c.id = ma.community_id
    WHERE ua.id = p_a AND ub.id = p_b
      AND lower(trim(c.name)) <> 'general'
      AND c.deleted_at IS NULL
  );
$$;

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

  -- Friendship wins outright: no community filtering is applied at all.
  IF COALESCE(v_friend, false) THEN RETURN 'friend'; END IF;

  -- General deliberately does not count here.
  IF COALESCE(public.shares_real_community(v_me, p_profile), false) THEN RETURN 'community'; END IF;

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
DECLARE v_state text; v_auth uuid := auth.uid();
BEGIN
  v_state := public.profile_access_state(p_profile);

  IF v_state = 'locked' THEN
    RETURN;  -- the ONLY empty state
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
      -- self and friend: unfiltered, community_id irrelevant
      v_state IN ('self','friend')
      OR (
        -- community: ONLY the shared slice. No NULL-community posts, no
        -- General posts — neither "belongs to the shared community".
        v_state = 'community'
        AND p.community_id IS NOT NULL
        AND NOT public.is_general_community(p.community_id)
        AND EXISTS (
          SELECT 1 FROM public.community_members cm
           WHERE cm.community_id = p.community_id
             AND cm.user_id = v_auth
        )
      )
    )
  ORDER BY p.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.shares_real_community(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_general_community(uuid)        TO authenticated;
