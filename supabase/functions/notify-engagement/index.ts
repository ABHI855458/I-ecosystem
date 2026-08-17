// REACTION/COMMENT/REALMOJI FROM A PINNED PERSON — shared by three triggers
// (trg_notify_reaction on `reactions`, trg_notify_comment on `comments`,
// trg_notify_realmoji_reaction on `post_realmoji_reactions`; payload.table
// tells us which). Reveal the actor's name only if the post owner has them
// pinned; otherwise generic copy. STANDARD tier either way.
//
// post_realmoji_reactions gets one extra hard rule on top of the pin check:
// if the post itself is visibility='anonymous', identity is NEVER revealed
// here, pinned or not — the RealMoji feature's own "no faces, no identity,
// ever, on the anon feed" rule (see AnonRealmojiCounts' doc in the Flutter
// client) has to hold at the notification layer too, or a push title would
// be the one place that leaks it.
import { claimNotification, isPinnedBy, displayNameFor, jsonResponse, sendToUser, supabaseAdmin } from "../_shared/notify.ts";
import type { WebhookPayload } from "../_shared/notify.ts";

interface ReactionRow {
  id: string;
  post_id: string;
  user_id: string;
  type: "emoji" | "face";
  emoji: string;
  created_at: string;
}

interface CommentRow {
  id: string;
  post_id: string;
  user_id: string;
  content: string;
  created_at: string;
}

interface RealmojiReactionRow {
  id: string;
  post_id: string;
  user_id: string;
  emoji_type: "like" | "joy" | "surprise" | "love" | "laughter" | "instant";
  created_at: string;
}

const REALMOJI_GLYPH: Record<RealmojiReactionRow["emoji_type"], string> = {
  like: "👍",
  joy: "😂",
  surprise: "😮",
  love: "❤️",
  laughter: "🤣",
  instant: "⚡",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, 405);

  const payload = (await req.json()) as WebhookPayload<ReactionRow | CommentRow | RealmojiReactionRow>;
  const row = payload.record;
  const isRealmoji = payload.table === "post_realmoji_reactions";
  const isReaction = payload.table === "reactions" || isRealmoji;
  const eventType = isRealmoji ? "realmoji_reaction" : isReaction ? "reaction" : "comment";

  const { data: post, error } = await supabaseAdmin
    .from("posts")
    .select("user_id, visibility")
    .eq("id", row.post_id)
    .maybeSingle();
  if (error || !post) {
    console.error("notify-engagement: post not found", row.post_id, error);
    return jsonResponse({ error: "post not found" }, 200);
  }
  const recipientId = post.user_id as string;
  const actorId = row.user_id;

  if (actorId === recipientId) return jsonResponse({ skipped: "self-engagement" });

  const isAnonPost = post.visibility === "anonymous";
  const pinned = isAnonPost ? false : await isPinnedBy(recipientId, actorId);

  const won = await claimNotification({
    recipientId,
    eventType,
    tier: "standard",
    dedupeKey: row.id,
  });
  if (!won) return jsonResponse({ skipped: "already sent" });

  let title: string;
  if (isRealmoji) {
    const glyph = REALMOJI_GLYPH[(row as RealmojiReactionRow).emoji_type];
    title = pinned
      ? `${await displayNameFor(actorId)} reacted ${glyph} to your post`
      : `Someone reacted ${glyph} to your post`;
  } else if (isReaction) {
    title = pinned
      ? `${await displayNameFor(actorId)} reacted to your post 🔥`
      : "Someone reacted to your post";
  } else {
    title = pinned
      ? `${await displayNameFor(actorId)} commented on your post`
      : "Someone commented on your post";
  }

  await sendToUser({
    userId: recipientId,
    title,
    body: isReaction ? "" : (row as CommentRow).content ?? "",
    tier: "standard",
    data: {
      type: eventType,
      screen: "post_detail",
      post_id: row.post_id,
      pinned: String(pinned),
    },
  });

  return jsonResponse({ sent: true, pinned });
});
