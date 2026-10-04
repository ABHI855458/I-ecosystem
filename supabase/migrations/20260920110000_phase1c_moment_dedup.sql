-- PHASE 1c, CORRECTED.
--
-- The previous migration added a 'friend_moment' type on the assumption
-- that a friend's Moment had no dedicated notification. It does:
-- notify_moment_new_post_to_friends (trigger trg_notify_moment_new_post_to_
-- friends on posts) already fires 'moment_new_post' — STANDARD, one row per
-- friend per Moment, naming the poster, body "Reply with your own to unlock
-- it before it's gone", deep-linked to screen=moment with the real post_id.
-- That is precisely what Phase 1c asks for, and it predates this work.
--
-- Caught by the Phase 1 test itself: a single friend Moment produced FOUR
-- notifications, among them both 'moment_new_post' and the new
-- 'friend_moment' — the same event, announced twice.
--
-- So the real defect was never a missing Moment notification. It was that
-- notify_post_fanout ALSO counted every Moment into the generic
-- "N friends posted today" batch. A friend posting a Moment therefore
-- incremented the all-posts counter as well, which both double-notified and
-- inflated that count with posts it was not describing.
--
-- Fix: Moments leave the generic friend batch entirely and
-- 'moment_new_post' stays their single path. 'friend_moment' is withdrawn
-- rather than left as a dead type nothing emits.
--
-- DELIBERATE DEVIATION FROM §3, flagged rather than silently taken: the
-- spec suggests Moments should batch with themselves ("2 friends posted
-- Moments today"). moment_new_post does not — it is one row per Moment.
-- Keeping it that way is the better trade against Phase 7's actionability
-- rule: a per-Moment row carries that Moment's post_id and opens it
-- directly, while a batched row can only land on the feed and makes the
-- reader hunt for a post that expires in 24h. Batching here would buy a
-- tidier count by giving up the deep link. Say the word and it flips.

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY[
    'reaction','ping','friend_request','friend_accepted','branch_view',
    'us_album_mutual','report_resolved','report_filed','announcement',
    'ping_answered','us_album_invite','comment','moment_contribution',
    'group_added','group_post','group_dip','community_post','friend_post',
    'streak_risk_red','streak_risk_blue','streak_milestone_blue',
    'group_streak_ping','group_streak_risk','group_streak_broken',
    'level_up','level_progress','leaderboard_movement','ping_unanswered',
    'group_ping_waiting','group_ping_replied','pinned_post_view',
    'moment_new_post','moment_reply_nudge',
    'pinned_profile_view'   -- Phase 1a. 'friend_moment' withdrawn, see above.
  ])
);

CREATE OR REPLACE FUNCTION public.notify_post_fanout()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_name text; v_esc text; v_day text; r record;
BEGIN
  IF NEW.deleted_at IS NOT NULL OR COALESCE(NEW.show_in_feed, true) IS NOT TRUE THEN
    RETURN NEW;
  END IF;
  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  IF NEW.community_id IS NOT NULL THEN
    SELECT name INTO v_name FROM public.communities WHERE id = NEW.community_id;
    IF v_name IS NOT NULL THEN
      v_esc := replace(v_name, '%', '%%');
      FOR r IN SELECT u.id AS uid FROM public.community_members m
                 JOIN public.users u ON u.auth_id = m.user_id
                WHERE m.community_id = NEW.community_id AND u.id <> NEW.user_id LOOP
        PERFORM public.notify_batched(r.uid, 'community_post', 'minor',
          'community_post:' || r.uid::text || ':' || NEW.community_id::text || ':' || v_day,
          'New post in ' || v_name, '%s new posts in ' || v_esc,
          jsonb_build_object('screen','community','community_id', NEW.community_id));
      END LOOP;
    END IF;
  END IF;

  -- Moments are excluded here on purpose — notify_moment_new_post_to_friends
  -- owns them, STANDARD and deep-linked. Counting them in as well both
  -- double-notified the same event and padded "N friends posted today" with
  -- posts that notification was not about.
  IF NEW.visibility <> 'anonymous' AND NEW.post_type IS DISTINCT FROM 'moment' THEN
    FOR r IN SELECT CASE WHEN requester_id = NEW.user_id THEN addressee_id ELSE requester_id END AS uid
               FROM public.friendships
              WHERE status = 'accepted' AND (requester_id = NEW.user_id OR addressee_id = NEW.user_id) LOOP
      PERFORM public.notify_batched(r.uid, 'friend_post', 'minor',
        'friend_post:' || r.uid::text || ':' || v_day,
        'A friend posted', '%s friends posted today',
        jsonb_build_object('screen','feed'));
    END LOOP;
  END IF;
  RETURN NEW;
END; $function$;
