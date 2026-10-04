-- "Seen by" on a GROUP post. Explicit request: "include the seen button in
-- the posts of group profile". post_views is keyed on posts.id and the
-- post_viewers RPC reads it directly, so a group post (group_posts.id) had
-- nowhere to record a view and no way to list one.
--
-- Same shape as post_views: one row per (post, viewer), no updates, the
-- timestamp is the first open.
CREATE TABLE IF NOT EXISTS public.group_post_views (
  group_post_id uuid NOT NULL REFERENCES public.group_posts(id) ON DELETE CASCADE,
  viewer_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_post_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS group_post_views_post_idx
  ON public.group_post_views (group_post_id, created_at DESC);

ALTER TABLE public.group_post_views ENABLE ROW LEVEL SECURITY;

-- Reads go through group_post_viewers() (SECURITY DEFINER, membership
-- gated). Direct selects are self-only, mirroring post_views' own posture.
DROP POLICY IF EXISTS group_post_views_select_own ON public.group_post_views;
CREATE POLICY group_post_views_select_own ON public.group_post_views
  FOR SELECT USING (viewer_id = public.current_user_id());

-- Records that the caller opened a group post. Members only, never the
-- author's own view — the same two exclusions record_post_view applies.
CREATE OR REPLACE FUNCTION public.record_group_post_view(p_group_post_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid;
  v_owner uuid;
  v_group uuid;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RETURN; END IF;

  SELECT user_id, group_id INTO v_owner, v_group
    FROM public.group_posts WHERE id = p_group_post_id AND deleted_at IS NULL;

  IF v_owner IS NULL OR v_owner = v_me THEN RETURN; END IF;
  IF NOT public.is_group_member(v_group, v_me) THEN RETURN; END IF;

  INSERT INTO public.group_post_views (group_post_id, viewer_id)
  VALUES (p_group_post_id, v_me)
  ON CONFLICT (group_post_id, viewer_id) DO NOTHING;
END;
$function$;

-- Everyone who has opened this group post, all-time. Same column list as
-- post_viewers so the client maps both with one PostViewer.fromRow.
CREATE OR REPLACE FUNCTION public.group_post_viewers(p_group_post_id uuid)
 RETURNS TABLE(user_id uuid, username text, name text, avatar_url text, is_pinned boolean, viewed_at timestamptz)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT id FROM public.users WHERE auth_id = auth.uid())
  SELECT
    u.id, u.username, u.name, u.profile_photo_url,
    EXISTS (
      SELECT 1 FROM public.pinned_people pp
       WHERE pp.user_id = (SELECT id FROM me) AND pp.pinned_user_id = u.id
    ) AS is_pinned,
    gpv.created_at
  FROM public.group_post_views gpv
  JOIN public.users u ON u.id = gpv.viewer_id
  JOIN public.group_posts gp ON gp.id = gpv.group_post_id
  WHERE gpv.group_post_id = p_group_post_id
    AND public.is_group_member(gp.group_id, (SELECT id FROM me))
  ORDER BY 5 DESC, gpv.created_at DESC;
$function$;
