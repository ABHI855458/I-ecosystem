-- "Is this post mine?" — one call, either kind of post, so a comment
-- surface can decide whether to offer Remove on somebody else's comment
-- without every call site having to thread an ownership flag down to it.
-- Returns a plain boolean and nothing else, so it leaks no identity on an
-- anonymous post.
CREATE OR REPLACE FUNCTION public.i_own_post(
  p_post_id uuid DEFAULT NULL,
  p_group_post_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN public.current_user_id() IS NULL THEN false
    WHEN p_post_id IS NOT NULL THEN EXISTS (
      SELECT 1 FROM public.posts p
       WHERE p.id = p_post_id AND p.user_id = public.current_user_id()
    )
    WHEN p_group_post_id IS NOT NULL THEN EXISTS (
      SELECT 1 FROM public.group_posts gp
       WHERE gp.id = p_group_post_id AND gp.user_id = public.current_user_id()
    )
    ELSE false
  END;
$function$;

GRANT EXECUTE ON FUNCTION public.i_own_post(uuid, uuid) TO authenticated;
