-- ============================================================================
-- A2: reactions to a 'friends'-visibility ("personal") post must be visible
-- ONLY to that post's own author — not to other friends who can also see
-- the post itself, and not publicly. This is deliberately narrower than
-- POST_CARD_SPEC.md's public face-reaction row, which is scoped to
-- anonymous/everyone posts only ("Face-reaction row applies to Friends/
-- Everyone feeds only" in that doc means the FEED KIND, not this app's new
-- 'friends'-visibility post type introduced alongside post_audiences —
-- naming collision, not the same concept).
--
-- CONFIRMED against the live DB before this migration: reactions_select and
-- post_realmoji_reactions_select's post_id branch both only check "does
-- this post exist" (transitively inheriting posts_select's own visibility
-- via the EXISTS subquery) — meaning any friend who can see a personal post
-- could also read who reacted to it. Tightened here to author-only, for
-- 'friends'-visibility rows specifically; 'everyone'/'anonymous'/'community'
-- posts keep their existing (unchanged) reaction-visibility behavior.
--
-- Idempotent, safe to re-run.
-- ============================================================================

DROP POLICY IF EXISTS "reactions_select" ON reactions;
CREATE POLICY "reactions_select" ON reactions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = reactions.post_id
      AND (
        p.visibility IS DISTINCT FROM 'friends'
        OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
      )
  )
  OR EXISTS (
    SELECT 1 FROM group_posts gp
    JOIN group_members gm ON gm.group_id = gp.group_id
    JOIN users u ON u.id = gm.user_id
    WHERE gp.id = reactions.group_post_id
    AND u.auth_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "post_realmoji_reactions_select" ON post_realmoji_reactions;
CREATE POLICY "post_realmoji_reactions_select" ON post_realmoji_reactions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM posts p
    WHERE p.id = post_realmoji_reactions.post_id
      AND p.deleted_at IS NULL
      AND (
        p.visibility IS DISTINCT FROM 'anonymous'
        OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
      )
      AND (
        p.visibility IS DISTINCT FROM 'friends'
        OR auth.uid() IN (SELECT auth_id FROM users WHERE id = p.user_id)
      )
  )
  OR EXISTS (
    SELECT 1 FROM group_posts gp
    JOIN group_members gm ON gm.group_id = gp.group_id
    JOIN users u ON u.id = gm.user_id
    WHERE gp.id = post_realmoji_reactions.group_post_id
    AND u.auth_id = auth.uid()
  )
);
