// purge-expired-media — removes group CHAT messages older than 48h AND
// their photos from storage.
//
// Group chat "goes off after 48 hrs" (20261003..._group_chat_photos_48h).
// The hourly SQL purge could delete the rows, but NOT the photo files:
// storage.objects has a protect_delete trigger, so files can only be
// removed through the Storage API. Without this the photos outlived their
// messages indefinitely (and the privacy policy says they are deleted).
//
// Order matters: files first, then rows. If a file removal fails, its row is
// kept so the next hourly run retries it — a row is never deleted while it
// still points at a live file.
//
// Auth: called by pg_cron/pg_net with the same shared secret notify-dispatch
// uses (verify_jwt is off; the secret is checked here).
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const BUCKET = "group-photos";
const BATCH = 200;

function pathFromUrl(url: string): string | null {
  const marker = `/storage/v1/object/public/${BUCKET}/`;
  const i = url.indexOf(marker);
  if (i < 0) return null;
  return decodeURIComponent(url.slice(i + marker.length).split("?")[0]);
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("DISPATCH_SECRET");
  if (!secret || req.headers.get("x-dispatch-secret") !== secret) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }

  const cutoff = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
  let removedFiles = 0;
  let removedRows = 0;

  // Bounded loop: at most 20 batches per run; the next run picks up the rest.
  for (let round = 0; round < 20; round++) {
    const { data, error } = await supabaseAdmin
      .from("group_messages")
      .select("id, photo_urls")
      .lt("created_at", cutoff)
      .limit(BATCH);
    if (error) {
      console.error("purge: select failed", error);
      break;
    }
    if (!data || data.length === 0) break;

    const paths: string[] = [];
    for (const row of data) {
      for (const u of (row.photo_urls ?? []) as string[]) {
        const p = typeof u === "string" ? pathFromUrl(u) : null;
        // Only ever chat files — never a group's album.
        if (p && p.includes("/chat/")) paths.push(p);
      }
    }

    if (paths.length > 0) {
      const { error: rmErr } = await supabaseAdmin.storage.from(BUCKET).remove(paths);
      if (rmErr) {
        // Keep the rows; retry next hour.
        console.error("purge: storage remove failed", rmErr);
        break;
      }
      removedFiles += paths.length;
    }

    const ids = data.map((r) => r.id);
    const { error: delErr } = await supabaseAdmin.from("group_messages").delete().in("id", ids);
    if (delErr) {
      console.error("purge: row delete failed", delErr);
      break;
    }
    removedRows += ids.length;
    if (data.length < BATCH) break;
  }

  return new Response(JSON.stringify({ ok: true, removedFiles, removedRows }), {
    headers: { "Content-Type": "application/json" },
  });
});
