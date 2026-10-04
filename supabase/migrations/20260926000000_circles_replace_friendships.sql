-- ============================================================================
-- Circles replace friend requests.
--
-- There is no friend request any more. Every user owns preset circles
-- (Friends, Close Friends, Family, Roommates / Work) plus any custom ones and
-- decides, alone, who is in them. "Friend" now means ONE thing everywhere:
--
--     viewer ∈ owner's Friends circle          -> public.in_friends_circle(owner, viewer)
--
-- It is one-directional on purpose: being in someone's circle gives YOU access
-- to THEIR stuff, never the reverse. Consent only exists where something is
-- actually shared: Duo albums (pending -> accept) and group albums
-- (group_invites -> accept).
--
-- This migration is additive: `friendships` is backfilled into circles and
-- then no longer read by anything. 20260926010000_drop_friendships.sql
-- removes it.
--
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. circles.kind + presets
-- ---------------------------------------------------------------------------
ALTER TABLE public.circles ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'custom';
ALTER TABLE public.circles DROP CONSTRAINT IF EXISTS circles_kind_check;
ALTER TABLE public.circles ADD CONSTRAINT circles_kind_check
  CHECK (kind IN ('friends','close_friends','family','work','custom'));

-- A user's pre-existing circle literally named "family" becomes the preset.
UPDATE public.circles c SET kind = 'family'
 WHERE lower(btrim(c.name)) = 'family' AND c.kind = 'custom'
   AND NOT EXISTS (SELECT 1 FROM public.circles o
                    WHERE o.creator_id = c.creator_id AND o.kind = 'family')
   AND c.id = (SELECT min(x.id::text)::uuid FROM public.circles x
                WHERE x.creator_id = c.creator_id AND lower(btrim(x.name)) = 'family');

CREATE UNIQUE INDEX IF NOT EXISTS circles_one_preset_per_kind
  ON public.circles (creator_id, kind) WHERE kind <> 'custom';

-- Friends is compulsory: it can't be deleted or renamed, and no circle can
-- change kind. Only the owner's own client request is blocked; account
-- deletion (service role, auth.uid() IS NULL) cascades through normally.
CREATE OR REPLACE FUNCTION public.protect_circle_kind()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.kind = 'friends' THEN
      RAISE EXCEPTION 'The Friends circle cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.kind IS DISTINCT FROM OLD.kind THEN
    RAISE EXCEPTION 'A circle''s kind cannot be changed';
  END IF;
  IF OLD.kind = 'friends' AND NEW.name IS DISTINCT FROM OLD.name THEN
    RAISE EXCEPTION 'The Friends circle cannot be renamed';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_protect_circle_kind ON public.circles;
CREATE TRIGGER trg_protect_circle_kind
  BEFORE UPDATE OR DELETE ON public.circles
  FOR EACH ROW EXECUTE FUNCTION public.protect_circle_kind();

