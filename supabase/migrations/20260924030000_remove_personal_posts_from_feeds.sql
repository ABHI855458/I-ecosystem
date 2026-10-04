-- ============================================================================
-- Personal posts (post_type='single' — PostService's own default for an
-- ordinary post; NOT null, verified against the live table) were removed as
-- a feature this session — the old "post as yourself"/Everyone destination.
-- No new ones can be created any more (FriendsPostScreen and the composer's
-- Everyone destination are both gone from the client). This migration stops
-- EXISTING rows of that shape from still surfacing:
--
--   * friends_feed()             — the main Friends-tab scrolling feed
--   * profile_posts_for_viewer() — someone else's profile "Posts" tab
--
-- Moments (post_type='moment') and Us Album posts (post_type='us') are
-- untouched in both — this is a narrowing, not a re-scope. The client-side
-- equivalents (FeedService.fetchUserPosts / fetchEveryoneFeed) were fixed in
-- the same pass, not here — see feed_service.dart.
-- ============================================================================

-- ── friends_feed — restrict post_type to an allow-list (moment, us) ────────
-- Every other clause is byte-for-byte unchanged from
-- 20260922040000_friends_feed_no_reacted_or_time_exclusion.sql.
CREATE OR REPLACE FUNCTION public.friends_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS SETOF posts
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid())
  select p.* from public.posts p
  where p.deleted_at is null
    and p.post_type in ('moment', 'us')
    and p.visibility in ('everyone', 'friends')
    and (
      case
        when p.post_type = 'moment' then p.created_at > now() - interval '24 hours'
        else true
      end
    )
    and (
      p.user_id = (select id from me)
      or
      (p.post_type = 'us' and (p.user_id = (select id from me)
                            or p.partner_user_id = (select id from me)))
      or
      exists (select 1 from public.friendships f
              where f.status = 'accepted'
                and ((f.requester_id = (select id from me) and f.addressee_id = p.user_id)
                  or (f.addressee_id = (select id from me) and f.requester_id = p.user_id)))
      or
      (p.partner_user_id is not null and exists (
         select 1 from public.friendships f
          where f.status = 'accepted'
            and ((f.requester_id = (select id from me) and f.addressee_id = p.partner_user_id)
              or (f.addressee_id = (select id from me) and f.requester_id = p.partner_user_id))))
      or
      exists (select 1 from public.post_audiences pa
              join public.community_members cm on cm.community_id = pa.community_id
              where pa.post_id = p.id
                and pa.audience_kind = 'community'
                and cm.user_id = auth.uid())
      or
      exists (select 1 from public.post_audiences pa
              join public.circle_members cm on cm.circle_id = pa.circle_id
              where pa.post_id = p.id
                and pa.audience_kind = 'circle'
                and cm.member_id = (select id from me))
    )
  order by (p.user_id = (select id from me)) desc, p.created_at desc
  limit p_limit offset p_offset;
$function$;

-- ── profile_posts_for_viewer — Posts tab now shows only Us Album posts ─────
-- Moments have their own tab (fetchMomentsFor), so this becomes 'us'-only,
-- matching FeedService.fetchUserPosts's own-profile equivalent. Every other
-- clause is byte-for-byte unchanged from 20260924010000_us_album_post_composer.sql.
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
