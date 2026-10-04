// DELETE ACCOUNT — user-invoked (via supabase.functions.invoke from the
// client, not a DB webhook like every other function in this directory), so
// unlike its siblings this one must verify the caller itself rather than
// trusting a Postgres trigger payload. The caller's JWT is the only
// trusted input — no id is ever accepted from the request body.
//
// Soft-delete + ban, not a hard delete of auth.users:
//   - users(id) is referenced by group_posts.user_id, groups.created_by,
//     buckets.created_by, and bucket_contributions.user_id with
//     ON DELETE NO ACTION (confirmed via pg_constraint) — deleting
//     auth.users cascades into `users` (auth_id FK is ON DELETE CASCADE)
//     and that delete would then throw on the first NO ACTION FK it hits
//     for anyone who has ever posted in a group. A real hard-delete needs
//     those four relationships resolved explicitly (reassign or cascade
//     group ownership) — out of scope here, flagged rather than guessed at,
//     same spirit as this app's other "not built, here's why" notes
//     (see settings_screen.dart's _UnsupportedSection).
//   - Instead: soft-delete everywhere the app already has deleted_at
//     (posts, comments, group_posts, community_posts, users itself — NOT
//     `groups`, which has no deleted_at column at all; see the note at that
//     step), hard-delete the pure-relationship rows
//     that have no soft-delete concept, then ban the auth user so they
//     cannot sign back in. auth.users itself is left alone, sidestepping
//     the FK problem entirely.
// Self-contained rather than importing ../_shared/notify.ts: this function
// is deployed as its own bundle (not alongside the rest of supabase/functions),
// so a relative import that reaches outside this directory doesn't resolve
// at deploy time. supabaseAdmin/jsonResponse are duplicated here rather than
// pulling in notify.ts's own FCM dependency for two functions this doesn't use.
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return jsonResponse({ error: "missing bearer token" }, 401);

  // Verify the token ourselves (don't trust anything from the body) — a
  // plain anon-key client whose auth.getUser resolves the JWT to a real
  // user, same idiom the client SDK uses.
  const callerClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: authData, error: authError } = await callerClient.auth.getUser(token);
  if (authError || !authData.user) {
    return jsonResponse({ error: "invalid session" }, 401);
  }
  const authId = authData.user.id;

  const { data: userRow, error: userError } = await supabaseAdmin
    .from("users")
    .select("id")
    .eq("auth_id", authId)
    .maybeSingle();
  if (userError) {
    console.error("delete-account: users lookup failed:", userError);
    return jsonResponse({ error: "lookup failed" }, 500);
  }
  if (!userRow) {
    // No app-level row yet (e.g. bypassed onboarding) — nothing to soft
    // delete, but still ban the auth user below so the intent is honored.
    console.warn("delete-account: no users row for auth_id", authId);
  }
  const userId = userRow?.id as string | undefined;
  const nowIso = new Date().toISOString();

  // ---- 1. Collect this user's storage files BEFORE anything is scrubbed.
  // Resolved from the rows that own them, not by guessing path patterns:
  // only `posts`/`personas`/`profiles`/`reaction-photos` are keyed by user
  // id, while `group-photos` is keyed by group and `us-album-photos` by
  // album — a path-prefix sweep there would delete other people's files.
  const fileUrls: string[] = [];
  const collect = (v: unknown) => {
    if (typeof v === "string" && v.includes("/storage/v1/object/public/")) fileUrls.push(v);
    else if (Array.isArray(v)) v.forEach(collect);
  };

  if (userId) {
    const grab = async (table: string, cols: string, filter: Record<string, string>) => {
      let q = supabaseAdmin.from(table).select(cols);
      for (const [k, v] of Object.entries(filter)) q = q.eq(k, v);
      const { data } = await q;
      (data ?? []).forEach((row) => Object.values(row as object).forEach(collect));
    };
    await grab("posts", "image_url, photo_url_secondary, photo_urls, video_url", { user_id: userId });
    await grab("group_posts", "photo_url, photo_url_secondary, photo_urls", { user_id: userId });
    await grab("pings", "photo_url", { sender_id: userId });
    // ping_threads.photo_url is the ASKER's own attached photo (see
    // PingService's own doc) — sender_id, not receiver_id.
    await grab("ping_threads", "photo_url", { sender_id: userId });
    await grab("ping_replies", "photo_url, selfie_url", { replier_id: userId });
    await grab("reactions", "photo_url", { user_id: userId });
    await grab("user_realmojis", "image_url", { user_id: userId });
    await grab("group_messages", "photo_urls", { sender_id: userId });
    await grab("us_album_photos", "photo_url", { uploaded_by: userId });
    await grab("dips", "photo_url", { user_id: userId });
    await grab("bucket_contributions", "photo_url", { user_id: userId });
    await grab("memories", "media_url", { user_id: userId });
    await grab("moment_replies", "photo_url", { user_id: userId });
    await grab("highlights", "photos", { user_id: userId });
    await grab("community_posts", "photo_urls", { user_id: userId });
    await grab("users", "profile_photo_url, banner_url, anon_photo_url", { id: userId });

    // community_post_documents has no owner column of its own — it hangs
    // off community_posts (which does). Fetch the user's own post ids
    // first, then every document attached to them.
    const { data: ownCommunityPosts } = await supabaseAdmin
      .from("community_posts").select("id").eq("user_id", userId);
    const ownPostIds = (ownCommunityPosts ?? []).map((r) => (r as { id: string }).id);
    if (ownPostIds.length > 0) {
      const { data: postDocs } = await supabaseAdmin
        .from("community_post_documents").select("file_url").in("community_post_id", ownPostIds);
      (postDocs ?? []).forEach((row) => Object.values(row as object).forEach(collect));
    }

    // community_feed_documents hangs off community_feed_items, which is
    // authored by a MODERATOR (author_moderator_id -> moderators.profile_id
    // -> profiles.id, 1:1 with users.id), not a plain poster. Only reachable
    // if the deleting account is also a moderator profile.
    const { data: ownModeratorRows } = await supabaseAdmin
      .from("moderators").select("id").eq("profile_id", userId);
    const ownModeratorIds = (ownModeratorRows ?? []).map((r) => (r as { id: string }).id);
    if (ownModeratorIds.length > 0) {
      const { data: ownFeedItems } = await supabaseAdmin
        .from("community_feed_items").select("id").in("author_moderator_id", ownModeratorIds);
      const ownFeedItemIds = (ownFeedItems ?? []).map((r) => (r as { id: string }).id);
      if (ownFeedItemIds.length > 0) {
        const { data: feedDocs } = await supabaseAdmin
          .from("community_feed_documents").select("file_url").in("feed_item_id", ownFeedItemIds);
        (feedDocs ?? []).forEach((row) => Object.values(row as object).forEach(collect));
      }
    }
  }

  // ---- 2. Soft-delete: everything with a deleted_at column already,
  // matching the convention GroupService.deleteGroup/deletePost use.
  if (userId) {
    await supabaseAdmin.from("users").update({ deleted_at: nowIso }).eq("id", userId);
    await supabaseAdmin.from("posts").update({ deleted_at: nowIso }).eq("user_id", userId).is("deleted_at", null);
    await supabaseAdmin.from("comments").update({ deleted_at: nowIso }).eq("user_id", userId).is("deleted_at", null);
    await supabaseAdmin.from("group_posts").update({ deleted_at: nowIso }).eq("user_id", userId).is("deleted_at", null);
    // NOT groups. `groups` has NO deleted_at column (verified live:
    // information_schema returns 0 rows for it, and an UPDATE setting it
    // fails with 42703 "column does not exist"). This line used to sit here
    // and did nothing at all — supabase-js returns {data, error} rather than
    // throwing, so the error was discarded and the sweep carried on, leaving
    // a reader with the false impression that groups are soft-deleted on
    // account deletion. They are not, and should not be: a group is shared
    // property, and tombstoning one because its creator left would take
    // every other member's posts down with it. GroupService.deleteGroup had
    // this exact same bug fixed already (see its own doc); this was the
    // copy that got missed.
    await supabaseAdmin.from("community_posts").update({ deleted_at: nowIso }).eq("user_id", userId).is("deleted_at", null);

    // ---- 3. Hard-delete: pure relationship rows with no soft-delete concept.
    // Circles replaced friendships (20260926000000_circles_replace_friendships.sql).
    // `users` is soft-deleted, so FK cascades never fire — remove both
    // directions explicitly: my circles (and their rosters, which cascade
    // from circles), and me from everyone else's. Service role => auth.uid()
    // is null, which protect_circle_kind() lets through for the Friends circle.
    await supabaseAdmin.from("circle_members").delete().eq("member_id", userId);
    await supabaseAdmin.from("circles").delete().eq("creator_id", userId);
    await supabaseAdmin.from("group_invites").delete().or(`invitee_id.eq.${userId},invited_by.eq.${userId}`);
    await supabaseAdmin.from("group_members").delete().eq("user_id", userId);
    await supabaseAdmin.from("reactions").delete().eq("user_id", userId);
    await supabaseAdmin.from("post_realmoji_reactions").delete().eq("user_id", userId);
    // Added 2026-10-03 with the features they belong to: RealMoji reactions
    // on pings, the saved RealMoji selfies themselves (files are collected
    // above), group chat messages, and the user's own notification inbox.
    await supabaseAdmin.from("ping_realmoji_reactions").delete().eq("user_id", userId);
    await supabaseAdmin.from("user_realmojis").delete().eq("user_id", userId);
    await supabaseAdmin.from("group_messages").delete().eq("sender_id", userId);
    await supabaseAdmin.from("notifications").delete().eq("recipient_id", userId);
    await supabaseAdmin.from("pinned_people").delete().or(`user_id.eq.${userId},pinned_user_id.eq.${userId}`);

    // ---- 4. Ping history. The deletion policy states it is deleted, so it
    // is deleted — both directions, plus replies this user wrote.
    await supabaseAdmin.from("ping_replies").delete().eq("replier_id", userId);
    await supabaseAdmin.from("pings").delete().or(`sender_id.eq.${userId},receiver_id.eq.${userId}`);

    // ---- 5. Push token. Left behind, a deleted account could still receive
    // notifications on that device.
    await supabaseAdmin.from("device_tokens").delete().eq("user_id", userId);

    // ---- 6. PII scrub. auth.users cannot be deleted (see file header), but
    // nothing forces the app row to keep identifying data. email/name/
    // anon_name are NOT NULL, so they get non-identifying tombstones; every
    // nullable identifying column is nulled outright. The row survives only
    // so group_posts.user_id / groups.created_by FKs stay valid.
    //
    // birth_date is column-level REVOKEd from `authenticated`, but this
    // function runs on the service role, which is unaffected — the scrub
    // works without loosening that lock.
    await supabaseAdmin.from("users").update({
      email: `deleted+${userId}@deleted.invalid`,
      name: "deleted user",
      anon_name: "deleted",
      username: null,
      anon_name_2: null,
      birth_date: null,
      bio: null,
      department: null,
      profile_photo_url: null,
      banner_url: null,
      anon_photo_url: null,
    }).eq("id", userId);
  }
  // blocks is keyed by auth uid, not users.id — clear both directions.
  await supabaseAdmin.from("blocks").delete().or(`blocker_id.eq.${authId},blocked_id.eq.${authId}`);

  // ---- 7. Storage. Grouped per bucket; failures are logged but never abort
  // the deletion — a stuck file must not leave the account half-deleted.
  const byBucket = new Map<string, string[]>();
  for (const url of fileUrls) {
    const tail = url.split("/storage/v1/object/public/")[1];
    if (!tail) continue;
    const slash = tail.indexOf("/");
    if (slash < 1) continue;
    const bucket = tail.slice(0, slash);
    const path = decodeURIComponent(tail.slice(slash + 1));
    if (!byBucket.has(bucket)) byBucket.set(bucket, []);
    byBucket.get(bucket)!.push(path);
  }
  for (const [bucket, paths] of byBucket) {
    const { error } = await supabaseAdmin.storage.from(bucket).remove(paths);
    if (error) console.error(`delete-account: storage ${bucket} failed:`, error);
  }

  // Ban, don't delete, the auth user — see file header for why. A ~100-year
  // ban reads as permanent without Supabase's admin API needing a literal
  // "forever" sentinel.
  const { error: banError } = await supabaseAdmin.auth.admin.updateUserById(authId, {
    ban_duration: "876000h",
  });
  if (banError) {
    console.error("delete-account: ban failed:", banError);
    return jsonResponse({ error: "account data removed but sign-out enforcement failed" }, 500);
  }

  return jsonResponse({ ok: true });
});
