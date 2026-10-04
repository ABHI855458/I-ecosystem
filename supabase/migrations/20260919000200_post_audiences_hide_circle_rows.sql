-- A circle audience row named the circle to anyone who could see the post:
-- a silent member could read audience_kind='circle' plus the circle_id and
-- infer they were on a private list, which is exactly what circles promise
-- not to reveal. Circle rows are now readable ONLY by the post's author;
-- friends/community rows keep their existing visibility.
--
-- Safe for the app: no client code selects post_audiences (only the separate
-- group_post_audiences table is read), and can_view_post/friends_feed read it
-- as SECURITY DEFINER, so enforcement is unaffected.
DROP POLICY IF EXISTS post_audiences_select ON public.post_audiences;
CREATE POLICY post_audiences_select ON public.post_audiences FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.posts p
     WHERE p.id = post_audiences.post_id
       AND p.deleted_at IS NULL
       AND (p.visibility IS DISTINCT FROM 'anonymous'
            OR auth.uid() IN (SELECT users.auth_id FROM public.users WHERE users.id = p.user_id))
       AND (
         post_audiences.audience_kind <> 'circle'
         OR auth.uid() IN (SELECT users.auth_id FROM public.users WHERE users.id = p.user_id)
       )
  )
);
