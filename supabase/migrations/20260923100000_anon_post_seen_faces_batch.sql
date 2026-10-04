-- The anon feed's "seen" chip was falling back to decorative dots on any
-- busy post because fetchAnonPostSeenFaces was still a per-post fan-out —
-- one RPC call PER POST on the page, all fired via Future.wait at once.
-- Each has an 8s timeout; past ~4 concurrent calls the rest started timing
-- out and failing soft to []. The engagement fetch got this exact same
-- batching treatment already (20260907120000_anon_feed_engagement_batch);
-- seen-faces never did, and this is why. Reported as "if more than 4 [seen]
-- it's not showing the dp in the pill".
--
-- One round trip for the whole page instead of one per post.
CREATE OR REPLACE FUNCTION public.anon_post_seen_faces_batch(
  p_post_ids uuid[],
  p_limit integer DEFAULT 3
)
RETURNS TABLE(post_id uuid, photo_url text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT pid AS post_id, faces.photo_url
  FROM unnest(p_post_ids) AS pid
  CROSS JOIN LATERAL (
    SELECT latest_per_viewer.photo_url
    FROM (
      SELECT DISTINCT ON (pv.viewer_id) ur.image_url AS photo_url, pv.created_at
      FROM public.post_views pv
      JOIN public.user_realmojis ur
        ON ur.user_id = pv.viewer_id AND ur.feed_scope = 'anonymous'
      WHERE pv.post_id = pid
      ORDER BY pv.viewer_id, pv.created_at DESC
    ) latest_per_viewer
    ORDER BY latest_per_viewer.created_at DESC
    LIMIT p_limit
  ) faces;
$function$;

GRANT EXECUTE ON FUNCTION public.anon_post_seen_faces_batch(uuid[], integer) TO authenticated;
