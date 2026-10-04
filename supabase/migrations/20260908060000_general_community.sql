-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  "General" — the community every user belongs to by default          ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- CORRECTION to the earlier broadcast design. That published an
-- everyone-visibility POST, which lands in the friends/campus feed. What was
-- actually wanted is a COMMUNITY that every user is joined to by default, so
-- the General channel is an ordinary community feed — it just happens to have
-- everyone in it.
--
-- That is a better fit for this schema: announcements, priority notices,
-- polls and documents all already work per-community, so General inherits
-- every one of them instead of needing a parallel path.
--
-- community_members.user_id is an auth.uid() (profiles keyspace), NOT
-- users.id — this is the project's standing keyspace trap and getting it
-- wrong here would silently join nobody.

-- ── 1. The community ───────────────────────────────────────────────────
INSERT INTO public.communities (name, description)
SELECT 'General', 'Everyone on campus. Announcements from the college.'
 WHERE NOT EXISTS (
   SELECT 1 FROM public.communities WHERE lower(name) = 'general' AND deleted_at IS NULL
 );

-- ── 2. Join every existing user ────────────────────────────────────────
INSERT INTO public.community_members (community_id, user_id)
SELECT c.id, u.auth_id
  FROM public.communities c
  CROSS JOIN public.users u
 WHERE lower(c.name) = 'general'
   AND c.deleted_at IS NULL
   AND u.auth_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- ── 3. Join every FUTURE user, automatically ───────────────────────────
-- Without this, General is only "everyone" until the next signup.
CREATE OR REPLACE FUNCTION public.autojoin_general_community()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_general uuid;
BEGIN
  IF NEW.auth_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_general
    FROM public.communities
   WHERE lower(name) = 'general' AND deleted_at IS NULL
   LIMIT 1;

  IF v_general IS NOT NULL THEN
    INSERT INTO public.community_members (community_id, user_id)
    VALUES (v_general, NEW.auth_id)
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_autojoin_general ON public.users;
CREATE TRIGGER trg_autojoin_general
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.autojoin_general_community();

-- Also covers an existing row that gains an auth_id later.
DROP TRIGGER IF EXISTS trg_autojoin_general_upd ON public.users;
CREATE TRIGGER trg_autojoin_general_upd
  AFTER UPDATE OF auth_id ON public.users
  FOR EACH ROW WHEN (OLD.auth_id IS NULL AND NEW.auth_id IS NOT NULL)
  EXECUTE FUNCTION public.autojoin_general_community();

-- ── 4. Report ──────────────────────────────────────────────────────────
SELECT c.name,
       (SELECT count(*) FROM public.community_members m WHERE m.community_id = c.id) AS members,
       (SELECT count(*) FROM public.users WHERE auth_id IS NOT NULL) AS total_users
  FROM public.communities c
 WHERE lower(c.name) = 'general' AND c.deleted_at IS NULL;
