-- Widen the projection to everything FeedService._postItemFromRow reads, so
-- the client can build a FeedItem straight from this RPC instead of doing a
-- second unfiltered read of `posts` and narrowing on-device. The screen's
-- existing rule is that a viewer's device must never RECEIVE what it may not
-- see, so the filter has to stay server-side.
--
-- RETURNS TABLE is part of the signature, so this needs DROP + CREATE.
DROP FUNCTION IF EXISTS public.profile_posts_for_viewer(uuid);

CREATE FUNCTION public.profile_posts_for_viewer(p_profile uuid)
RETURNS TABLE(
  id uuid, user_id uuid, content text, image_url text, photo_urls text[],
  photo_url_secondary text, inset_on_right boolean,
  visibility text, community_id uuid, community_name text,
  prompt text, post_type text, moment_color text, partner_user_id uuid,
  aspect_ratio text, photo_fit text,
  music_title text, music_artist text, music_url text,
  created_at timestamptz
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_state text; v_auth uuid := auth.uid();
BEGIN
  v_state := public.profile_access_state(p_profile);

  IF v_state = 'locked' THEN
    RETURN;  -- the ONLY empty state
  END IF;

  RETURN QUERY
  SELECT p.id, p.user_id, p.content, p.image_url, p.photo_urls,
         p.photo_url_secondary, COALESCE(p.inset_on_right, true),
         p.visibility, p.community_id, c.name,
         p.prompt, p.post_type, p.moment_color, p.partner_user_id,
         p.aspect_ratio, p.photo_fit,
         p.music_title, p.music_artist, p.music_url,
         (p.created_at AT TIME ZONE 'UTC')::timestamptz
  FROM public.posts p
  LEFT JOIN public.communities c ON c.id = p.community_id
  WHERE p.user_id = p_profile
    AND p.deleted_at IS NULL
    -- Same exclusions the profile Posts tab already applies (fetchUserPosts):
    -- moments and memories have their own surfaces, anon has its own feed.
    AND p.visibility IN ('everyone','friends')
    AND p.post_type IS DISTINCT FROM 'moment'
    AND p.post_type IS DISTINCT FROM 'memory'
    AND (
      v_state IN ('self','friend')
      OR (
        v_state = 'community'
        AND p.community_id IS NOT NULL
        AND NOT public.is_general_community(p.community_id)
        AND EXISTS (
          SELECT 1 FROM public.community_members cm
           WHERE cm.community_id = p.community_id AND cm.user_id = v_auth
        )
      )
    )
  ORDER BY p.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_posts_for_viewer(uuid) TO authenticated;
