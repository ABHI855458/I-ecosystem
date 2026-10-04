-- Duo: end it completely + edit only your own audience (2026-09-27).
--
-- User ask: "give an option to terminate the us album, delete it completely",
-- and on a Duo post's three-dot menu "edit their audience ... it doesn't
-- affect the other Duo user". (Group posts already had this per member via
-- share_group_post; the app now offers it to the post's author too.)
--
-- 1. end_duo(album): either partner ends the Duo at once, no second
--    confirmation (the old request/confirm handshake had no UI anywhere).
--    Deleting the album cascades to its photos and to the feed posts made
--    from them (FKs are ON DELETE CASCADE). The other partner is told.
--    Photo FILES stay in storage (unlisted, reachable only by exact URL);
--    storage objects can't be removed from SQL.
-- 2. my_duo_post_audience / set_my_duo_post_audience(post): read and rewrite
--    ONLY the caller's side of a Duo photo's audience (uploader_* if they
--    uploaded it, partner_* otherwise). sync_us_album_post then rebuilds the
--    post's audience as the union of both sides, so the partner's choice is
--    untouched. Empty circles = "my Friends circle", same as elsewhere.

ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['reaction'::text, 'ping'::text, 'branch_view'::text, 'us_album_mutual'::text, 'report_resolved'::text, 'report_filed'::text, 'announcement'::text, 'ping_answered'::text, 'us_album_invite'::text, 'comment'::text, 'moment_contribution'::text, 'group_added'::text, 'group_invite'::text, 'group_post'::text, 'group_dip'::text, 'community_post'::text, 'friend_post'::text, 'streak_risk_red'::text, 'streak_risk_blue'::text, 'streak_milestone_blue'::text, 'group_streak_ping'::text, 'group_streak_risk'::text, 'group_streak_broken'::text, 'level_up'::text, 'level_progress'::text, 'leaderboard_movement'::text, 'ping_unanswered'::text, 'group_ping_waiting'::text, 'group_ping_replied'::text, 'pinned_post_view'::text, 'pinned_group_post_view'::text, 'moment_new_post'::text, 'moment_reply_nudge'::text, 'pinned_profile_view'::text, 'rank_overtaken'::text, 'rank_regained'::text, 'streak_rank_overtaken'::text, 'start_streak_nudge'::text, 'streak_standing'::text, 'window_prompt'::text, 'break_live_count'::text, 'midday_report'::text, 'day_digest'::text, 'lifecycle_cooling'::text, 'lifecycle_lapsed'::text, 'lifecycle_dormant'::text, 'activation_nudge'::text, 'graduation'::text, 'ping_reply_liked'::text, 'us_album_accepted'::text, 'group_profile_view'::text, 'us_album_ended'::text])));

-- pings.source_post_id had no ON DELETE action, so any ping sent from a post
-- blocked deleting that post (found testing end_duo). A ping outlives the
-- post it came from; it just loses the link.
ALTER TABLE public.pings DROP CONSTRAINT pings_source_post_id_fkey;
ALTER TABLE public.pings ADD CONSTRAINT pings_source_post_id_fkey
  FOREIGN KEY (source_post_id) REFERENCES public.posts(id) ON DELETE SET NULL;

-- 1 -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.end_duo(p_album uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id(); v_album public.us_albums%ROWTYPE;
        v_other uuid; v_name text;
BEGIN
  SELECT * INTO v_album FROM public.us_albums WHERE id = p_album;
  IF v_album.id IS NULL OR v_me IS NULL OR v_me NOT IN (v_album.user_a, v_album.user_b) THEN
    RAISE EXCEPTION 'Duo not found';
  END IF;
  v_other := CASE WHEN v_album.user_a = v_me THEN v_album.user_b ELSE v_album.user_a END;

  DELETE FROM public.us_albums WHERE id = p_album;  -- cascades photos + posts

  IF v_album.status = 'accepted' AND v_other IS NOT NULL THEN
    SELECT COALESCE(NULLIF(btrim(name), ''), anon_name, 'Someone') INTO v_name
      FROM public.users WHERE id = v_me;
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    VALUES (v_other, 'us_album_ended', v_me, 'standard',
            v_name || ' ended your Duo 💔',
            jsonb_build_object('screen','profile'),
            'us_album_ended:' || p_album::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;
END $function$;

-- 2 -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_duo_post_audience(p_post uuid)
 RETURNS TABLE(circle_ids uuid[], community_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id(); v_photo public.us_album_photos%ROWTYPE;
        v_album public.us_albums%ROWTYPE;
BEGIN
  SELECT ph.* INTO v_photo FROM public.posts p
    JOIN public.us_album_photos ph ON ph.id = p.us_album_photo_id
   WHERE p.id = p_post AND p.deleted_at IS NULL;
  SELECT * INTO v_album FROM public.us_albums WHERE id = v_photo.album_id;
  IF v_photo.id IS NULL OR v_me IS NULL OR v_me NOT IN (v_album.user_a, v_album.user_b) THEN
    RAISE EXCEPTION 'Not your Duo post';
  END IF;
  IF v_me = v_photo.uploaded_by THEN
    RETURN QUERY SELECT v_photo.uploader_circle_ids, v_photo.uploader_community_ids;
  ELSE
    RETURN QUERY SELECT v_photo.partner_circle_ids, v_photo.partner_community_ids;
  END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.set_my_duo_post_audience(p_post uuid, p_circle_ids uuid[] DEFAULT '{}'::uuid[], p_community_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id(); v_photo public.us_album_photos%ROWTYPE;
        v_album public.us_albums%ROWTYPE; v_circles uuid[]; v_comms uuid[];
BEGIN
  SELECT ph.* INTO v_photo FROM public.posts p
    JOIN public.us_album_photos ph ON ph.id = p.us_album_photo_id
   WHERE p.id = p_post AND p.deleted_at IS NULL;
  SELECT * INTO v_album FROM public.us_albums WHERE id = v_photo.album_id;
  IF v_photo.id IS NULL OR v_me IS NULL OR v_me NOT IN (v_album.user_a, v_album.user_b) THEN
    RAISE EXCEPTION 'Not your Duo post';
  END IF;

  -- Only my own circles and communities I'm actually in.
  v_circles := ARRAY(SELECT c.id FROM public.circles c
                      WHERE c.id = ANY (COALESCE(p_circle_ids, '{}')) AND c.creator_id = v_me);
  v_comms := ARRAY(SELECT cm.community_id FROM public.community_members cm
                    WHERE cm.community_id = ANY (COALESCE(p_community_ids, '{}'))
                      AND cm.user_id = auth.uid());

  IF v_me = v_photo.uploaded_by THEN
    UPDATE public.us_album_photos
       SET uploader_circle_ids = v_circles, uploader_community_ids = v_comms
     WHERE id = v_photo.id;
  ELSE
    -- us_album_photos_guard only lets the partner side change inside this flag.
    PERFORM set_config('app.duo_approving', 'on', true);
    UPDATE public.us_album_photos
       SET partner_circle_ids = v_circles, partner_community_ids = v_comms
     WHERE id = v_photo.id;
    PERFORM set_config('app.duo_approving', 'off', true);
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public.end_duo(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.my_duo_post_audience(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_my_duo_post_audience(uuid, uuid[], uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_duo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_duo_post_audience(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_duo_post_audience(uuid, uuid[], uuid[]) TO authenticated;
