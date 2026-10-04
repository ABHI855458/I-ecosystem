-- "Attach real DP to the top 2-3 seen-dots" on an ANONYMOUS post.
--
-- This is NOT the same request as the reaction-face fix earlier — a
-- reaction is a voluntary act the reactor chose to attach their anon
-- persona to; VIEWING is passive (recordView fires on scroll, no consent
-- gesture). post_views.viewer_id is a real, raw user id — returning it, or
-- their real profile_photo_url, to the anon post's author would let them
-- see the actual faces of everyone who merely scrolled past their
-- anonymous post. That is a strictly worse leak than the "who pinned who"
-- one already audited this session, on the app's own anonymity feature.
--
-- So this mirrors the EXISTING, already-shipped precedent for exactly this
-- shape of problem: _OnPhotoReactionStack's real-reactor-photos, which are
-- deliberately "identity-free" (the reactor's own chosen anon-scope
-- RealMoji selfie, never their name or real photo). Applied here the same
-- way: a viewer contributes a face ONLY if they have saved a
-- feed_scope='anonymous' RealMoji selfie (an affirmative choice to have an
-- anon-feed face at all), and only that selfie is returned — never
-- viewer_id, never profile_photo_url, never anon_name.
--
-- A viewer with no anon selfie saved contributes nothing (same fallback
-- shape the reaction stack already uses: decorative dot instead).
CREATE OR REPLACE FUNCTION public.anon_post_seen_faces(p_post_id uuid, p_limit int DEFAULT 3)
RETURNS TABLE(photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
  SELECT DISTINCT ON (pv.viewer_id) ur.image_url
  FROM public.post_views pv
  JOIN public.user_realmojis ur
    ON ur.user_id = pv.viewer_id AND ur.feed_scope = 'anonymous'
  WHERE pv.post_id = p_post_id
  ORDER BY pv.viewer_id, pv.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.anon_post_seen_faces(uuid, int) TO authenticated;
