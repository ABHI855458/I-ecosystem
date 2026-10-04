-- ============================================================================
-- PING — missing UPDATE policies. Neither `pings` nor `ping_replies` had ANY
-- UPDATE policy at all (confirmed live) — PingService.markSeen/markViewed
-- (see supabase/migrations/20260905040000_ping_real_persistence.sql) would
-- silently no-op under RLS without these.
-- ============================================================================

-- A ping's RECEIVER may update their own received ping (used to stamp
-- seen_at the instant they reveal it). Same trust level as this app's other
-- "your own row" update policies (e.g. posts_update_own) — no column-level
-- restriction, matching that existing convention.
CREATE POLICY "pings_update_receiver" ON pings FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = receiver_id)
);

-- A reply is only ever marked "viewed" by the ORIGINAL PING'S SENDER —
-- viewing their own reply starts the 24h ping-back window.
CREATE POLICY "ping_replies_update_ping_sender" ON ping_replies FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM pings p
    WHERE p.id = ping_replies.ping_id
      AND auth.uid() IN (SELECT auth_id FROM users WHERE id = p.sender_id)
  )
);
