// PUSH DISPATCHER — the delivery half of notification_system_spec.md.
//
// Every notification in this app is a row in `notifications`, written by the
// notify_* SQL triggers. Those triggers own the COPY (§3) and the TIER (§2);
// the BEFORE INSERT hook set_notification_push_slot() owns the TIMING (§1,
// §7) by stamping push_after. This function owns delivery and nothing else:
// it takes rows whose push_after has arrived, sends them, and stamps
// push_sent_at.
//
// Keeping it this way is deliberate. The alternative — the per-source-table
// notify-ping / notify-engagement / notify-profile-view functions — would
// have meant every notification's copy existing twice, once in plpgsql for
// the in-app row and once in TypeScript for the push, drifting apart the
// first time either changed. Those functions stay deployed for the two
// cron-driven jobs (prompt-rotation, live-activity-nudge) that have no
// `notifications` row behind them.
//
// Auth: called by pg_cron/pg_net with a shared secret, not a user JWT, so
// verify_jwt is off and the secret is checked here instead.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPush } from "../_shared/fcm.ts";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

interface Row {
  id: string;
  recipient_id: string;
  type: string;
  tier: string;
  title: string;
  body: string | null;
  data: Record<string, unknown>;
}

// Give-up ceiling for a notification whose push keeps failing: enforced
// inside claim_due_notifications() itself now (push_attempts < 5), not here
// — claiming and filtering had to become one atomic statement together (see
// 20260925010000_notify_dispatch_claim.sql). A row that fails is left
// unsettled (push_sent_at stays NULL) so the next sweep retries it, but
// something permanently unsendable (a token FCM rejects every time, a
// malformed payload) must not be retried forever at 288 sweeps a day. Once
// it stops being claimed it is simply never delivered, which is the honest
// outcome; push_sent_at deliberately stays NULL rather than being stamped to
// make it "go away".

