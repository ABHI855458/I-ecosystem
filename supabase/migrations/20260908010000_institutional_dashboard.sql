-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  INSTITUTIONAL DASHBOARD — Principal / Dean access                   ║
-- ║  Run blocks in order. Block 2 needs their real emails first.         ║
-- ╚══════════════════════════════════════════════════════════════════════╝


-- ═══ BLOCK 1 ═══════════════════════════════════════════════════════════
-- SECURITY FIX — unrelated to the dashboard, but found while auditing it
-- and currently leaking. Ship this even if the rest is deferred.
--
-- `posts_feed` is security_invoker=false, so it reads `posts` PAST row-level
-- security. Its WHERE gates anonymous+community but says nothing about
-- 'friends' visibility — so any authenticated user can read every
-- friends-only post in the app by querying the view directly.
--
-- Measured live: a user who is a friend of nobody sees 9 friends-only posts
-- through the view, versus the 3 RLS correctly allows on the table.
--
-- Fix: gate 'friends' rows on can_view_post(), the same function
-- posts_select already uses. Anonymous behaviour is untouched (an anon row
-- is not 'friends'), so the Anon feed is unaffected.

CREATE OR REPLACE VIEW public.posts_feed AS
 SELECT id,
        CASE
            WHEN visibility = 'anonymous'::text AND NOT (EXISTS ( SELECT 1
               FROM users u
              WHERE u.id = p.user_id AND u.auth_id = auth.uid())) THEN NULL::uuid
            ELSE user_id
        END AS user_id,
    content, image_url, visibility, community_id, music_id, music_url,
    music_title, music_artist, prompt, photo_fit, aspect_ratio, post_type,
    view_count, created_at, updated_at,
    ( SELECT au.anon_photo_url FROM users au WHERE au.id = p.user_id) AS anon_photo_url,
    prompt_id,
    ( SELECT au.total_score FROM users au WHERE au.id = p.user_id) AS author_total_score,
    ( SELECT au.level FROM users au WHERE au.id = p.user_id) AS author_level,
    CASE
        WHEN visibility = 'anonymous'::text
        THEN ( SELECT NULLIF(btrim(au.anon_name), '') FROM users au WHERE au.id = p.user_id)
        ELSE NULL::text
    END AS anon_name,
    moment_color
   FROM posts p
  WHERE deleted_at IS NULL
    AND (visibility IS DISTINCT FROM 'anonymous'::text
         OR community_id IS NULL
         OR (EXISTS ( SELECT 1 FROM community_members cm
                       WHERE cm.community_id = p.community_id
                         AND cm.user_id = auth.uid())))
    -- ↓ THE FIX
    AND (visibility IS DISTINCT FROM 'friends'::text OR public.can_view_post(id));


-- ═══ BLOCK 2 ═══════════════════════════════════════════════════════════
-- Institutional accounts. One identity per person (Decision A).
--
-- Two rows are needed per person and they live in different id spaces:
--   • public.users      — so they can AUTHOR posts (posts_insert requires
--                         auth.uid() to match users.auth_id for posts.user_id)
--   • public.moderators — so the dashboard's role checks admit them
--
-- PREREQUISITE: the Auth account must already exist. Create it in the
-- Supabase dashboard (Authentication ▸ Add user) or via the admin
-- dashboard's Users page, then run this.
--
-- Idempotent: re-running repairs a partial provision rather than erroring.

CREATE OR REPLACE FUNCTION public.provision_institutional_account(
  p_email        text,
  p_display_name text,
  p_role         text DEFAULT 'global_moderator')
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_auth uuid;
  v_user uuid;
BEGIN
  IF p_role NOT IN ('global_moderator','community_moderator','admin') THEN
    RAISE EXCEPTION 'bad role: %', p_role;
  END IF;

  SELECT id INTO v_auth FROM auth.users WHERE lower(email) = lower(p_email);
  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'No auth user for %. Create the login first.', p_email;
  END IF;

  -- App-side user row, so their posts have a valid author.
  INSERT INTO public.users (auth_id, email, name, anon_name, onboarding_completed)
  VALUES (v_auth, lower(p_email), p_display_name,
          'office_' || replace(v_auth::text,'-',''), true)
  ON CONFLICT (auth_id) DO UPDATE
     SET name = EXCLUDED.name, onboarding_completed = true
  RETURNING id INTO v_user;

  IF v_user IS NULL THEN
    SELECT id INTO v_user FROM public.users WHERE auth_id = v_auth;
  END IF;

  -- Dashboard role. is_protected stays false so Abhishek can revoke them.
  INSERT INTO public.moderators (email, role, is_protected)
  VALUES (lower(p_email), p_role, false)
  ON CONFLICT (email) DO UPDATE SET role = EXCLUDED.role;

  RETURN 'provisioned ' || p_email || ' as ' || p_role || ' (users.id=' || v_user || ')';
