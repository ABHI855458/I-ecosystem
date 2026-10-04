-- Block the author of an ANONYMOUS community post without learning who they
-- are (2026-09-27).
--
-- User ask: three dots on community posts to report or block that user.
-- Named posts could already be blocked; anonymous ones couldn't (the app
-- never has their author id, by design, see community_posts_feed).
--
-- * anon_blocks: blocks made from an anonymous post. NO client access at all:
--   a normal `blocks` row would put the author's id in the blocker's own
--   "Blocked users" list, which reads names from it, and that would unmask
--   the anonymous poster.
-- * is_blocked_user() counts anon_blocks too (both directions), so every
--   place that already honours blocks honours these.
-- * block_community_post_author(post): blocks the post's author: a normal
--   block for a named post, an anon block for an anonymous one.
-- * my_anon_blocks() / unblock_anon(id): list ("Anonymous poster", never a
--   name) and undo, for the Blocked users screen.
-- * community_posts_feed now hides blocked authors' anonymous posts too (it
--   exempted them before, since an anonymous author couldn't be blocked).

CREATE TABLE IF NOT EXISTS public.anon_blocks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
ALTER TABLE public.anon_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.anon_blocks FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_blocked_user(viewer_auth uuid, target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.blocks b
    JOIN public.users u ON u.id = target_user_id
    WHERE (b.blocker_id = viewer_auth AND b.blocked_id = u.auth_id)
       OR (b.blocker_id = u.auth_id  AND b.blocked_id = viewer_auth)
  ) OR EXISTS (
    SELECT 1 FROM public.anon_blocks ab
    JOIN public.users u ON u.id = target_user_id
    WHERE (ab.blocker_id = viewer_auth AND ab.blocked_id = u.auth_id)
       OR (ab.blocker_id = u.auth_id  AND ab.blocked_id = viewer_auth)
  );
$function$;

CREATE OR REPLACE FUNCTION public.block_community_post_author(p_post uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_author_auth uuid; v_anon boolean; v_community uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  SELECT u.auth_id, p.is_anonymous, p.community_id
    INTO v_author_auth, v_anon, v_community
    FROM public.community_posts p JOIN public.users u ON u.id = p.user_id
   WHERE p.id = p_post AND p.deleted_at IS NULL;
  -- Only a post the caller could actually see.
  IF v_author_auth IS NULL OR NOT public.is_community_member(v_community, auth.uid()) THEN
    RAISE EXCEPTION 'Post not found';
  END IF;
  IF v_author_auth = auth.uid() THEN
    RAISE EXCEPTION 'You cannot block yourself';
  END IF;
  IF v_anon THEN
    INSERT INTO public.anon_blocks (blocker_id, blocked_id)
    VALUES (auth.uid(), v_author_auth)
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING;
  ELSE
    INSERT INTO public.blocks (blocker_id, blocked_id)
    VALUES (auth.uid(), v_author_auth)
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING;
  END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.my_anon_blocks()
 RETURNS TABLE(id uuid, created_at timestamptz)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ab.id, ab.created_at FROM public.anon_blocks ab
   WHERE ab.blocker_id = auth.uid()
   ORDER BY ab.created_at DESC;
$function$;

CREATE OR REPLACE FUNCTION public.unblock_anon(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  DELETE FROM public.anon_blocks WHERE id = p_id AND blocker_id = auth.uid();
$function$;

REVOKE EXECUTE ON FUNCTION public.block_community_post_author(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.my_anon_blocks() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.unblock_anon(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.block_community_post_author(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_anon_blocks() TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_anon(uuid) TO authenticated;

-- Feed: blocked authors' anonymous posts are hidden too now.
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
     AND (p.user_id = v_me OR NOT public.is_blocked_user(auth.uid(), p.user_id))
   ORDER BY p.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END $function$;
