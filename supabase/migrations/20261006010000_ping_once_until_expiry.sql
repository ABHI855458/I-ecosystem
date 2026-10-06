-- One ping per person per window (explicit request, 2026-10-06: "you only
-- ping a person once in the time interval until it expires").
--
-- send_ping / send_ping_multi refused a second ping only while the first
-- was still status = 'pending' — so the moment the receiver answered, the
-- sender could ping again inside the same window. The receiver is now the
-- one who keeps sending (several photos, until the ping expires — see the
-- composer's _fetchPhotoTargets), so the sender's block has to hold for
-- the whole window, replied or not. expires_at alone is the test.
--
-- Patched in place from the live definitions rather than restated: both
-- functions have drifted from their original migrations (see the live-DB
-- drift note) and a restated copy would silently revert that.
DO $$
DECLARE
  v_def text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'send_ping' AND p.pronamespace = 'public'::regnamespace;
  v_new := regexp_replace(v_def, E'\\s+and status = ''pending''(\\s+and group_id is null)', E'\\1');
  IF v_new = v_def THEN
    IF v_def NOT LIKE '%status = ''pending''%' THEN
      RAISE NOTICE 'send_ping already patched';
    ELSE
      RAISE EXCEPTION 'send_ping: ping-once clause not found in the expected shape';
    END IF;
  ELSE
    EXECUTE v_new;
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'send_ping_multi' AND p.pronamespace = 'public'::regnamespace;
  v_new := replace(v_def, 'AND status = ''pending'' AND group_id IS NULL', 'AND group_id IS NULL');
  IF v_new = v_def THEN
    IF v_def NOT LIKE '%status = ''pending''%' THEN
      RAISE NOTICE 'send_ping_multi already patched';
    ELSE
      RAISE EXCEPTION 'send_ping_multi: ping-once clause not found in the expected shape';
    END IF;
  ELSE
    EXECUTE v_new;
  END IF;
END $$;
