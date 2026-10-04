-- ============================================================================
-- Friend requests are gone for good (see 20260926000000_circles_replace_
-- friendships.sql — circles are the graph now). Nothing in the database or
-- the app reads `friendships` any more (checked: 0 pg_proc bodies, 0 client
-- queries), so:
--   * the request/accept notification triggers and their functions go,
--   * the table is archived, not dropped, and locked away from clients —
--     a missed reference now ERRORS loudly instead of silently returning [].
--     Drop friendships_archive_20260926 once nothing has complained.
--   * the long-broken is_in_circle() (referenced columns that don't exist)
--     goes too.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================

BEGIN;

DROP TRIGGER IF EXISTS trg_notify_friend_request ON public.friendships;
DROP TRIGGER IF EXISTS trg_notify_friend_accepted ON public.friendships;
DROP FUNCTION IF EXISTS public.notify_friend_request();
DROP FUNCTION IF EXISTS public.notify_friend_accepted();
DROP FUNCTION IF EXISTS public.is_in_circle(uuid, uuid);

ALTER TABLE public.friendships RENAME TO friendships_archive_20260926;
REVOKE ALL ON public.friendships_archive_20260926 FROM PUBLIC, anon, authenticated;

COMMIT;
