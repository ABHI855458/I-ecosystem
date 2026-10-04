-- ============================================================================
-- Shared albums: everyone involved picks their OWN audience.
--
-- DUO — a 'mutual' photo is no longer published the moment it's uploaded.
--   The uploader picks their circles/communities; the partner is notified,
--   picks theirs, and approves. Only then does the post go live, and it goes
--   live to the UNION of both audiences. An unchosen side defaults to that
--   person's own Friends circle.
--
-- GROUP — a group post goes live immediately with the poster's audience.
--   Every other member is notified and can share the same post to their own
--   circles / Friends circle / communities (group_post_audiences.shared_by).
--   However many members' audiences a viewer falls into, it is still ONE
--   group_posts row, so they get one card: every feed selects from
--   group_posts with EXISTS over the audience rows, never a join.
--
-- Builds on 20260926000000_circles_replace_friendships.sql.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Group post audiences: per-member, with circles
-- ---------------------------------------------------------------------------
ALTER TABLE public.group_post_audiences
  ADD COLUMN IF NOT EXISTS shared_by uuid REFERENCES public.users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS circle_id uuid REFERENCES public.circles(id) ON DELETE CASCADE;

UPDATE public.group_post_audiences a SET shared_by = gp.user_id
  FROM public.group_posts gp
 WHERE gp.id = a.group_post_id AND a.shared_by IS NULL;

ALTER TABLE public.group_post_audiences DROP CONSTRAINT IF EXISTS group_post_audiences_audience_kind_check;
ALTER TABLE public.group_post_audiences ADD CONSTRAINT group_post_audiences_audience_kind_check
  CHECK (audience_kind IN ('friends','community','circle'));
ALTER TABLE public.group_post_audiences DROP CONSTRAINT IF EXISTS group_post_audiences_kind_match;
ALTER TABLE public.group_post_audiences ADD CONSTRAINT group_post_audiences_kind_match CHECK (
     (audience_kind = 'community' AND community_id IS NOT NULL AND circle_id IS NULL)
  OR (audience_kind = 'circle'    AND circle_id    IS NOT NULL AND community_id IS NULL)
  OR (audience_kind = 'friends'   AND community_id IS NULL     AND circle_id IS NULL));

CREATE UNIQUE INDEX IF NOT EXISTS group_post_audiences_one_per_sharer
  ON public.group_post_audiences
     (group_post_id, shared_by, audience_kind,
      COALESCE(community_id, circle_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- shared_by is always the writer; a circle must be the writer's own.
CREATE OR REPLACE FUNCTION public.group_post_audiences_stamp()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.shared_by := public.current_user_id();
  END IF;
  IF NEW.shared_by IS NULL THEN
    SELECT user_id INTO NEW.shared_by FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;
  IF NEW.audience_kind = 'circle' AND NOT EXISTS (
       SELECT 1 FROM public.circles c WHERE c.id = NEW.circle_id AND c.creator_id = NEW.shared_by) THEN
    RAISE EXCEPTION 'You can only share to your own circles';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_group_post_audiences_stamp ON public.group_post_audiences;
CREATE TRIGGER trg_group_post_audiences_stamp
  BEFORE INSERT ON public.group_post_audiences
  FOR EACH ROW EXECUTE FUNCTION public.group_post_audiences_stamp();

-- Any member of the post's group may add rows for themselves.
DROP POLICY IF EXISTS group_post_audiences_insert_own ON public.group_post_audiences;
CREATE POLICY group_post_audiences_insert_own ON public.group_post_audiences FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.group_posts gp
     WHERE gp.id = group_post_audiences.group_post_id
       AND public.is_group_member(gp.group_id, public.current_user_id())));

DROP POLICY IF EXISTS group_post_audiences_delete_own ON public.group_post_audiences;
CREATE POLICY group_post_audiences_delete_own ON public.group_post_audiences FOR DELETE
  USING (shared_by = public.current_user_id());

