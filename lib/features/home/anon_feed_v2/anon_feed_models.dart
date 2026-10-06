import 'package:flutter/material.dart';

import '../../../shared/time_ago.dart';
import 'anon_feed_icons.dart';
import 'anon_feed_tokens.dart';

// ---------------------------------------------------------------------------
// Data models — originally a direct translation of §14.2's FEED/COMMENTS/
// OTHERS_REACTED/PING_PROMPTS/SAVED_MOJIS fixture consts. Comments are real
// now (see the note below, where kAnonComments used to live); everything
// else here (kAnonFeed's own seed rows, saved-mojis, ping prompts, viewer
// roster) is still fixture data — same posture as the rest of this app's
// ping/anon features before their own backend wiring passes.
// ---------------------------------------------------------------------------

class AnonPersona {
  const AnonPersona({required this.name, required this.color, required this.glyph});
  final String name;
  final Color color;
  final PersonaGlyphShape glyph;

  factory AnonPersona.of(String name) =>
      AnonPersona(name: name, color: AnonFeedColors.personaColorFor(name), glyph: personaGlyphFor(name));
}

class AnonSavedMoji {
  const AnonSavedMoji({required this.emoji, required this.bg});
  final String emoji;
  final Color bg;
}

const List<AnonSavedMoji> kAnonSavedMojis = [
  AnonSavedMoji(emoji: '🔥', bg: Color(0xFFC3B9A6)),
  AnonSavedMoji(emoji: '❤️', bg: Color(0xFFC9BFB2)),
  AnonSavedMoji(emoji: '👀', bg: Color(0xFFA8BFA4)),
  AnonSavedMoji(emoji: '😂', bg: Color(0xFFC6C0D2)),
  AnonSavedMoji(emoji: '💀', bg: Color(0xFFB4BEC6)),
  AnonSavedMoji(emoji: '🥺', bg: Color(0xFFCFC0B4)),
  AnonSavedMoji(emoji: '🙌', bg: Color(0xFFBCC7B6)),
];

class AnonPingPrompt {
  const AnonPingPrompt({required this.text});
  final String text;
}

const List<AnonPingPrompt> kAnonPingPrompts = [
  AnonPingPrompt(text: 'What were you actually feeling in this photo?'),
  AnonPingPrompt(text: "What's the part you left out?"),
  AnonPingPrompt(text: 'Who do you wish knew about this?'),
  AnonPingPrompt(text: 'What would you tell yourself a year ago?'),
];

// AnonReactor/kAnonOthersReacted and AnonComment/kAnonComments (the fixture
// "who reacted" rail and comment list this sheet used to render) are gone —
// replaced with real data. Comments now come from
// CommentService.fetchRecentAnon (see AnonThreadComment in
// comment_service.dart) rendered via AnonPersona.of(handle) for the DP,
// never a name/photo. The "who reacted" rail has no real non-leaking
// backend yet — `reactions` (unlike `comments` and
// `post_realmoji_reactions`) still has NO visibility-aware SELECT policy
// (confirmed live 2026-09-03: `reactions_select` is
// `EXISTS (SELECT 1 FROM posts WHERE id = post_id)`, no anonymity check at
// all), so a real per-reactor list would either leak real identity on an
// anonymous post or require fixing that policy first — out of scope here.
// The sheet keeps only the real aggregate count (already fetched via
// ReactionService.fetchSummary, see _hydrateCounts) and drops the
// per-person avatar rail entirely rather than fabricate or leak one.

class AnonFeedPost {
  const AnonFeedPost({
    required this.community,
    required this.timeAgo,
    required this.viewerCount,
    this.authorScore = 0,
    required this.extraReactions,
    required this.commentCount,
    required this.score,
    required this.tier,
    required this.caption,
    required this.prompt,
    this.id,
    this.imageUrl,
    this.personaPhotoUrl,
    this.secondaryPhotoUrl,
    this.videoUrl,
    this.videoMs,
    this.insetOnRight = true,
  });

  /// Real `posts.id` for a row loaded from the backend; null for the
  /// hardcoded [kAnonFeed] demo entries below. Needed so reactions/comments
  /// can be keyed to an actual post, and so the "already reacted" feed
  /// filter has something to match on.
  final String? id;

  /// Real `posts.image_url`; null for text-only posts and for the demo
  /// entries (which render the card's flat placeholder fill).
  final String? imageUrl;

  /// A VIDEO anon post (2026-10-06): the card plays this instead of the
  /// still, which stays as [imageUrl] (the poster).
  final String? videoUrl;
  final int? videoMs;


