-- PROFILE POSTS — recognize post_audiences community shares, not just
-- posts.community_id.
--
-- The profile composer's audience picker (profile_v2_create_flows.dart,
-- see "cz he shared his post in the community" report) writes community
-- shares as post_audiences(audience_kind='community') rows with
-- posts.community_id left NULL — the exact same shape friends_feed and
-- can_view_post already handle. profile_posts_for_viewer never learned
-- that shape: it only ever checked p.community_id directly, so a
-- 'community' viewer could see the post in their friends feed (which DOES
-- read post_audiences) but got nothing on the profile itself.
--
-- Confirmed live: shreyasgalag has 3 posts shared via post_audiences to
-- General/RVCE with community_id NULL on the post row — all invisible to
-- profile_posts_for_viewer before this fix, all real per-community shares.
CREATE OR REPLACE FUNCTION public.profile_posts_for_viewer(p_profile uuid)
RETURNS TABLE(id uuid, user_id uuid, content text, image_url text, photo_urls text[], photo_url_secondary text, inset_on_right boolean, visibility text, community_id uuid, community_name text, prompt text, post_type text, moment_color text, partner_user_id uuid, aspect_ratio text, photo_fit text, music_title text, music_artist text, music_url text, created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER
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
         -- community_name/community_id now prefer the DIRECT column but
         -- fall back to the post_audiences share, so a shared-via-audience
         -- post still labels which community it was shared to.
         COALESCE(p.community_id, pa.community_id),
         COALESCE(c.name, ca.name),
         p.prompt, p.post_type, p.moment_color, p.partner_user_id,
         p.aspect_ratio, p.photo_fit,
         p.music_title, p.music_artist, p.music_url,
         (p.created_at AT TIME ZONE 'UTC')::timestamptz
  FROM public.posts p
  LEFT JOIN public.communities c ON c.id = p.community_id
  -- One community-audience row per post is all the UI ever writes today
  -- (single-community picker) — DISTINCT ON keeps this a plain LEFT JOIN
  -- even if that ever changes to allow more than one.
  LEFT JOIN LATERAL (
    SELECT pa2.community_id FROM public.post_audiences pa2
     WHERE pa2.post_id = p.id AND pa2.audience_kind = 'community'
     LIMIT 1
  ) pa ON true
  LEFT JOIN public.communities ca ON ca.id = pa.community_id
  WHERE p.user_id = p_profile
    AND p.deleted_at IS NULL
    AND p.visibility IN ('everyone','friends')
    AND p.post_type IS DISTINCT FROM 'moment'
    AND p.post_type IS DISTINCT FROM 'memory'
    AND (
      v_state IN ('self','friend')
      OR (
        v_state = 'community'
        AND COALESCE(p.community_id, pa.community_id) IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.community_members cm
           WHERE cm.community_id = COALESCE(p.community_id, pa.community_id)
             AND cm.user_id = v_auth
        )
      )
    )
  ORDER BY p.created_at DESC;
END;
$function$;
