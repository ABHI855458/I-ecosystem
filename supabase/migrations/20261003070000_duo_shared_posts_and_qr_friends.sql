-- ============================================================================
-- Duo posts are SHARED by both partners, and a QR scan makes the two people
-- friends (explicit requests, 2026-10-03).
--
-- 1. DUO POSTS — "if either one posts it shall appear in feed, and the other
--    person shall be notified as posted, choose your audience and post; but
--    if anyone of them makes it private it becomes private for both, and
--    anyone of them can remove the post."
--
--    A Duo post is ONE `posts` row carrying both people (user_id =
--    whoever shot it, partner_user_id = the other). Until now only
--    posts.user_id could touch it, so the partner could neither hide it
--    nor delete it, and was never told it existed.
--
--    Permissive policies OR together in Postgres, so each right is ADDED as
--    its own policy rather than rewriting the existing author policies —
--    nothing about the author's own rights changes.
--
--      * posts_update_duo_partner  — the partner can flip show_in_feed
--        (making it private hides it for BOTH, since there is only one row)
--        and edit the shared caption.
--      * posts_delete_duo_partner  — either side can remove it.
--      * post_audiences_*_duo_partner — the partner can add THEIR OWN
--        circles as an audience ("choose your audience and post"), so the
--        same photo reaches their friends too, and can take them away
--        again. post_audience_admits already ORs every audience row, so
--        one extra row is all it takes.
--
-- 2. notify_duo_post() — tells the partner the moment it is posted, with
--    the "choose your audience" call to action. New type 'duo_post'.
--
-- 3. add_mutual_friends() — the QR scanner's missing half: scanning a code
--    puts each person in the OTHER's Friends circle. Cross-user writes are
--    impossible under circle_members' own RLS (a circle belongs to its
--    creator), so this is SECURITY DEFINER and deliberately narrow: it
--    touches ONLY the two 'friends' circles of the two ids involved, and
--    one of them must be the caller.
--
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

-- ── 1. Duo posts: the partner gets the same rights over the shared row ────

DROP POLICY IF EXISTS posts_update_duo_partner ON public.posts;
CREATE POLICY posts_update_duo_partner ON public.posts
  FOR UPDATE TO authenticated
  USING (partner_user_id IS NOT NULL AND partner_user_id = public.current_user_id())
  WITH CHECK (partner_user_id IS NOT NULL AND partner_user_id = public.current_user_id());

DROP POLICY IF EXISTS posts_delete_duo_partner ON public.posts;
CREATE POLICY posts_delete_duo_partner ON public.posts
  FOR DELETE TO authenticated
  USING (partner_user_id IS NOT NULL AND partner_user_id = public.current_user_id());

-- True when this post is a Duo post whose OTHER half is the caller.
CREATE OR REPLACE FUNCTION public.is_my_duo_post(p_post uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.posts p
     WHERE p.id = p_post
       AND p.deleted_at IS NULL
       AND p.partner_user_id IS NOT NULL
       AND p.partner_user_id = public.current_user_id()
  );
$function$;

REVOKE ALL ON FUNCTION public.is_my_duo_post(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_my_duo_post(uuid) TO authenticated;

DROP POLICY IF EXISTS post_audiences_insert_duo_partner ON public.post_audiences;
CREATE POLICY post_audiences_insert_duo_partner ON public.post_audiences
  FOR INSERT TO authenticated
  WITH CHECK (public.is_my_duo_post(post_id));

DROP POLICY IF EXISTS post_audiences_delete_duo_partner ON public.post_audiences;
CREATE POLICY post_audiences_delete_duo_partner ON public.post_audiences
  FOR DELETE TO authenticated
  USING (public.is_my_duo_post(post_id));

-- The existing select policy hides 'circle' rows from everyone but the
-- author; the partner needs to read the ones they added back.
DROP POLICY IF EXISTS post_audiences_select_duo_partner ON public.post_audiences;
CREATE POLICY post_audiences_select_duo_partner ON public.post_audiences
  FOR SELECT TO authenticated
  USING (public.is_my_duo_post(post_id));

-- ── 2. Tell the partner it was posted ─────────────────────────────────────

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
    'ping_unreplied','group_message',
    -- new
    'duo_post'
  ])
);

CREATE OR REPLACE FUNCTION public.notify_duo_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_who text;
BEGIN
  IF NEW.partner_user_id IS NULL
     OR NEW.partner_user_id = NEW.user_id
     OR NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Your Duo')
    INTO v_who FROM public.users u WHERE u.id = NEW.user_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.partner_user_id, 'duo_post', NEW.user_id, 'major',
          COALESCE(v_who, 'Your Duo') || ' posted to your Duo 💞',
          'Choose your audience and post it to your friends too',
          jsonb_build_object(
            'screen', 'duo_post',
            'post_id', NEW.id,
            'us_album_id', NEW.us_album_id
          ),
          'duo_post:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_duo_post ON public.posts;
CREATE TRIGGER trg_notify_duo_post
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_duo_post();

REVOKE ALL ON FUNCTION public.notify_duo_post() FROM PUBLIC, anon, authenticated;

-- ── 3. A QR scan makes the two people friends, both ways ──────────────────

CREATE OR REPLACE FUNCTION public.add_mutual_friends(p_other uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id();
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_other IS NULL OR p_other = v_me THEN RETURN; END IF;
  IF public.is_blocked_user(auth.uid(), p_other) THEN
    RAISE EXCEPTION 'Cannot add this user.';
  END IF;
  -- Each person needs their default circles to exist before anyone can be
  -- put in them (a brand-new account may not have been seeded yet).
  PERFORM public.seed_default_circles(v_me);
  PERFORM public.seed_default_circles(p_other);

  INSERT INTO public.circle_members (circle_id, member_id)
  SELECT c.id, x.member
    FROM (VALUES (v_me, p_other), (p_other, v_me)) AS x(owner, member)
    JOIN public.circles c ON c.creator_id = x.owner AND c.kind = 'friends'
  ON CONFLICT (circle_id, member_id) DO NOTHING;
END;
$function$;

REVOKE ALL ON FUNCTION public.add_mutual_friends(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_mutual_friends(uuid) TO authenticated;

COMMIT;