  /// The poster's chosen anon persona photo (`users.anon_photo_url`,
  /// surfaced by the `posts_feed` view next to a MASKED user_id — see
  /// migration 20260912000000). Identifies a persona, never a person. Null
  /// when they haven't set one, in which case the card falls back to the
  /// generated glyph avatar.
  final String? personaPhotoUrl;

  /// The dual photo's un-flattened inset layer (`posts.photo_url_secondary`,
  /// surfaced by `posts_feed` — see migration 20260917040000). Null for
  /// every ordinary post, in which case the card renders [imageUrl] flat,
  /// same as always. When set, the card renders the same interactive
  /// tap-to-swap DualPhotoView the friends feed uses — "how in friends feed
  /// click on the other dual camera photo interchanges its position, make
  /// the same in anon feed as well".
  final String? secondaryPhotoUrl;

  /// Which corner the inset started in (`posts.inset_on_right`). Meaningless
  /// when [secondaryPhotoUrl] is null.
  final bool insetOnRight;

  final String community;
  final String timeAgo;
  final int viewerCount;

  /// The POST AUTHOR's combined score (posts_feed.author_total_score) — not
  /// the viewer's.
  ///
  /// ALWAYS 0 ON ANONYMOUS POSTS, and that is a privacy requirement, not a
  /// gap to fill in. This doc used to claim the opposite — "identity-free:
  /// a score can't be mapped back to an account" — which was FALSE and is
  /// exactly how a de-anonymization leak shipped: `users_select` is
  /// USING (true) with SELECT grants on total_score/level, so an exact
  /// score is a JOIN key, not an anonymous statistic. On live data
  /// (total_score, level) uniquely identified 7 of 9 accounts and resolved
  /// every anonymous post to a real name and email.
  ///
  /// posts_feed now NULLs both columns for visibility='anonymous' (see
  /// 20260921030000_posts_feed_anon_score_fingerprint.sql), so this
  /// arrives 0 there. Do NOT "restore" it by reading the score from
  /// another table, and do NOT substitute a tier/bucket — tier is only
  /// non-identifying at scale; at small N the outlying buckets are still
  /// narrowable.
  ///
  /// Masking user_id does not help while a unique fingerprint ships beside
  /// it. That is the actual constraint.
  final int authorScore;

  /// NULLABLE on purpose: null means "not fetched yet", which is NOT the
  /// same as 0 ("nobody reacted"). `posts_feed` doesn't carry engagement
  /// counts, so a row built by [fromRow] starts unknown and is filled in
  /// later by the screen's own live fetch (see
  /// _AnonFeedScreenV2State._hydrateCounts). Rendering 0 in the meantime
  /// would actively lie — it reads as "no one reacted" on a post that may
  /// well have reactions. Call sites render a skeleton while null.
  final int? extraReactions;
  final int? commentCount;

  final int score;
  final String tier;
  final String caption;
  final String prompt;

  /// Used to patch live counts into an already-rendered post without
  /// refetching the row itself.
  ///
  /// EVERY field must be carried through. authorScore was missing, so the
  /// first _hydrateCounts pass silently reset it to its default of 0 — and
  /// since the header badge hides at 0, the poster's score and level tag
  /// disappeared the moment counts landed. Reported as the badge "not
  /// appearing after we start scrolling", because a swipe re-reads
  /// authorScore from the already-patched row.
  AnonFeedPost copyWith({int? extraReactions, int? commentCount}) =>
      AnonFeedPost(
        id: id,
        imageUrl: imageUrl,
        personaPhotoUrl: personaPhotoUrl,
        secondaryPhotoUrl: secondaryPhotoUrl,
        insetOnRight: insetOnRight,
        community: community,
        timeAgo: timeAgo,
        viewerCount: viewerCount,
        authorScore: authorScore,
        extraReactions: extraReactions ?? this.extraReactions,
        commentCount: commentCount ?? this.commentCount,
        score: score,
        tier: tier,
        caption: caption,
        prompt: prompt,
      );

