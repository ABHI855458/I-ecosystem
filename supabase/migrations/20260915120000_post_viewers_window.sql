-- "Here" (feed) vs "Seen" (profile) — same viewer list, two time horizons.
--
-- Already correct before this change, and deliberately left alone:
--   * is_pinned is computed against THE CALLER's pinned_people, not the
--     post author's. So if A and B have pinned different people, B opening
--     the list on A's post sees B's OWN pinned people surfaced first — the
--     stated requirement, already the existing behaviour.
--   * ordering is (is_pinned DESC, viewed_at DESC).
--
-- What's new: an optional window. On the FEED the button answers "who is
-- here", which is a recency claim, so it takes p_window_hours = 3 and shows
-- only views from the last 3 hours. On the PROFILE it answers "who has
-- seen this", which is a history claim, so it passes NULL and shows
-- everything ever.
--
-- The exception that makes the window non-trivial: a PINNED viewer is shown
-- regardless of how long ago they viewed, on both surfaces. Explicit
-- instruction — "even if they have visited, no time limit to show the
-- pinned people". So the window filters non-pinned rows only.
--
-- Signature change (1 arg -> 1 arg + defaulted 2nd) needs a DROP: adding a
-- defaulted parameter via CREATE OR REPLACE would leave the old 1-arg
-- function in place and make post_viewers(uuid) ambiguous.
DROP FUNCTION IF EXISTS public.post_viewers(uuid);

CREATE FUNCTION public.post_viewers(
  p_post_id uuid,
  p_window_hours integer DEFAULT NULL
)
RETURNS TABLE(
  user_id uuid, username text, name text, avatar_url text,
  is_pinned boolean, viewed_at timestamp with time zone
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  with me as (select id from public.users where auth_id = auth.uid())
  select
    u.id,
    u.username,
    u.name,
    u.profile_photo_url,
    exists (
      select 1
        from public.pinned_people pp
       where pp.user_id = (select id from me)
         and pp.pinned_user_id = u.id
    ) as is_pinned,
    pv.created_at
  from public.post_views pv
  join public.users u on u.id = pv.viewer_id
  where pv.post_id = p_post_id
    and public.post_engagement_visible(p_post_id)
    and (
      p_window_hours is null
      or pv.created_at >= now() - make_interval(hours => p_window_hours)
      -- pinned viewers ignore the window entirely
      or exists (
        select 1
          from public.pinned_people pp
         where pp.user_id = (select id from me)
           and pp.pinned_user_id = u.id
      )
    )
  order by 5 desc, pv.created_at desc;
$$;

GRANT EXECUTE ON FUNCTION public.post_viewers(uuid, integer) TO authenticated;