-- Circle rows stay private to whoever shared them (same rule as post_audiences).
DROP POLICY IF EXISTS group_post_audiences_select ON public.group_post_audiences;
CREATE POLICY group_post_audiences_select ON public.group_post_audiences FOR SELECT
  USING ((audience_kind <> 'circle' OR shared_by = public.current_user_id())
         AND EXISTS (SELECT 1 FROM public.group_posts gp
                      WHERE gp.id = group_post_audiences.group_post_id));

-- One audience rule for group posts, row by row, each judged against the
-- member who shared it.
CREATE OR REPLACE FUNCTION public.group_post_audience_admits(p_group_post_id uuid, p_author_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_post_audiences a
     WHERE a.group_post_id = p_group_post_id
       AND (
            (a.audience_kind = 'friends'
             AND public.in_friends_circle(COALESCE(a.shared_by, p_author_id), public.current_user_id()))
         OR (a.audience_kind = 'circle'
             AND EXISTS (SELECT 1 FROM public.circle_members cm
                          WHERE cm.circle_id = a.circle_id
                            AND cm.member_id = public.current_user_id()))
         OR (a.audience_kind = 'community'
             AND a.community_id IS NOT NULL
             AND public.is_community_member(a.community_id, auth.uid()))
       )
  );
$$;

-- One row per group post, however many audience rows admit the viewer.
CREATE OR REPLACE FUNCTION public.group_post_audience_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, group_id uuid, group_name text, group_icon_url text, user_id uuid, username text, name text, avatar_url text, caption text, photo_url text, photo_urls text[], created_at timestamp with time zone, aspect_ratio text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
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
    and public.group_post_audience_admits(gp.id, gp.user_id)
  order by gp.created_at desc
  limit p_limit offset p_offset;
$function$;

CREATE OR REPLACE FUNCTION public.join_group_from_shared_post(p_group_post_id uuid)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
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

  IF public.is_group_member(v_group, v_me) THEN
    RETURN false;
  END IF;

  -- Same rule group_post_audience_feed uses.
  SELECT public.group_post_audience_admits(gp.id, gp.user_id)
    INTO v_ok
    FROM public.group_posts gp WHERE gp.id = p_group_post_id;

  IF NOT COALESCE(v_ok, false) THEN
    RAISE EXCEPTION 'This group post was not shared with you.';
  END IF;

  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group, v_me, 'member')
  ON CONFLICT DO NOTHING;

  RETURN true;
END;
$function$;

