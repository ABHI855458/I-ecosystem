// PING RECEIVED — fired by trg_notify_ping (AFTER INSERT ON pings).
// "🔔 [name] just pinged you — 3hrs to reply" → opens locket camera flow.
//
// Unlike profile views/reactions/comments, a ping's sender is never
// anonymized here — that's a deliberate reading of the spec (only events
// 3/4/5 are gated by pinned_people).
import { claimNotification, displayNameFor, jsonResponse, sendToUser } from "../_shared/notify.ts";
import type { WebhookPayload } from "../_shared/notify.ts";

interface PingRow {
  id: string;
  sender_id: string;
  receiver_id: string;
  group_id: string | null;
  prompt: string;
  status: string;
  expires_at: string | null;
  created_at: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  const payload = (await req.json()) as WebhookPayload<PingRow>;
  const ping = payload.record;

  const won = await claimNotification({
    recipientId: ping.receiver_id,
    eventType: "ping_received",
    tier: "major",
    dedupeKey: ping.id,
  });
  if (!won) return jsonResponse({ skipped: "already sent" });

  const senderName = await displayNameFor(ping.sender_id);

  let hoursToReply = 3;
  if (ping.expires_at) {
    const msRemaining = new Date(ping.expires_at).getTime() - Date.now();
    hoursToReply = Math.max(1, Math.round(msRemaining / (1000 * 60 * 60)));
  }

  await sendToUser({
    userId: ping.receiver_id,
    title: `🔔 ${senderName} just pinged you — ${hoursToReply}hrs to reply`,
    body: ping.prompt,
    tier: "major",
    data: {
      type: "ping_received",
      screen: "ping_camera",
      ping_id: ping.id,
      sender_id: ping.sender_id,
    },
  });

  return jsonResponse({ sent: true });
});
