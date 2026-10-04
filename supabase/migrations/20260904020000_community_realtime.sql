-- ============================================================================
-- Add the new community tables to Postgres logical replication so the app
-- can subscribe with supabase-flutter's .channel(...).onPostgresChanges(...).
--
-- CONFIRMED against the live database on 2026-09-04 via the Supabase MCP:
-- the only publication with any table in it is
-- supabase_realtime_messages_publication (table: messages). There is no
-- `supabase_realtime` publication at all yet — every other realtime
-- subscription in this codebase (reaction_service.dart, score_service.dart,
-- viewer_service.dart) targets a table that was never actually added to a
-- publication; score_service.dart's own comment says its subscribe is
-- "no-op if table doesn't exist yet" and wraps it in try/catch, which is
-- almost certainly masking exactly this gap. This migration creates the
-- publication if missing and adds only the tables this feature needs.
--
-- Realtime respects RLS on each table, so adding community_streaks here
-- does not widen who can read it — only members already covered by
-- community_streaks_select receive change events.
--
-- Every statement is idempotent, safe to re-run.
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.community_posts;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.community_streaks;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;

  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.community_feed_items;
  EXCEPTION WHEN duplicate_object THEN
    NULL;
  END;
END $$;