END;
$function$;

REVOKE ALL ON FUNCTION public.provision_institutional_account(text,text,text) FROM PUBLIC, anon, authenticated;

-- ── RUN THESE TWO ONCE YOU HAVE THE EMAILS ────────────────────────────
-- select public.provision_institutional_account(
--          'principal@rvce.edu.in', 'Principal, RVCE');
-- select public.provision_institutional_account(
--          'dean@rvce.edu.in',      'Dean, RVCE');


-- ═══ BLOCK 3 ═══════════════════════════════════════════════════════════
-- Dashboard read access across every feed.
--
-- Deliberately an RPC, NOT a permissive SELECT policy on `posts`.
-- A policy would hand moderators the raw rows including `user_id` on
-- ANONYMOUS posts — silently de-anonymising the whole anon feed to the
-- Principal and Dean. This returns the same posts with the anon author
-- masked exactly as students see them, so the anonymity promise holds for
-- institutional viewers too.
--
-- If a named disciplinary case ever needs de-anonymisation, that should be
-- a separate, deliberately-logged action — not a side effect of opening a
-- dashboard tab.

DROP FUNCTION IF EXISTS public.dashboard_feed(text,integer,integer);

CREATE FUNCTION public.dashboard_feed(
  p_scope  text DEFAULT 'all',      -- all | anon | friends | everyone | moment | us
  p_limit  integer DEFAULT 50,
  p_offset integer DEFAULT 0)
 RETURNS TABLE(
   id uuid, user_id uuid, author_name text, author_avatar text,
   is_anonymous boolean, anon_name text,
   content text, image_url text, visibility text, post_type text,
   community_id uuid, community_name text,
   comment_count integer, reaction_count integer, view_count integer,
   -- `posts.created_at` is timestamp WITHOUT time zone (unlike every other
   -- table here, which uses timestamptz). Declaring timestamptz made
   -- RETURN QUERY fail with 42804 on every call.
   created_at timestamp)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.is_admin_or_global_mod() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;

  RETURN QUERY
  SELECT p.id,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::uuid ELSE p.user_id END,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::text ELSE u.name END,
         CASE WHEN p.visibility = 'anonymous' THEN NULL::text ELSE u.profile_photo_url END,
         (p.visibility = 'anonymous'),
         CASE WHEN p.visibility = 'anonymous'
              THEN COALESCE(NULLIF(btrim(u.anon_name),''),'anonymous') END,
         p.content, p.image_url, p.visibility, p.post_type,
         p.community_id, c.name,
         (SELECT COUNT(*)::int FROM comments cm
           WHERE cm.post_id = p.id AND cm.deleted_at IS NULL),
         (SELECT COUNT(*)::int FROM post_realmoji_reactions r WHERE r.post_id = p.id),
         COALESCE(p.view_count,0),
         p.created_at
    FROM posts p
    JOIN users u ON u.id = p.user_id
    LEFT JOIN communities c ON c.id = p.community_id
   WHERE p.deleted_at IS NULL
     AND p.post_type IS DISTINCT FROM 'memory'
     AND (p_scope = 'all'
       OR (p_scope = 'anon'     AND p.visibility = 'anonymous')
       OR (p_scope = 'friends'  AND p.visibility = 'friends')
       OR (p_scope = 'everyone' AND p.visibility = 'everyone')
       OR (p_scope = 'moment'   AND p.post_type  = 'moment')
       OR (p_scope = 'us'       AND p.post_type  = 'us'))
   ORDER BY p.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_feed(text,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dashboard_feed(text,integer,integer) TO authenticated;

-- Community posts, same gate, same shape.
DROP FUNCTION IF EXISTS public.dashboard_community_feed(uuid,integer,integer);

CREATE FUNCTION public.dashboard_community_feed(
  p_community uuid DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0)
 RETURNS TABLE(
   id uuid, community_id uuid, community_name text,
   author_name text, is_anonymous boolean,
   body text, photo_urls text[], created_at timestamptz)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.is_admin_or_global_mod() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;

  RETURN QUERY
  SELECT cp.id, cp.community_id, c.name,
         CASE WHEN cp.is_anonymous THEN NULL::text ELSE u.name END,
         -- community_posts stores `body` + `photo_urls[]`, NOT content/image_url
         -- (those are the `posts` table's names). Confirmed against the live
         -- column list; the wrong names would have thrown 42703 on every call.
         cp.is_anonymous, cp.body, cp.photo_urls, cp.created_at
    FROM community_posts cp
    JOIN communities c ON c.id = cp.community_id
    LEFT JOIN users u ON u.id = cp.user_id
   WHERE cp.deleted_at IS NULL
     AND (p_community IS NULL OR cp.community_id = p_community)
   ORDER BY cp.created_at DESC
   LIMIT p_limit OFFSET p_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_community_feed(uuid,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dashboard_community_feed(uuid,integer,integer) TO authenticated;


-- ═══ BLOCK 4 ═══════════════════════════════════════════════════════════
-- notifications.type gains 'announcement'.
-- The CHECK constraint is a fixed whitelist; an insert of a new type fails
-- outright without this.

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'reaction','ping','friend_request','friend_accepted','branch_view',
    'us_album_mutual','report_resolved','report_filed',
    'announcement'
  ]));


