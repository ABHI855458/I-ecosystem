-- FIX 1 — a thin Tier-1 set must fall THROUGH, not starve the sheet.
-- `IF FOUND THEN RETURN` short-circuits on a single row, so the one prompt
-- in the library with a linked set ("OVERRRATED COLLEGE PLACE", 1 ping)
-- gave that post a 1-option sheet — worse than having none. Require >= 3.
CREATE OR REPLACE FUNCTION public.ping_prompts_for_post(p_post_id uuid)
RETURNS TABLE(id uuid, prompt_text text, tier text, prompt_kind text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_me uuid; v_author uuid; v_vis text; v_prompt uuid; v_community uuid;
  v_limit int; v_is_friend boolean := false; v_tier1 int;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  SELECT p.user_id, p.visibility, p.prompt_id, p.community_id
    INTO v_author, v_vis, v_prompt, v_community
    FROM public.posts p
   WHERE p.id = p_post_id AND p.deleted_at IS NULL;

  IF v_author IS NULL THEN RETURN; END IF;

  -- TIER 1 — the prompt-bar question's own set, only if it is a real set.
  IF v_prompt IS NOT NULL THEN
    SELECT count(*) INTO v_tier1
      FROM public.ping_prompts pp
     WHERE pp.daily_prompt_id = v_prompt AND pp.active;

    IF COALESCE(v_tier1, 0) >= 3 THEN
      RETURN QUERY
      SELECT pp.id, pp.prompt_text, 'prompt'::text, pp.prompt_kind
        FROM public.ping_prompts pp
       WHERE pp.daily_prompt_id = v_prompt AND pp.active
       ORDER BY pp.created_at
       LIMIT v_limit;
      RETURN;
    END IF;
  END IF;

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
    SELECT sp.id, sp.prompt_text, 'community'::text, sp.prompt_kind
      FROM public.ping_sheet_prompts sp
     WHERE sp.community_id = v_community AND sp.active
     ORDER BY sp.sort_order NULLS LAST, sp.created_at
     LIMIT v_limit;
    IF FOUND THEN RETURN; END IF;
  END IF;

  -- TIER 3 — generic default for this post's scope.
  RETURN QUERY
  SELECT sp.id, sp.prompt_text, 'default'::text, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL
     AND sp.active
     AND sp.scope = CASE WHEN v_vis = 'anonymous' THEN 'anonymous' ELSE 'everyone' END
   ORDER BY sp.sort_order NULLS LAST, sp.created_at
   LIMIT v_limit;
END;
$$;

-- FIX 3 — deactivate the six legacy generic rows.
-- They sit at sort_order 0-5 in EVERY global scope, so they win every
-- LIMIT 6 and are the single reason each scope's sheet looked identical.
-- Deactivated, not deleted: they are referenced by existing pings.
UPDATE public.ping_sheet_prompts
   SET active = false
 WHERE community_id IS NULL
   AND prompt_text IN (
     'Hey, want to hang out? 👋',
     'WELL DONE BRO',
     'Coffee sometime? ☕',
     'Let''s catch up soon!',
     'Miss you! Where you been?',
     'Long time no see!'
   );
