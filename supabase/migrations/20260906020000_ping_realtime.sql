-- ============================================================================
-- PING — live updates.
--
-- `pings`/`ping_replies` were not in the supabase_realtime publication
-- (verified), and ping_page.dart only ever loaded on mount + auth events, so
-- nothing told the receiver's device that a ping had arrived, or the
-- sender's device that a reply/seen had landed. Everything looked broken
-- from the UI even though every write was landing correctly server-side.
--
-- Realtime applies RLS per subscriber, so this leaks nothing the client
-- couldn't already SELECT:
--   * a person ping's receiver sees their own row (pings_select branch 2)
--   * a group member sees the thread's rows once they've answered
--   * an ANONYMOUS ping's receiver sees NOTHING here — pings_select
--     deliberately withholds that row so sender_id can't be read, which
--     also means no realtime event reaches them. That's why PingPage keeps
--     a slow poll alongside this subscription: the poll goes through
--     ping_inbox(), which is the masked path, so anonymous pings still show
--     up promptly without ever exposing the sender.
-- REPLICA IDENTITY stays default (primary key only) — the client reloads
-- through the RPCs on any event rather than reading payload columns, so
-- there's no reason to widen what the WAL emits.
-- ============================================================================

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.pings;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.ping_replies;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
