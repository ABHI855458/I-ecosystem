-- Push-notification infrastructure + the spec's §5 fixes.
--
-- Context: supabase/schema.sql has declared device_tokens, active_sessions
-- and notification_events since the Edge Functions were written, but none
-- of the three were ever applied to the live project — every notify-*
-- function would have failed at its first claimNotification()/sendToUser()
-- call. This migration is what makes schema.sql true.
--
-- Deliberate deviation from schema.sql: TIMESTAMPTZ, not TIMESTAMP. The
-- whole notification_system_spec.md is written in IST wall-clock windows
-- (quiet hours 23:00–07:30, snack 11:00–11:30, lunch 12:30–14:00), so
-- every timestamp the dispatcher compares MUST carry a zone or the windows
-- silently evaluate against whatever the server session's TimeZone is.
-- schema.sql is updated to match in the same change.

-- ----------------------------------------
-- DEVICE TOKENS — push targets per user
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, token)
);

CREATE INDEX IF NOT EXISTS device_tokens_user_idx ON device_tokens(user_id);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "device_tokens_select_own" ON device_tokens;
CREATE POLICY "device_tokens_select_own" ON device_tokens FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
DROP POLICY IF EXISTS "device_tokens_insert_own" ON device_tokens;
CREATE POLICY "device_tokens_insert_own" ON device_tokens FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
DROP POLICY IF EXISTS "device_tokens_update_own" ON device_tokens;
CREATE POLICY "device_tokens_update_own" ON device_tokens FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
DROP POLICY IF EXISTS "device_tokens_delete_own" ON device_tokens;
CREATE POLICY "device_tokens_delete_own" ON device_tokens FOR DELETE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ----------------------------------------
-- ACTIVE SESSIONS — presence heartbeat
-- ----------------------------------------
CREATE TABLE IF NOT EXISTS active_sessions (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  community_id UUID REFERENCES communities(id) ON DELETE SET NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS active_sessions_community_idx
  ON active_sessions(community_id, last_seen_at);

ALTER TABLE active_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "active_sessions_select_own" ON active_sessions;
CREATE POLICY "active_sessions_select_own" ON active_sessions FOR SELECT USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
DROP POLICY IF EXISTS "active_sessions_upsert_own" ON active_sessions;
CREATE POLICY "active_sessions_upsert_own" ON active_sessions FOR INSERT WITH CHECK (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);
DROP POLICY IF EXISTS "active_sessions_update_own" ON active_sessions;
CREATE POLICY "active_sessions_update_own" ON active_sessions FOR UPDATE USING (
  auth.uid() IN (SELECT auth_id FROM users WHERE id = user_id)
);

-- ----------------------------------------
-- NOTIFICATION EVENTS — idempotency ledger for the Edge Functions
-- ----------------------------------------
-- event_type is widened past schema.sql's original 7 to cover every event
-- in notification_system_spec.md §2/§4 — claimNotification() inserts here
-- before sending, so an event_type with no CHECK slot can never be pushed.
CREATE TABLE IF NOT EXISTS notification_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipient_id UUID REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  tier TEXT NOT NULL CHECK (tier IN ('minor', 'standard', 'major')),
  dedupe_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS notification_events_dedupe_idx
  ON notification_events(event_type, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS notification_events_recipient_idx
  ON notification_events(recipient_id, created_at DESC);

ALTER TABLE notification_events ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: RLS on with zero grants is default-deny for
-- anon/authenticated. Only the service-role key (Edge Functions) reaches it.
