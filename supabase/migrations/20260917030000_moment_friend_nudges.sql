-- Moment reply nudges to friends. Three moments in a friend's inbox for
-- every Moment posted: "X posted a Moment" right away, a reminder at 3h if
-- still unreplied, and a second reminder at 8h (3h + 5h) if it's STILL
-- unreplied — "send notification to all the users who are friends of the
-- user to reply to the moment... once they post and after that 3 hrs if
-- they havent replied and again after 5 hrs if they still havent replied
-- send it like [a] dopamine hitting message."
--
-- All three ride the existing notifications table + notify-dispatch-sweep
-- cron (every 5 min) — no new delivery path, same as every other
-- notification type in this app.

-- 1) Fires once per Moment, to every accepted friend of its poster.
CREATE OR REPLACE FUNCTION public.notify_moment_new_post_to_friends()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_name text;
BEGIN
  IF NEW.post_type IS DISTINCT FROM 'moment'
     OR NEW.visibility = 'anonymous' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(u.name), ''), 'Someone') INTO v_name
    FROM public.users u WHERE u.id = NEW.user_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  SELECT
    CASE WHEN f.requester_id = NEW.user_id THEN f.addressee_id ELSE f.requester_id END,
    'moment_new_post', NEW.user_id, NEW.id, 'standard',
    v_name || ' just posted a Moment 🌅',
    'Reply with your own to unlock it before it''s gone',
    jsonb_build_object('screen', 'moment', 'post_id', NEW.id),
    'moment_new_post:' || NEW.id::text || ':' ||
      (CASE WHEN f.requester_id = NEW.user_id THEN f.addressee_id ELSE f.requester_id END)::text
  FROM public.friendships f
  WHERE f.status = 'accepted'
    AND (f.requester_id = NEW.user_id OR f.addressee_id = NEW.user_id)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_moment_new_post_to_friends ON public.posts;
CREATE TRIGGER trg_notify_moment_new_post_to_friends
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_moment_new_post_to_friends();

-- 2) Sweep: the two reminder milestones, one row per (moment, friend,
-- milestone) — the unique dedupe_key means each fires exactly once no
-- matter how many times this runs before the window closes.
CREATE OR REPLACE FUNCTION public.notify_moment_reply_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- +3h reminder — same "dopamine hit" register as the initial post, not a
  -- bland nag: keep it about what's waiting to be unlocked, not the clock.
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  SELECT
    CASE WHEN f.requester_id = p.user_id THEN f.addressee_id ELSE f.requester_id END AS friend_id,
    'moment_reply_nudge', p.user_id, p.id, 'standard',
    '👀 ' || COALESCE(NULLIF(btrim(u.name), ''), 'a friend') || '''s Moment is still locked for you',
    'Add your own photo to see what everyone else is seeing',
    jsonb_build_object('screen', 'moment', 'post_id', p.id),
    'moment_reply_nudge:1:' || p.id::text || ':' ||
      (CASE WHEN f.requester_id = p.user_id THEN f.addressee_id ELSE f.requester_id END)::text
  FROM public.posts p
  JOIN public.users u ON u.id = p.user_id
  JOIN public.friendships f ON f.status = 'accepted'
    AND (f.requester_id = p.user_id OR f.addressee_id = p.user_id)
  WHERE p.post_type = 'moment'
    AND p.visibility <> 'anonymous'
    AND p.deleted_at IS NULL
    AND p.created_at <= now() - interval '3 hours'
    AND p.created_at > now() - interval '24 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.moment_replies mr
       WHERE mr.moment_post_id = p.id
         AND mr.user_id = (CASE WHEN f.requester_id = p.user_id THEN f.addressee_id ELSE f.requester_id END)
    )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  -- +8h reminder (3h + 5h) — only for whoever is STILL silent after the
  -- first nudge.
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  SELECT
    CASE WHEN f.requester_id = p.user_id THEN f.addressee_id ELSE f.requester_id END AS friend_id,
    'moment_reply_nudge', p.user_id, p.id, 'major',
    '⏳ Last chance on ' || COALESCE(NULLIF(btrim(u.name), ''), 'their') || ''' Moment',
    'It''s about to be gone for good — reply now to see it',
    jsonb_build_object('screen', 'moment', 'post_id', p.id),
    'moment_reply_nudge:2:' || p.id::text || ':' ||
      (CASE WHEN f.requester_id = p.user_id THEN f.addressee_id ELSE f.requester_id END)::text
  FROM public.posts p
  JOIN public.users u ON u.id = p.user_id
  JOIN public.friendships f ON f.status = 'accepted'
    AND (f.requester_id = p.user_id OR f.addressee_id = p.user_id)
  WHERE p.post_type = 'moment'
    AND p.visibility <> 'anonymous'
    AND p.deleted_at IS NULL
    AND p.created_at <= now() - interval '8 hours'
    AND p.created_at > now() - interval '24 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.moment_replies mr
       WHERE mr.moment_post_id = p.id
         AND mr.user_id = (CASE WHEN f.requester_id = p.user_id THEN f.addressee_id ELSE f.requester_id END)
    )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
END;
$function$;

SELECT cron.schedule(
  'notify-moment-reply-reminders',
  '*/15 * * * *',
  $$SELECT public.notify_moment_reply_reminders();$$
);
