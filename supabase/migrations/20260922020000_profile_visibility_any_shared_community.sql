-- PROFILE VISIBILITY — any shared community counts, General included.
--
-- Explicit product decision, reversing an earlier one: shares_real_community
-- and profile_posts_for_viewer both special-cased General OUT ("General
-- deliberately does not count here") because everyone is auto-joined to it,
-- and counting it would make every profile browsable by every user.
--
-- Reported bug that changed this: a user saw a non-friend's post in their
-- FRIENDS feed via a shared community (friends_feed has no such exclusion),
-- opened that person's profile, and saw nothing — profile_access_state
-- returned 'locked' because their only shared community was General.
-- Confirmed live on real accounts:
--
--   shared_communities   = General
--   counts_as_community  = false  (before this migration)
--   are_friends          = false
--   -> profile showed LOCKED despite the post already being visible in-feed
--
-- Ruling: "not just general the communities the users are in common all
-- that matters" — ANY shared community should unlock the profile's
-- community-visible posts, matching what the viewer can already see of
-- that person in their own feed. The asymmetry (visible in feed, invisible
-- on profile) was the actual bug; which communities count was never really
-- the design intent, just an accidental side effect of the General
-- exclusion.
CREATE OR REPLACE FUNCTION public.shares_real_community(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM users ua
    JOIN community_members ma ON ma.user_id = ua.auth_id
    JOIN community_members mb ON mb.community_id = ma.community_id
    JOIN users ub ON ub.auth_id = mb.user_id
    JOIN communities c ON c.id = ma.community_id
    WHERE ua.id = p_a AND ub.id = p_b
      AND c.deleted_at IS NULL
  );
$function$;

-- profile_posts_for_viewer: drop the matching NOT is_general_community
-- clause so a 'community' viewer sees posts audienced to ANY community they
-- share with the profile owner, General included.
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
         p.visibility, p.community_id, c.name,
         p.prompt, p.post_type, p.moment_color, p.partner_user_id,
         p.aspect_ratio, p.photo_fit,
         p.music_title, p.music_artist, p.music_url,
         (p.created_at AT TIME ZONE 'UTC')::timestamptz
  FROM public.posts p
  LEFT JOIN public.communities c ON c.id = p.community_id
  WHERE p.user_id = p_profile
    AND p.deleted_at IS NULL
    AND p.visibility IN ('everyone','friends')
    AND p.post_type IS DISTINCT FROM 'moment'
    AND p.post_type IS DISTINCT FROM 'memory'
    AND (
      v_state IN ('self','friend')
      OR (
        v_state = 'community'
        AND p.community_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.community_members cm
           WHERE cm.community_id = p.community_id AND cm.user_id = v_auth
        )
      )
    )
  ORDER BY p.created_at DESC;
END;
$function$;
