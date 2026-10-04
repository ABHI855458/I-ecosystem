-- ============================================================================
-- Make reactions and comments on ANONYMOUS posts readable.
--
-- Confirmed live 2026-09-04: reactions and comments on an anonymous post were
-- invisible to EVERYONE, including the person who wrote them. Writes
-- succeeded (both *_insert policies only check user_id ownership), reads
-- returned zero rows, and nothing ever raised — the app's standing
-- silent-empty-list failure mode. The anon feed therefore always showed 0
-- reactions and 0 comments no matter what anyone did.
--
-- WHY. Two SELECT policies exist on each table, and they are NOT both
-- permissive:
--     reactions_block_filter / comments_block_filter  -> RESTRICTIVE (AND'd)
--     reactions_select       / comments_select        -> PERMISSIVE  (the
--                                                        only thing granting)
-- Each permissive policy grants via `EXISTS (SELECT 1 FROM posts p WHERE
-- p.id = ...)`. That subquery is itself subject to `posts` RLS, and
-- posts_select restricts anonymous rows to their author:
--     visibility IS DISTINCT FROM 'anonymous'
--     OR auth.uid() IN (SELECT auth_id FROM users WHERE id = posts.user_id)
-- So for an anonymous post the EXISTS is false for every non-author, the
-- permissive policy grants nothing, and no row is returned. (The author
-- can't see them either, since a reactor is generally not the post's author.)
--
-- THE FIX. Resolve post visibility through a SECURITY DEFINER helper so the
-- lookup isn't re-filtered by posts_select — the same pattern this schema
-- already uses for exactly this class of problem (can_view_post,
-- is_community_member, get_group_wall). Anonymity is preserved: this only
-- says whether a post's ENGAGEMENT is readable. It exposes no user_id, and
-- the anon feed already shows every anonymous post to every signed-in user
-- through the `posts_feed` view (which bypasses posts_select the same way).
--
-- Deliberately NOT touched: the *_block_filter restrictive policies (blocking
-- still applies on top), the INSERT/UPDATE/DELETE policies, and the group
-- branch of each policy, which is reproduced verbatim below.
--
-- NOTE: applied via `supabase db query --linked -f`, not `db push` — this
-- project's live ledger is drifted. Same convention as
-- 20260909000000_ping_reply_selfie.sql.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.post_engagement_visible(p_post_id uuid)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.posts p
     WHERE p.id = p_post_id
       AND p.deleted_at IS NULL
       -- 'anonymous', 'everyone' and 'community' posts: engagement is as
       -- readable as the post is. 'friends' keeps its real audience gate,
       -- reusing the existing can_view_post rather than restating it.
       AND (p.visibility <> 'friends' OR public.can_view_post(p.id))
  );
$$;

REVOKE ALL ON FUNCTION public.post_engagement_visible(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_engagement_visible(uuid) TO authenticated;

-- ── reactions_select ────────────────────────────────────────────────────────
-- Was: EXISTS(posts p WHERE p.id = reactions.post_id AND (p.visibility IS
-- DISTINCT FROM 'friends' OR viewer is author)) OR <group branch>.
-- The friends gate is now can_view_post (via the helper), which is strictly
-- more correct: it also honours post_audiences, which the inline check
-- didn't.
DROP POLICY IF EXISTS "reactions_select" ON public.reactions;
CREATE POLICY "reactions_select" ON public.reactions FOR SELECT USING (
  (reactions.post_id IS NOT NULL
    AND public.post_engagement_visible(reactions.post_id))
  OR EXISTS (
    SELECT 1
      FROM public.group_posts gp
      JOIN public.group_members gm ON gm.group_id = gp.group_id
      JOIN public.users u ON u.id = gm.user_id
     WHERE gp.id = reactions.group_post_id
       AND u.auth_id = auth.uid()
  )
);

-- ── comments_select ─────────────────────────────────────────────────────────
-- Group branch reproduced verbatim; only the post branch changes.
DROP POLICY IF EXISTS "comments_select" ON public.comments;
CREATE POLICY "comments_select" ON public.comments FOR SELECT USING (
  comments.deleted_at IS NULL
  AND (
    (comments.post_id IS NOT NULL
      AND public.post_engagement_visible(comments.post_id))
    OR (comments.group_post_id IS NOT NULL AND EXISTS (
      SELECT 1
        FROM public.group_posts gp
        JOIN public.group_members gm ON gm.group_id = gp.group_id
        JOIN public.users u ON u.id = gm.user_id
       WHERE gp.id = comments.group_post_id
         AND u.auth_id = auth.uid()
    ))
  )
);
