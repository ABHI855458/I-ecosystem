-- PHASE 4e RULING: "best community" prefers the LARGER board.
--
-- Was: ORDER BY rnk ASC, members DESC — lowest rank number wins, so the
-- emulator user was told "You're #1 of 2 in Placements & Prep" while also
-- sitting #2 of 9 in General. A two-person board carries no bragging weight;
-- #2 of 9 is the standing actually worth reporting.
--
-- Now: ORDER BY members DESC, rnk ASC — the biggest board the user belongs
-- to, and among equally sized boards their best position on one.
--
-- Known edge, accepted deliberately: someone last on a big board now hears
-- "#9 of 9 in General" instead of a flattering position on a tiny one. That
-- is the honest reading of where they stand, and §6.6's rule that every
-- number be real applies to unflattering numbers too.
CREATE OR REPLACE FUNCTION public.notify_streak_standing(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  n int := 0;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  WITH ranked AS (
    SELECT c.id AS community_id, c.name AS cname, u.id AS user_id,
           row_number() OVER (
             PARTITION BY c.id
             ORDER BY public.effective_community_streak(u.daily_streak, u.daily_streak_last) DESC,
                      COALESCE(cs.xp,0) DESC, u.id) AS rnk,
           count(*) OVER (PARTITION BY c.id) AS members
      FROM public.communities c
      JOIN public.community_members cm ON cm.community_id = c.id
      JOIN public.users u ON u.auth_id = cm.user_id
      LEFT JOIN public.community_streaks cs ON cs.community_id = c.id AND cs.user_id = u.id
     WHERE c.deleted_at IS NULL AND u.deleted_at IS NULL
  ),
  best AS (
    SELECT DISTINCT ON (user_id) user_id, community_id, cname, rnk, members
      FROM ranked
     WHERE members > 1
     ORDER BY user_id, members DESC, rnk ASC   -- THE RULING
  )
  INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
  SELECT b.user_id, 'streak_standing', 'minor',
         'You''re #' || b.rnk || ' of ' || b.members || ' in ' || b.cname || ' by streak',
         jsonb_build_object('screen','community','community_id', b.community_id),
         'streak_standing:' || b.user_id::text || ':' || v_today::text
    FROM best b
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
