import 'package:flutter/material.dart';

import 'ping_visual_kit.dart' show pingTintFor;

// ---------------------------------------------------------------------------
// Unified Ping feed data model — replaces the split _PingEntry/_GroupUi/
// _AnonThreadUi (ping_screen.dart's old 3-tab models) with one shape all
// three origins render through. Still 100% local/demo state (no Supabase
// calls anywhere in the Ping feature, matching how it already worked before
// this rebuild) — see design-refs/no implemented/Ping Page.dc.html's
// README, "State Management" section, for the shape this mirrors.
// ---------------------------------------------------------------------------

/// Which kind of ping this is. The reference design only shows
/// person-to-person pings — [group]/[anonymous] are kept (not in the
/// spec) so existing Group/Anonymous ping functionality survives the
/// merge into one feed, per explicit product decision.
enum PingOrigin { person, group, anonymous }

enum PingBucket { toReply, replies, sent }

class PingFeedEntry {
  PingFeedEntry({
    required this.id,
    required this.origin,
    required this.bucket,
    required this.displayName,
    required this.avatarColor,
    required this.prompt,
    this.replyText,
    this.sentAt,
    this.revealedAt,
    this.viewedAt,
    this.windowHours = 3,
    List<String>? sentReplies,
    this.pingedBack = false,
    this.groupName,
    this.communityTag,
    this.seen = false,
    this.groupMembers,
    this.groupStreak = 0,
    List<PingComment>? comments,
  }) : sentReplies = sentReplies ?? [],
       comments = comments ?? [];

  final String id;
  final PingOrigin origin;
  PingBucket bucket;

  /// Person name / group name / anon handle, depending on [origin].
  final String displayName;
  final Color avatarColor;
  final String prompt;

  /// Single-reply text (Replies bucket, pre-rebuild shape) — the running
  /// multi-send list lives in [sentReplies] once a reply window is open.
  String? replyText;

  final DateTime? sentAt;

  /// Set the instant a To-Reply row's hold-to-reveal completes — drives
  /// both the 3h reply window (windowHours from here) and the "never
  /// re-blur again" rule (see HoldToRevealBlur).
  DateTime? revealedAt;

  /// Set the instant a Reply row's hold-to-reveal completes — drives the
  /// Reply "viewed" flat-card state and the 24h ping-back window.
  DateTime? viewedAt;

  /// Reply-window length in hours. 3 for person pings per spec; existing
  /// Group/Anonymous demo data used 6h before this rebuild — kept as-is
  /// for those two origins rather than re-deriving behavior nobody asked
  /// to change.
  final int windowHours;

  /// Running list of replies sent within an open To-Reply window (spec:
  /// "unlimited within the window — send more anytime").
  final List<String> sentReplies;

  bool pingedBack;

  /// Only set when [origin] != person.
  final String? groupName;
  final String? communityTag;

  /// Sent-bucket only: whether the recipient has opened this ping —
  /// distinct from [viewedAt], which is "I viewed THEIR reply" (drives
  /// ping-back) and only applies to Replies-bucket entries. Mirrors the
  /// old `_SentPing.seen` bool.
  bool seen;

  /// Only set for origin == group — the per-member data the GROUP WALL
  /// mosaic renders (see ping_group_wall.dart). Null for person/anonymous.
  final List<GroupMember>? groupMembers;

  /// Only set for origin == group — the group's own streak count (days the
  /// group has kept a wall going), shown as a 🔥 badge on the Group Wall
  /// header, mirroring the friend-strip streak badge.
  final int groupStreak;

  /// Group Wall reciprocity gate: every answered member's photo stays
  /// blurred/locked (see GroupMemberState-independent "locked" treatment in
  /// ping_group_wall.dart) until the current user has sent at least one
  /// photo reply of their own to this group ping. [sentReplies] already
  /// tracks that — it's the same list [PingExpandedCard] appends to.
  bool get wallUnlocked => sentReplies.isNotEmpty;

  /// Only set for a Replies-bucket entry that's been viewed — comment
  /// thread shown on the Reply Detail screen.
  final List<PingComment> comments;

  /// Anonymous pings are receive-only per spec — [displayName] still holds
  /// a real-looking demo handle internally, but every UI surface must
  /// render "Someone" instead (never resolve to a name), so this getter is
  /// what row/detail widgets should actually display.
  String get renderedName =>
      origin == PingOrigin.anonymous ? 'Someone' : displayName;

