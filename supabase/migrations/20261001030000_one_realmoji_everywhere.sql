-- One RealMoji set for both feeds (explicit request, 2026-10-01: "both use
-- the same real emoji"). The app now reads and writes only the 'everyone'
-- scope; anon-feed faces read it too.

-- Anyone who only had an anon selfie for an emoji keeps it, as their one.
INSERT INTO public.user_realmojis (user_id, emoji_type, image_url, feed_scope, created_at)
SELECT a.user_id, a.emoji_type, a.image_url, 'everyone', a.created_at
  FROM public.user_realmojis a
 WHERE a.feed_scope = 'anonymous'
   AND NOT EXISTS (
     SELECT 1 FROM public.user_realmojis e
      WHERE e.user_id = a.user_id AND e.emoji_type = a.emoji_type
        AND e.feed_scope = 'everyone')
ON CONFLICT (user_id, feed_scope, emoji_type) DO NOTHING;

CREATE OR REPLACE FUNCTION public.anon_post_reaction_faces(p_post_id uuid)
 RETURNS TABLE(emoji_type text, image_url text, reacted_at timestamp with time zone)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.emoji_type::text, m.image_url, r.created_at
  from public.post_realmoji_reactions r
  left join public.user_realmojis m
    on m.user_id = r.user_id and m.feed_scope = 'everyone' and m.emoji_type = r.emoji_type
  where r.post_id = p_post_id and public.post_engagement_visible(p_post_id)
  order by r.created_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.anon_post_seen_faces(p_post_id uuid, p_limit integer DEFAULT 3)
 RETURNS TABLE(photo_url text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT photo_url FROM (
    SELECT DISTINCT ON (pv.viewer_id) ur.image_url AS photo_url, pv.created_at
    FROM public.post_views pv
    JOIN public.user_realmojis ur
      ON ur.user_id = pv.viewer_id AND ur.feed_scope = 'everyone'
    WHERE pv.post_id = p_post_id
    ORDER BY pv.viewer_id, pv.created_at DESC
  ) latest_per_viewer
  ORDER BY created_at DESC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.anon_post_seen_faces_batch(p_post_ids uuid[], p_limit integer DEFAULT 3)
 RETURNS TABLE(post_id uuid, photo_url text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT pid AS post_id, faces.photo_url
  FROM unnest(p_post_ids) AS pid
  CROSS JOIN LATERAL (
    SELECT latest_per_viewer.photo_url
    FROM (
      SELECT DISTINCT ON (pv.viewer_id) ur.image_url AS photo_url, pv.created_at
      FROM public.post_views pv
      JOIN public.user_realmojis ur
        ON ur.user_id = pv.viewer_id AND ur.feed_scope = 'everyone'
      WHERE pv.post_id = pid
      ORDER BY pv.viewer_id, pv.created_at DESC
    ) latest_per_viewer
    ORDER BY latest_per_viewer.created_at DESC
    LIMIT p_limit
  ) faces;
$function$;
