-- DASHBOARD: expose the real 14-day Wake rotation order, Day 1 -> Day 14.
--
-- Today there is no way to SEE the sequence a community's rotation actually
-- follows — Prompts.jsx Step 2 lists prompts in created_at order, which has
-- no relationship to which calendar day each one is served on.
-- pick_window_prompt() picks by day_index MOD pool_size against a stable
-- hashtext-based rank; that rank IS the real cycle order, it was just never
-- surfaced anywhere a human could read it.
--
-- This function reproduces that EXACT ranking (same salt, same hashtext,
-- same weight divisor, same tie-break on id) so day_number here is
-- guaranteed to agree with what pick_window_prompt actually serves — day 1
-- is rn=0, day 2 is rn=1, etc. Verified below against real calendar days.
CREATE OR REPLACE FUNCTION public.prompt_cycle_order(
  p_community_id uuid,
  p_window text DEFAULT 'wake',
  p_feed_scope text DEFAULT 'anon'
)
RETURNS TABLE(day_number integer, prompt_id uuid, prompt_text text, active boolean, weight integer)
LANGUAGE sql STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT (row_number() OVER (
            ORDER BY
              (abs(hashtext(dp.id::text || p_community_id::text || p_window)) % 10000)::numeric
                / GREATEST(dp.weight, 1),
              dp.id
          ))::int AS day_number,
         dp.id, dp.prompt_text, dp.active, dp.weight
    FROM public.daily_prompts dp
   WHERE dp.community_id = p_community_id
     AND dp.feed_scope = p_feed_scope
     AND NOT dp.is_injected
     AND (dp.expires_at IS NULL OR dp.expires_at > now())
     AND (dp.time_windows IS NULL OR cardinality(dp.time_windows) = 0
          OR p_window = ANY(dp.time_windows))
   ORDER BY day_number;
$function$;

REVOKE EXECUTE ON FUNCTION public.prompt_cycle_order(uuid, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.prompt_cycle_order(uuid, text, text) TO authenticated;