-- Clients may only create 'custom' circles; presets come from the seeder.
CREATE OR REPLACE FUNCTION public.circles_insert_custom_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NEW.kind <> 'custom'
     AND current_setting('app.seeding_circles', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'Preset circles are created automatically';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_circles_insert_custom_only ON public.circles;
CREATE TRIGGER trg_circles_insert_custom_only
  BEFORE INSERT ON public.circles
  FOR EACH ROW EXECUTE FUNCTION public.circles_insert_custom_only();

CREATE OR REPLACE FUNCTION public.seed_default_circles(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM set_config('app.seeding_circles', 'on', true);
  INSERT INTO public.circles (creator_id, name, kind)
  SELECT p_user, v.name, v.kind
    FROM (VALUES ('friends','Friends'),
                 ('close_friends','Close Friends'),
                 ('family','Family'),
                 ('work','Roommates / Work')) AS v(kind, name)
   WHERE NOT EXISTS (SELECT 1 FROM public.circles c
                      WHERE c.creator_id = p_user AND c.kind = v.kind);
  PERFORM set_config('app.seeding_circles', 'off', true);
END $$;
REVOKE ALL ON FUNCTION public.seed_default_circles(uuid) FROM PUBLIC, anon, authenticated;

-- Client entry point (onboarding calls it; idempotent).
CREATE OR REPLACE FUNCTION public.ensure_default_circles()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_me uuid := public.current_user_id();
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  PERFORM public.seed_default_circles(v_me);
END $$;
REVOKE ALL ON FUNCTION public.ensure_default_circles() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_default_circles() TO authenticated;

-- Every new account gets its presets immediately.
CREATE OR REPLACE FUNCTION public.trg_seed_default_circles()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM public.seed_default_circles(NEW.id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_users_seed_default_circles ON public.users;
CREATE TRIGGER trg_users_seed_default_circles
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.trg_seed_default_circles();

-- Close Friends are friends: adding someone to Close Friends also puts them
-- in Friends.
CREATE OR REPLACE FUNCTION public.close_friends_imply_friends()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_owner uuid; v_friends uuid;
BEGIN
  SELECT c.creator_id INTO v_owner FROM public.circles c
   WHERE c.id = NEW.circle_id AND c.kind = 'close_friends';
  IF v_owner IS NULL THEN RETURN NEW; END IF;
  SELECT id INTO v_friends FROM public.circles
   WHERE creator_id = v_owner AND kind = 'friends';
  IF v_friends IS NOT NULL THEN
    INSERT INTO public.circle_members (circle_id, member_id)
    VALUES (v_friends, NEW.member_id)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_close_friends_imply_friends ON public.circle_members;
CREATE TRIGGER trg_close_friends_imply_friends
  AFTER INSERT ON public.circle_members
  FOR EACH ROW EXECUTE FUNCTION public.close_friends_imply_friends();

-- ---------------------------------------------------------------------------
-- 2. The one "friend" primitive + internal views (never exposed to clients)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.friends_circle_members AS
  SELECT c.creator_id AS owner_id, cm.member_id
    FROM public.circles c
    JOIN public.circle_members cm ON cm.circle_id = c.id
   WHERE c.kind = 'friends';

-- Unordered pairs where EITHER person has the other in their Friends circle.
-- Only for pair jobs (streaks, lifecycle), never for visibility.
CREATE OR REPLACE VIEW public.friend_pairs AS
  SELECT DISTINCT LEAST(owner_id, member_id) AS a, GREATEST(owner_id, member_id) AS b
    FROM public.friends_circle_members
   WHERE owner_id <> member_id;

REVOKE ALL ON public.friends_circle_members FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.friend_pairs FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.in_friends_circle(p_owner uuid, p_viewer uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT p_owner IS NOT NULL AND p_viewer IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.circles c
      JOIN public.circle_members cm ON cm.circle_id = c.id
     WHERE c.creator_id = p_owner AND c.kind = 'friends' AND cm.member_id = p_viewer
  );
$$;
REVOKE ALL ON FUNCTION public.in_friends_circle(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.in_friends_circle(uuid, uuid) TO authenticated;

-- Audience rule for a 'friends'-visibility post (everything except the
-- author/partner shortcut, which callers handle):
--   * the post names circles  -> ONLY members of those circles
--   * it names none           -> the author's (or Duo partner's) Friends circle
--   * plus any community audience rows, always additive.
CREATE OR REPLACE FUNCTION public.post_audience_admits(p_post_id uuid, p_viewer uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.posts p
     WHERE p.id = p_post_id
       AND (
         CASE WHEN EXISTS (SELECT 1 FROM public.post_audiences pa
                            WHERE pa.post_id = p.id AND pa.audience_kind = 'circle')
              THEN EXISTS (SELECT 1 FROM public.post_audiences pa
                             JOIN public.circle_members cm ON cm.circle_id = pa.circle_id
                            WHERE pa.post_id = p.id AND pa.audience_kind = 'circle'
                              AND cm.member_id = p_viewer)
              ELSE public.in_friends_circle(p.user_id, p_viewer)
                   OR public.in_friends_circle(p.partner_user_id, p_viewer)
         END
         OR EXISTS (SELECT 1 FROM public.post_audiences pa
                      JOIN public.users vu ON vu.id = p_viewer
                      JOIN public.community_members cm
                        ON cm.community_id = pa.community_id AND cm.user_id = vu.auth_id
                     WHERE pa.post_id = p.id AND pa.audience_kind = 'community')
       )
  );
$$;
REVOKE ALL ON FUNCTION public.post_audience_admits(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Backfill: every user gets presets; accepted friendships -> both sides'
--    Friends circles (bypasses the same-community rule on purpose, so nobody
--    loses access they already had).
-- ---------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.users LOOP
    PERFORM public.seed_default_circles(r.id);
  END LOOP;
END $$;

INSERT INTO public.circle_members (circle_id, member_id)
SELECT c.id, CASE WHEN c.creator_id = f.requester_id THEN f.addressee_id ELSE f.requester_id END
  FROM public.friendships f
  JOIN public.circles c
    ON c.kind = 'friends' AND c.creator_id IN (f.requester_id, f.addressee_id)
 WHERE f.status = 'accepted'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Friend helpers rewritten in place (policies referencing them keep working)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_friend_of(target_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.in_friends_circle(target_user_id, public.current_user_id());
$$;

CREATE OR REPLACE FUNCTION public.is_friend_of_either(target_a uuid, target_b uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.in_friends_circle(target_a, public.current_user_id())
      OR public.in_friends_circle(target_b, public.current_user_id());
$$;

CREATE OR REPLACE FUNCTION public.can_view_post(p_post_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_viewer_id  uuid;
  v_author_id  uuid;
  v_partner_id uuid;
  v_visibility text;
BEGIN
  SELECT id INTO v_viewer_id FROM users WHERE auth_id = auth.uid();
  IF v_viewer_id IS NULL THEN RETURN FALSE; END IF;

  SELECT user_id, partner_user_id, visibility
    INTO v_author_id, v_partner_id, v_visibility
    FROM posts WHERE id = p_post_id;
  IF v_author_id IS NULL THEN RETURN FALSE; END IF;

  IF v_viewer_id = v_author_id OR v_viewer_id = v_partner_id THEN RETURN TRUE; END IF;
  IF v_visibility <> 'friends' THEN RETURN TRUE; END IF;

  -- The viewer learns nothing about WHY they can see it: circle membership
  -- stays unreadable to members.
  RETURN public.post_audience_admits(p_post_id, v_viewer_id);
END $$;

CREATE OR REPLACE FUNCTION public.friends_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS SETOF posts LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  with me as (select id from public.users where auth_id = auth.uid())
  select p.* from public.posts p
  where p.deleted_at is null
    and p.post_type in ('moment', 'us')
    and p.visibility in ('everyone', 'friends')
    and (
      case
        when p.post_type = 'moment' then p.created_at > now() - interval '24 hours'
        else true
      end
    )
    and (
      p.user_id = (select id from me)
      or p.partner_user_id = (select id from me)
      or public.post_audience_admits(p.id, (select id from me))
    )
  order by (p.user_id = (select id from me)) desc, p.created_at desc
  limit p_limit offset p_offset;
$$;

-- Duo posts on a profile: the 'friend' state no longer grants every post;
-- each one still has to admit the viewer (a Close-Friends-only Duo photo stays
-- Close-Friends-only on the profile too).
CREATE OR REPLACE FUNCTION public.profile_posts_for_viewer(p_profile uuid)
 RETURNS TABLE(id uuid, user_id uuid, content text, image_url text, photo_urls text[], photo_url_secondary text, inset_on_right boolean, visibility text, community_id uuid, community_name text, prompt text, post_type text, moment_color text, partner_user_id uuid, aspect_ratio text, photo_fit text, music_title text, music_artist text, music_url text, created_at timestamp with time zone)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_state text; v_auth uuid := auth.uid();
BEGIN
  v_state := public.profile_access_state(p_profile);

  IF v_state = 'locked' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id, p.user_id, p.content, p.image_url, p.photo_urls,
         p.photo_url_secondary, COALESCE(p.inset_on_right, true),
         p.visibility,
         COALESCE(p.community_id, pa.community_id),
         COALESCE(c.name, ca.name),
         p.prompt, p.post_type, p.moment_color, p.partner_user_id,
         p.aspect_ratio, p.photo_fit,
         p.music_title, p.music_artist, p.music_url,
         (p.created_at AT TIME ZONE 'UTC')::timestamptz
  FROM public.posts p
  LEFT JOIN public.communities c ON c.id = p.community_id
  LEFT JOIN LATERAL (
    SELECT pa2.community_id FROM public.post_audiences pa2
     WHERE pa2.post_id = p.id AND pa2.audience_kind = 'community'
     LIMIT 1
  ) pa ON true
  LEFT JOIN public.communities ca ON ca.id = pa.community_id
  WHERE (p.user_id = p_profile OR p.partner_user_id = p_profile)
    AND p.deleted_at IS NULL
    AND p.visibility IN ('everyone','friends')
    AND p.post_type = 'us'
    AND (
      v_state = 'self'
      OR (v_state = 'friend' AND public.can_view_post(p.id))
      OR (
        v_state = 'community'
        AND COALESCE(p.community_id, pa.community_id) IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.community_members cm
           WHERE cm.community_id = COALESCE(p.community_id, pa.community_id)
             AND cm.user_id = v_auth
        )
      )
    )
  ORDER BY p.created_at DESC;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Duo: the pending -> accept step IS the consent. No friendship needed.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS us_albums_insert ON public.us_albums;
CREATE POLICY us_albums_insert ON public.us_albums FOR INSERT
  WITH CHECK (
    auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = ANY (ARRAY[us_albums.user_a, us_albums.user_b]))
    AND auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = us_albums.created_by)
    AND status = 'pending'
    AND user_a <> user_b
  );

DROP POLICY IF EXISTS us_album_photos_insert ON public.us_album_photos;
CREATE POLICY us_album_photos_insert ON public.us_album_photos FOR INSERT
  WITH CHECK (
    auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = us_album_photos.uploaded_by)
    AND EXISTS (
      SELECT 1 FROM us_albums a
       WHERE a.id = us_album_photos.album_id
         AND auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = ANY (ARRAY[a.user_a, a.user_b]))
         AND (a.status = 'accepted'
              OR auth.uid() IN (SELECT users.auth_id FROM users WHERE users.id = a.created_by))
    )
  );

DROP FUNCTION IF EXISTS public.are_accepted_friends(uuid, uuid);
DROP FUNCTION IF EXISTS public.is_mutual_friend_of_both(uuid, uuid);

-- ---------------------------------------------------------------------------
-- 6. Group albums: invite -> accept. Nobody can be put into a group any more.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.group_invites (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invitee_id  uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  invited_by  uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (group_id, invitee_id)
);
CREATE INDEX IF NOT EXISTS group_invites_invitee_idx ON public.group_invites (invitee_id);

ALTER TABLE public.group_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS group_invites_select ON public.group_invites;
CREATE POLICY group_invites_select ON public.group_invites FOR SELECT
  USING (invitee_id = public.current_user_id()
         OR public.is_group_member(group_id, public.current_user_id()));

-- Invitee declines; any member can withdraw a pending invite.
DROP POLICY IF EXISTS group_invites_delete ON public.group_invites;
CREATE POLICY group_invites_delete ON public.group_invites FOR DELETE
  USING (invitee_id = public.current_user_id()
         OR public.is_group_member(group_id, public.current_user_id()));
-- No INSERT/UPDATE policies: writes go through the RPCs below.

GRANT SELECT, DELETE ON public.group_invites TO authenticated;

CREATE OR REPLACE FUNCTION public.invite_to_group(p_group uuid, p_user_ids uuid[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_me uuid := public.current_user_id(); v_n integer;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF NOT public.is_group_member(p_group, v_me) THEN
    RAISE EXCEPTION 'Only group members can invite people';
  END IF;
  INSERT INTO public.group_invites (group_id, invitee_id, invited_by)
  SELECT p_group, u.id, v_me
    FROM public.users u
   WHERE u.id = ANY (p_user_ids)
     AND u.id <> v_me
     AND NOT public.is_group_member(p_group, u.id)
  ON CONFLICT (group_id, invitee_id) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.invite_to_group(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_to_group(uuid, uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_group_invite(p_invite uuid, p_accept boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_me uuid := public.current_user_id(); v_inv public.group_invites%ROWTYPE;
BEGIN
  SELECT * INTO v_inv FROM public.group_invites WHERE id = p_invite;
  IF v_inv.id IS NULL OR v_inv.invitee_id IS DISTINCT FROM v_me THEN
    RAISE EXCEPTION 'Invite not found';
  END IF;
  IF p_accept THEN
    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (v_inv.group_id, v_me, 'member')
    ON CONFLICT (group_id, user_id) DO NOTHING;
  END IF;
  DELETE FROM public.group_invites WHERE id = p_invite;
  RETURN v_inv.group_id;
END $$;
REVOKE ALL ON FUNCTION public.respond_group_invite(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_group_invite(uuid, boolean) TO authenticated;

-- Direct adds of OTHER people are gone. Self-join paths (public groups, QR,
-- shared-post join RPC) and the creator's own first-admin row remain.
DROP POLICY IF EXISTS admin_add_members ON public.group_members;
DROP POLICY IF EXISTS member_add_members ON public.group_members;

-- ---------------------------------------------------------------------------
-- 7. Notifications
-- ---------------------------------------------------------------------------
DELETE FROM public.notifications WHERE type IN ('friend_request','friend_accepted');

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'reaction','ping','branch_view','us_album_mutual','report_resolved','report_filed',
  'announcement','ping_answered','us_album_invite','comment','moment_contribution',
  'group_added','group_invite','group_post','group_dip','community_post','friend_post',
  'streak_risk_red','streak_risk_blue','streak_milestone_blue','group_streak_ping',
  'group_streak_risk','group_streak_broken','level_up','level_progress',
  'leaderboard_movement','ping_unanswered','group_ping_waiting','group_ping_replied',
  'pinned_post_view','pinned_group_post_view','moment_new_post','moment_reply_nudge',
  'pinned_profile_view','rank_overtaken','rank_regained','streak_rank_overtaken',
  'start_streak_nudge','streak_standing','window_prompt','break_live_count',
  'midday_report','day_digest','lifecycle_cooling','lifecycle_lapsed','lifecycle_dormant',
  'activation_nudge','graduation','ping_reply_liked'
]::text[]));

CREATE OR REPLACE FUNCTION public.notify_group_invite()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_group text; v_name text;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(NULLIF(btrim(u.name), ''), 'Someone') INTO v_name
    FROM public.users u WHERE u.id = NEW.invited_by;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.invitee_id, 'group_invite', NEW.invited_by, 'standard',
          v_name || ' invited you to ' || v_group,
          'Accept to start sharing photos in the group album',
          jsonb_build_object('screen','group_invite','group_id', NEW.group_id,
                             'invite_id', NEW.id),
          'group_invite:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_group_invite ON public.group_invites;
CREATE TRIGGER trg_notify_group_invite
  AFTER INSERT ON public.group_invites
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_invite();

-- Nobody is "added" by someone else any more; a new member row means that
-- person accepted or joined. Tell the other members.
CREATE OR REPLACE FUNCTION public.notify_group_added()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_group text; v_name text;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(NULLIF(btrim(u.name), ''), 'Someone') INTO v_name
    FROM public.users u WHERE u.id = NEW.user_id;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  SELECT gm.user_id, 'group_added', NEW.user_id, 'standard',
         v_name || ' joined ' || v_group,
         jsonb_build_object('screen','group','group_id', NEW.group_id),
         'group_added:' || NEW.group_id::text || ':' || NEW.user_id::text || ':' || gm.user_id::text
    FROM public.group_members gm
   WHERE gm.group_id = NEW.group_id AND gm.user_id <> NEW.user_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------------
-- 8. Every other function that read friendships (live definitions, only the
--    friendship clause swapped).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_community_members_for_ping()
 RETURNS TABLE(user_id uuid, username text, name text, avatar_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT id, auth_id FROM public.users WHERE auth_id = auth.uid())
  SELECT DISTINCT ON (u.id)
    u.id, u.username, u.name, u.profile_photo_url
  FROM public.community_members cm
  JOIN public.users u ON u.auth_id = cm.user_id
  , me
  WHERE cm.community_id IN (
    SELECT cm2.community_id FROM public.community_members cm2 WHERE cm2.user_id = me.auth_id
  )
  AND u.id <> me.id
  -- People in MY Friends circle are shown separately on the ping page.
  AND NOT public.in_friends_circle(me.id, u.id)
  ORDER BY u.id;
$function$
;

CREATE OR REPLACE FUNCTION public.profile_access_state(p_profile uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid; v_friend boolean;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN RETURN 'locked'; END IF;
  IF v_me = p_profile THEN RETURN 'self'; END IF;

  -- 'friend' = the profile owner put me in their Friends circle. One-way:
  -- the owner decides their own audience, nobody accepts anything.
  v_friend := public.in_friends_circle(p_profile, v_me);

  -- Being in their Friends circle wins outright: no community filtering.
  IF COALESCE(v_friend, false) THEN RETURN 'friend'; END IF;

  -- General deliberately does not count here.
  IF COALESCE(public.shares_real_community(v_me, p_profile), false) THEN RETURN 'community'; END IF;

  RETURN 'locked';
END;
$function$
;

CREATE OR REPLACE FUNCTION public.join_group_from_shared_post(p_group_post_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me    uuid;
  v_group uuid;
  v_ok    boolean;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;

  SELECT gp.group_id INTO v_group
    FROM public.group_posts gp
   WHERE gp.id = p_group_post_id AND gp.deleted_at IS NULL;

  IF v_group IS NULL THEN
    RAISE EXCEPTION 'That post is no longer available.';
  END IF;

  -- Already in it: succeed quietly rather than erroring, so a double tap
  -- (or a stale card) is a no-op instead of a scary failure toast.
  IF public.is_group_member(v_group, v_me) THEN
    RETURN false;
  END IF;

  -- Same two qualifying paths group_post_audience_feed uses.
  SELECT EXISTS (
    SELECT 1 FROM public.group_posts gp
    WHERE gp.id = p_group_post_id
      AND gp.deleted_at IS NULL
      AND (
        (
          EXISTS (SELECT 1 FROM public.group_post_audiences gpa
                   WHERE gpa.group_post_id = gp.id AND gpa.audience_kind = 'friends')
          AND public.in_friends_circle(gp.user_id, v_me)
        )
        OR EXISTS (
          SELECT 1 FROM public.group_post_audiences gpa
          JOIN public.community_members cm ON cm.community_id = gpa.community_id
          WHERE gpa.group_post_id = gp.id
            AND gpa.audience_kind = 'community'
            AND cm.user_id = auth.uid()
        )
      )
  ) INTO v_ok;

  IF NOT COALESCE(v_ok, false) THEN
    RAISE EXCEPTION 'This group post was not shared with you.';
  END IF;

  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group, v_me, 'member')
  ON CONFLICT DO NOTHING;

  RETURN true;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ping_prompts_for_post(p_post_id uuid)
 RETURNS TABLE(id uuid, prompt_text text, tier text, prompt_kind text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid; v_author uuid; v_vis text; v_prompt uuid; v_community uuid;
  v_limit int; v_is_friend boolean := false; v_tier1 int;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  SELECT COALESCE(value, 6) INTO v_limit FROM public.app_settings WHERE key = 'ping_prompt_limit';
  v_limit := COALESCE(v_limit, 6);

  SELECT p.user_id, p.visibility, p.prompt_id, p.community_id
    INTO v_author, v_vis, v_prompt, v_community
    FROM public.posts p
   WHERE p.id = p_post_id AND p.deleted_at IS NULL;

  IF v_author IS NULL THEN RETURN; END IF;

  -- TIER 1 — the prompt-bar question's own set, only if it is a real set.
  IF v_prompt IS NOT NULL THEN
    SELECT count(*) INTO v_tier1
      FROM public.ping_prompts pp
     WHERE pp.daily_prompt_id = v_prompt AND pp.active;

    IF COALESCE(v_tier1, 0) >= 3 THEN
      RETURN QUERY
      SELECT pp.id, pp.prompt_text, 'prompt'::text, pp.prompt_kind
        FROM public.ping_prompts pp
       WHERE pp.daily_prompt_id = v_prompt AND pp.active
       ORDER BY random()
       LIMIT v_limit;
      RETURN;
    END IF;
  END IF;

  IF v_me IS NOT NULL THEN
    v_is_friend := public.in_friends_circle(v_author, v_me);
  END IF;

  -- TIER 2 — community set for a non-friend on a community-tagged post.
  IF v_community IS NOT NULL AND NOT v_is_friend THEN
    RETURN QUERY
    SELECT sp.id, sp.prompt_text, 'community'::text, sp.prompt_kind
      FROM public.ping_sheet_prompts sp
     WHERE sp.community_id = v_community AND sp.active
     ORDER BY random()
     LIMIT v_limit;
    IF FOUND THEN RETURN; END IF;
  END IF;

  -- TIER 3 — generic default for this post's scope.
  RETURN QUERY
  SELECT sp.id, sp.prompt_text, 'default'::text, sp.prompt_kind
    FROM public.ping_sheet_prompts sp
   WHERE sp.community_id IS NULL
     AND sp.active
     AND sp.scope = CASE WHEN v_vis = 'anonymous' THEN 'anonymous' ELSE 'everyone' END
   ORDER BY random()
   LIMIT v_limit;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone, aspect_ratio text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid())
  select gp.id, gp.group_id, g.name, g.icon_url, gp.user_id, u.username, u.name,
         u.profile_photo_url, gp.caption, gp.photo_url, gp.photo_urls,
         gp.created_at, gp.aspect_ratio
  from public.group_posts gp
  join public.groups g on g.id = gp.group_id
  join public.users u on u.id = gp.user_id
  where gp.user_id <> (select id from me)
    and gp.deleted_at is null
    and (
      (
        exists (select 1 from public.group_post_audiences gpa
                where gpa.group_post_id = gp.id and gpa.audience_kind = 'friends')
        and public.in_friends_circle(gp.user_id, (select id from me))
      )
      or
      exists (select 1 from public.group_post_audiences gpa
              join public.community_members cm on cm.community_id = gpa.community_id
              where gpa.group_post_id = gp.id
                and gpa.audience_kind = 'community'
                and cm.user_id = auth.uid())
    )
  order by gp.created_at desc
  limit p_limit offset p_offset;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_post_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
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
    FOR r IN SELECT fcm.member_id AS uid
               FROM public.friends_circle_members fcm
              WHERE fcm.owner_id = NEW.user_id LOOP
      PERFORM public.notify_batched(r.uid, 'friend_post', 'minor',
        'friend_post:' || r.uid::text || ':' || v_day,
        'A friend posted', '%s friends posted today',
        jsonb_build_object('screen','feed'));
    END LOOP;
  END IF;
  RETURN NEW;
END; $function$
;

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
    f.member_id,
    'moment_new_post', NEW.user_id, NEW.id, 'standard',
    v_name || ' just posted a Moment 🌅',
    'Reply with your own to unlock it before it''s gone',
    jsonb_build_object('screen', 'moment', 'post_id', NEW.id),
    'moment_new_post:' || NEW.id::text || ':' ||
      (f.member_id)::text
  FROM public.friends_circle_members f
  WHERE f.owner_id = NEW.user_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$
;

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
    f.member_id AS friend_id,
    'moment_reply_nudge', p.user_id, p.id, 'standard',
    '👀 ' || COALESCE(NULLIF(btrim(u.name), ''), 'a friend') || '''s Moment is still locked for you',
    'Add your own photo to see what everyone else is seeing',
    jsonb_build_object('screen', 'moment', 'post_id', p.id),
    'moment_reply_nudge:1:' || p.id::text || ':' ||
      (f.member_id)::text
  FROM public.posts p
  JOIN public.users u ON u.id = p.user_id
  JOIN public.friends_circle_members f ON f.owner_id = p.user_id
  WHERE p.post_type = 'moment'
    AND p.visibility <> 'anonymous'
    AND p.deleted_at IS NULL
    AND p.created_at <= now() - interval '3 hours'
    AND p.created_at > now() - interval '24 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.moment_replies mr
       WHERE mr.moment_post_id = p.id
         AND mr.user_id = (f.member_id)
    )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  -- +8h reminder (3h + 5h) — only for whoever is STILL silent after the
  -- first nudge.
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  SELECT
    f.member_id AS friend_id,
    'moment_reply_nudge', p.user_id, p.id, 'major',
    '⏳ Last chance on ' || COALESCE(NULLIF(btrim(u.name), ''), 'their') || ''' Moment',
    'It''s about to be gone for good — reply now to see it',
    jsonb_build_object('screen', 'moment', 'post_id', p.id),
    'moment_reply_nudge:2:' || p.id::text || ':' ||
      (f.member_id)::text
  FROM public.posts p
  JOIN public.users u ON u.id = p.user_id
  JOIN public.friends_circle_members f ON f.owner_id = p.user_id
  WHERE p.post_type = 'moment'
    AND p.visibility <> 'anonymous'
    AND p.deleted_at IS NULL
    AND p.created_at <= now() - interval '8 hours'
    AND p.created_at > now() - interval '24 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.moment_replies mr
       WHERE mr.moment_post_id = p.id
         AND mr.user_id = (f.member_id)
    )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_streak_escalation(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_win   text := public.notification_window(p_at);
  v_stage int;
  v_tier  text;
  v_hours int := GREATEST(1, CEIL(EXTRACT(EPOCH FROM
                   ((v_today + 1)::timestamp - (p_at AT TIME ZONE 'Asia/Kolkata'))) / 3600.0)::int);
  n int := 0; r record;
BEGIN
  v_stage := CASE v_win
               WHEN 'day_end'   THEN 1
               WHEN 'evening'   THEN 2
               WHEN 'last_call' THEN 3
               WHEN 'wind_down' THEN 4
               ELSE 0 END;
  IF v_stage = 0 THEN RETURN 0; END IF;   -- not an escalation window
  v_tier := CASE WHEN v_stage = 4 THEN 'major' ELSE 'standard' END;

  PERFORM set_config('app.notif_trusted', 'on', true);

  -- ---------------- RED: personal anon streak ----------------
  FOR r IN SELECT id, daily_streak FROM public.users
            WHERE COALESCE(daily_streak,0) > 0
              AND (daily_streak_last IS NULL OR daily_streak_last < v_today)
              AND deleted_at IS NULL
  LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.id, 'streak_risk_red', v_tier,
      CASE v_stage
        WHEN 1 THEN 'Your 🔴 ' || r.daily_streak || '-day streak needs a post today'
        WHEN 2 THEN 'Still time — your 🔴 ' || r.daily_streak || '-day streak ends at midnight'
        WHEN 3 THEN 'Last call: your 🔴 ' || r.daily_streak || '-day streak ends in ' || v_hours || 'h'
        ELSE        r.daily_streak || ' days about to end — one anon post saves it'
      END,
      -- Phase 7 actionability: straight into the composer that fixes it.
      jsonb_build_object('screen','composer','feed_scope','anon'),
      'streak_risk_red:' || r.id::text || ':' || v_today::text || ':s' || v_stage)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  -- ---------------- BLUE: per friend pair ----------------
  FOR r IN SELECT f.a, f.b,
                  public.ping_streak_between(f.a, f.b) AS streak
             FROM public.friend_pairs f
  LOOP
    CONTINUE WHEN COALESCE(r.streak,0) = 0;
    -- Self-cancel: a reply between these two today removes the risk.
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.ping_replies rp JOIN public.pings p ON p.id = rp.ping_id
       WHERE rp.deleted_at IS NULL
         AND ((p.sender_id = r.a AND p.receiver_id = r.b) OR (p.sender_id = r.b AND p.receiver_id = r.a))
         AND ((rp.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date = v_today);

    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    SELECT s.me, 'streak_risk_blue', s.other, v_tier,
      CASE v_stage
        WHEN 1 THEN 'Your 🔵 ' || r.streak || '-day streak with ' || COALESCE(u.name, u.anon_name, 'them') || ' needs a reply'
        WHEN 2 THEN COALESCE(u.name, u.anon_name, 'They') || ' is still waiting — ' || r.streak || ' days 🔵'
        WHEN 3 THEN 'Your streak with ' || COALESCE(u.name, u.anon_name, 'them') || ' ends tonight — ' || r.streak || ' days 🔵'
        ELSE        r.streak || ' days with ' || COALESCE(u.name, u.anon_name, 'them') || ' about to end 🔵'
      END,
      jsonb_build_object('screen','ping','user_id', s.other),
      'streak_risk_blue:' || s.me::text || ':' || s.other::text || ':' || v_today::text || ':s' || v_stage
      FROM (VALUES (r.a, r.b), (r.b, r.a)) AS s(me, other)
      JOIN public.users u ON u.id = s.other
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 2;
  END LOOP;

  -- ---------------- GROUP: shared all-or-nothing streak ----------------
  FOR r IN SELECT d.group_id, d.thread_id, g.name AS gname,
                  s.current_streak, s.today_replied, s.today_total
             FROM public.group_ping_days d
             JOIN public.groups g ON g.id = d.group_id
             CROSS JOIN LATERAL public.group_ping_streak(d.group_id) s
            WHERE d.on_date = v_today AND NOT d.resolved
              AND s.today_open AND s.today_replied < s.today_total
  LOOP
    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    SELECT m.user_id, 'group_streak_risk', v_tier,
      CASE v_stage
        WHEN 1 THEN r.gname || ' needs everyone today — ' || (r.today_total - r.today_replied) || ' still to reply'
        WHEN 2 THEN r.gname || '''s ' || COALESCE(r.current_streak,0) || '-day streak needs ' || (r.today_total - r.today_replied) || ' more'
        WHEN 3 THEN r.gname || '''s ' || COALESCE(r.current_streak,0) || '-day streak is at risk — ' || (r.today_total - r.today_replied) || ' members haven''t replied yet'
        ELSE        r.gname || '''s streak ends at midnight — ' || (r.today_total - r.today_replied) || ' still silent'
      END,
      jsonb_build_object('screen','group','group_id', r.group_id, 'thread_id', r.thread_id),
      'group_streak_risk:' || r.group_id::text || ':' || v_today::text || ':' || m.user_id::text || ':s' || v_stage
      FROM public.group_members m WHERE m.group_id = r.group_id
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.notify_midday_report(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_day date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_since timestamp := (p_at AT TIME ZONE 'UTC') - INTERVAL '6 hours';
  n int := 0;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  WITH counted AS (
    SELECT u.id AS user_id,
           (SELECT count(*) FROM public.posts p
             WHERE p.deleted_at IS NULL
               AND p.created_at > v_since
               AND p.user_id <> u.id
               AND (
                 public.in_friends_circle(p.user_id, u.id)
                 OR (p.community_id IS NOT NULL AND EXISTS (
                       SELECT 1 FROM public.community_members cm
                        WHERE cm.community_id = p.community_id AND cm.user_id = u.auth_id))
               ))::int AS posts
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  )
  INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
  SELECT c.user_id, 'midday_report', 'minor',
         c.posts || ' post' || CASE WHEN c.posts = 1 THEN '' ELSE 's' END
           || ' in the last 6 hours — catch up',
         jsonb_build_object('screen','feed'),
         'midday_report:' || c.user_id::text || ':' || v_day::text
    FROM counted c
   WHERE c.posts > 0                         -- zero sends nothing at all
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.recalc_lifecycle(p_user uuid DEFAULT NULL::uuid, p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date; n int;
BEGIN
  INSERT INTO public.user_lifecycle (user_id, segment, last_open_on, computed_at)
  SELECT u.id,
         CASE
           WHEN u.last_open_at IS NULL THEN 'new'
           WHEN (v_today - u.last_open_at) >= 14 THEN 'dormant'
           WHEN (v_today - u.last_open_at) >= 7  THEN 'lapsed'
           WHEN (v_today - u.last_open_at) >= 3  THEN
             -- COOLING requires something live to lose; without that they are
             -- simply quiet, and a "you'll lose your streak" hook would be a
             -- lie. Such users stay MID until they cross into LAPSED.
             CASE WHEN COALESCE(u.daily_streak,0) > 0
                       OR EXISTS (SELECT 1 FROM public.friend_pairs f
                                   WHERE (f.a=u.id OR f.b=u.id)
                                     AND public.ping_streak_between(f.a, f.b) > 0)
                  THEN 'cooling' ELSE 'mid' END
           -- Opened within 2 days: NEW until all three activation artefacts
           -- exist, MID afterwards (§6.6A/B).
           WHEN EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.user_id = u.id)
            AND EXISTS (SELECT 1 FROM public.us_albums a
                         WHERE (a.user_a = u.id OR a.user_b = u.id) AND a.status='accepted')
            AND EXISTS (SELECT 1 FROM public.circles c WHERE c.creator_id = u.id)
             THEN 'mid'
           ELSE 'new'
         END,
         u.last_open_at, p_at
    FROM public.users u
   WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
     AND (p_user IS NULL OR u.id = p_user)
  ON CONFLICT (user_id) DO UPDATE SET
    segment      = EXCLUDED.segment,
    last_open_on = EXCLUDED.last_open_on,
    computed_at  = EXCLUDED.computed_at,
    -- THE RETURN PATH. Leaving dormant for any other segment means they came
    -- back, so the latch is released and pushes resume. This is the only
    -- thing that ever clears it.
    dormant_notified_at = CASE WHEN EXCLUDED.segment = 'dormant'
                               THEN public.user_lifecycle.dormant_notified_at
                               ELSE NULL END;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$
;

COMMIT;
