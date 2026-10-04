-- AUTHORIZATION FIX for inject_prompt().
--
-- As first written the function was SECURITY DEFINER and EXECUTE-granted to
-- `authenticated`, with no permission check of its own. SECURITY DEFINER
-- runs the body as the owner, so row-level security on daily_prompts never
-- applied: daily_prompts_write_scoped requires
--
--   is_admin_or_global_mod() OR is_community_moderator_for(community_id)
--
-- for every ordinary INSERT (that policy is the ONLY thing authorizing the
-- dashboard's normal "Ask the community something…" box), and the RPC walked
-- straight past it. Any signed-in student could call
--
--   rpc('inject_prompt', { p_community_id: <any community>, p_prompt_text: … })
--
-- and put arbitrary text at the top of that community's prompt bar for the
-- whole window, outranking the curated rotation, with the ping prompts
-- attached for good measure. Injection is the one write in this system that
-- is deliberately high-priority and immediate, which makes it exactly the
-- wrong one to leave unguarded.
--
-- The guard below is the same predicate as the policy, calling the same two
-- helpers, so the two cannot mean different things — only a change to the
-- policy itself could separate them.
--
-- SECURITY DEFINER is kept rather than dropped to INVOKER because the body
-- also reads the pool='fallback' ping prompts and the communities row, and
-- the function should not start failing for a legitimate moderator if a
-- future SELECT policy on either narrows. The check is now explicit instead
-- of implicit, which is the property that was actually missing.
CREATE OR REPLACE FUNCTION public.inject_prompt(
  p_community_id uuid,
  p_prompt_text  text,
  p_feed_scope   text DEFAULT 'anon',
  p_prompt_kind  text DEFAULT 'photo'
)
RETURNS TABLE(prompt_id uuid, window_key text, ping_prompts_attached integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_window text;
  v_day    date;
  v_id     uuid;
  v_pings  int := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;

  IF btrim(coalesce(p_prompt_text, '')) = '' THEN
    RAISE EXCEPTION 'Prompt text is required.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.communities
                  WHERE id = p_community_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Unknown or inactive community.';
  END IF;

  -- THE FIX. Mirrors daily_prompts_write_scoped.
  IF NOT (public.is_admin_or_global_mod()
          OR public.is_community_moderator_for(p_community_id)) THEN
    RAISE EXCEPTION 'You do not moderate that community.';
  END IF;

  SELECT w.window_key, w.for_day INTO v_window, v_day
    FROM public.current_prompt_window() w;

  INSERT INTO public.daily_prompts
    (prompt_text, community_id, prompt_kind, feed_scope, time_windows,
     weight, active, category, is_injected, injected_at)
  VALUES
    (btrim(p_prompt_text), p_community_id, p_prompt_kind, p_feed_scope,
     ARRAY[v_window]::text[], 5, true, 'injected', true, now())
  RETURNING id INTO v_id;

  -- Copy the generic fallback set for this feed scope onto the new prompt.
  INSERT INTO public.ping_prompts
    (prompt_text, daily_prompt_id, pool, prompt_kind, weight, active)
  SELECT pp.prompt_text, v_id, 'linked', pp.prompt_kind, pp.weight, true
    FROM public.ping_prompts pp
   WHERE pp.pool = 'fallback'
     AND pp.active
   ORDER BY pp.created_at
   LIMIT 10;
  GET DIAGNOSTICS v_pings = ROW_COUNT;

  RETURN QUERY SELECT v_id, v_window, v_pings;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.inject_prompt(uuid, text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.inject_prompt(uuid, text, text, text) TO authenticated;

-- Record a behaviour that is easy to misread from the body: the injected
-- front-check filters on community and window but NOT on feed_scope, so one
-- injection surfaces in both the friends bar and the anonymous bar. That is
-- intended — an injection means "show this to them now" — and the dashboard
-- says so. The feed_scope stored on an injected row is therefore inert.
COMMENT ON FUNCTION public.pick_window_prompt(uuid, text, date, text) IS
  'Prompt for one community+window+day. An injected prompt whose injected_at '
  'falls inside this occurrence of the window wins outright (most recent '
  'first); it is matched on community and window only, NOT feed_scope, so an '
  'injection shows in both feeds. Otherwise the standing rotation is indexed '
  'by day_index MOD pool_size over a stable permutation, with injected rows '
  'excluded from the pool so an injection never shifts the cycle.';
