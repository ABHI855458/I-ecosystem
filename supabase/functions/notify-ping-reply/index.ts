// PING REPLIED — fired by trg_notify_ping_reply (AFTER INSERT ON ping_replies).
// "🔥 [name] replied to your ping. Tap to reveal." → opens blur-reveal viewer.
import { claimNotification, displayNameFor, jsonResponse, sendToUser, supabaseAdmin } from "../_shared/notify.ts";
import type { WebhookPayload } from "../_shared/notify.ts";

interface PingReplyRow {
  id: string;
  ping_id: string;
  replier_id: string;
  photo_url: string;
  created_at: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  const payload = (await req.json()) as WebhookPayload<PingReplyRow>;
  const reply = payload.record;

  // The reply row only carries ping_id — resolve the original ping to find
  // who sent it (the notification recipient here, not the replier).
  const { data: ping, error } = await supabaseAdmin
    .from("pings")
    .select("sender_id")
    .eq("id", reply.ping_id)
    .maybeSingle();
  if (error || !ping) {
    console.error("notify-ping-reply: could not resolve ping", reply.ping_id, error);
    return jsonResponse({ error: "ping not found" }, 200); // 200 so pg_net doesn't retry forever
  }
  const recipientId = ping.sender_id as string;

  // Never push someone their OWN reply. This matters most for GROUP pings:
  // sendGroupPing deliberately includes the sender as a recipient (see
  // PingService's own doc on anonymous group pings), so when the sender
  // replies on their own thread, sender_id === replier_id and this used to
  // push them "🔥 <their own name> replied to your ping."
  //
  // The DB trigger notify_ping_reply() has always had this exact guard
  // (`v_sender = NEW.replier_id → RETURN NEW`), so no in-app notification
  // row was ever written for a self-reply — only this push escaped, which
  // is why it read as a notification with nothing behind it in the list.
  if (recipientId === reply.replier_id) {
    return jsonResponse({ skipped: "self reply" });
  }

  const won = await claimNotification({
    recipientId,
    eventType: "ping_replied",
    tier: "major",
    dedupeKey: reply.id,
  });
  if (!won) return jsonResponse({ skipped: "already sent" });

  const replierName = await displayNameFor(reply.replier_id);

  await sendToUser({
    userId: recipientId,
    title: `🔥 ${replierName} replied to your ping. Tap to reveal.`,
    body: "",
    tier: "major",
    data: {
      type: "ping_replied",
      screen: "ping_reveal",
      ping_id: reply.ping_id,
      ping_reply_id: reply.id,
    },
  });

  return jsonResponse({ sent: true });
});
