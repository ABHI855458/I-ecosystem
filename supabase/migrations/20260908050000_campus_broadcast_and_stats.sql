-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Campus broadcast + dashboard overview stats                        ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ═══ 1. BROADCAST TO EVERY USER ════════════════════════════════════════
-- "goes to all users irrespective of the community joined".
--
-- Deliberately NOT community_feed_items: that table's community_id is NOT
-- NULL, and the app fetches announcements one community at a time
-- (fetchPriorityItems(communityId)), so a row there can only ever reach that
-- community's members. Making it global would need a schema change AND an
-- app change.
--
-- A `posts` row with visibility='everyone' already reaches every signed-in
-- user through the feed they open by default — no app change at all — and
-- the notification below puts it on their notification screen too. That is
-- the honest way to say "everyone" in this schema.
--
-- Returns the new post id.

CREATE OR REPLACE FUNCTION public.broadcast_to_campus(
  p_body      text,
  p_image_url text DEFAULT NULL,
  p_notify    boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me   uuid;
  v_post uuid;
  v_n    integer;
BEGIN
  IF NOT public.is_admin_or_global_mod() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;

  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'This account has no app profile.';
  END IF;

  IF COALESCE(btrim(p_body),'') = '' AND p_image_url IS NULL THEN
    RAISE EXCEPTION 'Write something, or attach a photo.';
  END IF;

  INSERT INTO public.posts (user_id, content, image_url, visibility)
  VALUES (v_me, NULLIF(btrim(p_body),''), p_image_url, 'everyone')
  RETURNING id INTO v_post;

  IF p_notify THEN
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, post_id, tier, title, body, dedupe_key)
    SELECT u.id, 'announcement', v_me, v_post, 'major',
           'Campus announcement',
           left(COALESCE(btrim(p_body),'New announcement'), 140),
           'broadcast:' || v_post::text || ':' || u.id::text
      FROM public.users u
     WHERE u.auth_id IS NOT NULL AND u.id <> v_me
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'broadcast % -> % recipients', v_post, v_n;
  END IF;

  RETURN v_post;
END;
$function$;

REVOKE ALL ON FUNCTION public.broadcast_to_campus(text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.broadcast_to_campus(text,text,boolean) TO authenticated;


-- ═══ 2. OVERVIEW STATS ═════════════════════════════════════════════════
-- One round trip for the Home tab's summary, rather than a dozen counts
-- fired from the browser.

CREATE OR REPLACE FUNCTION public.dashboard_stats()
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r jsonb;
BEGIN
  IF NOT public.is_admin_or_global_mod() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;

  SELECT jsonb_build_object(
    'users',            (SELECT count(*) FROM users WHERE auth_id IS NOT NULL),
    'posts_total',      (SELECT count(*) FROM posts WHERE deleted_at IS NULL),
    'posts_anon',       (SELECT count(*) FROM posts WHERE deleted_at IS NULL AND visibility='anonymous'),
    'posts_today',      (SELECT count(*) FROM posts WHERE deleted_at IS NULL
                            AND created_at > (now() at time zone 'utc') - interval '24 hours'),
    'communities',      (SELECT count(*) FROM communities WHERE deleted_at IS NULL),
    'community_posts',  (SELECT count(*) FROM community_posts WHERE deleted_at IS NULL),
    'comments',         (SELECT count(*) FROM comments WHERE deleted_at IS NULL),
    'reactions',        (SELECT count(*) FROM post_realmoji_reactions),
    'pings',            (SELECT count(*) FROM pings),
    'groups',           (SELECT count(*) FROM groups),
    'announcements',    (SELECT count(*) FROM community_feed_items WHERE deleted_at IS NULL),
    'active_7d',        (SELECT count(DISTINCT user_id) FROM posts
                          WHERE created_at > (now() at time zone 'utc') - interval '7 days'),
    -- 14-day posting sparkline, oldest first.
    'daily', (
      SELECT COALESCE(jsonb_agg(x.n ORDER BY x.d), '[]'::jsonb) FROM (
        SELECT g.d::date AS d,
               (SELECT count(*) FROM posts p
                 WHERE p.deleted_at IS NULL AND p.created_at::date = g.d::date) AS n
          FROM generate_series(
                 ((now() at time zone 'utc')::date - 13),
                 (now() at time zone 'utc')::date, interval '1 day') g(d)
      ) x
    )
  ) INTO r;
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dashboard_stats() TO authenticated;
