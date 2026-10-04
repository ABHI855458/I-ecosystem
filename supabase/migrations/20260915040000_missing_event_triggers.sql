-- notification_system_spec.md §2 — the ten events marked "❌ missing".
-- Copy is taken verbatim from §3; tiers from §2. Every {name} below is
-- interpolated from the users row at fire time, never hardcoded.

-- ═══ US-ALBUM INVITE (MAJOR) ════════════════════════════════════════════
-- §6: "Never confirm a Us album's existence to anyone outside the pair."
-- The only recipient here is the other half of the pair, so this is safe.
CREATE OR REPLACE FUNCTION public.notify_us_album_invite()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_recipient uuid; v_name text;
BEGIN
  v_recipient := CASE WHEN NEW.created_by = NEW.user_a THEN NEW.user_b ELSE NEW.user_a END;
  IF v_recipient IS NULL OR v_recipient = NEW.created_by THEN RETURN NEW; END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_name
    FROM public.users WHERE id = NEW.created_by;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, data, dedupe_key)
  VALUES (v_recipient, 'us_album_invite', NEW.created_by, 'major',
          v_name || ' started an Us album with you',
          jsonb_build_object('screen','us_album','album_id', NEW.id),
          'us_album_invite:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_us_album_invite ON public.us_albums;
CREATE TRIGGER trg_notify_us_album_invite
  AFTER INSERT ON public.us_albums
  FOR EACH ROW EXECUTE FUNCTION public.notify_us_album_invite();

-- ═══ COMMENT (STANDARD) ═════════════════════════════════════════════════
-- §3 gives two variants; the preview one is used, with the comment's first
-- 40 characters in the body. An anonymous comment is never attributed (§6).
CREATE OR REPLACE FUNCTION public.notify_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_owner uuid; v_name text; v_anon boolean := COALESCE(NEW.is_anonymous,false);
BEGIN
  IF NEW.post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.post_id;
  ELSIF NEW.group_post_id IS NOT NULL THEN
    SELECT user_id INTO v_owner FROM public.group_posts WHERE id = NEW.group_post_id;
  END IF;

  IF v_owner IS NULL OR v_owner = NEW.user_id THEN RETURN NEW; END IF;

  IF v_anon THEN
    v_name := 'Someone';
  ELSE
    SELECT COALESCE(name, anon_name, 'someone') INTO v_name
      FROM public.users WHERE id = NEW.user_id;
  END IF;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, dedupe_key)
  VALUES (v_owner, 'comment',
          CASE WHEN v_anon THEN NULL ELSE NEW.user_id END,   -- §6: no actor_id when anon
          NEW.post_id, 'standard',
          v_name || ' commented on your post',
          CASE WHEN NEW.content IS NULL OR NEW.content = '' THEN NULL
               WHEN length(NEW.content) > 40 THEN left(NEW.content, 40) || '…'
               ELSE NEW.content END,
          'comment:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_comment ON public.comments;
CREATE TRIGGER trg_notify_comment
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_comment();

-- ═══ MOMENT CONTRIBUTION (STANDARD) ═════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_moment_contribution()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_owner uuid; v_name text; v_anon boolean := COALESCE(NEW.is_anonymous,false);
BEGIN
  SELECT user_id INTO v_owner FROM public.posts WHERE id = NEW.moment_post_id;
  IF v_owner IS NULL OR v_owner = NEW.user_id THEN RETURN NEW; END IF;

  IF v_anon THEN v_name := 'Someone';
  ELSE SELECT COALESCE(name, anon_name, 'someone') INTO v_name
         FROM public.users WHERE id = NEW.user_id;
  END IF;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, data, dedupe_key)
  VALUES (v_owner, 'moment_contribution',
          CASE WHEN v_anon THEN NULL ELSE NEW.user_id END,
          NEW.moment_post_id, 'standard',
          v_name || ' added to your Moment',
          jsonb_build_object('screen','moment','post_id', NEW.moment_post_id),
          'moment_contribution:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_moment_contribution ON public.moment_replies;
CREATE TRIGGER trg_notify_moment_contribution
  AFTER INSERT ON public.moment_replies
  FOR EACH ROW EXECUTE FUNCTION public.notify_moment_contribution();

-- ═══ ADDED TO A GROUP (STANDARD) ════════════════════════════════════════
-- group_members carries no "added_by" column, so there is no actor to name
-- and the copy stays passive rather than inventing one.
CREATE OR REPLACE FUNCTION public.notify_group_added()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_group text;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;

  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key)
  VALUES (NEW.user_id, 'group_added', 'standard',
          'You were added to ' || v_group,
          jsonb_build_object('screen','group','group_id', NEW.group_id),
          'group_added:' || NEW.group_id::text || ':' || NEW.user_id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_group_added ON public.group_members;
CREATE TRIGGER trg_notify_group_added
  AFTER INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_added();

-- ═══ BATCHED FAN-OUTS (MINOR) — spec §2, §3, §5.4 ═══════════════════════
-- All four go through notify_batched(), so a busy group produces one row
-- per member per day whose count climbs, not one row per post.
--
-- Group/community names are interpolated into a format() template, so any
-- literal % in a name is doubled first or format() would read it as a
-- placeholder and raise.

-- GROUP POST — "3 posts in {group} today"
CREATE OR REPLACE FUNCTION public.notify_group_post()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_group text; v_esc text; v_day text; r record;
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  v_esc := replace(v_group, '%', '%%');
  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  FOR r IN SELECT user_id FROM public.group_members
            WHERE group_id = NEW.group_id AND user_id <> NEW.user_id LOOP
    PERFORM public.notify_batched(
      r.user_id, 'group_post', 'minor',
      'group_post:' || r.user_id::text || ':' || NEW.group_id::text || ':' || v_day,
      'New post in ' || v_group,
      '%s posts in ' || v_esc || ' today',
      jsonb_build_object('screen','group','group_id', NEW.group_id));
  END LOOP;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_group_post ON public.group_posts;
CREATE TRIGGER trg_notify_group_post AFTER INSERT ON public.group_posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_post();

-- DIP — "{group} is active — 4 dips in the last hour". Bucketed by the
-- hour, not the day, because the copy says "in the last hour".
CREATE OR REPLACE FUNCTION public.notify_group_dip()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
DECLARE v_group text; v_esc text; v_bucket text; r record;
BEGIN
  SELECT name INTO v_group FROM public.groups WHERE id = NEW.group_id;
  IF v_group IS NULL THEN RETURN NEW; END IF;
  v_esc := replace(v_group, '%', '%%');
  v_bucket := to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYYYMMDDHH24');

  FOR r IN SELECT user_id FROM public.group_members
            WHERE group_id = NEW.group_id AND user_id <> NEW.user_id LOOP
    PERFORM public.notify_batched(
      r.user_id, 'group_dip', 'minor',
      'group_dip:' || r.user_id::text || ':' || NEW.group_id::text || ':' || v_bucket,
      v_group || ' is active — 1 dip in the last hour',
      v_esc || ' is active — %s dips in the last hour',
      jsonb_build_object('screen','group','group_id', NEW.group_id));
  END LOOP;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_group_dip ON public.dips;
CREATE TRIGGER trg_notify_group_dip AFTER INSERT ON public.dips
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_dip();

-- POST FAN-OUT — community ("5 new posts in {community}") and friends
-- ("3 friends posted today"), both off the same INSERT.
--
-- §6: an ANONYMOUS post never feeds the friend fan-out. A count scoped to
-- "your friends" is a much narrower set than a community, and on a small
-- friend list "1 friend posted" plus a timestamp is enough to point at the
-- author of an anon post. The community count is a pure aggregate over a
-- large membership and names nobody, so anon posts still count there.
CREATE OR REPLACE FUNCTION public.notify_post_fanout()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','pg_temp' AS $$
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
      FOR r IN SELECT u.id AS uid
                 FROM public.community_members m
                 JOIN public.users u ON u.auth_id = m.user_id   -- keyed on auth_id
                WHERE m.community_id = NEW.community_id AND u.id <> NEW.user_id LOOP
        PERFORM public.notify_batched(
          r.uid, 'community_post', 'minor',
          'community_post:' || r.uid::text || ':' || NEW.community_id::text || ':' || v_day,
          'New post in ' || v_name,
          '%s new posts in ' || v_esc,
          jsonb_build_object('screen','community','community_id', NEW.community_id));
      END LOOP;
    END IF;
  END IF;

  IF NEW.visibility <> 'anonymous' THEN
    FOR r IN SELECT CASE WHEN requester_id = NEW.user_id THEN addressee_id
                         ELSE requester_id END AS uid
               FROM public.friendships
              WHERE status = 'accepted'
                AND (requester_id = NEW.user_id OR addressee_id = NEW.user_id) LOOP
      PERFORM public.notify_batched(
        r.uid, 'friend_post', 'minor',
        'friend_post:' || r.uid::text || ':' || v_day,
        'A friend posted',
        '%s friends posted today',
        jsonb_build_object('screen','feed'));
    END LOOP;
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_notify_post_fanout ON public.posts;
CREATE TRIGGER trg_notify_post_fanout AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_post_fanout();
