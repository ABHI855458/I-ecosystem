-- BUG FIX (reported: "my friends were getting the same notification
-- several times"). Root cause traced precisely:
--
-- registerDeviceToken() correctly upserts on (user_id, token), so the
-- SAME token value is never duplicated. But nothing ever removed a user's
-- OLDER token(s) once a NEW one was issued for what is really the same
-- physical device -- and FCM tokens rotate more often than assumed (app
-- updates, Play Services updates, cache clears). Tokens accumulated
-- indefinitely. One user in this table had SIX live Android token rows,
-- all from one device, all from a two-day span.
--
-- sendToUser() (_shared/notify.ts) fetches EVERY row for a user and sends
-- to all of them in parallel with no dedup and no cleanup on failure -- so
-- that user's device received every push up to 6 times.
--
-- One-time cleanup: keep only the most-recently-updated token per
-- (user_id, platform), delete the rest. The self-healing fixes in
-- _shared/fcm.ts / notify.ts and the client's registerDeviceToken (see
-- their own commits) stop this from re-accumulating.
DELETE FROM public.device_tokens dt
WHERE dt.id NOT IN (
  SELECT DISTINCT ON (user_id, platform) id
  FROM public.device_tokens
  ORDER BY user_id, platform, updated_at DESC
);
