-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  SECURITY: revoke anon EXECUTE on every SECURITY DEFINER function    ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- THE PROBLEM
-- Postgres grants EXECUTE on new functions to PUBLIC by default, and `anon`
-- inherits it. 67 SECURITY DEFINER functions were therefore callable with
-- the anon key — which ships inside the app binary and is public by design.
-- 29 of them WRITE.
--
-- Verified exploitable, unauthenticated, against the live project:
--   apply_score_decay        HTTP 200 — the scheduled decay job. An attacker
--                            can run it repeatedly to wipe every user's score.
--   claim_moderator_profile  HTTP 204
--   record_post_view         HTTP 204
--
-- THE FIX
-- Revoke EXECUTE from PUBLIC and anon on every SECURITY DEFINER function in
-- `public`, then re-grant to `authenticated` only for the ones the app calls
-- while signed in. Trigger functions need no grant at all — a trigger runs as
-- the table owner regardless of who holds EXECUTE.
--
-- Nothing in the app calls an RPC before sign-in (AuthGate gates the whole
-- tree), so no legitimate path loses access.

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosecdef
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
  END LOOP;
END $$;

-- Re-grant to signed-in users, only for what the client actually calls.
-- Anything absent here is either a trigger function or an internal helper,
-- and neither needs a direct grant.
DO $$
DECLARE
  fn text;
  wanted text[] := ARRAY[
    'anon_feed_engagement','anon_post_reaction_faces','community_leaderboard',
    'dashboard_community_feed','dashboard_feed','dashboard_group_posts',
    'dashboard_stats','friends_feed','get_group_wall','get_moment_replies',
    'get_moment_reply_counts','get_thread_handle','get_thread_handles',
    'group_post_audience_feed','group_public_profile','groups_with_counts_for_user',
    'is_post_author_pinned','list_pinned_people','mark_ping_seen',
    'mark_wall_reply_opened','my_contributed_moment_ids','my_group_walls',
    'my_manageable_communities','my_ping_streaks','my_post_viewers',
    'my_score_gain_since','pin_person','ping_back_anonymous','ping_inbox',
    'ping_post_author','ping_prompts_for_post','post_viewers','record_daily_open',
    'record_post_view','score_leaderboard','send_group_ping','send_ping',
    'toggle_pin_post_author','touch_post_presence','unpin_person',
    'broadcast_to_campus','provision_institutional_account'
  ];
BEGIN
  FOR fn IN SELECT unnest(wanted) LOOP
    EXECUTE (
      SELECT coalesce(string_agg(
               format('GRANT EXECUTE ON FUNCTION %s TO authenticated;', p.oid::regprocedure),
               ' '), 'SELECT 1')
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = fn
    );
  END LOOP;
END $$;

-- provision_institutional_account stays admin-only: it mints accounts.
REVOKE ALL ON FUNCTION public.provision_institutional_account(text,text,text)
  FROM PUBLIC, anon, authenticated;

-- Report what anon can still execute. Expect 0.
SELECT count(*)::int AS anon_executable_secdef
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.prosecdef
   AND has_function_privilege('anon', p.oid, 'EXECUTE');
