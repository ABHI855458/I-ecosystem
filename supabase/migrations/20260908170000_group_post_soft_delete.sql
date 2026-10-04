-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Group posts: real soft delete                                       ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- CORRECTION to an earlier claim of mine: `group_posts.deleted_at` DOES
-- exist, and all three SELECT policies already filter it. The audit note
-- saying otherwise was carried over from a stale plan file and was wrong.
--
-- What is actually broken:
--
--   1. GroupService.deletePost does a HARD `.delete()`. That destroys the
--      row, so comments and reactions pointing at it are orphaned — every
--      other surface in this app soft-deletes for exactly that reason.
--
--   2. Only `group_posts_update_moderator` (admin/global mod) can UPDATE,
--      so an AUTHOR has no way to set deleted_at on their own post. They
--      could only hard-delete it.
--
-- This adds the author's UPDATE path. The moderator policy is left alone.

DROP POLICY IF EXISTS "group_posts_update_own" ON public.group_posts;
CREATE POLICY "group_posts_update_own" ON public.group_posts
FOR UPDATE USING (
  user_id IN (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
) WITH CHECK (
  user_id IN (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
);

-- Group admins can take down a member's post in their own group — the same
-- authority they already have to remove the member.
DROP POLICY IF EXISTS "group_posts_update_group_admin" ON public.group_posts;
CREATE POLICY "group_posts_update_group_admin" ON public.group_posts
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.group_members gm
      JOIN public.users u ON u.id = gm.user_id
     WHERE gm.group_id = group_posts.group_id
       AND gm.role = 'admin'
       AND u.auth_id = auth.uid()
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.group_members gm
      JOIN public.users u ON u.id = gm.user_id
     WHERE gm.group_id = group_posts.group_id
       AND gm.role = 'admin'
       AND u.auth_id = auth.uid()
  )
);
