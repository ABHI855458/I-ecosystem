-- Follow-up to 20260926000000_backfill_group_community_id.sql. That
-- backfill picked each creator's EARLIEST-joined community with no check
-- on whether it still exists — and on this account, the earliest-joined
-- communities are almost all soft-deleted test data from 2026-09-19.
-- Confirmed live: the demo teaser post never showed up in the friends feed
-- because the client's own "my communities" list (fetchJoinedCommunities)
-- correctly filters out deleted communities, so a group pointed at a
-- deleted one was invisible to the teaser fetch even though the RPC itself
-- doesn't check deleted_at and happily returned rows when queried directly
-- with the raw community id — a gap between what the SQL function allows
-- and what the client can ever ask it for.
--
-- Fix: repick community_id for every group currently pointing at NULL or
-- at a deleted community, preferring the creator's earliest-joined ACTIVE
-- (deleted_at IS NULL) community this time.
UPDATE public.groups g
   SET community_id = pick.community_id
  FROM (
    SELECT DISTINCT ON (u.id) u.id AS user_id, cm.community_id
      FROM public.users u
      JOIN public.community_members cm ON cm.user_id = u.auth_id
      JOIN public.communities c ON c.id = cm.community_id
     WHERE c.deleted_at IS NULL
     ORDER BY u.id, cm.joined_at ASC
  ) pick
 WHERE g.created_by = pick.user_id
   AND (
     g.community_id IS NULL
     OR EXISTS (
       SELECT 1 FROM public.communities c2
        WHERE c2.id = g.community_id AND c2.deleted_at IS NOT NULL
     )
   );
