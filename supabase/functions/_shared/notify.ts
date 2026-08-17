// Core tiered-notification helper shared by every notify-* function.
//
// Severity system: 'minor' | 'standard' | 'major' — matches the three-tier
// system the Flutter client already renders (see NotifPriority.{low,normal,
// high} and the glow/shimmer border in _NotifCard, lib/features/
// notifications/notifications_screen.dart). 'major' pushes carry
// style: 'glow_shimmer' in their data payload so the client can apply that
// same treatment to a remote push, not just in-app events.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { sendPush } from "./fcm.ts";

export type Tier = "minor" | "standard" | "major";

// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected into every
// Edge Function's environment by the Supabase platform — nothing to
// configure here. Service role bypasses RLS, which is required: these
// functions read pinned_people, active_sessions, device_tokens etc. across
// arbitrary users, not just "the caller's own" rows.
export const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/**
 * THE identity-reveal check. Delegates to the is_pinned_by() SQL function
 * (supabase/schema.sql) rather than querying pinned_people directly here,
 * so there is exactly one place — in the database, not scattered across
 * five Edge Functions — that answers "should this name be revealed."
 *
 * recipientId = who's receiving the notification (profile owner / post
 * owner). actorId = who did the thing (viewer / reactor / commenter).
 * Returns true only if recipientId has actorId in their pinned_people.
 */
export async function isPinnedBy(recipientId: string, actorId: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc("is_pinned_by", {
    p_recipient_id: recipientId,
    p_actor_id: actorId,
  });
  if (error) {
    console.error("is_pinned_by RPC failed:", error);
    // Fail closed: on error, treat as NOT pinned so identity never leaks
    // due to a transient DB error.
    return false;
  }
  return data === true;
}

/**
 * Idempotency guard. Inserts a claim row before sending; a unique-index
 * conflict on (event_type, dedupe_key) means this exact notification was
 * already sent (e.g. pg_net retried the trigger delivery, or the cron job
 * re-ran inside the same window) — caller should skip sending in that
 * case. Returns true iff this call won the claim.
 */
export async function claimNotification(params: {
  recipientId: string;
  eventType: string;
  tier: Tier;
  dedupeKey: string;
}): Promise<boolean> {
  const { error } = await supabaseAdmin.from("notification_events").insert({
    recipient_id: params.recipientId,
    event_type: params.eventType,
    tier: params.tier,
    dedupe_key: params.dedupeKey,
  });
  if (error) {
    if (error.code === "23505") return false; // unique violation — already sent
    console.error("claimNotification insert failed:", error);
    return false; // fail closed — don't send if we can't confirm idempotency
  }
  return true;
}

/**
 * Sends a push to every device_tokens row for a user. Best-effort per
 * token — one stale/invalid token doesn't stop delivery to the user's
 * other devices.
 */
export async function sendToUser(params: {
  userId: string;
  title: string;
  body: string;
  tier: Tier;
  data?: Record<string, string>;
}): Promise<void> {
  const { data: tokens, error } = await supabaseAdmin
    .from("device_tokens")
    .select("token")
    .eq("user_id", params.userId);

  if (error) {
    console.error("device_tokens lookup failed:", error);
    return;
  }
  if (!tokens || tokens.length === 0) return;

  const payloadData: Record<string, string> = {
    tier: params.tier,
    ...(params.tier === "major" ? { style: "glow_shimmer" } : {}),
    ...(params.data ?? {}),
  };

  await Promise.all(
    tokens.map((row: { token: string }) =>
      sendPush({ token: row.token, title: params.title, body: params.body, data: payloadData })
    ),
  );
}

/** First name / handle for notification copy — falls back to anon_name. */
export async function displayNameFor(userId: string): Promise<string> {
  const { data } = await supabaseAdmin
    .from("users")
    .select("name, anon_name")
    .eq("id", userId)
    .maybeSingle();
  if (!data) return "someone";
  const first = (data.name as string | null)?.trim().split(/\s+/)[0];
  return first || (data.anon_name as string) || "someone";
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Standard shape of the payload notify_webhook() sends from a Postgres
 * trigger (mirrors Supabase's native Database Webhooks format). */
export interface WebhookPayload<T> {
  type: "INSERT";
  table: string;
  schema: string;
  record: T;
}