  /// Builds a feed post from a `posts_feed` row (see
  /// FeedService.fetchAnonFeed). That view masks user_id on anonymous rows
  /// the caller doesn't own, so nothing identifying is available here by
  /// design — the anon card never shows a name or avatar anyway.
  ///
  /// Engagement counts are NOT in `posts_feed`; they're owned by other
  /// services (ReactionService / CommentService). Reaction and comment
  /// counts are therefore left NULL here — meaning "unknown, not yet
  /// fetched" — and hydrated later by the screen. They are deliberately
  /// NOT defaulted to 0, which would render as a confident "no one
  /// reacted" on a post that may have plenty. See [extraReactions]' doc.
  ///
  /// TODO(feed): add reaction_count / comment_count columns to the
  /// `posts_feed` view so a single feed query returns counts alongside the
  /// rows, and this hydration round-trip (plus its skeleton state) can go
  /// away entirely. Tracked in
  /// supabase/migrations/2026-08-25_feed_rules.sql's own TODO block.
  factory AnonFeedPost.fromRow(Map<String, dynamic> row) {
    final createdAt = row['created_at'] != null
        ? DateTime.tryParse(row['created_at'] as String)
        : null;
    return AnonFeedPost(
      id: row['id'] as String?,
      imageUrl: row['image_url'] as String?,
      personaPhotoUrl: row['anon_photo_url'] as String?,
      secondaryPhotoUrl: row['photo_url_secondary'] as String?,
      videoUrl: row['video_url'] as String?,
      videoMs: (row['video_duration_ms'] as num?)?.toInt(),
      insetOnRight: row['inset_on_right'] as bool? ?? true,
      // `communities` isn't joined into posts_feed, so the community label
      // falls back to empty rather than a fabricated one — the card's meta
      // row simply renders nothing there when it's blank.
      community: '',
      timeAgo: formatRelativeTime(createdAt, withAgo: true),
      // posts.view_count, surfaced through posts_feed and maintained by
      // record_post_view() (one row per distinct viewer, so this is
      // people-who-saw-it, not impressions). It was hardcoded 0 here, which
      // is why the "N here" presence chip never appeared on a single real
      // post — _LivePresenceChip hides itself at 0 per the no-bare-zero
      // rule, so with every post reporting 0 the control simply did not
      // exist in the app. Reported as "where is the live here button in
      // anon post".
      authorScore: (row['author_total_score'] as num?)?.toInt() ?? 0,
      viewerCount: (row['view_count'] as num?)?.toInt() ?? 0,
      extraReactions: null,
      commentCount: null,
      score: 0,
      tier: '',
      caption: (row['content'] as String?) ?? '',
      prompt: (row['prompt'] as String?) ?? '',
    );
  }
}

const List<AnonFeedPost> kAnonFeed = [
  AnonFeedPost(
    community: 'CSE',
    timeAgo: '2h ago',
    viewerCount: 7,
    extraReactions: 41,
    commentCount: 14,
    score: 230,
    tier: 'Rising Voice',
    caption:
        "Does anyone else feel like they're performing a version of themselves that isn't really them?",
    prompt: "What's something you've never told anyone here?",
  ),
  AnonFeedPost(
    community: 'Campus',
    timeAgo: '5h ago',
    viewerCount: 12,
    extraReactions: 63,
    commentCount: 28,
    score: 512,
    tier: 'Trusted',
    caption:
        "I've been eating lunch alone in the library stairwell for three weeks and telling everyone I'm busy.",
    prompt: "What's been weighing on you this week?",
  ),
  AnonFeedPost(
    community: '3rd Year',
    timeAgo: '9h ago',
    viewerCount: 4,
    extraReactions: 19,
    commentCount: 6,
    score: 87,
    tier: 'New here',
    caption: 'Called my mom crying at 2am and then pretended it was about the wifi.',
    prompt: 'When did you last feel genuinely seen?',
  ),
];

/// §6 live-chip stacked dots + §6.1 popover names — a fixed "here now"
/// roster the spec hardcodes identically across posts (viewerNames in
/// §14.3's renderVals), independent of each post's own viewerCount number.
const List<AnonPersona> kAnonViewerRoster = [
  AnonPersona(name: 'quietmoon', color: Color(0xFFB8A98F), glyph: PersonaGlyphShape.ring),
  AnonPersona(name: 'paper.crane', color: Color(0xFF9FAE9C), glyph: PersonaGlyphShape.triangle),
  AnonPersona(name: 'ringer_02', color: Color(0xFFA89BB5), glyph: PersonaGlyphShape.crescent),
  AnonPersona(name: 'no.name.7', color: Color(0xFFC9B79A), glyph: PersonaGlyphShape.diamond),
];

/// §7.5 on-photo reaction stack — 2 fixed chips, independent of persona
/// roster (own fill palette per spec).
class AnonReactionChip {
  const AnonReactionChip({required this.emoji, required this.bg});
  final String emoji;
  final Color bg;
}

const List<AnonReactionChip> kAnonReactionStack = [
  AnonReactionChip(emoji: '😊', bg: Color(0xFFF0E7D5)),
  AnonReactionChip(emoji: '🔥', bg: Color(0xFFF2DED4)),
];
