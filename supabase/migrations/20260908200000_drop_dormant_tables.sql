-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Drop dormant tables — features that were never finished             ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- Each of these has ZERO rows, no client reference (`grep from('<table>')`
-- across lib/ returns nothing), no external foreign key pointing at it, and
-- no policy outside the table itself. Verified before writing this file.
--
-- Kept deliberately, despite also being dormant:
--   buckets, bucket_contributions   bucket_service.dart still compiles against them
--   memories                        memory_service.dart, reached from feed_service
--   highlights                      wall_service.dart
--   follows                         `close_group_view_posts` on posts references it
--   vibe_tags                       10 real rows
--   community_feed_poll_*           the community board's real poll feature
--
-- Dropping those would break the build or an existing policy, so they are a
-- separate, deliberate piece of work rather than part of a cleanup pass.

-- Superseded by pings.anonymous — the whole anon-ping thread model was
-- replaced by a flag on the ordinary pings table.
DROP TABLE IF EXISTS public.anon_ping_messages     CASCADE;
DROP TABLE IF EXISTS public.anon_ping_participants CASCADE;
DROP TABLE IF EXISTS public.anon_ping_threads      CASCADE;

-- Never built past the schema.
DROP TABLE IF EXISTS public.discussion_room_messages CASCADE;
DROP TABLE IF EXISTS public.discussion_rooms        CASCADE;
DROP TABLE IF EXISTS public.poll_votes              CASCADE;
DROP TABLE IF EXISTS public.poll_options            CASCADE;
DROP TABLE IF EXISTS public.circles                 CASCADE;
DROP TABLE IF EXISTS public.mood_tracks             CASCADE;
DROP TABLE IF EXISTS public.pins                    CASCADE;
DROP TABLE IF EXISTS public.account_views           CASCADE;
DROP TABLE IF EXISTS public.collages                CASCADE;

SELECT count(*)::int AS tables_remaining
  FROM information_schema.tables
 WHERE table_schema='public' AND table_type='BASE TABLE';
