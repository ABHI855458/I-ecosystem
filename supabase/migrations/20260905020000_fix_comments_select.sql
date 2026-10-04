-- ============================================================================
-- FIX comments_select — two live bugs found while wiring the anon comment
-- sheet to real data, both confirmed by direct introspection of the live
-- policy (not schema.sql, which is stale here):
--
-- 1. comments_select's anonymous-post branch requires
--    `auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)` — i.e.
--    only the POST'S OWN AUTHOR can read ANY comments on an anonymous post.
--    That was presumably meant to mirror posts_select's own rule, but
--    posts_feed (what the Anon feed actually queries) applies NO visibility
--    restriction — every authenticated user can see every anonymous post,
--    just with user_id masked. Comments should follow the same policy:
--    visible to everyone, identity masked separately (via
--    anonymous_comment_authors / post_thread_handles), not hidden outright.
--    As shipped, every comment on an anonymous post was invisible to
--    everyone except its author — the exact opposite of "anonymous", and a
--    silent-empty-list bug (RLS filters rows; there is no error).
--
-- 2. comments_select never had a group_post_id branch — it only checks
--    `comments.post_id`, so a comment with `group_post_id` set (post_id
--    NULL) can never match the EXISTS clause. Group-post comments have been
--    writable (CommentService.post) but NEVER READABLE by anyone, ever,
--    since the group_post_id column was added
--    (20260903030000_comments_group_post_id.sql) — confirmed live today.
-- ============================================================================

DROP POLICY IF EXISTS "comments_select" ON comments;

CREATE POLICY "comments_select" ON comments FOR SELECT USING (
  deleted_at IS NULL AND (
    (
      post_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM posts p WHERE p.id = comments.post_id AND p.deleted_at IS NULL
      )
    ) OR (
      group_post_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM group_posts gp
        JOIN group_members gm ON gm.group_id = gp.group_id
        JOIN users u ON u.id = gm.user_id
        WHERE gp.id = comments.group_post_id AND u.auth_id = auth.uid()
      )
    )
  )
);
