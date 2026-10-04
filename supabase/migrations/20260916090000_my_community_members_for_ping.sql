-- "When gone to ping someone section I shall see below that widget list of
-- all the members in the communities the user has joined" — the Ping page
-- currently only lists accepted friends; this adds every member of every
-- community the caller has joined, so any of them can be pinged too.
--
-- Needs an RPC rather than a plain PostgREST embed: community_members.
-- user_id stores the AUTH id (auth.users.id), not users.id, so there is no
-- FK for PostgREST to embed users(*) through directly.
CREATE OR REPLACE FUNCTION public.my_community_members_for_ping()
RETURNS TABLE(user_id uuid, username text, name text, avatar_url text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
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
  ORDER BY u.id;
$$;

REVOKE ALL ON FUNCTION public.my_community_members_for_ping() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_community_members_for_ping() TO authenticated;
