-- NOTIFICATION SYSTEM — PHASE 2: pinned-view coverage (spec §6.7B).
--
-- "A pinned person viewing any of your content notifies you, STANDARD,
--  surface named... Never names the pinned person (they don't know they're
--  pinned)."
--
-- Before: ONE path existed (notify_pinned_post_view on post_views) with a
-- single generic title for every kind of post, no group-post path at all,
-- and two separate ways to recover the viewer's identity.
--
-- ==================== THE PRIVACY FIX (ruling 2) =====================
--
-- actor_id was set to the viewer on every pinned_post_view row. NULLing it
-- is necessary but was NOT sufficient, and assuming it was would have
-- shipped a fix that does not fix anything:
--
--   notification_feed_service selects `dedupe_key` alongside the row, and
--   the key was built as 'pinned_post_view:<post_id>:<viewer_id>'. The
--   recipient therefore received the viewer's UUID in plain text whether or
--   not any widget rendered it.
--
-- Hashing the viewer into the key would not have helped either. The
-- recipient is the person who created the pin list, so they can enumerate
-- their own pinned users (list_pinned_people) and hash each candidate until
-- one matches — a search space of at most 5.
--
-- So the viewer is removed from the key entirely and the dedupe unit
-- becomes (content, campus day) instead of (content, viewer):
--
--   * Nothing viewer-derived is stored on a row the recipient can read.
--   * Two different pinned people viewing the same post on the same day now
--     collapse to one notification. That is correct rather than lossy —
--     the copy is "Someone you pinned saw your post", which is equally true
--     of one viewer or three, and it never named anyone to begin with.
--   * The same person viewing repeatedly still collapses, as before.
--
-- Everything the recipient can read is now about their OWN content
-- (post_id, group_post_id, their own user id), never about the viewer.

-- ============ 1. POSTS: post / Dip / Moment, surface named ===========
CREATE OR REPLACE FUNCTION public.notify_pinned_post_view()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_owner uuid; v_vis text; v_kind text;
  v_title text; v_screen text; v_day text;
BEGIN
  SELECT user_id, visibility, post_type INTO v_owner, v_vis, v_kind
  FROM public.posts WHERE id = NEW.post_id AND deleted_at IS NULL;

  IF v_owner IS NULL OR v_owner = NEW.viewer_id THEN RETURN NEW; END IF;

  IF NOT COALESCE(public.is_pinned_by(v_owner, NEW.viewer_id), false) THEN
    RETURN NEW;
  END IF;

  -- Surface naming, §6.7B. Anonymous is checked FIRST: an anon post is a
  -- Dip regardless of its post_type, and §6.5 requires anon-post copy to
  -- say "Dip" with no group name present, which is exactly this row's
  -- shape (a personal post has no group anywhere in it).
  IF v_vis = 'anonymous' THEN
    v_title  := 'Someone you pinned saw your Dip 👀';
    v_screen := 'post';
  ELSIF v_kind = 'moment' THEN
    v_title  := 'Someone you pinned saw your Moment 👀';
    v_screen := 'moment';
  ELSE
    v_title  := 'Someone you pinned saw your post 👀';
    v_screen := 'post';
  END IF;

  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  PERFORM set_config('app.notif_trusted', 'on', true);
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  VALUES (v_owner, 'pinned_post_view',
          NULL,                      -- privacy fix: never the viewer
          NEW.post_id, 'standard', v_title, NULL,
          jsonb_build_object('screen', v_screen, 'post_id', NEW.post_id),
          'pinned_post_view:' || NEW.post_id::text || ':' || v_day)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  PERFORM set_config('app.notif_trusted', 'off', true);

  RETURN NEW;
END;
$function$;

-- ==================== 2. GROUP POSTS (new path) ======================
-- group_post_views has existed all along with no trigger on it, so this
-- surface notified nobody.
--
-- post_id stays NULL: notifications_post_id_fkey references posts(id), and
-- a group post id would violate it. The id travels in data instead.
--
-- Deep link is tab-level (screen='group' + group_id) by the standing
-- decision to park entity-level group links as post-launch polish.
CREATE OR REPLACE FUNCTION public.notify_pinned_group_post_view()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_owner uuid; v_group uuid; v_day text;
BEGIN
  SELECT gp.user_id, gp.group_id INTO v_owner, v_group
    FROM public.group_posts gp
   WHERE gp.id = NEW.group_post_id AND gp.deleted_at IS NULL;

  IF v_owner IS NULL OR v_owner = NEW.viewer_id THEN RETURN NEW; END IF;

  IF NOT COALESCE(public.is_pinned_by(v_owner, NEW.viewer_id), false) THEN
    RETURN NEW;
  END IF;

  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  PERFORM set_config('app.notif_trusted', 'on', true);
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  VALUES (v_owner, 'pinned_post_view', NULL, NULL, 'standard',
          'Someone you pinned saw your group post 👀', NULL,
          jsonb_build_object('screen','group','group_id', v_group,
                             'group_post_id', NEW.group_post_id),
          'pinned_group_post_view:' || NEW.group_post_id::text || ':' || v_day)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  PERFORM set_config('app.notif_trusted', 'off', true);

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pinned_group_post_view ON public.group_post_views;
CREATE TRIGGER trg_notify_pinned_group_post_view
AFTER INSERT ON public.group_post_views
FOR EACH ROW EXECUTE FUNCTION public.notify_pinned_group_post_view();

-- ================== 3. PROFILE (Phase 1a, key fixed) =================
-- Same dedupe leak as the post path: the Phase 1a key embedded the viewer.
-- actor_id was already NULL there; this closes the other half.
CREATE OR REPLACE FUNCTION public.notify_pinned_profile_view()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_day text;
BEGIN
  IF NEW.viewer_id = NEW.viewed_user_id THEN RETURN NEW; END IF;

  IF NOT COALESCE(public.is_pinned_by(NEW.viewed_user_id, NEW.viewer_id), false) THEN
    RETURN NEW;
  END IF;

  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  PERFORM set_config('app.notif_trusted', 'on', true);
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.viewed_user_id, 'pinned_profile_view', NULL, 'standard',
          'Someone you pinned visited your profile 👀', NULL,
          jsonb_build_object('screen','profile'),
          -- owner id only. The owner IS the recipient, so this discloses
          -- nothing they do not already know.
          'pinned_profile_view:' || NEW.viewed_user_id::text || ':' || v_day)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  PERFORM set_config('app.notif_trusted', 'off', true);

  RETURN NEW;
END;
$function$;
