-- Phase 4 — Notification pipeline.
--
-- There is no notifications table, no notification_events writer, no
-- device_tokens writer, and notify_webhook() (the function schema.sql's
-- trigger declarations reference) does not exist live — confirmed via
-- pg_proc. Only one Edge Function (delete-account) is deployed; the six
-- notify-* functions in supabase/functions/ were never wired to any
-- trigger. This migration is a from-scratch, in-app (no push yet) pipeline:
-- a real `notifications` table, populated by SECURITY DEFINER triggers on
-- the events that already exist as tables, read by a real inbox client
-- (see lib/services/notification_feed_service.dart and the
-- notifications_screen.dart rewrite).
--
-- Explicitly NOT built here, per product decision: gender in any
-- notification; any notification that fires because a user DIDN'T do
-- something (no streak-punishment); pinned-person notifications (removed
-- from scope — pinning lives only in the profile eye sheet); visitor
-- notifications for branches under app_config.visitor_branch_min_students.

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipient_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('reaction', 'ping', 'friend_request', 'friend_accepted', 'branch_view')),
  actor_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  post_id uuid REFERENCES public.posts(id) ON DELETE SET NULL,
  tier text NOT NULL CHECK (tier IN ('minor', 'standard', 'major')),
  title text NOT NULL,
  body text,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  dedupe_key text,
  read_at timestamptz,
  -- Nullable and unused today — costs nothing now, and means adding push
  -- later is one Edge Function + a UPDATE on this column, not a migration.
  push_sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS notifications_dedupe_idx
  ON public.notifications (type, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS notifications_recipient_idx
  ON public.notifications (recipient_id, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notifications_select_own ON public.notifications;
CREATE POLICY notifications_select_own ON public.notifications
  FOR SELECT TO authenticated
  USING (recipient_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));

DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
CREATE POLICY notifications_update_own ON public.notifications
  FOR UPDATE TO authenticated
  USING (recipient_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()))
  WITH CHECK (recipient_id = (SELECT id FROM public.users WHERE auth_id = auth.uid()));
-- No INSERT/DELETE policy for authenticated/anon — every row is written by
-- a SECURITY DEFINER trigger below, never directly by a client.

-- Belt-and-suspenders on top of the UPDATE policy: forces every column
-- except read_at back to its OLD value, so even a client that could craft
-- an UPDATE hitting another user's notification (it can't — the USING
-- clause above already blocks that) or tries to rewrite its own
-- title/body/tier can only ever actually change read_at.
CREATE OR REPLACE FUNCTION public.lock_notification_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.recipient_id := OLD.recipient_id;
  NEW.type := OLD.type;
  NEW.actor_id := OLD.actor_id;
  NEW.post_id := OLD.post_id;
  NEW.tier := OLD.tier;
  NEW.title := OLD.title;
  NEW.body := OLD.body;
  NEW.data := OLD.data;
  NEW.dedupe_key := OLD.dedupe_key;
  NEW.created_at := OLD.created_at;
  NEW.push_sent_at := OLD.push_sent_at;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_lock_notification_fields ON public.notifications;
CREATE TRIGGER trg_lock_notification_fields
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.lock_notification_fields();

