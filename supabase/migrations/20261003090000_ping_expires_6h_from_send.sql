-- ============================================================================
-- Every ping closes 6 hours after it was SENT (explicit request + choice,
-- 2026-10-03: "pings shall expire after 6 hrs and they can again ping
-- again" → "6h from sending").
--
-- Was:   CASE WHEN seen_at IS NOT NULL THEN seen_at + 6h
--             ELSE created_at + 24h END
-- Now:   created_at + 6h
--
-- `expires_at` is a STORED GENERATED column, so the expression is changed
-- in place with Postgres 17's ALTER COLUMN ... SET EXPRESSION — no drop and
-- re-add, so pings_open_pair_idx and every reader stay attached (the table
-- is rewritten and the index rebuilt as part of the statement).
--
-- Nothing else needs to change for "they can ping again": send_ping's
-- PING_ALREADY_OPEN guard, fetchSent, the Ping page's friend row and Open
-- Loops all key off `expires_at > now()`, so the moment a ping is six hours
-- old the sender is free to ping that person again and they reappear.
--
-- Note: applying this immediately closes every currently-open ping that is
-- already more than six hours old.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

ALTER TABLE public.pings
  ALTER COLUMN expires_at SET EXPRESSION AS (created_at + interval '6 hours');

COMMIT;
