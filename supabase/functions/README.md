# Notification system — Edge Functions

Backend for the 7 notification events (ping received/replied, pinned-vs-
anonymous profile views, pinned-vs-anonymous reactions/comments, per-
community prompt rotation, per-community live-activity nudges). Schema
lives in `supabase/schema.sql` (search for "NOTIFICATION SYSTEM"); this
directory is the Edge Function side.

## Files

| Function | Trigger | Does |
|---|---|---|
| `_shared/notify.ts` | — | `isPinnedBy()`, `claimNotification()` (idempotency), `sendToUser()`, `displayNameFor()` |
| `_shared/fcm.ts` | — | FCM HTTP v1 sender (service-account JWT → access token → push) |
| `notify-ping` | `pings` INSERT | PING RECEIVED |
| `notify-ping-reply` | `ping_replies` INSERT | PING REPLIED |
| `notify-profile-view` | `profile_views` INSERT | PROFILE VIEW (pinned reveal / anonymous) |
| `notify-engagement` | `reactions` INSERT, `comments` INSERT | REACTION/COMMENT (pinned reveal / anonymous) |
| `prompt-rotation` | pg_cron, every 3h | PROMPT ROTATION, per community |
| `live-activity-nudge` | pg_cron, every 6h | LIVE ACTIVITY NUDGE, per community |

## Identity-reveal enforcement

Every function that might reveal a name calls `isPinnedBy(recipientId,
actorId)` in `_shared/notify.ts`, which is a thin wrapper over the
`is_pinned_by(p_recipient_id, p_actor_id)` SQL function in
`schema.sql`. That SQL function is the **only** place the `pinned_people`
table gets queried for this purpose — `EXECUTE` is revoked from
`anon`/`authenticated` and granted only to `service_role`, so a client can
never call it directly to probe "does user X have me pinned." The
non-pinned branch in `notify-profile-view` and `notify-engagement` never
looks up the actor's name at all — there's no code path where an
anonymous viewer's identity is fetched, so it can't leak by accident.

## Required manual setup (nothing here does this for you)

1. **Enable extensions** (Supabase Dashboard → Database → Extensions, or
   SQL editor): `pg_net`, `pg_cron` — also declared via `CREATE EXTENSION
   IF NOT EXISTS` in `schema.sql`, but some Supabase plans require enabling
   them from the dashboard first.

2. **Set the two GUCs `notify_webhook()` and the cron jobs read** (SQL
   editor, run once, as a role with `ALTER DATABASE` privileges):
   ```sql
   ALTER DATABASE postgres SET app.settings.edge_function_base_url =
     'https://uehqazxnodndutjvxemq.supabase.co/functions/v1';
   ALTER DATABASE postgres SET app.settings.service_role_key =
     '<service_role_key from Project Settings → API>';
   ```
   Reconnect afterward (existing connections don't pick up new GUCs).

3. **Firebase project for FCM** — create one, then from Project Settings →
   Service accounts → Generate new private key, download the JSON and set:
   ```sh
   supabase secrets set FCM_PROJECT_ID=<project_id>
   supabase secrets set FCM_CLIENT_EMAIL=<client_email>
   supabase secrets set FCM_PRIVATE_KEY="<private_key, \n's are fine literally>"
   ```
   `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are injected automatically
   into every Edge Function — nothing to set for those.

4. **Deploy**:
   ```sh
   supabase functions deploy notify-ping notify-ping-reply \
     notify-profile-view notify-engagement prompt-rotation live-activity-nudge
   ```

5. **Client**: nothing in `lib/` sends a device token to `device_tokens`
   yet — the app has no remote-push plugin (only
   `flutter_local_notifications`, which is on-device-only and can't
   produce a push token). `NotificationService.registerDeviceToken()` in
   `lib/core/notification_service.dart` is the integration point once a
   push plugin (e.g. `firebase_messaging`) is added; that's a separate,
   deliberately-deferred step (adding it now would need a Firebase project
   + `google-services.json` / `GoogleService-Info.plist` this environment
   can't generate, and would risk breaking the current build until those
   land).

6. **Presence heartbeat**: `active_sessions` (schema.sql) has no writer
   yet either — it's what `live-activity-nudge`'s `live_count` and
   `notify-profile-view`'s live-vs-delivered-after-the-fact check read
   from. Wire a periodic upsert (`user_id`, `community_id`,
   `last_seen_at = now()`) from wherever the app tracks "which community
   screen is currently open," roughly every 30s while foregrounded.

## Testing a function locally

```sh
supabase functions serve notify-ping --env-file supabase/functions/.env.local
curl -i --location --request POST 'http://localhost:54321/functions/v1/notify-ping' \
  --header 'Content-Type: application/json' \
  --data '{"type":"INSERT","table":"pings","schema":"public","record":{
    "id":"...", "sender_id":"...", "receiver_id":"...",
    "prompt":"Show me your view 👀", "status":"pending",
    "expires_at":null, "created_at":"2026-07-29T00:00:00Z"
  }}'
```
