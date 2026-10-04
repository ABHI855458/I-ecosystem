-- ============================================================================
-- PING — real persistence for person-to-person pings. Until now the whole
-- Ping tab (PingPage) rendered seedPingFeed()/seedOpenLoops()/
-- seedPingGroups() — hardcoded fixture data, zero Supabase calls anywhere in
-- ping_screen.dart/ping_page.dart. `pings`/`ping_replies` were already live
-- (PingService.pingGroupMembers writes `pings`, confirmed) but nothing ever
-- read them back, and the shape didn't support everything the UI needs.
--
-- SCOPE: this migration + the PingService/PingPage wiring that follows it
-- cover PERSON-to-person pings only (PingOrigin.person) — the bulk of the
-- feature. Group pings (PingOrigin.group / GroupMember / group wall) and
-- anonymous pings (PingOrigin.anonymous) map onto `ping_groups` and
-- `anon_ping_threads/participants/messages` respectively, which are a
-- meaningfully different data/reveal model each and are NOT wired in this
-- pass — PingPage keeps rendering seed data for those two origins, clearly
-- short of "real", and that's flagged to the user rather than silently
-- left half-working.
-- ============================================================================

-- ping_replies.photo_url was NOT NULL — the UI sends text replies too.
ALTER TABLE ping_replies ALTER COLUMN photo_url DROP NOT NULL;
ALTER TABLE ping_replies ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'photo';
ALTER TABLE ping_replies ADD COLUMN IF NOT EXISTS body TEXT;
ALTER TABLE ping_replies
  ADD CONSTRAINT ping_replies_kind_check CHECK (kind IN ('photo', 'text'));
ALTER TABLE ping_replies
  ADD CONSTRAINT ping_replies_kind_payload_check CHECK (
    (kind = 'photo' AND photo_url IS NOT NULL) OR (kind = 'text' AND body IS NOT NULL)
  );

-- `set_ping_replied()` (already live) writes NEW.replied_at on a
-- status-change UPDATE — the column just never existed, so the function was
-- dead weight; nothing could ever attach its trigger without it erroring.
ALTER TABLE pings ADD COLUMN IF NOT EXISTS replied_at TIMESTAMP;

-- PingFeedEntry.windowHours (3 for a person ping) and the "your ping was
-- seen" state (currently a demo timer in ping_screen.dart) both need a
-- column — neither existed.
ALTER TABLE pings ADD COLUMN IF NOT EXISTS window_hours INT NOT NULL DEFAULT 3;
ALTER TABLE pings ADD COLUMN IF NOT EXISTS seen_at TIMESTAMP;

-- Bridges "a reply landed" to the existing status-transition function —
-- nothing previously flipped `pings.status` to 'replied' on a reply, so
-- set_ping_replied()'s own UPDATE trigger had nothing to ever fire on.
CREATE OR REPLACE FUNCTION mark_ping_replied()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
BEGIN
  UPDATE pings SET status = 'replied' WHERE id = NEW.ping_id AND status IS DISTINCT FROM 'replied';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mark_ping_replied ON ping_replies;
CREATE TRIGGER trg_mark_ping_replied
  AFTER INSERT ON ping_replies FOR EACH ROW
  EXECUTE FUNCTION mark_ping_replied();

DROP TRIGGER IF EXISTS trg_set_ping_replied ON pings;
CREATE TRIGGER trg_set_ping_replied
  BEFORE UPDATE ON pings FOR EACH ROW
  EXECUTE FUNCTION set_ping_replied();

-- enforce_ping_limit() (5 pings/24h, already live) was written but never
-- attached to anything — the cap did not actually apply.
DROP TRIGGER IF EXISTS trg_enforce_ping_limit ON pings;
CREATE TRIGGER trg_enforce_ping_limit
  BEFORE INSERT ON pings FOR EACH ROW
  EXECUTE FUNCTION enforce_ping_limit();

-- Storage for photo replies, mirroring reaction-photos' own shape.
INSERT INTO storage.buckets (id, name, public)
VALUES ('ping-photos', 'ping-photos', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "ping_photos_public_read" ON storage.objects;
CREATE POLICY "ping_photos_public_read" ON storage.objects FOR SELECT USING (
  bucket_id = 'ping-photos'
);

DROP POLICY IF EXISTS "ping_photos_authenticated_upload" ON storage.objects;
CREATE POLICY "ping_photos_authenticated_upload" ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'ping-photos' AND auth.role() = 'authenticated'
);
