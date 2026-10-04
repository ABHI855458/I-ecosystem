-- CORRECTION: the previous version's DISTINCT ON forced its own ORDER BY
-- viewer_id first, so the outer LIMIT picked 3 viewers by UUID order, not
-- by who viewed most recently. Wrapped so recency drives the LIMIT while
-- DISTINCT ON still collapses a viewer's repeat views to their latest one.
CREATE OR REPLACE FUNCTION public.anon_post_seen_faces(p_post_id uuid, p_limit int DEFAULT 3)
RETURNS TABLE(photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT photo_url FROM (
    SELECT DISTINCT ON (pv.viewer_id) ur.image_url AS photo_url, pv.created_at
    FROM public.post_views pv
    JOIN public.user_realmojis ur
      ON ur.user_id = pv.viewer_id AND ur.feed_scope = 'anonymous'
    WHERE pv.post_id = p_post_id
    ORDER BY pv.viewer_id, pv.created_at DESC
  ) latest_per_viewer
  ORDER BY created_at DESC
  LIMIT p_limit;
$$;
