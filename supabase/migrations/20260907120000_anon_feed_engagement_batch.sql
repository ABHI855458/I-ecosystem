-- ============================================================================
-- anon_feed_engagement(uuid[]) — one round trip for a whole page of the Anon
-- feed's reaction/comment data.
--
-- WHY: _hydrateCounts fired anon_reaction_counts + my-reaction + comment-count
-- (+ reaction faces when non-zero) PER POST. A 20-post page is 60-80 requests,
-- and the client already had to throttle itself to 4 at a time to stop
-- saturating the connection and timing out — so a page finished hydrating
-- ~15-20 sequential waves after it appeared. That is the "all the pages are
-- loading too much" the cards' skeletons were showing.
--
-- This is the batch the feed's own TODO asked for. It changes no schema and no
-- visibility rule: the same post_engagement_visible() gate that
-- anon_post_reaction_faces applies is applied here, per post, so a post the
-- caller may not see engagement for returns empty counts exactly as before.
--
-- Applied via `supabase db query --linked -f` (this project's ledger is
-- drifted; db push is not used).
-- ============================================================================

DROP FUNCTION IF EXISTS public.anon_feed_engagement(uuid[]);

CREATE FUNCTION public.anon_feed_engagement(p_post_ids uuid[])
 RETURNS TABLE(
   post_id       uuid,
   comment_count integer,
   my_reaction   text,
   counts        jsonb,
   faces         jsonb
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me UUID;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH ids AS (
    -- DISTINCT so a duplicated id in the page can't produce two rows for
    -- the same post and have the client apply whichever landed last.
    SELECT DISTINCT unnest(p_post_ids) AS id
  ),
  vis AS (
    SELECT i.id, public.post_engagement_visible(i.id) AS ok FROM ids i
  ),
  cmt AS (
    SELECT c.post_id AS id, COUNT(*)::int AS n
      FROM public.comments c
      JOIN vis v ON v.id = c.post_id AND v.ok
     WHERE c.deleted_at IS NULL
     GROUP BY c.post_id
  ),
  mine AS (
    SELECT DISTINCT ON (r.post_id) r.post_id AS id, r.emoji_type::text AS emoji
      FROM public.post_realmoji_reactions r
      JOIN ids i ON i.id = r.post_id
     WHERE r.user_id = v_me
     ORDER BY r.post_id, r.created_at DESC
  ),
  cnt AS (
    SELECT a.post_id AS id,
           jsonb_agg(
             jsonb_build_object('emoji_type', a.emoji_type, 'count', a.count)
             ORDER BY a.count DESC
           ) AS j
      FROM public.anon_reaction_counts a
      JOIN vis v ON v.id = a.post_id AND v.ok
     GROUP BY a.post_id
  ),
  fc AS (
    SELECT r.post_id AS id,
           jsonb_agg(
             jsonb_build_object('emoji_type', r.emoji_type, 'image_url', m.image_url)
             ORDER BY r.created_at DESC
           ) AS j
      FROM public.post_realmoji_reactions r
      JOIN vis v ON v.id = r.post_id AND v.ok
      LEFT JOIN public.user_realmojis m
             ON m.user_id = r.user_id
            AND m.feed_scope = 'anonymous'
            AND m.emoji_type = r.emoji_type
     GROUP BY r.post_id
  )
  SELECT i.id,
         COALESCE(cmt.n, 0),
         mine.emoji,
         COALESCE(cnt.j, '[]'::jsonb),
         COALESCE(fc.j, '[]'::jsonb)
    FROM ids i
    LEFT JOIN cmt  ON cmt.id  = i.id
    LEFT JOIN mine ON mine.id = i.id
    LEFT JOIN cnt  ON cnt.id  = i.id
    LEFT JOIN fc   ON fc.id   = i.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.anon_feed_engagement(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.anon_feed_engagement(uuid[]) TO authenticated;
