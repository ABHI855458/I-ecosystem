-- ============================================================================
-- Group pings + the Blurred Group Teaser, corrected.
--
-- 1. PING RULE — a group only its creator has joined cannot be pinged.
--    Supersedes 20260926040000_group_ping_includes_invitees.sql: invitees
--    are pinged only after they accept. Keeps the log_score_event receipt
--    from 20260926000000_group_ping_sent_score_event.sql.
--
-- 2. PRIVATE GROUPS — non-members in the group's community get a teaser:
--    first photo clear and the rest blurred; a ONE-photo post is teased too,
--    with that photo blurred client-side. The previous version (a) teased
--    PUBLIC groups as well, whose "Join" sheet then failed for every private
--    group it also showed, and (b) silently dropped posts whose photos were
--    only in photo_url (cardinality(NULL) is NULL).
--    The instant any member shares the post with the viewer
--    (group_post_audience_admits), it leaves the teaser and arrives in full
--    through group_post_audience_feed — once.
--
-- 3. PUBLIC GROUPS — every post is fully visible to members of the group's
--    community: in the feed (group_post_audience_feed) and on the group's
--    own profile (RLS on group_posts / groups / group_members).
--
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================

BEGIN;

-- 1 -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_group_ping(p_group_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5, p_photo_url text DEFAULT NULL::text)
 RETURNS TABLE(thread_id uuid, recipients integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me UUID;
  v_thread UUID;
  v_label TEXT;
  v_n INT;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.is_group_member(p_group_id, v_me) THEN
    RAISE EXCEPTION 'Not a member of that group.';
  END IF;

  -- A group only you have joined can't be pinged: invitees are pinged
  -- once they ACCEPT, not before (explicit rule). Checked up front so no
  -- thread is opened and nothing counts toward the 5/24h limit.
  IF NOT EXISTS (SELECT 1 FROM public.group_members gm
                  WHERE gm.group_id = p_group_id AND gm.user_id <> v_me) THEN
    RAISE EXCEPTION 'Waiting for members to join this group.';
  END IF;

  IF p_anonymous THEN
    v_label := public.gen_handle();
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, group_id, prompt, anonymous, anon_display_name, window_hours, photo_url)
  VALUES (v_me, 'group', p_group_id, p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, group_id, prompt, anonymous, window_hours, photo_url)
  SELECT v_thread, v_me, gm.user_id, p_group_id, p_prompt, p_anonymous, p_window_hours, p_photo_url
    FROM public.group_members gm
   WHERE gm.group_id = p_group_id
     -- gm.user_id is users.id (verified live — matches users.id, not
     -- auth_id), which is exactly is_blocked_user's target_user_id shape.
     AND NOT public.is_blocked_user(auth.uid(), gm.user_id);

  SELECT count(*) INTO v_n
    FROM public.pings pp WHERE pp.thread_id = v_thread AND pp.receiver_id <> v_me;

  IF v_n = 0 THEN
    DELETE FROM public.ping_threads WHERE id = v_thread;
    DELETE FROM public.pings WHERE pings.thread_id = v_thread;
    RETURN QUERY SELECT NULL::UUID, 0;
    RETURN;
  END IF;

  UPDATE public.users SET ping_score = ping_score + 25 WHERE id = v_me;
  -- THE FIX: the one line this migration adds. Same call, same event_type,
  -- same amount as the 1:1 trigger — this is the receipt for an award that
  -- was already happening, not a new award.
  PERFORM public.log_score_event(v_me, 'ping_sent', 25);
  PERFORM public.open_group_ping_day(p_group_id, v_thread);

  RETURN QUERY SELECT v_thread, v_n;
END;
$function$;

-- 2 -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.group_posts_teaser_for_community(p_community_id uuid)
 RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, cover_photo_url text, hidden_photo_count integer, caption text, created_at timestamp with time zone)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT id FROM public.users WHERE auth_id = auth.uid()),
  src AS (
    SELECT gp.*, g.name AS gname, g.icon_url AS gicon,
           CASE WHEN cardinality(gp.photo_urls) > 0 THEN gp.photo_urls
                WHEN gp.photo_url IS NOT NULL THEN ARRAY[gp.photo_url]
                ELSE '{}'::text[] END AS photos
      FROM public.group_posts gp
      JOIN public.groups g ON g.id = gp.group_id
     WHERE gp.deleted_at IS NULL
       AND g.community_id = p_community_id
       -- Private groups only: a public group's posts are shown in full.
       AND COALESCE(g.visibility, 'private') <> 'public'
  )
  SELECT s.id, s.group_id, s.gname, s.gicon,
         s.photos[1] AS cover_photo_url,
         -- 0 = a one-photo post; the client blurs the cover itself then.
         GREATEST(cardinality(s.photos) - 1, 0) AS hidden_photo_count,
         s.caption, s.created_at
    FROM src s
   WHERE cardinality(s.photos) >= 1
     AND public.is_community_member(p_community_id, auth.uid())
     AND NOT public.is_blocked_user(auth.uid(), s.user_id)
     AND NOT EXISTS (SELECT 1 FROM public.group_members gm
                      WHERE gm.group_id = s.group_id AND gm.user_id = (SELECT id FROM me))
     -- Shared with me by any member -> I see it in full elsewhere, not here.
     AND NOT public.group_post_audience_admits(s.id, s.user_id)
   ORDER BY s.created_at DESC;
$function$;

-- 3 -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_public_group_in_my_community(p_group uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.groups g
     WHERE g.id = p_group AND g.visibility = 'public' AND g.community_id IS NOT NULL
       AND public.is_community_member(g.community_id, auth.uid())
  );
$$;
REVOKE ALL ON FUNCTION public.is_public_group_in_my_community(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_public_group_in_my_community(uuid) TO authenticated;

DROP POLICY IF EXISTS group_posts_select_public_community ON public.group_posts;
CREATE POLICY group_posts_select_public_community ON public.group_posts FOR SELECT
  USING (deleted_at IS NULL AND public.is_public_group_in_my_community(group_id));

DROP POLICY IF EXISTS groups_select_public_community ON public.groups;
CREATE POLICY groups_select_public_community ON public.groups FOR SELECT
  USING (public.is_public_group_in_my_community(id));

DROP POLICY IF EXISTS group_members_select_public_community ON public.group_members;
CREATE POLICY group_members_select_public_community ON public.group_members FOR SELECT
  USING (public.is_public_group_in_my_community(group_id));

-- Feed: shared-with-me posts OR any post of a public group in my community.
-- Still one row per group post however many paths admit it.
CREATE OR REPLACE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone, aspect_ratio text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid())
  select gp.id, gp.group_id, g.name, g.icon_url, gp.user_id, u.username, u.name,
         u.profile_photo_url, gp.caption, gp.photo_url, gp.photo_urls,
         gp.created_at, gp.aspect_ratio
  from public.group_posts gp
  join public.groups g on g.id = gp.group_id
  join public.users u on u.id = gp.user_id
  where gp.user_id <> (select id from me)
    and gp.deleted_at is null
    and not public.is_blocked_user(auth.uid(), gp.user_id)
    and (
      public.group_post_audience_admits(gp.id, gp.user_id)
      or public.is_public_group_in_my_community(gp.group_id)
    )
  order by gp.created_at desc
  limit p_limit offset p_offset;
$function$;

COMMIT;
