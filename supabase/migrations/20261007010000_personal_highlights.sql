-- Personal highlights (plan approved 2026-10-07): polaroids a person makes
-- themselves — pick photos from the phone, give it a name. Shown on their
-- profile and on their friends' Wall. Personal only: no Duo / group ones.
--
-- STORAGE. Each photo is a QUIET POST: posts.post_type = 'highlight',
-- visibility = 'friends', show_in_feed = false. Checked against the live
-- database before choosing this:
--   * every INSERT trigger on posts is inert for such a row (the score /
--     streak triggers are WHEN anonymous or WHEN moment; notify_duo_post
--     needs partner_user_id; notify_moment_new_post_to_friends needs
--     moment; notify_post_fanout returns early on show_in_feed = false);
--   * every feed / profile reader whitelists its post types (friends_feed,
--     fetchEveryoneFeed: 'moment','us'; profile_posts_for_viewer,
--     fetchUserPosts: 'us'), so a 'highlight' row appears in none of them;
--   * there is no CHECK on post_type, and no cron that purges posts.
-- In exchange reactions, comments, "seen by", reports and blocks all work
-- on a highlight photo with no new code, and WHO CAN SEE IT is exactly the
-- friends-post rule already in force (posts_select -> can_view_post ->
-- post_audience_admits -> in_friends_circle(author, viewer)).
--
-- TABLES. `highlights` already existed: empty, RLS on, no policies, and no
-- trigger / function / view depends on it (its only reader is the dead
-- WallService). It is reused as the header row (owner + title); its legacy
-- photos[] / icon_url columns stay, unused. `highlight_items` is new.
--
-- RULES. Read: an item is readable exactly when its post is; a highlight
-- when it is yours or at least one of its items is readable. The chain
-- only ever points one way (highlights -> highlight_items -> posts), which
-- is what keeps Postgres from reporting policy recursion. Write: no
-- policies at all — save_highlight / delete_highlight are the only way in.

BEGIN;

-- ── highlights: make the legacy table usable as a header row ────────────
ALTER TABLE public.highlights ALTER COLUMN photos SET DEFAULT '{}'::text[];
ALTER TABLE public.highlights ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE public.highlights
  ADD CONSTRAINT highlights_title_len
  CHECK (char_length(btrim(title)) BETWEEN 1 AND 24);
CREATE INDEX IF NOT EXISTS highlights_user_updated_idx
  ON public.highlights (user_id, updated_at DESC);

-- ── highlight_items ─────────────────────────────────────────────────────
CREATE TABLE public.highlight_items (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  highlight_id uuid NOT NULL REFERENCES public.highlights(id) ON DELETE CASCADE,
  -- One highlight per photo: a quiet post has no other home, and removing
  -- it from a highlight soft-deletes it (see save_highlight).
  post_id      uuid NOT NULL UNIQUE REFERENCES public.posts(id) ON DELETE CASCADE,
  position     integer NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX highlight_items_highlight_idx
  ON public.highlight_items (highlight_id, position);

ALTER TABLE public.highlight_items ENABLE ROW LEVEL SECURITY;

-- Supabase's default privileges hand ALL on a new public table to anon and
-- authenticated. Read-only for signed-in users, nothing for signed-out.
REVOKE ALL ON public.highlights      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.highlight_items FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.highlights      TO authenticated;
GRANT SELECT ON public.highlight_items TO authenticated;

-- The sub-select on posts runs under the CALLER's own posts policies, so
-- this inherits posts_select (friends -> can_view_post) and the
-- restrictive posts_block_filter. deleted_at is spelled out because
-- posts_select_own_or_moderator_always shows an author their own
-- soft-deleted rows.
CREATE POLICY highlight_items_select ON public.highlight_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.posts p
       WHERE p.id = highlight_items.post_id
         AND p.deleted_at IS NULL
    )
  );

CREATE POLICY highlights_select ON public.highlights
  FOR SELECT TO authenticated
  USING (
    user_id = public.current_user_id()
    OR EXISTS (
      SELECT 1 FROM public.highlight_items i
       WHERE i.highlight_id = highlights.id
    )
  );

