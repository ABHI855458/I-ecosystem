// PROMPT ROTATION — cron, every 3 hours (see pg_cron job 'prompt-rotation-job'
// in supabase/schema.sql, which POSTs here with an empty body — no webhook
// payload to parse, this runs top-to-bottom over every community).
//
// Per community (not global): pick the next prompt that hasn't run
// recently, update community_prompt_state, and notify members who have
// notifications_enabled for that community.
// "🌙 New prompt just dropped in [community] — '[prompt text]'"
import { claimNotification, jsonResponse, sendToUser, supabaseAdmin } from "../_shared/notify.ts";

// How many recently-used prompt ids to remember per community before a
// prompt is eligible to repeat. Capped to promptCount - 1 so rotation never
// gets stuck with zero eligible prompts on a small bank.
const RECENT_HISTORY_LEN = 10;

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  const { data: communities, error: communitiesError } = await supabaseAdmin
    .from("communities")
    .select("id, name")
    .is("deleted_at", null);
  if (communitiesError) {
    console.error("prompt-rotation: communities lookup failed", communitiesError);
    return jsonResponse({ error: "communities lookup failed" }, 500);
  }

  const { data: allPrompts, error: promptsError } = await supabaseAdmin
    .from("prompts")
    .select("id, text");
  if (promptsError || !allPrompts || allPrompts.length === 0) {
    console.error("prompt-rotation: prompts lookup failed", promptsError);
    return jsonResponse({ error: "no prompts available" }, 500);
  }

  const historyLen = Math.min(RECENT_HISTORY_LEN, allPrompts.length - 1);
  let rotated = 0;
  let notified = 0;

  for (const community of communities ?? []) {
    const { data: state } = await supabaseAdmin
      .from("community_prompt_state")
      .select("recent_prompt_ids")
      .eq("community_id", community.id)
      .maybeSingle();

    const recent: string[] = state?.recent_prompt_ids ?? [];
    let eligible = allPrompts.filter((p) => !recent.includes(p.id));
    if (eligible.length === 0) eligible = allPrompts; // bank exhausted — allow a repeat

    const chosen = eligible[Math.floor(Math.random() * eligible.length)];
    const newRecent = [chosen.id, ...recent].slice(0, historyLen);

    await supabaseAdmin.from("community_prompt_state").upsert({
      community_id: community.id,
      current_prompt_id: chosen.id,
      rotated_at: new Date().toISOString(),
      recent_prompt_ids: newRecent,
    });
    rotated++;

    const { data: members } = await supabaseAdmin
      .from("user_communities")
      .select("user_id")
      .eq("community_id", community.id)
      .eq("notifications_enabled", true);

    for (const member of members ?? []) {
      const won = await claimNotification({
        recipientId: member.user_id,
        eventType: "prompt_rotation",
        tier: "minor",
        dedupeKey: `${community.id}:${chosen.id}:${member.user_id}`,
      });
      if (!won) continue;

      await sendToUser({
        userId: member.user_id,
        title: `🌙 New prompt just dropped in ${community.name} — '${chosen.text}'`,
        body: "",
        tier: "minor",
        data: {
          type: "prompt_rotation",
          screen: "composer",
          community_id: community.id,
          prompt_id: chosen.id,
          prefill_prompt: chosen.text,
        },
      });
      notified++;
    }
  }

  return jsonResponse({ communitiesRotated: rotated, notificationsSent: notified });
});
