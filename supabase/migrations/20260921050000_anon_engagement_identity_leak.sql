-- LAUNCH-BLOCKING: anon de-anonymization via comments.user_id / reactions.user_id.
--
-- THE BUG. post_engagement_visible(post_id) returns TRUE for an anonymous
-- post (that is intentional — the comment/reaction COUNTS and BODIES are
-- meant to be public on an anon post). But comments_select and
-- reactions_select gated on nothing else, so every row's `user_id` came
-- back too, and `users` is readable, so the real commenter/reactor behind
-- an anonymous post resolved to a real name and email.
--
-- post_realmoji_reactions_select ALREADY had the correct guard — it ANDs an
-- extra existence check that the post is not anonymous. This applies that
-- same, already-proven predicate to the two tables that missed it. It is not
-- a new rule; it is the existing rule applied consistently.
--
-- Impersonated probe (real authenticated user, third party, via posts_feed
-- which is how the client actually reaches anon posts):
--   BEFORE: comments_readable=1, path2_commenter_id=1, path4_resolves_to_user=1
--   AFTER (required): 0, 0, 0
-- (reactions showed 0 only because no anon reaction exists yet — the policy
-- gap was verified directly against pg_policies rather than inferred from
-- absent data, since "no rows" and "no leak" are indistinguishable.)
--
-- SELF-VISIBILITY. Restricting the SELECT would also hide a user's OWN
-- comment/reaction on an anon post. For comments that is already covered by
-- the existing `comments_select_own_or_moderator_always`. For reactions
-- there was NO own-select policy (verified: reactions has only
-- block_filter / select / insert_own / update_own / delete_own), so one is
-- added here, mirroring post_realmoji_reactions_select_own exactly. Without
-- it, users would silently lose their own reaction state on anon posts.
--
-- Both USING clauses below are reproduced VERBATIM from the live
-- pg_policies output; the ONLY change is the added `AND EXISTS (... IS
-- DISTINCT FROM 'anonymous')` on the post_id branch. The group_post_id
-- branch is untouched — group posts are never anonymous.

-- ---------------------------------------------------------------- comments
DROP POLICY IF EXISTS "comments_select" ON public.comments;
CREATE POLICY "comments_select" ON public.comments
FOR SELECT USING (
  (deleted_at IS NULL) AND (
    (
      (post_id IS NOT NULL)
      AND post_engagement_visible(post_id)
      -- THE FIX: never expose commenter identity on an anonymous post.
      AND (EXISTS (
        SELECT 1 FROM posts p
         WHERE p.id = comments.post_id
           AND p.visibility IS DISTINCT FROM 'anonymous'::text
      ))
    )
    OR (
      (group_post_id IS NOT NULL) AND (EXISTS (
        SELECT 1
          FROM ((group_posts gp
            JOIN group_members gm ON ((gm.group_id = gp.group_id)))
            JOIN users u ON ((u.id = gm.user_id)))
         WHERE ((gp.id = comments.group_post_id) AND (u.auth_id = auth.uid()))
      ))
    )
  )
);

-- --------------------------------------------------------------- reactions
DROP POLICY IF EXISTS "reactions_select" ON public.reactions;
CREATE POLICY "reactions_select" ON public.reactions
FOR SELECT USING (
  (
    (post_id IS NOT NULL)
    AND post_engagement_visible(post_id)
    -- THE FIX: never expose reactor identity on an anonymous post.
    AND (EXISTS (
      SELECT 1 FROM posts p
       WHERE p.id = reactions.post_id
         AND p.visibility IS DISTINCT FROM 'anonymous'::text
    ))
  )
  OR (EXISTS (
    SELECT 1
      FROM ((group_posts gp
        JOIN group_members gm ON ((gm.group_id = gp.group_id)))
        JOIN users u ON ((u.id = gm.user_id)))
     WHERE ((gp.id = reactions.group_post_id) AND (u.auth_id = auth.uid()))
  ))
);

-- Restores self-visibility lost to the clause above. Mirrors
-- post_realmoji_reactions_select_own verbatim.
DROP POLICY IF EXISTS "reactions_select_own" ON public.reactions;
CREATE POLICY "reactions_select_own" ON public.reactions
FOR SELECT USING (
  auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = reactions.user_id)
);