-- ═══ BLOCK 5 ═══════════════════════════════════════════════════════════
-- PRIORITY fan-out. Campus-wide (Decision B).
--
-- Writes into the EXISTING community_feed_items channel the app's
-- Announcements tab already renders — no parallel system. What was missing
-- was the notification half: that table had no triggers at all, so a
-- priority notice was display-only.
--
-- CORRECTION vs. an earlier draft: `item_type` has its own CHECK allowing
-- only 'news' | 'poll' | 'daily_prompt', and the app already renders EVERY
-- row of this table under its PRIORITY header. So priority is not a new
-- item_type — it is a separate flag that decides whether an item also
-- NOTIFIES. That keeps rendering untouched (no app change, no CHECK
-- rewrite) and lets a routine notice be posted without pushing a major
-- alert to every student on campus.
--
-- tier='major' is the app's own top priority level (notifications.tier ∈
-- minor|standard|major, already read by NotificationFeedService).
--
-- Campus-wide: every user with an auth account, minus the author. At the
-- current 6 users this is trivial; past a few thousand this should move to
-- a queue + push worker rather than a synchronous fan-out. Flagged, not
-- solved, since it is not a demo-scale problem.

ALTER TABLE public.community_feed_items
  ADD COLUMN IF NOT EXISTS is_priority boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.community_feed_items.is_priority IS
  'Campus-wide major notification on insert. Rendering is unaffected — the '
  'app already shows every row of this table under its PRIORITY header.';

CREATE OR REPLACE FUNCTION public.fanout_priority_announcement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_author_users_id uuid;
  v_n integer;
BEGIN
  -- Only flagged items notify. Everything else still renders in the tab.
  IF NEW.is_priority IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  SELECT u.id INTO v_author_users_id
    FROM public.moderators m
    JOIN public.users u ON lower(u.email) = lower(m.email)
   WHERE m.id = NEW.author_moderator_id;

  INSERT INTO public.notifications
    (recipient_id, type, actor_id, tier, title, body, dedupe_key)
  SELECT u.id,
         'announcement',
         v_author_users_id,
         'major',
         COALESCE(NULLIF(btrim(NEW.title),''), 'Campus announcement'),
         NEW.body,
         'announce:' || NEW.id::text || ':' || u.id::text
    FROM public.users u
   WHERE u.auth_id IS NOT NULL
     AND (v_author_users_id IS NULL OR u.id <> v_author_users_id)
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'priority announcement % -> % recipients', NEW.id, v_n;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_fanout_priority_announcement ON public.community_feed_items;
CREATE TRIGGER trg_fanout_priority_announcement
  AFTER INSERT ON public.community_feed_items
  FOR EACH ROW EXECUTE FUNCTION public.fanout_priority_announcement();
