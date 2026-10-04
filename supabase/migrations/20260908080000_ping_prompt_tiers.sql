-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Three tiers of ping prompts + community-moderator scoping           ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- Which prompts appear in the ping dropdown depends on the post AND on the
-- relationship between the viewer and the poster:
--
--   TIER 1 · per prompt-bar question
--       The post answered a prompt (posts.prompt_id). That question's own
--       ping prompts are used — ping_prompts.daily_prompt_id, which already
--       existed and had nothing managing it.
--
--   TIER 2 · community set, for a non-friend
--       A friends-feed post tagged to a community, viewed by someone who is
--       NOT a friend of the poster. They reach it through the community, so
--       they get that community's set.
--
--   TIER 3 · default
--       Everything else — no prompt, or the viewer IS a friend (friendship
--       wins over community, per spec). The generic ping_sheet_prompts set
--       for the post's scope.
--
-- A per-community friends set needs a home, hence community_id below.

ALTER TABLE public.ping_sheet_prompts
  ADD COLUMN IF NOT EXISTS community_id uuid
    REFERENCES public.communities(id) ON DELETE CASCADE;

COMMENT ON COLUMN public.ping_sheet_prompts.community_id IS
  'Tier 2: the set shown to a NON-friend who reached a friends post through '
  'this community. NULL = the generic default set (tier 3).';

CREATE INDEX IF NOT EXISTS ping_sheet_prompts_community_idx
  ON public.ping_sheet_prompts (community_id) WHERE community_id IS NOT NULL;

-- How many may appear in the dropdown at once.
CREATE TABLE IF NOT EXISTS public.app_settings (
  key   text PRIMARY KEY,
  value integer NOT NULL
);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_settings_read ON public.app_settings;
CREATE POLICY app_settings_read ON public.app_settings FOR SELECT USING (true);
DROP POLICY IF EXISTS app_settings_write ON public.app_settings;
CREATE POLICY app_settings_write ON public.app_settings FOR ALL
  USING (public.is_admin_or_global_mod()) WITH CHECK (public.is_admin_or_global_mod());

INSERT INTO public.app_settings (key, value)
VALUES ('ping_prompt_limit', 6)
ON CONFLICT (key) DO NOTHING;


-- ── The resolver ───────────────────────────────────────────────────────
-- One function the app calls with a post id; it returns the prompts that
-- post should offer, already tier-resolved and limited. Keeping the tier
-- logic here rather than in the client means the rule cannot drift between
-- the two feeds that need it.

DROP FUNCTION IF EXISTS public.ping_prompts_for_post(uuid);

CREATE FUNCTION public.ping_prompts_for_post(p_post_id uuid)
 RETURNS TABLE(id uuid, prompt_text text, tier text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me        uuid;
  v_author    uuid;
  v_vis       text;
  v_prompt    uuid;
  v_community uuid;
  v_limit     int;
  v_is_friend boolean := false;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  SELECT p.user_id, p.visibility, p.prompt_id, p.community_id
    INTO v_author, v_vis, v_prompt, v_community
    FROM public.posts p
   WHERE p.id = p_post_id AND p.deleted_at IS NULL;

  IF v_author IS NULL THEN
    RETURN;
  END IF;

  -- TIER 1 — the prompt-bar question's own set.
  IF v_prompt IS NOT NULL THEN
    RETURN QUERY
    SELECT pp.id, pp.prompt_text, 'prompt'::text
      FROM public.ping_prompts pp
     WHERE pp.daily_prompt_id = v_prompt AND pp.active
     ORDER BY pp.created_at
     LIMIT v_limit;
    IF FOUND THEN RETURN; END IF;
  END IF;

  -- Friendship beats community: a friend always gets the friends set.
  IF v_me IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.friendships f
       WHERE f.status = 'accepted'
         AND ((f.requester_id = v_me AND f.addressee_id = v_author)
           OR (f.addressee_id = v_me AND f.requester_id = v_author))
    ) INTO v_is_friend;
  END IF;

  -- TIER 2 — community set for a non-friend on a community-tagged post.
  IF v_community IS NOT NULL AND NOT v_is_friend THEN
    RETURN QUERY
    SELECT sp.id, sp.prompt_text, 'community'::text
      FROM public.ping_sheet_prompts sp
     WHERE sp.community_id = v_community AND sp.active
     ORDER BY sp.sort_order NULLS LAST, sp.created_at
     LIMIT v_limit;
    IF FOUND THEN RETURN; END IF;
  END IF;

  -- TIER 3 — the generic default for this post's scope.
  RETURN QUERY
  SELECT sp.id, sp.prompt_text, 'default'::text
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL
     AND sp.active
     AND sp.scope = CASE WHEN v_vis = 'anonymous' THEN 'anonymous' ELSE 'everyone' END
   ORDER BY sp.sort_order NULLS LAST, sp.created_at
   LIMIT v_limit;
