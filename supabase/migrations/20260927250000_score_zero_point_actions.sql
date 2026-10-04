-- Points for the actions that earned nothing (2026-09-27).
--
-- User ask: "see if any post card gives zero points and if so give some
-- points to that score card". Three actions had no award trigger at all, so
-- the reward card after them read +0:
--   * replying to someone's Moment (moment_replies)   -> +20 'moment_reply'
--   * posting in a group (group_posts)                 -> +25 'group_post'
--   * adding a Duo photo (us_album_photos)             -> +20 'duo_photo'
-- Same shape as award_moment_score (glow_score + a score_events row, which
-- is what the reward card reads). Each capped at 5 awards per IST day so the
-- points can't be farmed by spamming posts.

CREATE OR REPLACE FUNCTION public.award_capped(p_user uuid, p_type text, p_points int)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF p_user IS NULL THEN RETURN; END IF;
  IF (SELECT count(*) FROM public.score_events e
       WHERE e.user_id = p_user AND e.event_type = p_type
         AND e.created_at >= ((now() AT TIME ZONE 'Asia/Kolkata')::date::timestamp AT TIME ZONE 'Asia/Kolkata')) >= 5 THEN
    RETURN;
  END IF;
  UPDATE public.users SET glow_score = glow_score + p_points WHERE id = p_user;
  PERFORM public.log_score_event(p_user, p_type, p_points);
END $function$;

CREATE OR REPLACE FUNCTION public.award_moment_reply_score()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$ BEGIN PERFORM public.award_capped(NEW.user_id, 'moment_reply', 20); RETURN NEW; END $function$;

CREATE OR REPLACE FUNCTION public.award_group_post_score()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$ BEGIN PERFORM public.award_capped(NEW.user_id, 'group_post', 25); RETURN NEW; END $function$;

CREATE OR REPLACE FUNCTION public.award_duo_photo_score()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$ BEGIN PERFORM public.award_capped(NEW.uploaded_by, 'duo_photo', 20); RETURN NEW; END $function$;

DROP TRIGGER IF EXISTS trg_award_moment_reply_score ON public.moment_replies;
CREATE TRIGGER trg_award_moment_reply_score AFTER INSERT ON public.moment_replies
  FOR EACH ROW EXECUTE FUNCTION public.award_moment_reply_score();

DROP TRIGGER IF EXISTS trg_award_group_post_score ON public.group_posts;
CREATE TRIGGER trg_award_group_post_score AFTER INSERT ON public.group_posts
  FOR EACH ROW EXECUTE FUNCTION public.award_group_post_score();

DROP TRIGGER IF EXISTS trg_award_duo_photo_score ON public.us_album_photos;
CREATE TRIGGER trg_award_duo_photo_score AFTER INSERT ON public.us_album_photos
  FOR EACH ROW EXECUTE FUNCTION public.award_duo_photo_score();

-- Internal only (Postgres grants EXECUTE to PUBLIC by default).
REVOKE EXECUTE ON FUNCTION public.award_capped(uuid, text, int) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_moment_reply_score() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_group_post_score() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_duo_photo_score() FROM PUBLIC, anon, authenticated;
