-- Ping page groups row (user request 2026-09-29): the most active group
-- first, and MY ping streak with each group shown on its chip.
--
-- One row per group I'm a member of:
--   my_streak  — my own member streak with the group (the same number
--                group_ping_member_streak_map gives me on the group screen)
--   activity   — group pings + replies + group posts in the last 7 days
--   last_active — newest of those, for tie-breaks and never-active groups
-- Ordered most active first.
CREATE OR REPLACE FUNCTION public.my_group_ping_overview()
RETURNS TABLE (group_id uuid, my_streak integer, activity integer, last_active timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH me AS (SELECT public.current_user_id() AS id),
  mine AS (
    SELECT gm.group_id FROM public.group_members gm, me WHERE gm.user_id = me.id
  ),
  events AS (
    SELECT t.group_id, (t.created_at AT TIME ZONE 'UTC') AS at
      FROM public.ping_threads t JOIN mine USING (group_id)
     WHERE t.kind = 'group' AND t.created_at > (now() AT TIME ZONE 'UTC') - interval '7 days'
    UNION ALL
    SELECT p.group_id, (r.created_at AT TIME ZONE 'UTC')
      FROM public.ping_replies r
      JOIN public.pings p ON p.id = r.ping_id
      JOIN mine ON mine.group_id = p.group_id
     WHERE r.deleted_at IS NULL
       AND r.created_at > (now() AT TIME ZONE 'UTC') - interval '7 days'
    UNION ALL
    SELECT gp.group_id, gp.created_at
      FROM public.group_posts gp JOIN mine USING (group_id)
     WHERE gp.deleted_at IS NULL AND gp.created_at > now() - interval '7 days'
  )
  SELECT m.group_id,
         COALESCE((SELECT s.streak FROM public.group_ping_member_streak_map(m.group_id) s, me
                    WHERE s.user_id = me.id), 0),
         (SELECT count(*)::int FROM events e WHERE e.group_id = m.group_id),
         (SELECT max(e.at) FROM events e WHERE e.group_id = m.group_id)
    FROM mine m
   ORDER BY 3 DESC, 4 DESC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION public.my_group_ping_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_group_ping_overview() TO authenticated;