END;
$function$;

REVOKE ALL ON FUNCTION public.ping_prompts_for_post(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ping_prompts_for_post(uuid) TO authenticated;


-- ── Community moderators may manage their own community's prompts ──────
-- The earlier lockdown (20260908020000) made prompt authoring admin-only,
-- which is right for the GLOBAL sets but wrong for a community moderator
-- appointed to run one community.

DROP POLICY IF EXISTS "daily_prompts_insert_moderator" ON public.daily_prompts;
DROP POLICY IF EXISTS "daily_prompts_update_moderator" ON public.daily_prompts;
DROP POLICY IF EXISTS "daily_prompts_delete_moderator" ON public.daily_prompts;

CREATE POLICY "daily_prompts_write_scoped" ON public.daily_prompts
FOR ALL USING (
  public.is_admin_or_global_mod()
  OR (community_id IS NOT NULL AND public.is_community_moderator_for(community_id))
) WITH CHECK (
  public.is_admin_or_global_mod()
  OR (community_id IS NOT NULL AND public.is_community_moderator_for(community_id))
);

-- ping_prompts hang off a daily_prompt, so scope follows that prompt's
-- community.
DROP POLICY IF EXISTS "ping_prompts_insert_admin" ON public.ping_prompts;
DROP POLICY IF EXISTS "ping_prompts_update_admin" ON public.ping_prompts;
DROP POLICY IF EXISTS "ping_prompts_delete_admin" ON public.ping_prompts;

CREATE POLICY "ping_prompts_write_scoped" ON public.ping_prompts
FOR ALL USING (
  public.is_admin()
  OR EXISTS (
    SELECT 1 FROM public.daily_prompts dp
     WHERE dp.id = ping_prompts.daily_prompt_id
       AND dp.community_id IS NOT NULL
       AND public.is_community_moderator_for(dp.community_id)
  )
) WITH CHECK (
  public.is_admin()
  OR EXISTS (
    SELECT 1 FROM public.daily_prompts dp
     WHERE dp.id = ping_prompts.daily_prompt_id
       AND dp.community_id IS NOT NULL
       AND public.is_community_moderator_for(dp.community_id)
  )
);

-- A community's own friends-post set (tier 2) is likewise theirs to manage;
-- the global sets (community_id IS NULL) stay admin-only.
DROP POLICY IF EXISTS "ping_sheet_prompts_insert_admin" ON public.ping_sheet_prompts;
DROP POLICY IF EXISTS "ping_sheet_prompts_update_admin" ON public.ping_sheet_prompts;
DROP POLICY IF EXISTS "ping_sheet_prompts_delete_admin" ON public.ping_sheet_prompts;

CREATE POLICY "ping_sheet_prompts_write_scoped" ON public.ping_sheet_prompts
FOR ALL USING (
  public.is_admin()
  OR (community_id IS NOT NULL AND public.is_community_moderator_for(community_id))
) WITH CHECK (
  public.is_admin()
  OR (community_id IS NOT NULL AND public.is_community_moderator_for(community_id))
);
