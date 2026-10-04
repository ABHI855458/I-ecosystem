-- Nobody can leave "General".
--
-- It is the community every user is auto-joined to (20260908060000) and the
-- channel institutional announcements reach the whole campus through. A
-- student who left it would silently stop receiving those, which is exactly
-- the content they must not be able to opt out of.
--
-- Enforced here rather than only in the UI: hiding the button stops the
-- honest case, not a direct API call, and the auto-join trigger would fight
-- a manual leave forever without this.

DROP POLICY IF EXISTS "mem_leave" ON public.community_members;

CREATE POLICY "mem_leave" ON public.community_members
FOR DELETE USING (
  user_id = auth.uid()
  AND NOT EXISTS (
    SELECT 1 FROM public.communities c
     WHERE c.id = community_members.community_id
       AND lower(c.name) = 'general'
       AND c.deleted_at IS NULL
  )
);

-- Moderators still need to be able to remove someone from any community
-- (a real moderation action), General included.
DROP POLICY IF EXISTS "mem_remove_moderator" ON public.community_members;
CREATE POLICY "mem_remove_moderator" ON public.community_members
FOR DELETE USING (public.can_moderate_community(community_id));
