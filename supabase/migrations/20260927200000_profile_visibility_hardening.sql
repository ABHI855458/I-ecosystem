-- Profile visibility hardening (2026-09-27).
--
-- User ask: "cross check the visibility of the posts — everyone can open
-- others' profiles but they can only see what is permitted to them".
--
-- 1. profile_posts_for_viewer: the 'community' branch (viewer shares a
--    community with the profile owner but is not in their Friends circle)
--    returned every Duo post tagged with that community WITHOUT checking the
--    audience the posters picked. So a post narrowed to, e.g., Close Friends
--    would show on the profile to any classmate. No live post had that shape
--    when this was checked, but nothing prevented one. Every non-self viewer
--    now goes through can_view_post(), the same gate the feeds use.
-- 2. us_album_photos_select: a mutual Duo photo was readable by a friend of
--    EITHER partner, ignoring the audience each partner picked for the post
--    it became (sync_us_album_post). If the photo has a live post, the photo
--    now follows that post's audience. Photos without a post keep the old
--    rule.

CREATE OR REPLACE FUNCTION public.profile_posts_for_viewer(p_profile uuid)
 RETURNS TABLE(id uuid, user_id uuid, content text, image_url text, photo_urls text[], photo_url_secondary text, inset_on_right boolean, visibility text, community_id uuid, community_name text, prompt text, post_type text, moment_color text, partner_user_id uuid, aspect_ratio text, photo_fit text, music_title text, music_artist text, music_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_state text; v_auth uuid := auth.uid();
BEGIN
  v_state := public.profile_access_state(p_profile);

  IF v_state = 'locked' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id, p.user_id, p.content, p.image_url, p.photo_urls,
         p.photo_url_secondary, COALESCE(p.inset_on_right, true),
         p.visibility,
         COALESCE(p.community_id, pa.community_id),
         COALESCE(c.name, ca.name),
         p.prompt, p.post_type, p.moment_color, p.partner_user_id,
         p.aspect_ratio, p.photo_fit,
         p.music_title, p.music_artist, p.music_url,
         (p.created_at AT TIME ZONE 'UTC')::timestamptz
  FROM public.posts p
  LEFT JOIN public.communities c ON c.id = p.community_id
  LEFT JOIN LATERAL (
    SELECT pa2.community_id FROM public.post_audiences pa2
     WHERE pa2.post_id = p.id AND pa2.audience_kind = 'community'
     LIMIT 1
  ) pa ON true
  LEFT JOIN public.communities ca ON ca.id = pa.community_id
  WHERE (p.user_id = p_profile OR p.partner_user_id = p_profile)
    AND p.deleted_at IS NULL
    AND p.visibility IN ('everyone','friends')
    AND p.post_type = 'us'
    AND (
      v_state = 'self'
      OR (v_state = 'friend' AND public.can_view_post(p.id))
      OR (
        v_state = 'community'
        AND COALESCE(p.community_id, pa.community_id) IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.community_members cm
           WHERE cm.community_id = COALESCE(p.community_id, pa.community_id)
             AND cm.user_id = v_auth
        )
        -- The audience the posters picked still applies.
        AND public.can_view_post(p.id)
      )
    )
  ORDER BY p.created_at DESC;
END;
$function$;

-- A mutual Duo photo is visible to the viewer iff its live post is (or, with
-- no post yet, the old friend-of-either rule).
CREATE OR REPLACE FUNCTION public.duo_photo_visible(p_photo uuid, p_album uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.posts p
                  WHERE p.us_album_photo_id = p_photo AND p.deleted_at IS NULL)
      THEN EXISTS (SELECT 1 FROM public.posts p
                    WHERE p.us_album_photo_id = p_photo AND p.deleted_at IS NULL
                      AND public.can_view_post(p.id))
    ELSE public.album_is_accepted_and_friend_of_either(p_album)
  END;
$function$;

DROP POLICY IF EXISTS us_album_photos_select ON public.us_album_photos;
CREATE POLICY us_album_photos_select ON public.us_album_photos
  FOR SELECT USING (
    (EXISTS (SELECT 1 FROM public.us_albums a
              WHERE a.id = us_album_photos.album_id
                AND auth.uid() IN (SELECT users.auth_id FROM public.users
                                    WHERE users.id = ANY (ARRAY[a.user_a, a.user_b]))))
    OR (visibility = 'mutual' AND public.duo_photo_visible(id, album_id))
  );

-- Used by the policy above, so signed-in users need it; signed-out never.
REVOKE EXECUTE ON FUNCTION public.duo_photo_visible(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duo_photo_visible(uuid, uuid) TO authenticated;
