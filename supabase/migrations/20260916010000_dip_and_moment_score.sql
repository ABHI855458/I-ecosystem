-- Dip and Moment scoring — neither awarded anything before this. Explicit
-- spec: dip = 15, a Moment posted anonymously = 25 (same as any anon post
-- — trg_award_anon_post_score already covers this, fires on
-- visibility='anonymous' regardless of post_type, so nothing changes
-- there), a Moment posted in the poster's own name = 30.
--
-- The new moment trigger's WHEN clause explicitly excludes
-- visibility='anonymous' so an anonymous Moment is never double-awarded
-- (25 from the existing trigger + 30 from this one) — it gets exactly one
-- of the two, matching "moment posted anonymously 25... in his own name
-- 30" as an either/or, not additive.
CREATE OR REPLACE FUNCTION public.award_moment_score()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  UPDATE public.users SET glow_score = glow_score + 30 WHERE id = NEW.user_id;
  PERFORM public.log_score_event(NEW.user_id, 'moment_post', 30);
  PERFORM public.bump_daily_streak(NEW.user_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_award_moment_score ON public.posts;
CREATE TRIGGER trg_award_moment_score
  AFTER INSERT ON public.posts
  FOR EACH ROW
  WHEN (NEW.post_type = 'moment' AND NEW.visibility IS DISTINCT FROM 'anonymous')
  EXECUTE FUNCTION public.award_moment_score();

-- Dip — 15 points, no daily-streak bump (that's the RED anon-post streak's
-- own mechanic; a dip is a different, group-scoped activity).
CREATE OR REPLACE FUNCTION public.award_dip_score()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  UPDATE public.users SET glow_score = glow_score + 15 WHERE id = NEW.user_id;
  PERFORM public.log_score_event(NEW.user_id, 'dip_post', 15);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_award_dip_score ON public.dips;
CREATE TRIGGER trg_award_dip_score
  AFTER INSERT ON public.dips
  FOR EACH ROW EXECUTE FUNCTION public.award_dip_score();
