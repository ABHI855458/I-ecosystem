-- "From your communities" on the Ping page sits directly BELOW the friends
-- row, and was listing people who were already in that row — so the same
-- person showed up twice on one screen with no explanation of why.
-- Explicit question: "in ping page why did from your community appear".
--
-- The section's job is to surface people you are NOT already friends with
-- but share a community with; anyone already a friend is reachable from the
-- row above. Accepted friendships are excluded here (pending ones are not —
-- a pending request is not yet a way to reach someone).
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
  AND NOT EXISTS (
    SELECT 1 FROM public.friendships f
    WHERE f.status = 'accepted'
      AND ((f.requester_id = me.id AND f.addressee_id = u.id)
        OR (f.addressee_id = me.id AND f.requester_id = u.id))
  )
  ORDER BY u.id;
$function$;
