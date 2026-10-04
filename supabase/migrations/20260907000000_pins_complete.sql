-- Phase 1 — Pinning, completed.
--
-- `pinned_people` and two of its four RPCs (toggle_pin_post_author,
-- is_post_author_pinned) already exist live. `list_pinned_people`,
-- `unpin_person`, and `is_pinned_by` are declared in schema.sql but were
-- never applied to the live database — settings_screen.dart's Pinned
-- People section has been silently broken since it shipped. This migration
-- adds those three, plus the new profile-section pin flow (`pin_person`,
-- `shares_community`) and a hard max-5 cap that never existed server-side
-- (the old `enforce_pin_max()` referenced a nonexistent `pinner_id` column
-- and was dropped rather than fixed).
--
-- Identity: pinned_people.user_id / pinned_user_id both reference
-- users.id (confirmed live via information_schema — matches friendships,
-- reactions, post_presence). community_members.user_id references
-- profiles.id (= auth.uid()), a different keyspace — shares_community
-- bridges the two via users.auth_id, the same pattern is_community_member
-- already uses one level up.

-- ---------------------------------------------------------------------------
-- shares_community — do users A and B (both users.id) belong to any of the
-- same communities? Bridges users.id -> users.auth_id -> community_members
-- (keyed on profiles.id/auth.uid()) on both sides.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.shares_community(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM users ua
    JOIN community_members ma ON ma.user_id = ua.auth_id
    JOIN community_members mb ON mb.community_id = ma.community_id
    JOIN users ub ON ub.auth_id = mb.user_id
    WHERE ua.id = p_a AND ub.id = p_b
  );
$function$;

REVOKE ALL ON FUNCTION public.shares_community(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.shares_community(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- pin_person — the profile-section pin flow (distinct from
-- toggle_pin_post_author, which pins an anon post's author and predates
-- this feature). Rejects self-pin, requires a shared community, enforces
-- the cap explicitly (the trigger below is the backstop, not the primary
-- gate, so the caller gets a clean error message rather than a generic
-- trigger exception where avoidable... though both raise the same message
-- here for simplicity). Returns the caller's new pin count.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pin_person(p_pinned_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
  v_count integer;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'no matching users row for auth.uid()';
  END IF;
  IF p_pinned_user_id = v_me THEN
    RAISE EXCEPTION 'cannot pin yourself';
  END IF;
  IF NOT public.shares_community(v_me, p_pinned_user_id) THEN
    RAISE EXCEPTION 'can only pin someone in a shared community';
  END IF;

  SELECT count(*) INTO v_count FROM pinned_people WHERE user_id = v_me;
  IF v_count >= 5 THEN
    RAISE EXCEPTION 'pin limit reached (5)';
  END IF;

  INSERT INTO pinned_people (user_id, pinned_user_id)
  VALUES (v_me, p_pinned_user_id)
  ON CONFLICT (user_id, pinned_user_id) DO NOTHING;

  RETURN (SELECT count(*) FROM pinned_people WHERE user_id = v_me);
END;
$function$;

REVOKE ALL ON FUNCTION public.pin_person(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pin_person(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- list_pinned_people / unpin_person / is_pinned_by — declared in schema.sql,
-- never applied live. Signatures match that declaration so existing client
-- code (settings_screen.dart, post_author_pin_service.dart) starts working
-- as soon as this migration runs, with no client change needed for those.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_pinned_people()
RETURNS TABLE(pinned_user_id uuid, name text, profile_photo_url text, pinned_at timestamp)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT u.id, u.name, u.profile_photo_url, pp.created_at
  FROM pinned_people pp
  JOIN users u ON u.id = pp.pinned_user_id
  WHERE pp.user_id = (SELECT id FROM users WHERE auth_id = auth.uid())
  ORDER BY pp.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.list_pinned_people() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_pinned_people() TO authenticated;

-- Returns boolean (row actually deleted) — post_author_pin_service.dart's
-- unpin() already casts the RPC result `as bool`.
CREATE OR REPLACE FUNCTION public.unpin_person(p_pinned_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
BEGIN
  DELETE FROM pinned_people WHERE user_id = v_me AND pinned_user_id = p_pinned_user_id;
  RETURN FOUND;
END;
$function$;

REVOKE ALL ON FUNCTION public.unpin_person(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unpin_person(uuid) TO authenticated;

-- service_role only — the identity-reveal check called from the notify-*
-- Edge Functions, never directly probable by a client (that would let a
-- client discover who has pinned them without being told).
CREATE OR REPLACE FUNCTION public.is_pinned_by(p_recipient_id uuid, p_actor_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM pinned_people
    WHERE user_id = p_recipient_id AND pinned_user_id = p_actor_id
  );
$function$;

REVOKE ALL ON FUNCTION public.is_pinned_by(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_pinned_by(uuid, uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- enforce_pin_max — hard backstop trigger so the cap holds even for
-- toggle_pin_post_author's insert path, not just pin_person's. The
-- previous version of this function (dropped, see schema.sql:1117-1119)
-- referenced a nonexistent `pinner_id` column; the live column is
-- `user_id`.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_pin_max()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF (SELECT count(*) FROM pinned_people WHERE user_id = NEW.user_id) >= 5 THEN
    RAISE EXCEPTION 'pin limit reached (5)';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.enforce_pin_max() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enforce_pin_max ON public.pinned_people;
CREATE TRIGGER trg_enforce_pin_max
  BEFORE INSERT ON public.pinned_people
  FOR EACH ROW EXECUTE FUNCTION public.enforce_pin_max();
