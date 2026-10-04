-- ============================================================================
-- Split "Moments I contributed to" by the identity I contributed UNDER.
--
-- Replying to a Moment can now be done as yourself or as your anon persona
-- (moment_replies.is_anonymous, 20260907110000). The profile has to follow
-- that choice: "if replied as anon it would go to anon page in profile, in
-- real name means in moments it would go". Today my_contributed_moment_ids
-- returns everything, so an anonymous contribution shows up in the Moments
-- tab under your own name — which is the one place it must never appear.
--
-- p_anonymous: false = only the ones I contributed as myself (the Moments
-- tab), true = only the ones I contributed anonymously (the Anon tab),
-- null = both (the previous behaviour, kept so nothing that relies on it
-- silently changes).
--
-- Still scoped to auth.uid() — there is no parameter for whose contributions
-- to read, so this cannot be pointed at anyone else.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

DROP FUNCTION IF EXISTS public.my_contributed_moment_ids(boolean);

CREATE OR REPLACE FUNCTION public.my_contributed_moment_ids(
  p_anonymous boolean DEFAULT NULL)
 RETURNS TABLE(moment_post_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT r.moment_post_id
    FROM public.moment_replies r
    JOIN public.users u ON u.id = r.user_id
   WHERE u.auth_id = auth.uid()
     AND (p_anonymous IS NULL OR r.is_anonymous = p_anonymous)
   ORDER BY r.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.my_contributed_moment_ids(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_contributed_moment_ids(boolean) TO authenticated;

-- Drop the old zero-argument overload. Leaving both live means PostgREST has
-- two candidates for a no-arg call, and the one it would pick is the one with
-- no identity filter — i.e. the bug this migration exists to fix would come
-- back for any caller that hadn't been updated. The new function's DEFAULT
-- NULL makes it a drop-in for the no-arg call.
DROP FUNCTION IF EXISTS public.my_contributed_moment_ids();
