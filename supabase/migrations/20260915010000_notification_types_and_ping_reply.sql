-- notification_system_spec.md §5.2 and §5.3.
--
-- §5.2 — widen notifications.type. The old CHECK allowed 9 values; every
-- event the spec adds in §2 (and every streak/level event in §4) had no
-- legal `type` to insert under, so those triggers could not have been
-- written at all without this running first.
--
-- §5.3 — the ping-reply notification, called out in the spec as "the
-- single highest-priority gap — it's the core loop". `ping_replies` had
-- three triggers on it (score award, mark-replied, set-replied) and not
-- one of them notified the person whose ping was answered.

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  -- already live
  'reaction', 'ping', 'friend_request', 'friend_accepted', 'branch_view',
  'us_album_mutual', 'report_resolved', 'report_filed', 'announcement',
  -- spec §2, previously unrepresentable
  'ping_answered', 'us_album_invite', 'comment', 'moment_contribution',
  'group_added', 'group_post', 'group_dip', 'community_post', 'friend_post',
  -- spec §4 — the three streak systems + score/level progress
  'streak_risk_red', 'streak_risk_blue', 'streak_milestone_blue',
  'group_streak_ping', 'group_streak_risk', 'group_streak_broken',
  'level_up', 'level_progress', 'leaderboard_movement'
));

-- ----------------------------------------
-- PING ANSWERED (MAJOR) — spec §3, §5.3, §7
-- ----------------------------------------
-- Recipient is the ORIGINAL ping's sender, not the replier. Resolved
-- through pings.sender_id because ping_replies only carries ping_id.
--
-- Anonymity (spec §6): the replier is ALWAYS named, even when the ping
-- they are answering was sent anonymously — an anonymous ping hides the
-- SENDER from the receiver, and here the sender is the one being notified.
-- So actor_id is safe to set and the name is safe to put in the title.
CREATE OR REPLACE FUNCTION notify_ping_reply() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_sender       uuid;
  v_replier_name text;
BEGIN
  SELECT sender_id INTO v_sender FROM public.pings WHERE id = NEW.ping_id;

  -- No ping row, or you replied to your own ping: nothing to say.
  IF v_sender IS NULL OR v_sender = NEW.replier_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_replier_name
    FROM public.users WHERE id = NEW.replier_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (
    v_sender,
    'ping_answered',
    NEW.replier_id,
    'major',
    COALESCE(v_replier_name, 'someone') || ' answered your ping 🔥',
    NULL,
    -- screen/ping_id drive the client's tap-through into the blur-reveal
    -- viewer; the same keys the notify-ping-reply Edge Function puts in its
    -- FCM data payload, so a push tap and an in-app tap land identically.
    jsonb_build_object(
      'screen', 'ping_reveal',
      'ping_id', NEW.ping_id,
      'ping_reply_id', NEW.id
    ),
    'ping_answered:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_ping_reply ON ping_replies;
CREATE TRIGGER trg_notify_ping_reply
  AFTER INSERT ON ping_replies
  FOR EACH ROW EXECUTE FUNCTION notify_ping_reply();

-- ----------------------------------------
-- RealMoji copy (spec §3) — "{name} reacted {emoji} to your post"
-- ----------------------------------------
-- The trigger itself is already on the right table: spec §5.1 says
-- notify_reaction must "move to post_realmoji_reactions", but migration
-- 20260908160000_realmoji_notification.sql already added
-- trg_notify_realmoji_reaction there and it is enabled. Only the copy was
-- stale (emoji lived in `body`, not the title line the spec asks for), and
-- the legacy `reactions` trigger stays put because reaction_service.dart
-- still writes that table on the non-anon feed.
CREATE OR REPLACE FUNCTION notify_realmoji_reaction() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_owner      uuid;
  v_actor_name text;
  v_anon       boolean := false;
  v_emoji      text;
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id, (visibility = 'anonymous')
      INTO v_owner, v_anon
      FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  IF v_owner IS NULL OR v_owner = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name
    FROM public.users WHERE id = NEW.user_id;

  v_emoji := NULLIF(NEW.emoji_type::text, '');

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, dedupe_key)
  VALUES (
    v_owner,
    'reaction',
    -- The REACTOR is never anonymous — only a post's author can be — so
    -- naming them to the post's owner leaks nothing (spec §6).
    NEW.user_id,
    NEW.post_id,
    'standard',
    v_actor_name || ' reacted ' || COALESCE(v_emoji || ' ', '') || 'to your post',
    CASE WHEN v_anon THEN 'on your anonymous post' ELSE NULL END,
    'realmoji:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$$;
