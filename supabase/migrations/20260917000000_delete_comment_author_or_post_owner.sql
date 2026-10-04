-- Comment removal, for the two people who are entitled to it: the person
-- who wrote it, and the person who owns the post it sits under. Works the
-- same for a personal post (comments.post_id) and a group post
-- (comments.group_post_id), so every comment surface in the app -- friends
-- feed, anonymous feed, group feed/profile, Us Album -- gets one rule.
--
-- Soft delete, because comments_select already filters on deleted_at IS
-- NULL; a hard DELETE would also break the anonymous feed's counts, which
-- read the same rows.
--
-- SECURITY DEFINER: the table's own comments_delete_own policy covers only
-- the author, and adding a post-owner DELETE policy would let the owner
-- hard-delete rows. Routing through here keeps the delete soft and the
-- authorisation in one readable place.
CREATE OR REPLACE FUNCTION public.delete_comment(p_comment_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me        uuid;
  v_author    uuid;
  v_post      uuid;
  v_gpost     uuid;
  v_owner     uuid;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;

  SELECT c.user_id, c.post_id, c.group_post_id
    INTO v_author, v_post, v_gpost
    FROM public.comments c
   WHERE c.id = p_comment_id
     AND c.deleted_at IS NULL;

  -- Already gone, or never existed: a no-op rather than an error, so a
  -- double tap on Delete doesn't surface a scary message.
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_post IS NOT NULL THEN
    SELECT p.user_id INTO v_owner FROM public.posts p WHERE p.id = v_post;
  ELSIF v_gpost IS NOT NULL THEN
    SELECT gp.user_id INTO v_owner
      FROM public.group_posts gp WHERE gp.id = v_gpost;
  END IF;

  IF v_me <> COALESCE(v_author, '00000000-0000-0000-0000-000000000000'::uuid)
     AND v_me <> COALESCE(v_owner, '00000000-0000-0000-0000-000000000000'::uuid)
  THEN
    RAISE EXCEPTION 'You can only remove your own comment, or a comment on your own post.';
  END IF;

  UPDATE public.comments
     SET deleted_at = (now() AT TIME ZONE 'utc')
   WHERE id = p_comment_id;

  RETURN true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.delete_comment(uuid) TO authenticated;
