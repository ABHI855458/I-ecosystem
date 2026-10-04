-- Post notifications: only from people in MY circles (explicit request, 2026-09-28):
--   "no need to notify anyone posts to friends feed ... if they receive a post
--    from a person who is in his friends list then only notify, or anyone from
--    close friend, family, or anyone in the joined group posts a thing".
--
-- 1. friend_post / moment_new_post: recipient R is notified about a post by P
--    only when R has P (or P's Duo partner) in one of R's OWN friends /
--    close_friends / family circles, AND R is in P's audience. Before, it
--    fanned out to everyone in P's Friends circle — one-way (see
--    in_friends_circle), so people who never added P heard about every post.
-- 2. community_post: no longer sent at all (both the posts-trigger branch and
--    the post_audiences trigger). Community posts still appear in feeds.
-- 3. group_post (notify_group_post): unchanged — joined-group posts still notify.
--
-- Audience caveat: post_audiences rows are written by a separate client
-- request AFTER the post row, so at trigger time a circle-narrowed post is
-- not yet narrowed. The check therefore uses the default audience
-- (in_friends_circle). friend_post is a batched, nameless "A friend posted"
-- with no post id, so a narrower post can at most over-count that badge.

CREATE OR REPLACE FUNCTION public.has_in_my_circles(p_owner uuid, p_member uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_member IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.circles c
      JOIN public.circle_members cm ON cm.circle_id = c.id
     WHERE c.creator_id = p_owner
       AND c.kind IN ('friends', 'close_friends', 'family')
       AND cm.member_id = p_member);
$function$;
-- Internal helper: no client access (security lockdown 2026-09-27 rule).
REVOKE ALL ON FUNCTION public.has_in_my_circles(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_post_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_day text; r record;
BEGIN
  IF NEW.deleted_at IS NOT NULL OR COALESCE(NEW.show_in_feed, true) IS NOT TRUE THEN
    RETURN NEW;
  END IF;
  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  -- Moments excluded — notify_moment_new_post_to_friends owns them.
  IF NEW.visibility <> 'anonymous' AND NEW.post_type IS DISTINCT FROM 'moment' THEN
    FOR r IN SELECT DISTINCT fcm.member_id AS uid
               FROM public.friends_circle_members fcm
              WHERE fcm.owner_id IN (NEW.user_id, NEW.partner_user_id)
                AND fcm.member_id NOT IN (NEW.user_id, COALESCE(NEW.partner_user_id, NEW.user_id))
                AND (public.has_in_my_circles(fcm.member_id, NEW.user_id)
                     OR public.has_in_my_circles(fcm.member_id, NEW.partner_user_id)) LOOP
      PERFORM public.notify_batched(r.uid, 'friend_post', 'minor',
        'friend_post:' || r.uid::text || ':' || v_day,
        'A friend posted', '%s friends posted today',
        jsonb_build_object('screen','feed'));
    END LOOP;
  END IF;
  RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION public.notify_moment_new_post_to_friends()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_name text;
BEGIN
  IF NEW.post_type IS DISTINCT FROM 'moment'
     OR NEW.visibility = 'anonymous' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(u.name), ''), 'Someone') INTO v_name
    FROM public.users u WHERE u.id = NEW.user_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  SELECT
    f.member_id,
    'moment_new_post', NEW.user_id, NEW.id, 'standard',
    v_name || ' just posted a Moment 🌅',
    'Reply with your own to unlock it before it''s gone',
    jsonb_build_object('screen', 'moment', 'post_id', NEW.id),
    'moment_new_post:' || NEW.id::text || ':' ||
      (f.member_id)::text
  FROM public.friends_circle_members f
  WHERE f.owner_id = NEW.user_id
    AND public.has_in_my_circles(f.member_id, NEW.user_id)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_community_audience_post ON public.post_audiences;
