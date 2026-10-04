-- ============================================================================
-- CIRCLES — user-created private posting audiences.
--
-- A circle is visible ONLY to its creator. Membership is silent: a member is
-- never notified, and cannot discover the circle or their own membership in
-- it. That silence is STRUCTURAL, not cosmetic — see the RLS below: members
-- get no policy at all on either table, so a member's own query returns zero
-- rows no matter how it is written. The visibility decision therefore cannot
-- run as the viewer; it runs inside can_view_post(), which is already
-- SECURITY DEFINER and reads the tables as owner.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.circles (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name       text NOT NULL CHECK (btrim(name) <> '' AND length(name) <= 40),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS circles_creator_name_uniq
  ON public.circles (creator_id, lower(name));

CREATE TABLE IF NOT EXISTS public.circle_members (
  circle_id uuid NOT NULL REFERENCES public.circles(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  added_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (circle_id, member_id)
);
CREATE INDEX IF NOT EXISTS circle_members_member_idx ON public.circle_members (member_id);

-- Members are drawn only from people the creator already shares a community
-- with — enforced here, not merely filtered in the picker UI.
-- community_members.user_id holds an AUTH uid, so both sides map through
-- users.auth_id.
CREATE OR REPLACE FUNCTION public.circle_member_is_eligible(p_circle_id uuid, p_member_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.circles c
      JOIN public.users cu ON cu.id = c.creator_id
      JOIN public.users mu ON mu.id = p_member_id
      JOIN public.community_members cm_creator ON cm_creator.user_id = cu.auth_id
      JOIN public.community_members cm_member
        ON cm_member.user_id = mu.auth_id
       AND cm_member.community_id = cm_creator.community_id
     WHERE c.id = p_circle_id
  );
$$;

ALTER TABLE public.circles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_members ENABLE ROW LEVEL SECURITY;

-- Creator-only. There is deliberately NO member-facing policy: absence, not
-- a filter. A member querying these tables matches no policy and gets zero
-- rows for every command.
DROP POLICY IF EXISTS circles_creator_only ON public.circles;
CREATE POLICY circles_creator_only ON public.circles FOR ALL
  USING      (creator_id = public.current_user_id())
  WITH CHECK (creator_id = public.current_user_id());

DROP POLICY IF EXISTS circle_members_creator_only ON public.circle_members;
CREATE POLICY circle_members_creator_only ON public.circle_members FOR ALL
  USING (EXISTS (SELECT 1 FROM public.circles c
                  WHERE c.id = circle_id AND c.creator_id = public.current_user_id()))
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.circles c
             WHERE c.id = circle_id AND c.creator_id = public.current_user_id())
    AND public.circle_member_is_eligible(circle_id, member_id)
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.circles        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.circle_members TO authenticated;
REVOKE EXECUTE ON FUNCTION public.circle_member_is_eligible(uuid, uuid) FROM authenticated, anon;

-- ---------------------------------------------------------------------------
-- post_audiences gains 'circle', same shape as 'community'.
-- ---------------------------------------------------------------------------
ALTER TABLE public.post_audiences
  ADD COLUMN IF NOT EXISTS circle_id uuid REFERENCES public.circles(id) ON DELETE CASCADE;

ALTER TABLE public.post_audiences DROP CONSTRAINT IF EXISTS post_audiences_audience_kind_check;
ALTER TABLE public.post_audiences ADD  CONSTRAINT post_audiences_audience_kind_check
  CHECK (audience_kind = ANY (ARRAY['friends','community','circle']));

ALTER TABLE public.post_audiences DROP CONSTRAINT IF EXISTS post_audiences_community_kind_match;
ALTER TABLE public.post_audiences ADD  CONSTRAINT post_audiences_community_kind_match
  CHECK (
       (audience_kind = 'community' AND community_id IS NOT NULL AND circle_id IS NULL)
    OR (audience_kind = 'circle'    AND circle_id    IS NOT NULL AND community_id IS NULL)
    OR (audience_kind = 'friends'   AND community_id IS NULL     AND circle_id IS NULL)
  );

-- ---------------------------------------------------------------------------
-- An RLS BYPASS, removed. close_group_view_posts granted visibility via a
-- `follows` row and never consulted can_view_post, so it would have silently
-- overridden every friends/community/circle audience rule. Dormant only
-- because `follows` is empty (verified 0 rows) — dropped now while that is
-- still free to do.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS close_group_view_posts ON public.posts;

-- ---------------------------------------------------------------------------
-- can_view_post gains the circle branch. Runs SECURITY DEFINER, which is what
-- lets it read circle_members on behalf of a viewer who structurally cannot
-- read that table themselves.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_view_post(p_post_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_viewer_id  UUID;
  v_author_id  UUID;
  v_partner_id UUID;
  v_visibility TEXT;
BEGIN
  SELECT id INTO v_viewer_id FROM users WHERE auth_id = auth.uid();
  IF v_viewer_id IS NULL THEN RETURN FALSE; END IF;

  SELECT user_id, partner_user_id, visibility
    INTO v_author_id, v_partner_id, v_visibility
    FROM posts WHERE id = p_post_id;
  IF v_author_id IS NULL THEN RETURN FALSE; END IF;

  IF v_viewer_id = v_author_id OR v_viewer_id = v_partner_id THEN RETURN TRUE; END IF;
  IF v_visibility <> 'friends' THEN RETURN TRUE; END IF;

  IF EXISTS (
    SELECT 1 FROM friendships
    WHERE status = 'accepted'
      AND ((requester_id = v_author_id AND addressee_id = v_viewer_id) OR
           (requester_id = v_viewer_id AND addressee_id = v_author_id) OR
           (v_partner_id IS NOT NULL AND (
             (requester_id = v_partner_id AND addressee_id = v_viewer_id) OR
             (requester_id = v_viewer_id AND addressee_id = v_partner_id))))
  ) THEN RETURN TRUE; END IF;

  IF EXISTS (
    SELECT 1 FROM post_audiences pa
    WHERE pa.post_id = p_post_id
      AND pa.audience_kind = 'community'
      AND is_community_member(pa.community_id, auth.uid())
  ) THEN RETURN TRUE; END IF;

  -- Circle audience. The viewer learns nothing about WHY they can see it:
  -- no readable row, no notification, no membership lookup available to them.
  IF EXISTS (
    SELECT 1 FROM post_audiences pa
    JOIN circle_members cm ON cm.circle_id = pa.circle_id
    WHERE pa.post_id = p_post_id
      AND pa.audience_kind = 'circle'
      AND cm.member_id = v_viewer_id
  ) THEN RETURN TRUE; END IF;

  RETURN FALSE;
END;
$function$;
