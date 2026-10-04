-- Community "message" posts: anonymous stays anonymous, docs-only allowed
-- (2026-09-27).
--
-- User ask: a WhatsApp-style message box on the community page; posting
-- anonymously shows the ANON name, otherwise the real name; photos or PDFs
-- attached under the message.
--
-- 1. LEAK FIXED: community_posts_select let every member read every row, and
--    the app's feed query embedded users(name, anon_name, profile_photo_url)
--    and user_id for ANONYMOUS posts too, so each member's phone received the
--    real author behind every anonymous post (the UI just didn't show it).
--    Members now read only named posts + their own; the feed comes from
--    community_posts_feed(), which masks anonymous authors (anon name + anon
--    avatar, no user_id) for everyone except the author. Moderators keep
--    full access via community_posts_select_own_or_moderator_always.
--    Trade-off: realtime needs row visibility, so OTHER people's anonymous
--    posts appear on the next refresh instead of instantly.
-- 2. community_posts_not_empty required text or a photo, so a PDF-only
--    message was refused. Dropped; the app requires text or any attachment.

DROP POLICY IF EXISTS community_posts_select ON public.community_posts;
CREATE POLICY community_posts_select ON public.community_posts
  FOR SELECT USING (
    deleted_at IS NULL
    AND is_community_member(community_id, auth.uid())
    AND (NOT is_anonymous
         OR user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()))
  );

ALTER TABLE public.community_posts DROP CONSTRAINT IF EXISTS community_posts_not_empty;

CREATE OR REPLACE FUNCTION public.community_posts_feed(
  p_community uuid, p_since timestamptz, p_limit int DEFAULT 30, p_offset int DEFAULT 0)
 RETURNS TABLE(id uuid, community_id uuid, user_id uuid, body text, photo_urls text[],
               is_anonymous boolean, created_at timestamptz, is_mine boolean,
               author_name text, author_photo text, documents jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id();
BEGIN
  IF v_me IS NULL OR NOT public.is_community_member(p_community, auth.uid()) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id, p.community_id,
         CASE WHEN p.is_anonymous AND p.user_id <> v_me THEN NULL ELSE p.user_id END,
         p.body, p.photo_urls, p.is_anonymous, p.created_at,
         (p.user_id = v_me),
         CASE WHEN p.is_anonymous
              THEN COALESCE(NULLIF(btrim(u.anon_name), ''), 'anonymous')
              ELSE COALESCE(NULLIF(btrim(u.name), ''), 'someone') END,
         CASE WHEN p.is_anonymous THEN u.anon_photo_url ELSE u.profile_photo_url END,
         COALESCE((SELECT jsonb_agg(jsonb_build_object(
                     'id', d.id, 'file_url', d.file_url, 'file_name', d.file_name,
                     'file_size', d.file_size, 'position', d.position) ORDER BY d.position)
                     FROM public.community_post_documents d
                    WHERE d.community_post_id = p.id), '[]'::jsonb)
    FROM public.community_posts p
    JOIN public.users u ON u.id = p.user_id
   WHERE p.community_id = p_community
     AND p.deleted_at IS NULL
     AND p.created_at > p_since
     -- same block rule the old policy had: blocks hide named posts only
     AND (p.is_anonymous OR NOT public.is_blocked_user(auth.uid(), p.user_id))
   ORDER BY p.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END $function$;

REVOKE EXECUTE ON FUNCTION public.community_posts_feed(uuid, timestamptz, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.community_posts_feed(uuid, timestamptz, int, int) TO authenticated;