  bool get isRevealed => revealedAt != null;
  bool get isViewed => viewedAt != null;

  Duration? get replyWindowRemaining {
    final r = revealedAt;
    if (r == null) return null;
    final remaining = r
        .add(Duration(hours: windowHours))
        .difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Ping Back CTA is live within 5 days of the reply being viewed — was
  /// 24h; matches ping_back_anonymous()'s server-side window
  /// (20260907010000), which is the actual enforcement.
  bool get pingBackAvailable {
    final v = viewedAt;
    if (v == null || pingedBack) return false;
    return DateTime.now().difference(v) < const Duration(days: 5);
  }

  Duration? get pingBackRemaining {
    final v = viewedAt;
    if (v == null) return null;
    final remaining = v
        .add(const Duration(days: 5))
        .difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

// ---------------------------------------------------------------------------
// GroupMember — one tile in a group ping's GROUP WALL mosaic (replaces the
// Replies-row pattern for groups entirely, per the design doc's "Additional
// Features" section — a group ping is one shared moment with multiple
// unfolding parts, not N separate reply rows).
// ---------------------------------------------------------------------------

enum GroupMemberState { hasntAnswered, answeredUnopened, answeredOpened }

class GroupMember {
  GroupMember({
    required this.name,
    required this.avatarColor,
    required this.state,
    this.replyText,
  });

  final String name;
  final Color avatarColor;
  GroupMemberState state;
  final String? replyText;
}

/// An existing group the user belongs to — shown in the group chips row
/// (below the friend avatar strip) and as the member-picker source when
/// composing a new group ping. Distinct from a single To-Reply
/// [PingFeedEntry] with origin == group, which is one ALREADY-SENT ping
/// to a group, not the group itself.
class PingGroup {
  const PingGroup({
    required this.name,
    required this.memberColors,
    required this.memberCount,
  });

  final String name;

  /// Up to 3 colors for the overlapping-avatar chip stack.
  final List<Color> memberColors;
  final int memberCount;
}

// ---------------------------------------------------------------------------
// PingComment — Reply Detail screen's comment thread.
// ---------------------------------------------------------------------------

class PingComment {
  const PingComment({
    required this.author,
    required this.timestamp,
    required this.text,
  });
  final String author;
  final DateTime timestamp;
  final String text;
}

// ---------------------------------------------------------------------------
// OpenLoop — replaces the single page-level Ping Back banner. Symmetric:
// fires when EITHER you replied to an inbound ping, or they replied to
// yours. See README's "Open Loops" section for the exact bidirectional
// rule this models.
// ---------------------------------------------------------------------------

enum OpenLoopReason { theirReply, yourReply }

class OpenLoop {
  OpenLoop({
    required this.id,
    required this.name,
    required this.avatarColor,
    required this.isAnonymous,
    required this.reason,
    required this.expiresAt,
  });

  final String id;
  final String name;
  final Color avatarColor;
  final bool isAnonymous;
  final OpenLoopReason reason;
  final DateTime expiresAt;

  String get renderedName => isAnonymous ? 'Someone' : name;

  Duration get remaining {
    final d = expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  String get reasonLabel => reason == OpenLoopReason.yourReply
      ? 'you replied to theirs'
      : 'they replied to yours';
}

// ---------------------------------------------------------------------------
// Demo seed data — mirrors the rough shape of the old _pings/_groupUi/
// _AnonThreadUi const seeds, unified into one list so the merged feed has
// something in every bucket/origin to render out of the box.
// ---------------------------------------------------------------------------

List<PingFeedEntry> seedPingFeed() {
  final now = DateTime.now();
  return [
    // ── To Reply ──────────────────────────────────────────────────────
    PingFeedEntry(
      id: 'p1',
      origin: PingOrigin.person,
      bucket: PingBucket.toReply,
      displayName: 'alex_xyz',
      avatarColor: pingTintFor('alex_xyz'),
      prompt: 'Show me your view 👀',
      sentAt: now.subtract(const Duration(minutes: 40)),
    ),
    PingFeedEntry(
      id: 'p2',
      origin: PingOrigin.person,
      bucket: PingBucket.toReply,
      displayName: 'jordan_23',
      avatarColor: pingTintFor('jordan_23'),
      prompt: 'Quick selfie? 🤳',
      sentAt: now.subtract(const Duration(hours: 1, minutes: 10)),
    ),
    PingFeedEntry(
      id: 'g1',
      origin: PingOrigin.group,
      bucket: PingBucket.toReply,
      displayName: 'CS Study Group',
      avatarColor: pingTintFor('study_bug'),
      prompt: 'Where\'s everyone studying tonight?',
      sentAt: now.subtract(const Duration(minutes: 20)),
      windowHours: 6,
      groupName: 'CS Study Group',
      communityTag: 'CSE',
      groupStreak: 9,
      groupMembers: [
        GroupMember(
          name: 'priya',
          avatarColor: pingTintFor('priya'),
          state: GroupMemberState.answeredOpened,
          replyText: 'Library, 3rd floor 📚',
        ),
        GroupMember(
          name: 'rahul',
          avatarColor: pingTintFor('rahul'),
          state: GroupMemberState.answeredUnopened,
          replyText: 'Block C canteen',
        ),
        GroupMember(
          name: 'meera',
          avatarColor: pingTintFor('meera'),
          state: GroupMemberState.hasntAnswered,
        ),
        GroupMember(
          name: 'kabir',
          avatarColor: pingTintFor('kabir'),
          state: GroupMemberState.hasntAnswered,
        ),
      ],
    ),

    // ── Replies ───────────────────────────────────────────────────────
    PingFeedEntry(
      id: 'r1',
      origin: PingOrigin.person,
      bucket: PingBucket.replies,
      displayName: 'study_bug',
      avatarColor: pingTintFor('study_bug'),
      prompt: 'Pic of what you\'re doing? 📸',
      sentAt: now.subtract(const Duration(hours: 3)),
      viewedAt: now.subtract(const Duration(hours: 2, minutes: 40)),
      replyText: 'Cramming for the DBMS quiz, send help',
      comments: [
        PingComment(
          author: 'jordan_23',
          timestamp: now.subtract(const Duration(hours: 2, minutes: 10)),
          text: 'good luck 😭',
        ),
      ],
    ),
    PingFeedEntry(
      id: 'r2',
      origin: PingOrigin.anonymous,
      bucket: PingBucket.replies,
      displayName: 'anon_44f2',
      avatarColor: pingTintFor('library_mode'),
      prompt: 'Something you\'re not over yet',
      sentAt: now.subtract(const Duration(hours: 5)),
      windowHours: 6,
    ),

    // ── Sent ──────────────────────────────────────────────────────────
    PingFeedEntry(
      id: 's1',
      origin: PingOrigin.person,
      bucket: PingBucket.sent,
      displayName: 'sunset_chaser',
      avatarColor: pingTintFor('sunset_chaser'),
      prompt: 'Send me where you are 📍',
      sentAt: now.subtract(const Duration(minutes: 15)),
    ),
    PingFeedEntry(
      id: 's2',
      origin: PingOrigin.person,
      bucket: PingBucket.sent,
      displayName: 'coffee_talk',
      avatarColor: pingTintFor('coffee_talk'),
      prompt: 'Show me your view 👀',
      sentAt: now.subtract(const Duration(hours: 2)),
      seen: true,
    ),
  ];
}

List<OpenLoop> seedOpenLoops() {
  final now = DateTime.now();
  return [
    OpenLoop(
      id: 'ol1',
      name: 'study_bug',
      avatarColor: pingTintFor('study_bug'),
      isAnonymous: false,
      reason: OpenLoopReason.theirReply,
      expiresAt: now.add(const Duration(hours: 21, minutes: 20)),
    ),
    OpenLoop(
      id: 'ol2',
      name: 'coffee_talk',
      avatarColor: pingTintFor('coffee_talk'),
      isAnonymous: false,
      reason: OpenLoopReason.yourReply,
      expiresAt: now.add(const Duration(hours: 11)),
    ),
  ];
}

List<PingGroup> seedPingGroups() => [
  PingGroup(
    name: 'CS Study Group',
    memberColors: [
      pingTintFor('jordan_23'),
      pingTintFor('coffee_talk'),
      pingTintFor('library_mode'),
    ],
    memberCount: 4,
  ),
  PingGroup(
    name: 'Weekend Squad',
    memberColors: [pingTintFor('sunset_chaser'), pingTintFor('alex_xyz')],
    memberCount: 5,
  ),
];
