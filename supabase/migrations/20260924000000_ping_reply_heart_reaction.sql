-- PING REPLY REACTIONS — explicit request: when the original ping's sender
-- opens a photo reply, they can heart-react to it, and the replier gets
-- notified. New feature — no reaction concept existed on pings/ping_replies
-- before this (checked: no reaction column on either table).

ALTER TABLE public.ping_replies
  ADD COLUMN IF NOT EXISTS liked_by_sender boolean NOT NULL DEFAULT false;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'reaction','ping','friend_request','friend_accepted','branch_view','us_album_mutual',
    'report_resolved','report_filed','announcement','ping_answered','us_album_invite','comment',
    'moment_contribution','group_added','group_post','group_dip','community_post','friend_post',
    'streak_risk_red','streak_risk_blue','streak_milestone_blue','group_streak_ping','group_streak_risk',
    'group_streak_broken','level_up','level_progress','leaderboard_movement','ping_unanswered',
    'group_ping_waiting','group_ping_replied','pinned_post_view','pinned_group_post_view',
    'moment_new_post','moment_reply_nudge','pinned_profile_view','rank_overtaken','rank_regained',
    'streak_rank_overtaken','start_streak_nudge','streak_standing','window_prompt','break_live_count',
    'midday_report','day_digest','lifecycle_cooling','lifecycle_lapsed','lifecycle_dormant',
    'activation_nudge','graduation',
    'ping_reply_liked'
  ]));

-- Only the ping's ORIGINAL SENDER may react to a reply addressed to them —
-- enforced here (not trusted from the client), matching every other ping
-- write's own trust boundary (send_ping, ping_back_anonymous, etc).
-- Toggles (not just sets) so a second tap un-hearts, same affordance shape
-- as every "like" button elsewhere. Returns the new state so the client
-- never has to guess which way it landed.
CREATE OR REPLACE FUNCTION public.toggle_ping_reply_like(p_reply_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid;
  v_sender uuid;
  v_replier uuid;
  v_ping_id uuid;
  v_new_state boolean;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  SELECT p.sender_id, r.replier_id, r.ping_id
    INTO v_sender, v_replier, v_ping_id
  FROM public.ping_replies r
  JOIN public.pings p ON p.id = r.ping_id
  WHERE r.id = p_reply_id AND r.deleted_at IS NULL;

  IF v_sender IS NULL THEN
    RAISE EXCEPTION 'reply not found';
  END IF;
  IF v_sender <> v_me THEN
    RAISE EXCEPTION 'only the ping sender can react to this reply';
  END IF;

  UPDATE public.ping_replies
     SET liked_by_sender = NOT liked_by_sender
   WHERE id = p_reply_id
   RETURNING liked_by_sender INTO v_new_state;

  IF v_new_state THEN
    INSERT INTO public.notifications
      (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
    VALUES (v_replier, 'ping_reply_liked', v_me, 'minor',
            'Your photo got a ❤️', NULL,
            jsonb_build_object('screen','ping_reveal','ping_id', v_ping_id, 'ping_reply_id', p_reply_id),
            'ping_reply_liked:' || p_reply_id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;

  RETURN v_new_state;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.toggle_ping_reply_like(uuid) TO authenticated;
