-- ============================================================================
-- "Notification if somebody messaged in group" (explicit request,
-- 2026-10-03) — a push + in-app row when another member posts in a group
-- CHAT (group_messages, 20261003020000).
--
--  * New notifications.type 'group_message'. The CHECK is replaced
--    wholesale (Postgres has no ADD VALUE for a CHECK list) with the live
--    55 values plus this one.
--  * notify_group_message(): one row per OTHER member, tier 'major' so
--    notify-dispatch pushes it rather than folding it into the digest.
--  * Burst control: the dedupe key buckets by sender + 2-minute window, so
--    someone firing off five messages produces ONE push, while a message
--    three minutes later notifies again. (notifications has a unique index
--    on (type, dedupe_key), which ON CONFLICT DO NOTHING rides.)
--  * The body is the message text, or "📷 Photo" for a photo-only message
--    — the same shape the chat list preview uses. A private group's
--    content is only ever sent to its own members, who can already read
--    it in the chat.
--
-- Community notifications are deliberately NOT touched: the only community
-- notifier live is trg_fanout_priority_announcement, which already returns
-- early unless is_priority — i.e. "only priority community notifications"
-- (same request) is already the live behaviour. notify_post_fanout no
-- longer has a community branch and notify_community_audience_post is
-- unwired, so ordinary community posts/chat notify nobody.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY[
    'reaction','ping','branch_view','us_album_mutual','report_resolved',
    'report_filed','announcement','ping_answered','us_album_invite','comment',
    'moment_contribution','group_added','group_invite','group_post','group_dip',
    'community_post','friend_post','streak_risk_red','streak_risk_blue',
    'streak_milestone_blue','group_streak_ping','group_streak_risk',
    'group_streak_broken','level_up','level_progress','leaderboard_movement',
    'ping_unanswered','group_ping_waiting','group_ping_replied',
    'pinned_post_view','pinned_group_post_view','moment_new_post',
    'moment_reply_nudge','pinned_profile_view','rank_overtaken','rank_regained',
    'streak_rank_overtaken','start_streak_nudge','streak_standing',
    'window_prompt','break_live_count','midday_report','day_digest',
    'lifecycle_cooling','lifecycle_lapsed','lifecycle_dormant',
    'activation_nudge','graduation','ping_reply_liked','us_album_accepted',
    'group_profile_view','us_album_ended','daily_drop','weekly_recap',
    'ping_unreplied',
    -- new
    'group_message'
  ])
);

CREATE OR REPLACE FUNCTION public.notify_group_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_who text;
  v_group text;
  v_body text;
  v_bucket text;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Someone')
    INTO v_who FROM public.users u WHERE u.id = NEW.sender_id;

  SELECT g.name INTO v_group FROM public.groups g WHERE g.id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;

  v_body := COALESCE(NULLIF(btrim(NEW.body), ''), '📷 Photo');

  -- 2-minute buckets: a burst collapses to one push, a later message gets
  -- its own.
  v_bucket := to_char(
    date_trunc('hour', NEW.created_at)
      + (floor(extract(minute FROM NEW.created_at)::int / 2) * interval '2 minutes'),
    'YYYYMMDDHH24MI'
  );

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT gm.user_id,
         'group_message',
         NEW.sender_id,
         'major',
         v_who || ' in ' || v_group,
         v_body,
         jsonb_build_object(
           'screen', 'group_chat',
           'group_id', NEW.group_id
         ),
         'group_message:' || NEW.group_id::text || ':' || NEW.sender_id::text
           || ':' || gm.user_id::text || ':' || v_bucket
    FROM public.group_members gm
   WHERE gm.group_id = NEW.group_id
     AND gm.user_id <> NEW.sender_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_group_message ON public.group_messages;
CREATE TRIGGER trg_notify_group_message
  AFTER INSERT ON public.group_messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_message();

REVOKE ALL ON FUNCTION public.notify_group_message() FROM PUBLIC, anon, authenticated;

COMMIT;
