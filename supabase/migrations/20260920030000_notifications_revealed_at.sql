-- Per-notification "the recipient has unblurred the actor's name" state.
--
-- Parallels read_at exactly, and for the same reason: it is the ONE kind of
-- column on this table the recipient themselves is allowed to write.
-- lock_notification_fields() pins recipient_id/type/actor_id/post_id/tier/
-- title/body/data/dedupe_key/created_at/push_sent_at back to their OLD
-- values on every client UPDATE — any column NOT in that list passes
-- through untouched, which is how read_at has always been client-writable
-- without a dedicated policy. revealed_at joins it, so the existing
-- notifications_update_own RLS policy (recipient_id = me) is the whole
-- access story; no new policy, no new RPC.
--
-- WHY PERSIST AT ALL, rather than holding reveal state in memory: the
-- canonical HoldToRevealBlur widget's own contract is "once true, this
-- widget never re-blurs" (lib/features/ping/ping_hold_reveal.dart). Its
-- only existing caller keeps that flag on a session-scoped model, but that
-- screen is fixture-backed — it has no persistence to speak of. The
-- notification inbox is real, durable, and synced, so honouring
-- "never re-blurs" there means surviving a scroll, a refetch, an app
-- restart and a second device. A column is the only thing that does that.
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS revealed_at timestamptz;

COMMENT ON COLUMN public.notifications.revealed_at IS
  'When the recipient hold-revealed the actor name on this notification. '
  'Client-writable (not pinned by lock_notification_fields), scoped by '
  'notifications_update_own. NULL = still blurred.';
