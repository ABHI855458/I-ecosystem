// LIVE ACTIVITY NUDGE — cron, every 6 hours (pg_cron job
// 'live-activity-nudge-job' in supabase/schema.sql). Per community:
// "⚡ [live_count] people are live in [community] right now"
//
// live_count is a real COUNT(*) over active_sessions — never fabricated.
// Only sent when live_count >= LIVE_THRESHOLD, so it stays silent on a
// quiet community instead of feeling hollow. Tier is 'standard' (vs.
// prompt-rotation's 'minor') — this only fires when there's a genuinely
// notable number of people around, so it earns slightly more weight than
// the routine 3h prompt drop; the spec's "minor-to-standard" band covers
// both without pinning either exactly to 'minor'.
import { claimNotification, jsonResponse, sendToUser, supabaseAdmin } from "../_shared/notify.ts";

const LIVE_THRESHOLD = 20;
const LIVE_SESSION_WINDOW_MS = 5 * 60 * 1000; // matches ~30s heartbeat cadence w/ slack

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  const { data: communities, error: communitiesError } = await supabaseAdmin
    .from("communities")
    .select("id, name")
    .is("deleted_at", null);
  if (communitiesError) {
    console.error("live-activity-nudge: communities lookup failed", communitiesError);
    return jsonResponse({ error: "communities lookup failed" }, 500);
  }

  const freshSince = new Date(Date.now() - LIVE_SESSION_WINDOW_MS).toISOString();
  // 6h bucket index — same value for every run inside one scheduling
  // window, so re-runs (e.g. a retried cron tick) dedupe per recipient
  // instead of re-notifying every 6 hours forever.
  const bucket = Math.floor(Date.now() / (6 * 60 * 60 * 1000));

  let eligible = 0;
  let notified = 0;

  for (const community of communities ?? []) {
    const { count, error: countError } = await supabaseAdmin
      .from("active_sessions")
      .select("user_id", { count: "exact", head: true })
      .eq("community_id", community.id)
      .gte("last_seen_at", freshSince);

    if (countError) {
      console.error("live-activity-nudge: count failed", community.id, countError);
      continue;
    }
    const liveCount = count ?? 0;
    if (liveCount < LIVE_THRESHOLD) continue;
    eligible++;

    const { data: members } = await supabaseAdmin
      .from("user_communities")
      .select("user_id")
      .eq("community_id", community.id)
      .eq("notifications_enabled", true);

    for (const member of members ?? []) {
      const won = await claimNotification({
        recipientId: member.user_id,
        eventType: "live_nudge",
        tier: "standard",
        dedupeKey: `${community.id}:${bucket}:${member.user_id}`,
      });
      if (!won) continue;

      await sendToUser({
        userId: member.user_id,
        title: `⚡ ${liveCount} people are live in ${community.name} right now`,
        body: "",
        tier: "standard",
        data: {
          type: "live_nudge",
          screen: "community",
          community_id: community.id,
          live_count: String(liveCount),
        },
      });
      notified++;
    }
  }

  return jsonResponse({ communitiesEligible: eligible, notificationsSent: notified });
});