-- ── save_highlight: create, rename, add / remove / reorder photos ───────
-- p_id null = new. p_post_ids is the full ordered list the highlight
-- should hold afterwards; the first one is the cover.
CREATE OR REPLACE FUNCTION public.save_highlight(
  p_id uuid, p_title text, p_post_ids uuid[]
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me    uuid;
  v_title text := btrim(coalesce(p_title, ''));
  v_ids   uuid[];
  v_id    uuid := p_id;
  v_n     integer;
  v_added boolean;
BEGIN
  SELECT u.id INTO v_me
    FROM public.users u
   WHERE u.auth_id = auth.uid() AND u.deleted_at IS NULL;
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'HIGHLIGHT_NOT_SIGNED_IN' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_title) < 1 OR char_length(v_title) > 24 THEN
    RAISE EXCEPTION 'HIGHLIGHT_BAD_TITLE';
  END IF;

  -- De-duplicated, first-seen order kept.
  SELECT array_agg(x.id ORDER BY x.ord) INTO v_ids
    FROM (
      SELECT DISTINCT ON (u.id) u.id, u.ord
        FROM unnest(coalesce(p_post_ids, '{}'::uuid[]))
             WITH ORDINALITY AS u(id, ord)
       WHERE u.id IS NOT NULL
       ORDER BY u.id, u.ord
    ) x;
  v_n := coalesce(array_length(v_ids, 1), 0);
  IF v_n < 1 OR v_n > 20 THEN
    RAISE EXCEPTION 'HIGHLIGHT_BAD_PHOTO_COUNT';
  END IF;

  IF v_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.highlights h
        WHERE h.id = v_id AND h.user_id = v_me) THEN
    RAISE EXCEPTION 'HIGHLIGHT_NOT_FOUND';
  END IF;

  -- Every photo must be the caller's OWN quiet highlight photo. Never
  -- someone else's post; never an anonymous one (it would unmask its
  -- author on their own profile); never a post that lives in a feed; never
  -- one that already belongs to a different highlight.
  IF EXISTS (
       SELECT 1
         FROM unnest(v_ids) AS t(id)
         LEFT JOIN public.posts p ON p.id = t.id
        WHERE p.id IS NULL
           OR p.user_id <> v_me
           OR p.deleted_at IS NOT NULL
           OR p.post_type IS DISTINCT FROM 'highlight'
           OR p.visibility IS DISTINCT FROM 'friends'
           OR p.show_in_feed IS NOT FALSE
           OR EXISTS (
                SELECT 1 FROM public.highlight_items i
                 WHERE i.post_id = t.id
                   AND i.highlight_id IS DISTINCT FROM v_id)
     ) THEN
    RAISE EXCEPTION 'HIGHLIGHT_BAD_PHOTO';
  END IF;

  IF v_id IS NULL THEN
    IF (SELECT count(*) FROM public.highlights h WHERE h.user_id = v_me) >= 12 THEN
      RAISE EXCEPTION 'HIGHLIGHT_LIMIT';
    END IF;
    INSERT INTO public.highlights (user_id, title)
    VALUES (v_me, v_title)
    RETURNING id INTO v_id;
  ELSE
    -- updated_at is what makes a polaroid "new" again on a friend's Wall,
    -- so it moves only when photos were ADDED — not on a rename, a
    -- reorder or a removal.
    v_added := EXISTS (
      SELECT 1 FROM unnest(v_ids) AS t(id)
       WHERE NOT EXISTS (
               SELECT 1 FROM public.highlight_items i
                WHERE i.highlight_id = v_id AND i.post_id = t.id)
    );
    UPDATE public.highlights h
       SET title = v_title,
           updated_at = CASE WHEN v_added THEN now() ELSE h.updated_at END
     WHERE h.id = v_id;
  END IF;

  -- Photos dropped from the highlight have nowhere else to live.
  UPDATE public.posts p
     SET deleted_at = now()
   WHERE p.user_id = v_me
     AND p.post_type = 'highlight'
     AND p.deleted_at IS NULL
     AND p.id IN (SELECT i.post_id FROM public.highlight_items i
                   WHERE i.highlight_id = v_id)
     AND NOT (p.id = ANY (v_ids));
  DELETE FROM public.highlight_items i
   WHERE i.highlight_id = v_id AND NOT (i.post_id = ANY (v_ids));

  INSERT INTO public.highlight_items (highlight_id, post_id, position)
  SELECT v_id, t.id, (t.ord - 1)::integer
    FROM unnest(v_ids) WITH ORDINALITY AS t(id, ord)
  ON CONFLICT (post_id) DO UPDATE SET position = EXCLUDED.position;

  RETURN v_id;
END;
$function$;

-- ── delete_highlight ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_highlight(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid;
BEGIN
  SELECT u.id INTO v_me
    FROM public.users u
   WHERE u.auth_id = auth.uid() AND u.deleted_at IS NULL;
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'HIGHLIGHT_NOT_SIGNED_IN' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.highlights h
        WHERE h.id = p_id AND h.user_id = v_me) THEN
    RAISE EXCEPTION 'HIGHLIGHT_NOT_FOUND';
  END IF;

  UPDATE public.posts p
     SET deleted_at = now()
   WHERE p.user_id = v_me
     AND p.post_type = 'highlight'
     AND p.deleted_at IS NULL
     AND p.id IN (SELECT i.post_id FROM public.highlight_items i
                   WHERE i.highlight_id = p_id);
  DELETE FROM public.highlights h WHERE h.id = p_id AND h.user_id = v_me;
END;
$function$;

-- Postgres grants EXECUTE to PUBLIC by default.
REVOKE ALL ON FUNCTION public.save_highlight(uuid, text, uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_highlight(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_highlight(uuid, text, uuid[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_highlight(uuid) TO authenticated, service_role;

-- ── "Someone you pinned saw your highlight" ─────────────────────────────
-- notify_pinned_post_view names the surface it is about. Without a branch
-- of its own a highlight photo read as "your post" and opened a post
-- screen; it now says "highlight" and opens the profile, where the
-- polaroid lives. Patched in place from the live definition rather than
-- restated (the live function has drifted from its migration before).
DO $$
DECLARE
  v_def text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'notify_pinned_post_view'
     AND p.pronamespace = 'public'::regnamespace;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'notify_pinned_post_view not found';
  END IF;
  IF v_def LIKE '%v_kind = ''highlight''%' THEN
    RAISE NOTICE 'notify_pinned_post_view already patched';
    RETURN;
  END IF;
  v_new := replace(
    v_def,
    E'    v_screen := ''moment'';\n  ELSE\n',
    E'    v_screen := ''moment'';\n'
    || E'  ELSIF v_kind = ''highlight'' THEN\n'
    || E'    v_title  := ''Someone you pinned saw your highlight 👀'';\n'
    || E'    v_screen := ''profile'';\n'
    || E'  ELSE\n'
  );
  IF v_new = v_def THEN
    RAISE EXCEPTION 'notify_pinned_post_view: moment branch not found in the expected shape';
  END IF;
  EXECUTE v_new;
END $$;

COMMIT;