/** Most recipients have one device; a few have two. */
async function tokensFor(userIds: string[]): Promise<Map<string, string[]>> {
  const map = new Map<string, string[]>();
  if (userIds.length === 0) return map;
  const { data, error } = await supabaseAdmin
    .from("device_tokens")
    .select("user_id, token")
    .in("user_id", userIds);
  if (error) {
    console.error("device_tokens lookup failed:", error);
    return map;
  }
  for (const r of data ?? []) {
    const list = map.get(r.user_id) ?? [];
    list.push(r.token);
    map.set(r.user_id, list);
  }
  return map;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("DISPATCH_SECRET");
  if (!secret || req.headers.get("x-dispatch-secret") !== secret) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }

  // The DB is the authority on which window we're in — same function the
  // timing hook uses, so the dispatcher can never disagree with it.
  const { data: win } = await supabaseAdmin.rpc("notification_window");
  const window = (win as string) ?? "evening";

  // claim_due_notifications() selects AND stamps push_claimed_at in one
  // atomic statement (CTE + FOR UPDATE SKIP LOCKED). This used to be a plain
  // SELECT here with the actual "sent" stamp only applied after the FCM
  // send completed below — which meant two overlapping invocations (the
  // AFTER INSERT trigger firing while the 5-minute cron sweep was
  // mid-flight, or several inserts in quick succession) could both select
  // and push the same row before either marked it sent. Claiming up front
  // closes that race; see supabase/migrations/20260925010000_notify_dispatch_claim.sql.
  const { data: due, error } = await supabaseAdmin.rpc("claim_due_notifications", { p_limit: 500 });

  if (error) {
    console.error("due-notification claim failed:", error);
    return new Response(JSON.stringify({ error: "query failed" }), { status: 500 });
  }
  const rows = (due ?? []) as Row[];
  if (rows.length === 0) {
    return new Response(JSON.stringify({ window, sent: 0, digests: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const byUser = new Map<string, Row[]>();
  for (const r of rows) {
    const list = byUser.get(r.recipient_id) ?? [];
    list.push(r);
    byUser.set(r.recipient_id, list);
  }

  const tokens = await tokensFor([...byUser.keys()]);
  // settled = genuinely delivered (or nothing to deliver to).
  // failed   = attempted and rejected by FCM; left unsettled so the next
  //            sweep retries, with push_attempts as the ceiling.
  const settled: string[] = [];
  const failed: string[] = [];
  const deadTokensThisRun = new Set<string>();
  let sent = 0, digests = 0;

  for (const [userId, list] of byUser) {
    const userTokens = tokens.get(userId) ?? [];
    if (userTokens.length === 0) {
      // Nobody to deliver to. Settle them anyway so they don't accumulate
      // and then all fire the day this user finally installs the app.
      settled.push(...list.map((r) => r.id));
      continue;
    }

    // §1 wake window: "Digest of overnight MINOR/STANDARD, batched into one."
    const minor = list.filter((r) => r.tier !== "major");
    const major = list.filter((r) => r.tier === "major");
    const useDigest = window === "wake_digest" && minor.length > 1;

    // rowIds travels with each message so success/failure can be recorded
    // against the exact rows that message represents — 1:1 for a major, and
    // the whole collapsed set for a wake digest.
    const toSend: {
      title: string;
      body: string;
      data: Record<string, string>;
      rowIds: string[];
    }[] = [];

    for (const r of major) {
      toSend.push({
        title: r.title,
        body: r.body ?? "",
        data: {
          tier: r.tier, type: r.type, notification_id: r.id,
          style: "glow_shimmer",
          ...Object.fromEntries(Object.entries(r.data ?? {}).map(([k, v]) => [k, String(v)])),
        },
        rowIds: [r.id],
      });
    }

    if (useDigest) {
      toSend.push({
        title: `${minor.length} things happened while you were away`,
        body: minor.slice(0, 2).map((r) => r.title).join(" · "),
        data: { tier: "minor", type: "digest", count: String(minor.length), screen: "notifications" },
        // One message stands in for every minor row it collapsed, so all of
        // them settle or retry together — there is no per-row delivery
        // result to attribute once they share a payload.
        rowIds: minor.map((r) => r.id),
      });
      digests++;
    } else {
      for (const r of minor) {
        toSend.push({
          title: r.title,
          body: r.body ?? "",
          data: {
            tier: r.tier, type: r.type, notification_id: r.id,
            ...Object.fromEntries(Object.entries(r.data ?? {}).map(([k, v]) => [k, String(v)])),
          },
          rowIds: [r.id],
        });
      }
    }

    for (const msg of toSend) {
      // A user may have several devices. One reachable device is delivery —
      // a second, stale token on an old phone must not drag the row back
      // into the retry queue and re-push it to the live device forever.
      //
      // BUG FIX (reported: "my friends were getting the same notification
      // several times"). This loop sends to EVERY token on file with no
      // dedup — and nothing ever removed a user's OLDER token once a newer
      // one was issued for the same physical device (tokens rotate more
      // often than assumed: app updates, Play Services updates, cache
      // clears). One real user had 6 live rows from one device; their
      // phone got every push 6 times. sendPush's return type also changed
      // (bare boolean -> {ok, deadToken}) — `if (ok)` on the old boolean
      // silently stopped meaning anything once ok became an always-truthy
      // object, which would have broken the delivered/failed accounting
      // entirely if left as-is.
      let delivered = false;
      for (const token of userTokens) {
        const result = await sendPush({ token, title: msg.title, body: msg.body, data: msg.data });
        if (result.ok) {
          sent++;
          delivered = true;
        }
        if (result.deadToken) deadTokensThisRun.add(token);
      }
      if (delivered) {
        settled.push(...msg.rowIds);
      } else {
        failed.push(...msg.rowIds);
      }
    }
  }

  // Self-healing cleanup — see the loop's own doc above. Deletes every
  // token FCM confirmed is gone, across every user this sweep touched, in
  // one batch rather than one delete per token.
  if (deadTokensThisRun.size > 0) {
    const { error: cleanupErr } = await supabaseAdmin
      .from("device_tokens")
      .delete()
      .in("token", [...deadTokensThisRun]);
    if (cleanupErr) {
      console.error("device_tokens cleanup failed:", cleanupErr);
    } else {
      console.log(`Removed ${deadTokensThisRun.size} dead token(s) this sweep`);
    }
  }

  if (settled.length > 0) {
    // set_push_sent() is SECURITY DEFINER and flips the trusted-write flag —
    // lock_notification_fields() would otherwise revert push_sent_at, which
    // would make every row eligible again on the next tick and re-push it.
    const { error: stampErr } = await supabaseAdmin.rpc("set_push_sent", { p_ids: settled });
    if (stampErr) console.error("set_push_sent failed:", stampErr);
  }

  if (failed.length > 0) {
    // Counts the attempt WITHOUT stamping push_sent_at, so the row is
    // retried by the next sweep until it hits MAX_PUSH_ATTEMPTS. Before
    // this existed, these rows were stamped as delivered and dropped.
    const { error: failErr } = await supabaseAdmin.rpc("record_push_failure", { p_ids: failed });
    if (failErr) console.error("record_push_failure failed:", failErr);
    console.error(`push: ${failed.length} row(s) failed to send, left for retry`);
  }

  return new Response(JSON.stringify({ window, due: rows.length, sent, failed: failed.length, digests }), {
    headers: { "Content-Type": "application/json" },
  });
});