-- ---------------------------------------------------------------------------
-- Someone reacted to your post.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_reaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_owner uuid;
  v_actor_name text;
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  IF v_owner IS NULL OR v_owner = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name FROM public.users WHERE id = NEW.user_id;

  INSERT INTO public.notifications (recipient_id, type, actor_id, post_id, tier, title, body, dedupe_key)
  VALUES (
    v_owner, 'reaction', NEW.user_id, NEW.post_id, 'minor',
    COALESCE(v_actor_name, 'someone') || ' reacted to your post',
    NEW.emoji,
    'reaction:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_reaction() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_reaction ON public.reactions;
CREATE TRIGGER trg_notify_reaction
  AFTER INSERT ON public.reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_reaction();

-- ---------------------------------------------------------------------------
-- Someone pinged you. Respects pings.anonymous — actor withheld (NULL)
-- when the ping itself is anonymous, same as the ping UI never reveals the
-- sender in that case.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_ping()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_name text;
BEGIN
  IF NEW.receiver_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.anonymous IS TRUE THEN
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
    VALUES (NEW.receiver_id, 'ping', NULL, 'major', 'Someone pinged you', NEW.prompt, 'ping:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  ELSE
    SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name FROM public.users WHERE id = NEW.sender_id;
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
    VALUES (
      NEW.receiver_id, 'ping', NEW.sender_id, 'major',
      COALESCE(v_actor_name, 'someone') || ' pinged you', NEW.prompt, 'ping:' || NEW.id::text
    )
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_ping() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_ping ON public.pings;
CREATE TRIGGER trg_notify_ping
  AFTER INSERT ON public.pings
  FOR EACH ROW EXECUTE FUNCTION public.notify_ping();

-- ---------------------------------------------------------------------------
-- Friend request received / accepted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_friend_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_name text;
BEGIN
  IF NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name FROM public.users WHERE id = NEW.requester_id;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
  VALUES (
    NEW.addressee_id, 'friend_request', NEW.requester_id, 'standard',
    COALESCE(v_actor_name, 'someone') || ' sent you a friend request', NULL,
    'friend_request:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_friend_request() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_friend_request ON public.friendships;
CREATE TRIGGER trg_notify_friend_request
  AFTER INSERT ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.notify_friend_request();

CREATE OR REPLACE FUNCTION public.notify_friend_accepted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_actor_name text;
BEGIN
  IF NOT (OLD.status = 'pending' AND NEW.status = 'accepted') THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name FROM public.users WHERE id = NEW.addressee_id;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
  VALUES (
    NEW.requester_id, 'friend_accepted', NEW.addressee_id, 'standard',
    COALESCE(v_actor_name, 'someone') || ' accepted your friend request', NULL,
    'friend_accepted:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_friend_accepted() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_friend_accepted ON public.friendships;
CREATE TRIGGER trg_notify_friend_accepted
  AFTER UPDATE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.notify_friend_accepted();

-- ---------------------------------------------------------------------------
-- Branch visitor notification. Fires per-view (profile_view_service.dart
-- already collapses to ~1 insert/hour per viewer-viewed pair client-side,
-- so this doesn't need its own additional dedupe window beyond the
-- dedupe_key uniqueness). Body is branch-only, no gender, ever; actor_id
-- is always NULL — the viewer is never identified beyond their branch.
-- Gated on all three: viewer has a derived branch, that branch has at
-- least app_config.visitor_branch_min_students, and the viewer opted in
-- via profiles.show_branch_signal.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_branch_view()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_viewer_branch text;
  v_show_signal boolean;
  v_count bigint;
  v_min int := 100;
BEGIN
  IF NEW.viewer_id = NEW.viewed_user_id THEN
    RETURN NEW;
  END IF;

  SELECT p.branch, p.show_branch_signal INTO v_viewer_branch, v_show_signal
  FROM public.users u
  JOIN public.profiles p ON p.id = u.auth_id
  WHERE u.id = NEW.viewer_id;

  IF v_viewer_branch IS NULL OR v_show_signal IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE((value #>> '{}')::int, 100) INTO v_min
  FROM public.app_config WHERE key = 'visitor_branch_min_students';

  SELECT student_count INTO v_count
  FROM public.branch_student_counts() WHERE branch = v_viewer_branch;

  IF COALESCE(v_count, 0) < v_min THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
  VALUES (
    NEW.viewed_user_id, 'branch_view', NULL, 'minor',
    'A ' || v_viewer_branch || ' student viewed your profile', NULL,
    'branch_view:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_branch_view() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_branch_view ON public.profile_views;
CREATE TRIGGER trg_notify_branch_view
  AFTER INSERT ON public.profile_views
  FOR EACH ROW EXECUTE FUNCTION public.notify_branch_view();
