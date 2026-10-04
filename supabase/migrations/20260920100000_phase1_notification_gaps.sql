-- NOTIFICATION SYSTEM — PHASE 1: close the three confirmed gaps.
--
-- Each of these was verified silent against the live database before being
-- written, not inferred from the spec:
--
--   a. A pinned person visiting your PROFILE produced zero notifications.
--      notify_pinned_post_view covers posts only; notify_branch_view fires
--      on profile_views but ignores pins entirely (it is the anonymous
--      "a CSE student checked out your profile" signal, gated on branch
--      size >= 100 and the viewer opting in).
--   b. A personal post that names a community as its AUDIENCE reached those
--      members' feeds silently. notify_post_fanout reads posts.community_id,
--      but the profile composer leaves that NULL and carries the community
--      in post_audiences — verified: feed visibility t, notifications (none).
--   c. A friend's Moment was folded into the generic "N friends posted
--      today" batch. Moments expire in 24h, so burying one in a MINOR batch
--      that only pushes in the wake/snack/lunch windows can cost the whole
--      lifetime of the post.

-- ====================== 1. TYPE CONSTRAINT ===========================
-- Two new types. Kept as a CHECK rather than promoted to an enum to match
-- what is already there; an enum migration would rewrite every dependent
-- function signature for no behavioural gain.
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
    -- PHASE 1 additions
    'pinned_profile_view',   -- 1a
    'friend_moment'          -- 1c
  ])
);

-- ================== 1a. PINNED PERSON VIEWED PROFILE =================
-- Mirrors notify_pinned_post_view, with one deliberate difference:
-- actor_id is left NULL.
--
-- §6.7B: "Never names the pinned person (they don't know they're pinned)."
-- Storing the actor and merely declining to render it is not the same
-- guarantee — notification_feed_service embeds
-- users!notifications_actor_id_fkey(name), so the name would be sitting in
-- the client's response whether or not any widget drew it, and the
-- blurred tap-to-reveal control exists precisely to turn such an actor into
-- a visible name. NULL is the only version of this that cannot leak.
--
-- (notify_pinned_post_view DOES set actor_id today. That is a pre-existing
-- inconsistency with the same rule, left alone here rather than changed
-- mid-phase; Phase 2 unifies all five pinned-view paths and is where it
-- belongs.)
--
-- Deduped per viewer per campus day: someone reloading your profile six
-- times is one event, not six, and a per-row key (what branch_view uses)
-- would make it six.
CREATE OR REPLACE FUNCTION public.notify_pinned_profile_view()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_day text;
BEGIN
  IF NEW.viewer_id = NEW.viewed_user_id THEN RETURN NEW; END IF;

  -- Owner must have pinned the viewer. is_pinned_by(owner, viewer).
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
          'pinned_profile_view:' || NEW.viewed_user_id::text || ':'
            || NEW.viewer_id::text || ':' || v_day)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  PERFORM set_config('app.notif_trusted', 'off', true);

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pinned_profile_view ON public.profile_views;
CREATE TRIGGER trg_notify_pinned_profile_view
AFTER INSERT ON public.profile_views
FOR EACH ROW EXECUTE FUNCTION public.notify_pinned_profile_view();

-- ============== 1b. COMMUNITY-AUDIENCE POST FAN-OUT ==================
-- The audience half of notify_post_fanout's community branch.
--
-- Fires on post_audiences rather than posts because that is where the fact
-- lives: the row is written AFTER the post insert (post_audiences_insert_own
-- requires the post to exist), so at the time notify_post_fanout runs there
-- is nothing yet to read.
--
-- Reuses type 'community_post' and the EXACT dedupe key shape
-- notify_post_fanout uses, so a member in a community that receives both a
-- direct post and an audience post on the same day gets one row counting
-- both, not two competing batches for the same community and day.
CREATE OR REPLACE FUNCTION public.notify_community_audience_post()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_post record; v_name text; v_esc text; v_day text; r record;
BEGIN
  IF NEW.audience_kind <> 'community' OR NEW.community_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.user_id, p.visibility, p.community_id, p.deleted_at, p.show_in_feed
    INTO v_post FROM public.posts p WHERE p.id = NEW.post_id;
  IF v_post.user_id IS NULL
     OR v_post.deleted_at IS NOT NULL
     OR COALESCE(v_post.show_in_feed, true) IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- Already covered by notify_post_fanout's own community branch. Without
  -- this the two would each fire for the same community and, sharing a
  -- dedupe key, inflate one batch to a count of 2 for a single post.
  IF v_post.community_id IS NOT DISTINCT FROM NEW.community_id THEN
    RETURN NEW;
  END IF;

  SELECT name INTO v_name FROM public.communities
   WHERE id = NEW.community_id AND deleted_at IS NULL;
  IF v_name IS NULL THEN RETURN NEW; END IF;

  v_esc := replace(v_name, '%', '%%');
  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  FOR r IN SELECT u.id AS uid FROM public.community_members m
             JOIN public.users u ON u.auth_id = m.user_id
            WHERE m.community_id = NEW.community_id AND u.id <> v_post.user_id LOOP
    PERFORM public.notify_batched(r.uid, 'community_post', 'minor',
      'community_post:' || r.uid::text || ':' || NEW.community_id::text || ':' || v_day,
      'New post in ' || v_name, '%s new posts in ' || v_esc,
      jsonb_build_object('screen','community','community_id', NEW.community_id));
  END LOOP;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_community_audience_post ON public.post_audiences;
CREATE TRIGGER trg_notify_community_audience_post
AFTER INSERT ON public.post_audiences
FOR EACH ROW EXECUTE FUNCTION public.notify_community_audience_post();

-- ================ 1c. A FRIEND POSTED A MOMENT =======================
-- notify_post_fanout, with the friend branch split by post_type.
--
-- A Moment gets its own type, its own dedupe key and STANDARD tier. The
-- tier is the point: MINOR only pushes in the wake digest and the two peak
-- windows (push_allowed), so a Moment posted at 2pm and folded into the
-- generic batch would not push until lunch the NEXT day — by which time the
-- 24h post is gone. STANDARD pushes in pre_class/snack/lunch/day_end/
-- evening/last_call, which is the same day.
--
-- It still batches with ITSELF ("2 friends posted Moments today") per §3 —
-- what it must never do is merge into the all-posts batch, which the
-- separate type and key guarantee.
CREATE OR REPLACE FUNCTION public.notify_post_fanout()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_name text; v_esc text; v_day text; v_author text; r record;
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

  IF NEW.visibility <> 'anonymous' THEN
    SELECT name INTO v_author FROM public.users WHERE id = NEW.user_id;
    v_author := COALESCE(NULLIF(btrim(v_author), ''), 'A friend');

    FOR r IN SELECT CASE WHEN requester_id = NEW.user_id THEN addressee_id ELSE requester_id END AS uid
               FROM public.friendships
              WHERE status = 'accepted' AND (requester_id = NEW.user_id OR addressee_id = NEW.user_id) LOOP
      IF NEW.post_type = 'moment' THEN
        PERFORM public.notify_batched(r.uid, 'friend_moment', 'standard',
          'friend_moment:' || r.uid::text || ':' || v_day,
          v_author || ' posted a Moment — 24h to see it',
          '%s friends posted Moments today',
          jsonb_build_object('screen','feed','post_id', NEW.id));
      ELSE
        PERFORM public.notify_batched(r.uid, 'friend_post', 'minor',
          'friend_post:' || r.uid::text || ':' || v_day,
          'A friend posted', '%s friends posted today',
          jsonb_build_object('screen','feed'));
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END; $function$;
