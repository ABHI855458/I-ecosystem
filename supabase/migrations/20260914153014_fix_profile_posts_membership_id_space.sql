-- CORRECTION: community_members.user_id holds auth_id (it FKs to profiles,
-- whose id = users.auth_id), NOT users.id. Verified on live data: joining
-- profiles.id to users.id matches 0 rows, to users.auth_id matches all 7.
-- The previous version compared cm.user_id to users.id, which is always
-- false — it would have hidden every community post from every viewer,
-- including on profiles they had full access to.
--
-- shares_community() already does this correctly (ma.user_id = ua.auth_id);
-- this brings the post filter into the same id space by using auth.uid()
-- directly, since the caller IS the viewer.

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
    RETURN;  -- zero rows; client renders the blurred "Be friends to view" state
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
      OR p.community_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.community_members cm
         WHERE cm.community_id = p.community_id
           AND cm.user_id = v_auth      -- auth_id space, not users.id
      )
    )
  ORDER BY p.created_at DESC;
END;
$$;
