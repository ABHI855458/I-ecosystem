-- posts_feed and anon_reaction_counts are SECURITY DEFINER views (they skip
-- the posts table's RLS and enforce visibility in their own WHERE clause)
-- and were SELECT-able by the `anon` role — i.e. with just the public API
-- key and no login. posts_feed's WHERE only gates 'friends' posts
-- (can_view_post) and community-scoped anonymous posts, so a signed-out
-- caller could read every 'everyone' post (Moments) and every anonymous post
-- outside a community, with the author's total_score/level attached.
--
-- Audit 2026-09-27: every reader is a logged-in screen (home, anon feed,
-- composer, profile, feed, post detail, moment card); neither website
-- (palster-site, legal-site) talks to Supabase. Signed-in behaviour is
-- unchanged.
revoke select on public.posts_feed from anon;
revoke select on public.anon_reaction_counts from anon;
