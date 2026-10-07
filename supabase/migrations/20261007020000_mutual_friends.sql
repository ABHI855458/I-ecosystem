-- Mutual friends (explicit request, 2026-10-06: "when searched the list
-- shall show the user's mutuals, when visited their profile as well — the
-- persons in my friends list and as well in their friends list — and in
-- suggestions as well shall show accordingly to the mutuals").
--
-- "Mutual" = someone in MY Friends circle who is also in THE OTHER
-- person's Friends circle. Circles are private (circles / circle_members
-- are creator-only under RLS), so the client can't work this out; these
-- SECURITY DEFINER functions do, and return only people who are already
-- in the caller's own Friends circle — never anyone outside it. What a
-- caller learns is "which of my own friends has X also added", nothing
-- more.
--
-- Blocks (either direction) and deleted accounts never appear, and a
-- signed-out caller (auth.uid() null -> no `me` row) gets nothing.

BEGIN;

-- ── Who we have in common ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mutual_friends(p_other uuid)
 RETURNS TABLE(user_id uuid, name text, username text, profile_photo_url text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (
    SELECT u.id, u.auth_id FROM public.users u WHERE u.auth_id = auth.uid()
  )
  SELECT u.id, u.name, u.username, u.profile_photo_url
    FROM me
    JOIN public.users o
      ON o.id = p_other AND o.deleted_at IS NULL AND o.id <> me.id
    JOIN public.friends_circle_members mine ON mine.owner_id = me.id
    JOIN public.friends_circle_members theirs
      ON theirs.owner_id = o.id AND theirs.member_id = mine.member_id
    JOIN public.users u ON u.id = mine.member_id
   WHERE u.deleted_at IS NULL
     AND u.id <> me.id
     AND u.id <> o.id
     AND NOT public.is_blocked_user(me.auth_id, o.id)
     AND NOT public.is_blocked_user(me.auth_id, u.id)
   ORDER BY lower(u.name), u.id;
$function$;

-- ── How many, for a whole list at once (search rows, suggestions) ───────
-- Only ids with at least one mutual come back; a missing id means 0. The
-- input is capped so one call can't be used to sweep the whole user table.
CREATE OR REPLACE FUNCTION public.mutual_friend_counts(p_ids uuid[])
 RETURNS TABLE(user_id uuid, mutual_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (
    SELECT u.id, u.auth_id FROM public.users u WHERE u.auth_id = auth.uid()
  ),
  targets AS (
    SELECT DISTINCT t.id
      FROM unnest((COALESCE(p_ids, '{}'::uuid[]))[1:200]) AS t(id)
  )
  SELECT o.id, count(*)::integer
    FROM me
    JOIN targets t ON t.id <> me.id
    JOIN public.users o ON o.id = t.id AND o.deleted_at IS NULL
    JOIN public.friends_circle_members theirs ON theirs.owner_id = o.id
    JOIN public.friends_circle_members mine
      ON mine.owner_id = me.id AND mine.member_id = theirs.member_id
    JOIN public.users u ON u.id = mine.member_id
   WHERE u.deleted_at IS NULL
     AND u.id <> me.id
     AND u.id <> o.id
     AND NOT public.is_blocked_user(me.auth_id, o.id)
     AND NOT public.is_blocked_user(me.auth_id, u.id)
   GROUP BY o.id;
$function$;

REVOKE ALL ON FUNCTION public.mutual_friends(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mutual_friend_counts(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mutual_friends(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mutual_friend_counts(uuid[]) TO authenticated, service_role;

-- ── Suggestions: most mutuals first ─────────────────────────────────────
-- Rebuilt from the LIVE definition (2026-10-07), which matches
-- 20260929040000_suggested_people_any_circle.sql: same candidate rule,
-- same columns in the same order, plus one new trailing column
-- (mutual_count) and a new leading sort key. A return-type change can't be
-- done with CREATE OR REPLACE, hence the DROP inside this transaction.
-- Older app builds read the rows by key and ignore the extra column.
DROP FUNCTION IF EXISTS public.suggested_people(integer);

CREATE FUNCTION public.suggested_people(p_limit integer DEFAULT 60)
 RETURNS TABLE(user_id uuid, name text, username text, profile_photo_url text, joined_at timestamp without time zone, community_name text, mutual_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (
    SELECT u.id, u.auth_id FROM public.users u WHERE u.auth_id = auth.uid()
  ),
  my_communities AS (
    SELECT cm.community_id FROM public.community_members cm, me
     WHERE cm.user_id = me.auth_id
  ),
  candidates AS (
    SELECT DISTINCT ON (u.id)
           u.id, u.name, u.username, u.profile_photo_url, u.created_at,
           c.name AS community_name
      FROM public.community_members cm
      JOIN my_communities mc ON mc.community_id = cm.community_id
      JOIN public.users u ON u.auth_id = cm.user_id
      LEFT JOIN public.communities c ON c.id = cm.community_id
      CROSS JOIN me
     WHERE u.id <> me.id
       AND u.deleted_at IS NULL
       AND u.onboarding_completed IS TRUE
       AND NOT public.is_blocked_user(me.auth_id, u.id)
       AND NOT EXISTS (
             SELECT 1 FROM public.circles fc
               JOIN public.circle_members m ON m.circle_id = fc.id
              WHERE fc.creator_id = me.id
                AND m.member_id = u.id)
     ORDER BY u.id
  ),
  scored AS (
    SELECT c.*,
           (SELECT count(*)::integer
              FROM me
              JOIN public.friends_circle_members mine ON mine.owner_id = me.id
              JOIN public.friends_circle_members theirs
                ON theirs.owner_id = c.id AND theirs.member_id = mine.member_id
              JOIN public.users mu ON mu.id = mine.member_id
             WHERE mu.deleted_at IS NULL
               AND mu.id <> c.id
               AND NOT public.is_blocked_user(me.auth_id, mu.id)) AS mutual_count
      FROM candidates c
  )
  SELECT id, name, username, profile_photo_url, created_at, community_name,
         mutual_count
    FROM scored
   ORDER BY mutual_count DESC, created_at DESC NULLS LAST
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 60), 1), 100);
$function$;

REVOKE ALL ON FUNCTION public.suggested_people(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggested_people(integer) TO authenticated, service_role;

COMMIT;
