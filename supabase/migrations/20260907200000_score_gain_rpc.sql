-- ============================================================================
-- my_score_gain_since(timestamptz) — what did that action actually earn me?
--
-- Every reward popup in the app said "+10", hardcoded at three call sites in
-- the composer, while the real rules award 25 for an anon post, 25 for a ping
-- sent, 20 for a ping reply, 3 for a comment, 2 for a reaction and 5 for
-- engagement received. So the number the user was shown was wrong for every
-- single action.
--
-- Points are granted by TRIGGERS (award_comment_given_score,
-- award_reaction_given_score, send_ping's own award, ...), so the client
-- cannot know the delta by counting what it did — it has to ask. The caller
-- timestamps just before the action and asks for everything credited since.
--
-- Returns the itemised events too, so the popup can say what the points were
-- FOR rather than just showing a number, plus the resulting total and level
-- so it can celebrate a level-up in the same breath.
--
-- Scoped to the caller by auth.uid(); there is no parameter for whose score
-- to read, so this cannot be used to inspect anyone else's.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

DROP FUNCTION IF EXISTS public.my_score_gain_since(timestamptz);

CREATE FUNCTION public.my_score_gain_since(p_since timestamptz)
 RETURNS TABLE(
   gained      integer,
   events      jsonb,
   total_score integer,
   level       integer
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me UUID;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    COALESCE((SELECT SUM(e.points)::int FROM public.score_events e
               WHERE e.user_id = v_me AND e.created_at >= p_since), 0),
    COALESCE((SELECT jsonb_agg(jsonb_build_object(
                       'event_type', e.event_type, 'points', e.points)
                     ORDER BY e.created_at)
                FROM public.score_events e
               WHERE e.user_id = v_me AND e.created_at >= p_since), '[]'::jsonb),
    (SELECT u.total_score FROM public.users u WHERE u.id = v_me),
    (SELECT u.level FROM public.users u WHERE u.id = v_me);
END;
$function$;

REVOKE ALL ON FUNCTION public.my_score_gain_since(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_score_gain_since(timestamptz) TO authenticated;
