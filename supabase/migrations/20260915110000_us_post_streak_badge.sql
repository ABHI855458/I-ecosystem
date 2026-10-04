-- Us-album post streak badge — client-facing data for the feed's new
-- flame+number overlay on shared (post_type='us') posts.
--
-- SECURITY FIX bundled in: ping_streak_between(uuid,uuid), added earlier
-- today (20260915060000_streak_and_level_notifications.sql) for internal
-- server-side use (the ping-reply trigger, the Last Call cron job), was
-- left with Postgres's default EXECUTE-to-PUBLIC grant — callable by the
-- anon key with ANY two arbitrary user ids, leaking whether/how long two
-- unrelated strangers have been ping-exchanging to anyone holding the
-- (public, ships-in-the-app-binary) anon key. Revoked here, matching the
-- house pattern in 20260908140000_revoke_anon_execute.sql. Internal
-- callers (the ping-reply trigger, the Last Call cron function) are
-- unaffected: both are themselves SECURITY DEFINER, so they execute this
-- call as the function owner, not as anon/authenticated.
REVOKE ALL ON FUNCTION public.ping_streak_between(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- The client needs a specific pair's streak, but must never be able to
-- probe an arbitrary pair — so this takes a post id, not two user ids, and
-- reuses can_view_post() (the same authorization primitive posts_select's
-- own RLS policy calls) to gate it: a viewer gets the number back only for
-- a post they could already see, which already publicly names both people
-- in that pair (design_solo_card.dart's fused-avatar header) — this adds
-- no exposure beyond what the post already shows.
CREATE OR REPLACE FUNCTION public.us_post_streak(p_post_id uuid)
RETURNS INTEGER LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
  v_author uuid;
  v_partner uuid;
BEGIN
  IF NOT public.can_view_post(p_post_id) THEN
    RETURN NULL;
  END IF;

  SELECT user_id, partner_user_id INTO v_author, v_partner
    FROM public.posts
   WHERE id = p_post_id AND post_type = 'us';

  IF v_author IS NULL OR v_partner IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN public.ping_streak_between(v_author, v_partner);
END;
$$;

GRANT EXECUTE ON FUNCTION public.us_post_streak(uuid) TO authenticated;

-- Bulk variant — the feed fetches a page of posts at once
-- (feed_service.dart's _attachAuthors), so one round trip beats N.
CREATE OR REPLACE FUNCTION public.us_post_streaks(p_post_ids uuid[])
RETURNS TABLE(post_id uuid, streak integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $$
BEGIN
  RETURN QUERY
  SELECT pid, public.us_post_streak(pid)
    FROM unnest(p_post_ids) AS pid
   WHERE public.us_post_streak(pid) IS NOT NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.us_post_streaks(uuid[]) TO authenticated;
