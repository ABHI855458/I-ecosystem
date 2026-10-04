-- dashboard_stats: admit community moderators, scoped to their community.
-- Overview is their landing page too; rejecting them outright made it an
-- error screen rather than a dashboard.
CREATE OR REPLACE FUNCTION public.dashboard_stats()
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  r jsonb;
  v_scoped uuid;
BEGIN
  IF public.is_admin_or_global_mod() THEN
    v_scoped := NULL;
  ELSIF public.current_moderator_role() = 'community_moderator' THEN
    v_scoped := public.current_moderator_community_id();
    IF v_scoped IS NULL THEN RAISE EXCEPTION 'no community assigned'; END IF;
  ELSE
    RAISE EXCEPTION 'not authorised';
  END IF;

  SELECT jsonb_build_object(
    'scoped_community', v_scoped,
    'users', (SELECT count(*) FROM users u WHERE u.auth_id IS NOT NULL
               AND (v_scoped IS NULL OR EXISTS (
                 SELECT 1 FROM community_members m
                  WHERE m.community_id = v_scoped AND m.user_id = u.auth_id))),
    'posts_total', (SELECT count(*) FROM posts WHERE deleted_at IS NULL
                     AND (v_scoped IS NULL OR community_id = v_scoped)),
    'posts_anon', (SELECT count(*) FROM posts WHERE deleted_at IS NULL AND visibility='anonymous'
                    AND (v_scoped IS NULL OR community_id = v_scoped)),
    'posts_today', (SELECT count(*) FROM posts WHERE deleted_at IS NULL
                     AND created_at > (now() at time zone 'utc') - interval '24 hours'
                     AND (v_scoped IS NULL OR community_id = v_scoped)),
    'communities', (SELECT count(*) FROM communities WHERE deleted_at IS NULL
                     AND (v_scoped IS NULL OR id = v_scoped)),
    'community_posts', (SELECT count(*) FROM community_posts WHERE deleted_at IS NULL
                         AND (v_scoped IS NULL OR community_id = v_scoped)),
    'comments', (SELECT count(*) FROM comments c WHERE c.deleted_at IS NULL
                  AND (v_scoped IS NULL OR EXISTS (
                    SELECT 1 FROM posts p WHERE p.id = c.post_id AND p.community_id = v_scoped))),
    'reactions', (SELECT count(*) FROM post_realmoji_reactions r
                   WHERE (v_scoped IS NULL OR EXISTS (
                     SELECT 1 FROM posts p WHERE p.id = r.post_id AND p.community_id = v_scoped))),
    'pings', (SELECT CASE WHEN v_scoped IS NULL THEN count(*) ELSE 0 END FROM pings),
    'groups', (SELECT CASE WHEN v_scoped IS NULL THEN count(*) ELSE 0 END FROM groups),
    'announcements', (SELECT count(*) FROM community_feed_items WHERE deleted_at IS NULL
                       AND (v_scoped IS NULL OR community_id = v_scoped)),
    'active_7d', (SELECT count(DISTINCT user_id) FROM posts
                   WHERE created_at > (now() at time zone 'utc') - interval '7 days'
                     AND (v_scoped IS NULL OR community_id = v_scoped)),
    'daily', (
      SELECT COALESCE(jsonb_agg(x.n ORDER BY x.d), '[]'::jsonb) FROM (
        SELECT g.d::date AS d,
               (SELECT count(*) FROM posts p
                 WHERE p.deleted_at IS NULL AND p.created_at::date = g.d::date
                   AND (v_scoped IS NULL OR p.community_id = v_scoped)) AS n
          FROM generate_series(((now() at time zone 'utc')::date - 13),
                               (now() at time zone 'utc')::date, interval '1 day') g(d)
      ) x
    )
  ) INTO r;
  RETURN r;
END;
$function$;
