-- ============================================================================
-- Community XP: award it for commenting, and record every grant in the ledger.
--
-- Verified live: the Streaks tab's XP display IS wired (community_leaderboard
-- reads community_streaks.xp), but only two things ever granted XP —
-- +10 for an anonymous post in the community (bump_community_streak) and
-- +2 to the author when someone reacts to one (award_community_reaction_xp).
-- Commenting on a community post, the most common thing people actually do
-- there, granted nothing, so most members sit at 0 XP / level 1 forever and
-- the whole progression reads as broken.
--
-- Two changes:
--   1. +3 XP for commenting on an anonymous community post, to the COMMENTER.
--      Matches the app-wide "+3 comment given" rule so the two systems agree.
--      Self-comments earn nothing, same guard the reaction award uses.
--   2. bump_community_streak now writes score_events too. It was the last
--      XP path with no ledger row, which made the audit trail (and the
--      "what did I just earn" popup) blind to community posting.
--
-- log_score_event swallows its own failures by design, so neither addition
-- can cost anyone the XP it sits beside.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

-- ── 1. Comment on a community post: +3 XP to the commenter ──────────────────

CREATE OR REPLACE FUNCTION public.award_community_comment_xp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_owner     UUID;
  v_community UUID;
  wk          DATE := current_week_start();
BEGIN
  IF new.post_id IS NULL THEN
    RETURN new;
  END IF;

  SELECT p.user_id, p.community_id INTO v_owner, v_community
    FROM public.posts p
   WHERE p.id = new.post_id
     AND p.visibility = 'anonymous'
     AND p.community_id IS NOT NULL;

  -- Not a community post, or you are commenting on your own: no XP. The
  -- self-check is what stops someone farming XP on their own thread.
  IF v_community IS NULL OR v_owner IS NULL OR v_owner = new.user_id THEN
    RETURN new;
  END IF;

  -- Only members earn community XP — commenting from outside shouldn't put
  -- you on that community's board.
  IF NOT EXISTS (
    SELECT 1 FROM public.community_members m
     JOIN public.users u ON u.auth_id = m.user_id
    WHERE m.community_id = v_community AND u.id = new.user_id
  ) THEN
    RETURN new;
  END IF;

  INSERT INTO public.community_streaks
    (community_id, user_id, xp, week_xp, week_start_on, updated_at)
  VALUES (v_community, new.user_id, 3, 3, wk, now())
  ON CONFLICT (community_id, user_id) DO UPDATE SET
    xp      = community_streaks.xp + 3,
    week_xp = CASE WHEN community_streaks.week_start_on = wk
                   THEN community_streaks.week_xp + 3 ELSE 3 END,
    week_start_on = wk,
    updated_at    = now();

  PERFORM public.log_score_event(new.user_id, 'community_xp', 3);
  RETURN new;
END $function$;

DROP TRIGGER IF EXISTS trg_award_community_comment_xp ON public.comments;
CREATE TRIGGER trg_award_community_comment_xp
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.award_community_comment_xp();

-- ── 2. Ledger row for community posting ─────────────────────────────────────
-- Body is otherwise byte-for-byte what was live; only the log_score_event
-- call at the end is new.

CREATE OR REPLACE FUNCTION public.bump_community_streak()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  d      DATE := (new.created_at AT TIME ZONE 'Asia/Kolkata')::date;
  wk     DATE := current_week_start();
  prev   DATE;
  prevwk DATE;
BEGIN
  SELECT last_post_on, week_start_on INTO prev, prevwk
    FROM community_streaks
   WHERE community_id = new.community_id AND user_id = new.user_id;

  INSERT INTO community_streaks (
    community_id, user_id, current_streak, longest_streak, last_post_on,
    xp, week_xp, week_start_on, updated_at
  )
  VALUES (new.community_id, new.user_id, 1, 1, d, 10, 10, wk, now())
  ON CONFLICT (community_id, user_id) DO UPDATE SET
    current_streak = CASE
      WHEN community_streaks.last_post_on = d THEN community_streaks.current_streak
      WHEN community_streaks.last_post_on = d - 1 THEN community_streaks.current_streak + 1
      ELSE 1
    END,
    longest_streak = GREATEST(community_streaks.longest_streak, CASE
      WHEN community_streaks.last_post_on = d THEN community_streaks.current_streak
      WHEN community_streaks.last_post_on = d - 1 THEN community_streaks.current_streak + 1
      ELSE 1
    END),
    last_post_on = d,
    xp      = community_streaks.xp + 10,
    week_xp = CASE WHEN community_streaks.week_start_on = wk
                   THEN community_streaks.week_xp + 10 ELSE 10 END,
    week_start_on = wk,
    updated_at    = now();

  PERFORM public.log_score_event(new.user_id, 'community_xp', 10);
  RETURN new;
END $function$;