-- A member (re)sets THEIR OWN audience for a group post. Replaces whatever
-- they shared before; passing nothing un-shares.
CREATE OR REPLACE FUNCTION public.share_group_post(
  p_group_post uuid,
  p_include_friends boolean,
  p_circle_ids uuid[] DEFAULT '{}',
  p_community_ids uuid[] DEFAULT '{}'
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_me uuid := public.current_user_id(); v_group uuid; v_n integer;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  SELECT group_id INTO v_group FROM public.group_posts
   WHERE id = p_group_post AND deleted_at IS NULL;
  IF v_group IS NULL OR NOT public.is_group_member(v_group, v_me) THEN
    RAISE EXCEPTION 'Only group members can share this post';
  END IF;

  DELETE FROM public.group_post_audiences
   WHERE group_post_id = p_group_post AND shared_by = v_me;

  INSERT INTO public.group_post_audiences (group_post_id, audience_kind, shared_by, circle_id, community_id)
  SELECT p_group_post, 'friends', v_me, NULL::uuid, NULL::uuid WHERE COALESCE(p_include_friends, false)
  UNION ALL
  SELECT p_group_post, 'circle', v_me, c.id, NULL::uuid
    FROM public.circles c
   WHERE c.id = ANY (COALESCE(p_circle_ids, '{}')) AND c.creator_id = v_me
  UNION ALL
  SELECT p_group_post, 'community', v_me, NULL::uuid, cm.community_id
    FROM public.community_members cm
   WHERE cm.community_id = ANY (COALESCE(p_community_ids, '{}')) AND cm.user_id = auth.uid();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.share_group_post(uuid, boolean, uuid[], uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_group_post(uuid, boolean, uuid[], uuid[]) TO authenticated;

-- What I've shared a group post to (for pre-filling the share sheet).
CREATE OR REPLACE FUNCTION public.my_group_post_share(p_group_post uuid)
RETURNS TABLE(audience_kind text, circle_id uuid, community_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT a.audience_kind, a.circle_id, a.community_id
    FROM public.group_post_audiences a
   WHERE a.group_post_id = p_group_post AND a.shared_by = public.current_user_id();
$$;
REVOKE ALL ON FUNCTION public.my_group_post_share(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_group_post_share(uuid) TO authenticated;

-- Every other member hears about each new post, and can share it onward.
CREATE OR REPLACE FUNCTION public.notify_group_post()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_group text; v_name text;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(NULLIF(btrim(u.name), ''), 'Someone') INTO v_name
    FROM public.users u WHERE u.id = NEW.user_id;
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT gm.user_id, 'group_post', NEW.user_id, 'standard',
         v_name || ' posted in ' || v_group,
         'Share it with your circles or communities',
         jsonb_build_object('screen','group','group_id', NEW.group_id,
                            'group_post_id', NEW.id),
         'group_post:' || NEW.id::text || ':' || gm.user_id::text
    FROM public.group_members gm
   WHERE gm.group_id = NEW.group_id AND gm.user_id <> NEW.user_id
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $function$;

-- ---------------------------------------------------------------------------
-- 2. Duo: both partners choose, both approve
-- ---------------------------------------------------------------------------
ALTER TABLE public.us_album_photos
  ADD COLUMN IF NOT EXISTS uploader_circle_ids    uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS uploader_community_ids uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS partner_circle_ids     uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS partner_community_ids  uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS partner_approved_at    timestamptz;

-- Photos that are already live stay live (their post_audiences rows were
-- written by the old client path and are left untouched).
UPDATE public.us_album_photos p SET partner_approved_at = p.created_at
  FROM public.posts po
 WHERE po.us_album_photo_id = p.id AND po.deleted_at IS NULL
   AND p.visibility = 'mutual' AND p.partner_approved_at IS NULL;

-- Clients can't forge the partner's side, and a circle id must belong to the
-- person whose side it is on.
CREATE OR REPLACE FUNCTION public.us_album_photos_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_album public.us_albums%ROWTYPE; v_partner uuid;
BEGIN
  IF auth.uid() IS NOT NULL
     AND current_setting('app.duo_approving', true) IS DISTINCT FROM 'on' THEN
    IF TG_OP = 'INSERT' THEN
      NEW.partner_circle_ids := '{}';
      NEW.partner_community_ids := '{}';
      NEW.partner_approved_at := NULL;
    ELSE
      NEW.partner_circle_ids := OLD.partner_circle_ids;
      NEW.partner_community_ids := OLD.partner_community_ids;
      NEW.partner_approved_at := OLD.partner_approved_at;
    END IF;
  END IF;
  SELECT * INTO v_album FROM public.us_albums WHERE id = NEW.album_id;
  v_partner := CASE WHEN v_album.user_a = NEW.uploaded_by THEN v_album.user_b ELSE v_album.user_a END;
  NEW.uploader_circle_ids := ARRAY(SELECT c.id FROM public.circles c
    WHERE c.id = ANY (NEW.uploader_circle_ids) AND c.creator_id = NEW.uploaded_by);
  NEW.partner_circle_ids := ARRAY(SELECT c.id FROM public.circles c
    WHERE c.id = ANY (NEW.partner_circle_ids) AND c.creator_id = v_partner);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_us_album_photos_guard ON public.us_album_photos;
CREATE TRIGGER trg_us_album_photos_guard
  BEFORE INSERT OR UPDATE ON public.us_album_photos
  FOR EACH ROW EXECUTE FUNCTION public.us_album_photos_guard();

CREATE OR REPLACE FUNCTION public.sync_us_album_post()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE
  v_album   public.us_albums%ROWTYPE;
  v_partner uuid;
  v_post    uuid;
  v_circles uuid[];
  v_comms   uuid[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET deleted_at = now()
     WHERE us_album_photo_id = OLD.id AND deleted_at IS NULL;
    RETURN OLD;
  END IF;

  SELECT * INTO v_album FROM public.us_albums WHERE id = NEW.album_id;
  IF v_album.id IS NULL THEN
    RETURN NEW;
  END IF;

  v_partner := CASE WHEN v_album.user_a = NEW.uploaded_by
                    THEN v_album.user_b ELSE v_album.user_a END;

  -- Live only when: shared (mutual), the Duo itself is accepted, AND the
  -- partner has approved this photo with their own audience.
  IF NEW.visibility = 'mutual' AND v_album.status = 'accepted'
     AND NEW.partner_approved_at IS NOT NULL THEN
    INSERT INTO public.posts (
      user_id, partner_user_id, us_album_id, us_album_photo_id,
      image_url, content, visibility, post_type, created_at
    )
    VALUES (
      NEW.uploaded_by, v_partner, NEW.album_id, NEW.id,
      NEW.photo_url, NEW.caption, 'friends', 'us', NEW.created_at
    )
    ON CONFLICT (us_album_photo_id) WHERE us_album_photo_id IS NOT NULL
    DO UPDATE SET image_url = EXCLUDED.image_url,
                  content   = EXCLUDED.content,
                  deleted_at = NULL
    RETURNING id INTO v_post;

    -- (Re)write the audience only when one of the two choices changed —
    -- a caption edit must not clobber it.
    IF TG_OP = 'INSERT'
       OR OLD.partner_approved_at IS DISTINCT FROM NEW.partner_approved_at
       OR OLD.uploader_circle_ids IS DISTINCT FROM NEW.uploader_circle_ids
       OR OLD.uploader_community_ids IS DISTINCT FROM NEW.uploader_community_ids
       OR OLD.partner_circle_ids IS DISTINCT FROM NEW.partner_circle_ids
       OR OLD.partner_community_ids IS DISTINCT FROM NEW.partner_community_ids THEN
      -- Each side: their picked circles, or their Friends circle when they
      -- picked none. Explicit rows for both, so neither side's default is
      -- lost when the other side narrowed theirs.
      v_circles := ARRAY(
        SELECT DISTINCT x FROM unnest(
          CASE WHEN cardinality(NEW.uploader_circle_ids) > 0 THEN NEW.uploader_circle_ids
               ELSE ARRAY(SELECT id FROM public.circles
                           WHERE creator_id = NEW.uploaded_by AND kind = 'friends') END
          || CASE WHEN cardinality(NEW.partner_circle_ids) > 0 THEN NEW.partner_circle_ids
               ELSE ARRAY(SELECT id FROM public.circles
                           WHERE creator_id = v_partner AND kind = 'friends') END
        ) AS x WHERE x IS NOT NULL);
      v_comms := ARRAY(SELECT DISTINCT x FROM unnest(
                   NEW.uploader_community_ids || NEW.partner_community_ids) AS x
                  WHERE x IS NOT NULL);

      DELETE FROM public.post_audiences
       WHERE post_id = v_post AND audience_kind IN ('circle','community');
      INSERT INTO public.post_audiences (post_id, audience_kind, circle_id)
      SELECT v_post, 'circle', x FROM unnest(v_circles) AS x;
      INSERT INTO public.post_audiences (post_id, audience_kind, community_id)
      SELECT v_post, 'community', x FROM unnest(v_comms) AS x;
    END IF;
  ELSE
    UPDATE public.posts SET deleted_at = now()
     WHERE us_album_photo_id = NEW.id AND deleted_at IS NULL;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_us_album_post ON public.us_album_photos;
CREATE TRIGGER trg_sync_us_album_post
  AFTER INSERT OR DELETE OR UPDATE OF visibility, photo_url, caption,
        partner_approved_at, uploader_circle_ids, uploader_community_ids,
        partner_circle_ids, partner_community_ids
  ON public.us_album_photos
  FOR EACH ROW EXECUTE FUNCTION public.sync_us_album_post();

-- Partner approves (or re-sets) their side and the photo goes live.
CREATE OR REPLACE FUNCTION public.approve_duo_photo(
  p_photo uuid,
  p_circle_ids uuid[] DEFAULT '{}',
  p_community_ids uuid[] DEFAULT '{}'
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_me uuid := public.current_user_id(); v_photo public.us_album_photos%ROWTYPE;
        v_album public.us_albums%ROWTYPE;
BEGIN
  SELECT * INTO v_photo FROM public.us_album_photos WHERE id = p_photo;
  SELECT * INTO v_album FROM public.us_albums WHERE id = v_photo.album_id;
  IF v_photo.id IS NULL OR v_me IS NULL
     OR v_me NOT IN (v_album.user_a, v_album.user_b) OR v_me = v_photo.uploaded_by THEN
    RAISE EXCEPTION 'Only the other person in this Duo can approve it';
  END IF;
  IF v_photo.visibility <> 'mutual' THEN
    RAISE EXCEPTION 'This photo is private to the album';
  END IF;
  PERFORM set_config('app.duo_approving', 'on', true);
  UPDATE public.us_album_photos SET
    partner_circle_ids = COALESCE(p_circle_ids, '{}'),
    partner_community_ids = ARRAY(
      SELECT cm.community_id FROM public.community_members cm
       WHERE cm.community_id = ANY (COALESCE(p_community_ids, '{}')) AND cm.user_id = auth.uid()),
    partner_approved_at = COALESCE(partner_approved_at, now())
  WHERE id = p_photo;
  PERFORM set_config('app.duo_approving', 'off', true);
END $$;
REVOKE ALL ON FUNCTION public.approve_duo_photo(uuid, uuid[], uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_duo_photo(uuid, uuid[], uuid[]) TO authenticated;

-- Notify the partner when a photo needs their approval, and the uploader
-- when it went live.
CREATE OR REPLACE FUNCTION public.notify_us_album_mutual()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_partner uuid; v_name text; v_pname text;
BEGIN
  SELECT CASE WHEN user_a = NEW.uploaded_by THEN user_b ELSE user_a END
    INTO v_partner FROM public.us_albums WHERE id = NEW.album_id;
  IF v_partner IS NULL THEN RETURN NEW; END IF;

  -- Needs the partner: newly mutual and not yet approved.
  IF NEW.visibility = 'mutual' AND NEW.partner_approved_at IS NULL
     AND (TG_OP = 'INSERT' OR OLD.visibility <> 'mutual') THEN
    SELECT COALESCE(NULLIF(btrim(name), ''), anon_name, 'Someone') INTO v_name
      FROM public.users WHERE id = NEW.uploaded_by;
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
    VALUES (v_partner, 'us_album_mutual', NEW.uploaded_by, 'major',
            v_name || ' added a photo to your Duo',
            'Pick who sees it on your side to post it together',
            jsonb_build_object('screen','us_album','album_id', NEW.album_id,
                               'photo_id', NEW.id, 'action','approve'),
            'us_album_mutual:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;

  -- Went live: tell the uploader.
  IF TG_OP = 'UPDATE' AND OLD.partner_approved_at IS NULL
     AND NEW.partner_approved_at IS NOT NULL THEN
    SELECT COALESCE(NULLIF(btrim(name), ''), anon_name, 'Someone') INTO v_pname
      FROM public.users WHERE id = v_partner;
    INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, data, dedupe_key)
    VALUES (NEW.uploaded_by, 'us_album_mutual', v_partner, 'standard',
            v_pname || ' approved your Duo photo — it''s live',
            jsonb_build_object('screen','us_album','album_id', NEW.album_id, 'photo_id', NEW.id),
            'us_album_live:' || NEW.id::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_notify_us_album_mutual ON public.us_album_photos;
CREATE TRIGGER trg_notify_us_album_mutual
  AFTER INSERT OR UPDATE ON public.us_album_photos
  FOR EACH ROW EXECUTE FUNCTION public.notify_us_album_mutual();

COMMIT;
