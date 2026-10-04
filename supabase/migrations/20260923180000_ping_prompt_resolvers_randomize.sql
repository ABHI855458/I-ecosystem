-- BUG FIX, found while verifying the default-ping-prompt content just
-- added: every tier of the ping-prompt resolvers picks its result with a
-- plain `ORDER BY sort_order NULLS LAST, created_at LIMIT v_limit` (Tier 1
-- of ping_prompts_for_post uses `ORDER BY created_at` alone) — a STATIC
-- top-N, no randomization anywhere in either function or on the client
-- (PingPromptService.fetch caches the result for the whole app session).
--
-- Consequence: every user, every time, was seeing the exact same fixed
-- N prompts for a given scope/community/prompt — literally always
-- whichever rows happened to have the lowest sort_order or the oldest
-- created_at. Every row past the limit was structurally unreachable,
-- which is exactly why the 80 new default prompts and 420 new General
-- Tier-1 ping-prompts added in the two prior migrations would otherwise
-- never have actually been shown to anyone — they were appended at a
-- higher sort_order / later created_at than the existing rows, putting
-- them permanently behind the same static short list every fetch.
--
-- Fixed in all four call sites (Tier 1/2/3 of ping_prompts_for_post, plus
-- ping_prompts_for_scope's own two branches) by switching to
-- `ORDER BY random() LIMIT v_limit`. Every active row in the pool now has
-- an equal chance of surfacing on each fresh (uncached) fetch, which is
-- also just the honestly-correct behaviour for "give people something
-- interesting to send" — a picker that never varies isn't a picker.
CREATE OR REPLACE FUNCTION public.ping_prompts_for_post(p_post_id uuid)
 RETURNS TABLE(id uuid, prompt_text text, tier text, prompt_kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
       ORDER BY random()
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
     ORDER BY random()
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
   ORDER BY random()
   LIMIT v_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ping_prompts_for_scope(p_scope text)
 RETURNS TABLE(id uuid, prompt_text text, card_color text, prompt_kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_limit int;
BEGIN
  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = p_scope
   ORDER BY random()
   LIMIT v_limit;
  IF FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT sp.id, sp.prompt_text, sp.card_color, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL AND sp.active AND sp.scope = 'everyone'
   ORDER BY random()
   LIMIT v_limit;
END;
$function$;
