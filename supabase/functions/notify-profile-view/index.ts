// PROFILE VIEW — fired by trg_notify_profile_view (AFTER INSERT ON profile_views).
//
// PINNED PERSON  (isPinnedBy(viewed_user_id, viewer_id) === true):
//   "👀 [name] is viewing you right now" (viewer's active_sessions row is
//   fresh) or "👀 [name] viewed you" (stale/no session — delivered after
//   the fact). MAJOR tier — glow/shimmer, per spec ("highest-value hook").
//
// NON-PINNED (anyone else, no exceptions):
//   "👀 Someone's viewing you right now" — name is never looked up, let
//   alone included in the payload. This is the hard privacy rule: the only
//   branch that can put a name in the notification is the isPinnedBy(...)
//   === true branch above.
import { claimNotification, isPinnedBy, displayNameFor, jsonResponse, sendToUser, supabaseAdmin } from "../_shared/notify.ts";
import type { WebhookPayload } from "../_shared/notify.ts";

interface ProfileViewRow {
  id: string;
  viewer_id: string;
  viewed_user_id: string;
  is_anonymous: boolean;
  created_at: string;
}

// A viewer counts as "live" if their presence heartbeat (active_sessions,
// see supabase/schema.sql) is fresher than this. Matches the freshness
// window used for LIVE ACTIVITY NUDGE's live_count.
const LIVE_WINDOW_MS = 90_000;

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  const payload = (await req.json()) as WebhookPayload<ProfileViewRow>;
  const view = payload.record;

  if (view.viewer_id === view.viewed_user_id) {
    return jsonResponse({ skipped: "self-view" });
  }

  const pinned = await isPinnedBy(view.viewed_user_id, view.viewer_id);

  const won = await claimNotification({
    recipientId: view.viewed_user_id,
    eventType: "profile_view",
    tier: pinned ? "major" : "minor",
    dedupeKey: view.id,
  });
  if (!won) return jsonResponse({ skipped: "already sent" });

  if (!pinned) {
    await sendToUser({
      userId: view.viewed_user_id,
      title: "👀 Someone's viewing you right now",
      body: "",
      tier: "minor",
      data: { type: "profile_view", screen: "profile", pinned: "false" },
    });
    return jsonResponse({ sent: true, pinned: false });
  }

  const { data: session } = await supabaseAdmin
    .from("active_sessions")
    .select("last_seen_at")
    .eq("user_id", view.viewer_id)
    .maybeSingle();

  const isLive = !!session &&
    Date.now() - new Date(session.last_seen_at as string).getTime() < LIVE_WINDOW_MS;

  const viewerName = await displayNameFor(view.viewer_id);

  await sendToUser({
    userId: view.viewed_user_id,
    title: isLive ? `👀 ${viewerName} is viewing you right now` : `👀 ${viewerName} viewed you`,
    body: "",
    tier: "major",
    data: {
      type: "profile_view",
      screen: "profile",
      pinned: "true",
      live: String(isLive),
      viewer_id: view.viewer_id,
    },
  });

  return jsonResponse({ sent: true, pinned: true, live: isLive });
});
