-- Suggestions widened (user request 2026-09-29): not only new users —
-- everyone I share a community with who isn't in ANY of my circles yet (was:
-- not in my Friends circle). Newest still first, so arrivals lead the strip.
CREATE OR REPLACE FUNCTION public.suggested_people(p_limit integer DEFAULT 60)
RETURNS TABLE (
  user_id uuid,
  name text,
  username text,
  profile_photo_url text,
  joined_at timestamp without time zone,
  community_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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
  )
  SELECT id, name, username, profile_photo_url, created_at, community_name
    FROM candidates
   ORDER BY created_at DESC NULLS LAST
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 60), 1), 100);
$$;

REVOKE ALL ON FUNCTION public.suggested_people(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.suggested_people(integer) TO authenticated;
