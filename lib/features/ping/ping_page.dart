// ============================================================================
// Ping Page — direct port of the design's reference implementation.
//
// Source: Claude Design project 20e30d75-43c2-4e12-ace7-c35792724115,
//         design_handoff_ping_page/flutter/lib/ping_page.dart
//
// This is a DITTO port. The reference file is the design expressed as code
// (written by the designer, paired with SPEC.md / COLORS_AND_SHAPES.md /
// Ping Page.dc.html). Earlier versions of this page were re-derived from the
// prose specs and drifted; porting the reference directly removes
// re-derivation as a source of drift. Keep it that way: when something looks
// wrong, diff against the reference rather than adjusting values by eye.
//
// Deliberate deviations from the reference (only these four):
//
//  1. Ping dropdown — the reference's inline `_compose()` sheet is replaced by
//     this app's existing PingPromptSheet (the colourful prompt-chip grid),
//     opened at heightFraction .62 / glass / rounded-top-only. Product decision.
//  2. Camera — the reference draws "[ back camera preview ]" placeholders. Its
//     own README says to wire the real camera in production, so the photo zone
//     opens PingCameraScreen instead.
//  3. Dashed borders — the reference approximates CSS `dashed` as solid (a
//     documented approximation). _DashedBorder below draws real dashes, which
//     is closer to the design than the reference itself.
//  4. Manrope is bundled here (pubspec `fonts:`), so type matches exactly.
//  5. Real backend for person, group, and anonymous pings (send/receive/
//     reply/seen/viewed, plus the Group Wall's per-thread reciprocity gate)
//     — kToReply/kSent/kReplies/kFriends/kGroups/kGroupWall were 100%
//     hardcoded fixture data with zero Supabase calls; they're now mutable,
//     loaded from PingService/CircleService/GroupService in
//     _PingPageState._loadRealPingData(), with the original hardcoded lists
//     kept only as the pre-load/empty-fetch seed (same posture as this
//     app's other real-data screens, e.g. AnonFeedScreenV2's kAnonFeed).
//     See supabase/migrations/20260906000000_ping_threads_group_wall_and_anonymity.sql
//     and PingService's own doc for the schema/RLS this assumes.
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, PostgresChangeEvent, RealtimeChannel;

import '../../core/glass.dart' show showGlassToast, showPingToast;
import '../../core/ping_haptics.dart';
import 'ping_turns.dart';
import '../../widgets/app_video.dart';
import '../../core/supabase_config.dart';
import '../../core/ui/immersive_chrome.dart';
import '../../services/current_user_service.dart';
import '../notifications/notifications_screen.dart' show notifState;
import '../../services/circle_service.dart';
import '../../services/community_service.dart';
import '../../services/group_service.dart';
import '../../services/block_service.dart';
import '../../services/ping_service.dart';
import '../../services/post_author_pin_service.dart';
import '../../services/score_gain_service.dart';
import '../../services/storage_service.dart';
import 'ping_prompt_sheet.dart';
import 'ping_realmoji.dart';
import '../../services/ping_realmoji_service.dart';
import 'ping_reveal_screen.dart' show PingCameraScreen, PingCapture;
import '../../shared/score_tier.dart';
import 'score_reward_dropdown.dart';
import 'text_ping_card.dart';
import '../profile_v2/profile_v2_icons.dart';

// ============================================================================
// tokens — palette, scaling, type
// ============================================================================

const double kDesignW = 402.0;

const kGround = Color(0xFF0B0B0D);
const kSurface1 = Color(0xFF131317);
const kSurface2 = Color(0xFF17171B);
const kText = Color(0xFFF5F4F1);
const kCyan = Color(0xFF29D3E8);
const kCyanLite = Color(0xFF7FE8F2);
const kCyanDeep = Color(0xFF1BAFC4);
const kCyanPale = Color(0xFFDFF9FB);
const kCyanTextHi = Color(0xE6CDF6FA); // rgba(205,246,250,.9)
const kClay = Color(0xFFA9A49A);
const kDarkOnCyan = Color(0xBF0B0B0D); // rgba(11,11,13,.75)

Color txt(double o) => kText.withValues(alpha: o);
Color clay(double o) => kClay.withValues(alpha: o);
Color w(double o) => Colors.white.withValues(alpha: o);
Color blk(double o) => Colors.black.withValues(alpha: o);

/// Earth-gradient avatar pairs (index by stable id hash).
const List<List<Color>> kEarth = [
  [Color(0xFFC97B5A), Color(0xFFA85D3E)], // 0 terracotta
  [Color(0xFFB08968), Color(0xFF8B6A4F)], // 1 tan
  [Color(0xFF7A8B6F), Color(0xFF5F7355)], // 2 sage
  [Color(0xFFD2A05C), Color(0xFFB8843F)], // 3 ochre
  [Color(0xFF8A7A6D), Color(0xFF6B5D52)], // 4 taupe
  [Color(0xFF6E8B8A), Color(0xFF516B6A)], // 5 slate-teal
];

/// CSS linear-gradient(deg) -> Flutter begin/end.
LinearGradient cssGradient(double deg, List<Color> colors) {
  final rad = (deg - 90) * math.pi / 180; // CSS 0deg=up; Flutter 0rad=right
  final dx = math.cos(rad), dy = math.sin(rad);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: colors,
  );
}

LinearGradient g150(Color a, Color b) => cssGradient(150, [a, b]);
LinearGradient g160(Color a, Color b) => cssGradient(160, [a, b]);
LinearGradient g180(Color a, Color b) => cssGradient(180, [a, b]);
LinearGradient g90(Color a, Color b) => cssGradient(90, [a, b]);

/// Scale helper — built once per page from device width. Every length and
/// font size on this page goes through it, which is what keeps the layout
/// matching the 402pt design canvas at any width.
class Scale {
  final double k;
  Scale(double screenW) : k = (screenW.clamp(320.0, 440.0)) / kDesignW;
  double call(double px) => px * k;
  double ls(double em, double fontPx) => em * fontPx * k; // letter-spacing
}

/// Text style factory. lh = line-height multiplier (CSS unitless).
TextStyle ts(
  Scale s, {
  required int weight,
  required double size,
  double lh = 1.2,
  double em = 0.0,
  required Color color,
}) => TextStyle(
  fontFamily: 'Manrope',
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontSize: s(size),
  height: lh,
  letterSpacing: em == 0 ? null : s.ls(em, size),
  color: color,
);

/// Irregular four-corner radius (the app's shape fingerprint).
BorderRadius r4(Scale s, double tl, double tr, double br, double bl) =>
    BorderRadius.only(
      topLeft: Radius.circular(s(tl)),
      topRight: Radius.circular(s(tr)),
      bottomRight: Radius.circular(s(br)),
      bottomLeft: Radius.circular(s(bl)),
    );

// ============================================================================
// models + sample data (mirrors the reference exactly)
// ============================================================================

/// What a promptless ping (prompt '') shows where a prompt would be — my
/// SENT rows and "re: …" lines on replies. The receiver's card reads
/// "<name> pinged you 👋" instead (see the kToReply mapping).
const kPromptlessOutbound = 'Pinged 👋';

/// A friendly, time-of-day greeting shown where a promptless ping has no
/// words (explicit request: "hola, hello, what's up… based on time"). Picked
/// by the ping's id so the same ping always reads the same; the stored
/// prompt stays '' so promptless handling (one-tap ping back,
/// notify_ping_reply wording) is untouched.
String pingGreeting(String pingId, [DateTime? at]) {
  final h = (at ?? DateTime.now()).toLocal().hour;
  final List<String> pool;
  if (h >= 5 && h < 12) {
    pool = const [
      'Good morning ☀️',
      'Morning! Slept well? 😴',
      'Rise and shine 🌅',
      'Hola, early bird 🐦',
      'Coffee yet? ☕',
    ];
  } else if (h >= 12 && h < 17) {
    pool = const [
      'Hey, what\'s up?',
      'Hello hello 😄',
      'Lunch done? 🍛',
      'Afternoon check-in ✌️',
      'Hola! How\'s the day going? 🌤️',
    ];
  } else if (h >= 17 && h < 22) {
    pool = const [
      'Good evening 🌆',
      'Hey! How was your day? 😊',
      'What\'s up tonight? 🎧',
      'Evening vibes ✨',
      'Hola, free to talk?',
    ];
  } else {
    pool = const [
      'Still up? 🌙',
      'Late night hello 🦉',
      'Can\'t sleep either? 😅',
      'Hey night owl ✨',
      'Psst… you awake? 👀',
    ];
  }
  return pool[pingId.hashCode.abs() % pool.length];
}

// No hand emoji here either — same rule as _cardLine (explicit request,
// 2026-10-02: no 👋 in replies unless a photo came with it).
const kPromptlessReplyTo = 'your ping';

class InboundPing {
  final String id, senderName, initial, prompt, time;
  final int tintIndex;
  final bool isGroup, isAnon;
  final int? groupCount;

  /// Set for every real fetched ping (group or person) — the logical
  /// `ping_threads` row this belongs to. Null only for the pre-load fixture
  /// rows below, which never need one.
  final String? threadId;

  /// The real sender to target for "ping them back" — null when [isAnon]
  /// (there's genuinely nothing to resolve; ping-back for those routes
  /// through pingBackAnonymous(pingId: id) instead) or for a fixture row.
  final String? senderId;

  InboundPing(
    this.id,
    this.senderName,
    this.initial,
    this.prompt,
    this.time,
    this.tintIndex, {
    this.isGroup = false,
    this.isAnon = false,
    this.groupCount,
    this.threadId,
    this.senderId,
    this.photoUrl,
    this.photoOpenedAt,
    this.myReplies = const [],
    this.promptless = false,
    this.sentAt,
  });

  /// When the ping was sent — backs the revealed card's relative time
  /// ("4m ago"), replacing the old "window open · …" line. Null only for
  /// pre-load fixture rows.
  final DateTime? sentAt;

  /// Sent with no prompt (prompt '' — every ping except Dip's is promptless
  /// since 2026-09-30). The card shows "<name> pinged you 👋" with a
  /// one-tap blue "Ping back" alongside photo/text.
  final bool promptless;

  /// My replies to this ping from the server (ping_inbox.my_replies), each
  /// with its like count — the durable version of the receipt rows.
  final List<MyPingReply> myReplies;

  /// A photo the asker attached to the ping (`pings.photo_url`) — shown on
  /// the card above the prompt. Null for a text-only ask.
  final String? photoUrl;

  /// `pings.photo_opened_at` via ping_inbox() — null means [photoUrl] is
  /// still a live, one-time-viewable tease; non-null means I already spent
  /// that view and the card shows a locked placeholder instead. See
  /// PingPage._openPingPhoto/_pingPhotoView.
  final DateTime? photoOpenedAt;
}

class OutboundPing {
  final String id, who, initial, prompt;
  final bool seen;

  /// `pings.thread_id` — shared by every ping of one multi-person send,
  /// which [_multiThreadIds] turns into a single card. Null for the
  /// optimistic `sentExtra` rows.
  final String? threadId;
  final String? avatarUrl;
  final bool replied;
  OutboundPing(
    this.id,
    this.who,
    this.initial,
    this.prompt,
    this.seen, {
    this.threadId,
    this.avatarUrl,
    this.replied = false,
  });
}

class InboundReply {
  final String id, who, prompt, body, when;
  final bool viewedInit;
  final String? pingBackLeft;

  /// `ping_replies.ping_id` — the original SENT ping this is a reply to.
  /// Lets the SENT row (a different list — [OutboundPing]) find its own
  /// reply's reaction state to show a heart badge, without SENT needing to
  /// carry reaction data of its own. Empty for the pre-load fixture rows.
  final String pingId;

  /// The replier's real `users.id` — always resolvable, even when the
  /// PING THEY'RE REPLYING TO was sent anonymously. Replying always
  /// identifies the replier to the ping's sender; only a ping's SENDER can
  /// ever be hidden from its RECEIVER in this app's anonymity model, never
  /// the other way around. "Ping them back" from here is therefore always
  /// a normal, real-identity send.
  final String replierId;

  /// True when the ORIGINAL ping (not this reply) was sent anonymously —
  /// label-only, per the doc above; it does not affect who "ping them
  /// back" targets.
  final bool isAnon;
  final String? groupName;

  /// Null for the pre-load fixture rows (which have nothing real to show)
  /// and for a text-only reply — [_photoView] falls back to the existing
  /// gradient+hatch placeholder in both cases.
  final String? photoUrl;

  /// A hold-to-record video answer (2026-10-06): when set, the viewer plays
  /// the clip where the photo would be.
  final String? videoUrl;
  final int? videoMs;

  /// The front-camera half of a dual capture (see PingCameraScreen,
  /// ping_reveal_screen.dart) — null for an album-picked photo or a
  /// text-only reply. Every selfie-inset render site treats null as "don't
  /// show the inset", not as "show it empty".
  final String? selfieUrl;

  /// Total hearts on this reply, and whether one of them is mine, as of the
  /// last load — the STARTING point for the `reactions` state map
  /// (ping_page.dart's own State field), which is what the heart button
  /// actually reads/writes. Kept here (not just in that map) so a fresh
  /// `_loadRealPingData()` doesn't forget a reaction that happened in an
  /// earlier session. Unified with the group-wall heart — see
  /// PingService.toggleReaction's own doc.
  final int reactionCount;
  final bool myReaction;

  InboundReply(
    this.id,
    this.who,
    this.prompt,
    this.body,
    this.when,
    this.viewedInit,
    this.pingBackLeft, {
    this.replierId = '',
    this.isAnon = false,
    this.groupName,
    this.photoUrl,
    this.videoUrl,
    this.videoMs,
    this.selfieUrl,
    this.reactionCount = 0,
    this.myReaction = false,
    this.pingId = '',
    this.threadId,
  });

  /// The replied-to ping's thread — a reply whose thread is a multi-person
  /// send lives in that card's slot, not in the REPLIES list.
  final String? threadId;
}

class Friend {
  final String id, who, initial;
  final int tintIndex, streak;

  /// The friend's real DP (`users.profile_photo_url`). The strip rendered a
  /// generated initial+tint circle for everyone because this field simply
  /// didn't exist — the value was already being fetched by
  /// CircleService.fetchFriendsCircleUsers (selects profile_photo_url) and then dropped
  /// on the floor at the Friend() construction site. [initial]/[tintIndex]
  /// stay as the fallback for a friend who genuinely has no photo set.
  final String? avatarUrl;

  Friend(
    this.id,
    this.who,
    this.initial,
    this.tintIndex,
    this.streak, {
    this.avatarUrl,
  });
}

/// A ping send that resolved without error but genuinely sent nothing (a
/// group with nobody else in it, a still-loading chip with no target) —
/// [openPromptSheet]'s own showError already put the specific reason on
/// screen (e.g. "No one else to ping yet") before throwing this, so nothing
/// else should toast on top of it. Its only job is to reach
/// showScoreRewardOverlay's loadGain as a failure, so the reward card never
/// opens claiming points for a send that never happened.
class _NothingToPing implements Exception {
  const _NothingToPing();
}

class PingGroup {
  final String id, name;
  final int count;
  final List<int> tintIndices;

  /// The group's DP (`groups.icon_url`). When set, the chip shows the real
  /// photo instead of the generated member-tint circles.
  final String? iconUrl;

  /// My ping streak with this group (my_group_ping_overview) — shown as the
  /// same blue flame the friend strip uses.
  final int streak;
  PingGroup(
    this.id,
    this.name,
    this.count,
    this.tintIndices, {
    this.iconUrl,
    this.streak = 0,
  });
}

// `var`, not `final` — _PingPageState._loadRealPingData() replaces these
// wholesale once a real fetch resolves (see this file's deviation #5 doc up
// top). Every one of the 30+ existing read sites below just reads whatever
// the current global value is, so replacing the list in place is the whole
// integration — no call site needs to change.
//
// kFriends/kGroups start EMPTY, not with demo names — real data only, from
// first frame. Explicit user correction (2026-09-03) established this for
// kFriends: a fixture name sitting in "Ping someone" indefinitely because
// the real fetch hadn't landed yet (or came back empty) read as fake data
// in what's meant to be a real app. kGroups follows the same rule now that
// group pings are real — a fixture "Basement Four"/"Thesis Hell" chip next
// to real groups would be exactly that kind of fake data.
// All five start EMPTY, not with fixture rows — real data only, from first
// frame. A fixture name (Naomi K./Priya/Ilana/...) sitting in TO REPLY,
// SENT, or REPLIES indefinitely because a real fetch hadn't landed yet (or
// came back empty) read as fake data in what's meant to be a real app; each
// section's own empty-state copy covers the true-empty case honestly
// instead. See _loadRealPingData's own doc on why a failed fetch (null)
// leaves whatever was already here alone rather than clearing it too.
var kFriends = <Friend>[];
var kGroups = <PingGroup>[];

/// Everyone in every community the caller has joined, not just accepted
/// friends — a second, separate row under "Ping someone". Explicit
/// request: "when gone to ping someone section I shall see below that
/// widget list of all the members in the community which the user has
/// joined". Empty until the first real fetch lands, same no-fixture-data
/// rule as kFriends/kGroups above.
var kCommunityMembers = <CommunityMember>[];
var kToReply = <InboundPing>[];

/// Set by MainShell._onOpenPingNotif when a ping/photoReply notification is
/// tapped, naming the `pings.id` to focus once the Ping tab is showing —
/// see that method's own doc for why this is a top-level ValueNotifier
/// rather than a constructor param. [_PingPageState] consumes it (and
/// resets it to null) in [_PingPageState._onPingFocusRequested].
final pingFocusRequest = ValueNotifier<String?>(null);

/// The group id I just sent a group ping to. Every group-ping entry point
/// (the Ping page chip, "Ping many", the group profile's Ping All) sets it,
/// so the flow is always the same: MainShell switches to the Ping tab, and
/// [_PingPageState._onGroupAnswerRequested] scrolls to that group's new wall
/// and opens the camera for my own answer — posting it unlocks the wall.
final groupWallAnswerRequest = ValueNotifier<String?>(null);

/// Whether the Ping tab is the one actually on screen — set by MainShell on
/// every tab change (initial value matches its own initial index: false
/// unless launched straight into Ping via debugInitialIndex).
///
/// PingScreen sits in MainShell's own `PageView(children: _screens)`,
/// built once in that widget's initState and never rebuilt on tab switch
/// (verified: a plain PageView with a fixed `children` list, not
/// `.builder`, keeps every page mounted) — so without this gate,
/// [_PingPageState]'s 20-second poll and its realtime-triggered reload
/// each fan out 15+ Supabase round trips (friends/toReply/sent/replies/
/// groups/walls/streaks/community members, plus one fetchMembers() per
/// group and one fetchWall() per open wall thread) FOREVER, regardless of
/// whether Ping is the visible tab. Reported as "the ping page is loading
/// too much".
///
/// Deliberately does NOT gate the very first load in initState — that one
/// exists specifically so the tab is instant the moment it's actually
/// opened (see _loadRealPingData's own doc on that bug fix) — only the
/// recurring poll/realtime reload while Ping is NOT on screen are skipped.
/// Flipping this back to true immediately triggers one catch-up reload
/// (see _PingPageState.initState's listener), so nothing sent while
/// hidden is stale for more than the time it takes to switch tabs.
final pingTabActive = ValueNotifier<bool>(false);
var kSent = <OutboundPing>[];
var kReplies = <InboundReply>[];

// ============================================================================
// shared primitives
// ============================================================================

/// Frosted glass container with irregular radius.
class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final Gradient? gradient;
  final Color? color;
  final Border? border;
  final List<BoxShadow>? shadow;
  final double blurSigma;
  const Glass({
    super.key,
    required this.child,
    required this.radius,
    this.gradient,
    this.color,
    this.border,
    this.shadow,
    this.blurSigma = 0,
  });

  @override
  Widget build(BuildContext c) {
    // Shadow must sit OUTSIDE the clip — a clipped box cannot paint its own
    // drop shadow, which is why the glass rows looked flat before.
    Widget box = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: gradient,
        color: color,
        border: border,
      ),
      child: child,
    );
    if (blurSigma > 0) {
      box = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: box,
        ),
      );
    }
    if (shadow != null) {
      box = DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
        child: box,
      );
    }
    return box;
  }
}

/// Conic progress ring (hold-to-reveal). Arc is the only coloured part, and
/// only while it fills; the centre dot is always neutral.
class RingPainter extends CustomPainter {
  final double p;
  final Color accent;
  RingPainter(this.p, this.accent);

  @override
  void paint(Canvas c, Size s) {
    final r = s.width / 2;
    final center = Offset(r, r);
    final sw = s.width * 0.08;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..color = w(.09);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..color = accent
      ..strokeCap = StrokeCap.round;
    c.drawCircle(center, r - sw / 2, track);
    if (p > 0) {
      c.drawArc(
        Rect.fromCircle(center: center, radius: r - sw / 2),
        -math.pi / 2,
        2 * math.pi * p,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(RingPainter o) => o.p != p || o.accent != accent;
}

/// 45deg hatch placeholder (stands in for a photo that hasn't rendered).
class HatchPainter extends CustomPainter {
  final double stripe;
  final Color a, b;
  HatchPainter(this.stripe, this.a, this.b);

  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.clipRect(Offset.zero & s);
    final pa = Paint()..color = a, pb = Paint()..color = b;
    final diag = s.width + s.height;
    double x = -s.height;
    bool flip = false;
    while (x < diag) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripe, 0)
        ..lineTo(x + stripe - s.height, s.height)
        ..lineTo(x - s.height, s.height)
        ..close();
      c.drawPath(path, flip ? pb : pa);
      x += stripe;
      flip = !flip;
    }
    c.restore();
  }

  @override
  bool shouldRepaint(HatchPainter o) => false;
}

/// Real dashed border. The reference approximates CSS `dashed` as solid and
/// documents it as a known gap; this closes it.
class _DashedBorder extends CustomPainter {
  final Color color;
  final double width, radius;
  static const double dash = 4, gap = 3;
  const _DashedBorder({required this.color, this.width = 1.5, this.radius = 0});

  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(radius)),
      );
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        c.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder o) =>
      o.color != color || o.radius != radius || o.width != width;
}

/// Pulsing dot (seen / live / window).
class PulseDot extends StatefulWidget {
  final double size;
  final Color color;
  final int ms;
  const PulseDot({
    super.key,
    this.size = 5,
    this.color = kCyan,
    this.ms = 3000,
  });
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.ms),
  )..repeat(reverse: true);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: ctl,
    builder: (_, _) {
      final t = Curves.easeInOut.transform(ctl.value);
      final o = ui.lerpDouble(.35, 1, t)!;
      final sc = ui.lerpDouble(1, 1.35, t)!;
      return Transform.scale(
        scale: sc,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: o),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: .9),
                blurRadius: 9,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Spring-tap wrapper (scale .94 + rotate -1deg).
class SpringTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const SpringTap({super.key, required this.child, this.onTap});
  @override
  State<SpringTap> createState() => _SpringTapState();
}

class _SpringTapState extends State<SpringTap> {
  bool down = false;
  @override
  Widget build(BuildContext c) => GestureDetector(
    onTapDown: (_) => setState(() => down = true),
    onTapUp: (_) => setState(() => down = false),
    onTapCancel: () => setState(() => down = false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: down ? .94 : 1,
      duration: const Duration(milliseconds: 180),
      curve: const Cubic(.34, 1.56, .64, 1),
      child: AnimatedRotation(
        turns: down ? -1 / 360 : 0,
        duration: const Duration(milliseconds: 180),
        curve: const Cubic(.34, 1.56, .64, 1),
        child: widget.child,
      ),
    ),
  );
}

/// Identity avatar — earth gradient for named people, dashed clay for
/// anonymous (anonymous never takes the accent, and never resolves to a real
/// name or tint).
Widget avatarCircle(
  Scale s, {
  required double size,
  required double fontSize,
  required String initial,
  required int tintIndex,
  required bool isAnon,
  double borderAlpha = .14,
}) {
  final box = Container(
    width: s(size),
    height: s(size),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: isAnon
          ? null
          : g160(kEarth[tintIndex][0], kEarth[tintIndex][1]),
      color: isAnon ? clay(.12) : null,
      border: isAnon ? null : Border.all(color: w(borderAlpha), width: 1),
    ),
    child: Text(
      initial,
      style: ts(
        s,
        weight: 500,
        size: fontSize,
        color: isAnon ? clay(.9) : kDarkOnCyan,
      ),
    ),
  );
  if (!isAnon) return box;
  // deviation #3 — real dashes for the anonymous ring.
  return CustomPaint(
    painter: _DashedBorder(color: clay(.5), radius: s(size) / 2),
    child: box,
  );
}

// ============================================================================
// page
// ============================================================================

class PingPage extends StatefulWidget {
  const PingPage({super.key});
  @override
  State<PingPage> createState() => _PingPageState();
}

class _PingPageState extends State<PingPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ---- state (mirror of the reference's Component.state) ----

  /// True until the first _loadRealPingData() call has resolved (success
  /// OR failure — either way, a real answer has arrived). BUG FIX
  /// (explicit report — "opens empty, loads a few seconds later, shall be
  /// instant"): kToReply/kReplies/kSent/etc. all start genuinely empty by
  /// design (see this file's own "real data only, from first frame" doc)
  /// — there was no distinction between "confirmed nothing to show" and
  /// "haven't heard back yet", so every section rendered as a bare "0
  /// waiting" header with nothing below it during that window, on the
  /// same one-time cold-start race every eagerly-built MainShell tab hits
  /// (see initState's own doc on why this page loads at app launch,
  /// regardless of which tab is visible). Only gates the FIRST load —
  /// every reload after (polling, resume, a real send) leaves whatever
  /// was already on screen in place, per this file's existing convention.
  bool _firstLoadPending = true;

  final revealed = <String, DateTime>{};
  final viewed = <String, bool>{};

  /// My reaction state on a given reply — keyed by reply id, same shape as
  /// [viewed]. Shared by BOTH surfaces: a 1:1 reply in `_photoView` and a
  /// group-wall tile in `_wallTile`, since both now go through the same
  /// unified `toggle_ping_reply_reaction` RPC (see PingService.toggleReaction's
  /// own doc). Seeded from InboundReply/WallSlot's own reactionCount/
  /// myReaction on load, then only ever changed by [_toggleReaction]'s own
  /// optimistic flip + server correction — never by a plain re-read
  /// overwriting an in-flight toggle mid-request.
  final reactions = <String, ({bool mine, int count})>{};

  /// Hearts (or un-hearts) the reply identified by [replyId]. Optimistic
  /// (flips `mine` and moves `count` by ±1 immediately), then corrected from
  /// the server's real return value — a toggle that raced a page refresh or
  /// hit a stale double-tap must land on what the server actually recorded,
  /// not on "whatever the client guessed twice in a row". [initialMine]/
  /// [initialCount] are the model's own last-loaded values, used only the
  /// first time this id is touched this session (falls back to whatever is
  /// already in [reactions] otherwise, so a second tap starts from the true
  /// current state, not the stale load-time one).
  Future<void> _toggleReaction(
    String replyId, {
    required bool initialMine,
    required int initialCount,
  }) async {
    final before =
        reactions[replyId] ?? (mine: initialMine, count: initialCount);
    setState(
      () => reactions[replyId] = (
        mine: !before.mine,
        count: before.count + (before.mine ? -1 : 1),
      ),
    );
    try {
      final (liked, count) = await PingService.instance.toggleReaction(replyId);
      if (mounted)
        setState(() => reactions[replyId] = (mine: liked, count: count));
    } catch (_) {
      if (mounted) setState(() => reactions[replyId] = before);
    }
  }

  final captured = <String, bool>{};

  /// Keyed like [captured] (`wall:threadId` for the group wall) —
  /// true while a reply for that key is mid-flight to the server.
  /// Blocks a second tap from firing a second insert before the first
  /// round-trip lands, which is exactly the race that could still slip
  /// a duplicate group-ping reply past the UI even with the server-side
  /// one-reply-per-thread trigger backing it up (enforce_group_ping_
  /// reply_once) — this is belt, that trigger is suspenders.
  final _wallSending = <String>{};

  /// The just-captured reply photo's uploaded public URL, keyed by ping id
  /// (a wall composer's own reply keys this as `'wall:$threadId'`, since a
  /// person can have more than one wall open at once) — set right after
  /// upload by [_openCamera]/[_openWallCamera], consumed by the matching
  /// send button.
  final capturedPhotoUrl = <String, String>{};

  /// The uploaded selfie URL for a captured reply, same keying as
  /// [capturedPhotoUrl] — set alongside it by [_openCamera]/
  /// [_openWallCamera] only when the capture actually had a selfie half
  /// (a camera reply; never an album pick). Consumed by the matching send
  /// button and cleared on send, same as [capturedPhotoUrl].
  final capturedSelfieUrl = <String, String>{};

  /// The shot's LOCAL file path, same keying as [capturedPhotoUrl] — drawn
  /// the instant the camera returns. The preview used to wait on the upload
  /// AND a re-download of the same photo, so it sat on the blue hatch
  /// placeholder for seconds after every shot.
  final capturedLocalPath = <String, String>{};

  /// The in-flight photo upload per key. Send awaits it: Send is enabled
  /// the moment a photo is captured, and tapping it before the upload
  /// landed used to send the reply with NO photo (photoUrl still null).
  final _photoUploads = <String, Future<String?>>{};

  /// Local file of a wall photo I just posted, keyed by its uploaded URL
  /// (exactly what get_group_wall hands back as photo_url). Lets my own tile
  /// show the shot instantly instead of the tint during the download.
  final _myWallLocalPhoto = <String, String>{};

  final sentReplies = <String, List<String>>{};

  /// Whether the compact 'sent' dropdown (PingSentAnchor) is
  /// currently showing under a Send/Post pill — keyed the same way
  /// as [captured] (`'wall:<threadId>'` for the group wall, the ping
  /// id otherwise). Flipped true only once PingService.reply's
  /// network call actually succeeds, not optimistically like
  /// [sentReplies] — the old static chip list appended before the
  /// request even landed and never rolled back on failure; this
  /// confirmation should only ever reflect a real send.
  final sentDropdownOpen = <String, bool>{};

  /// What the send actually EARNED, keyed the same way as
  /// [sentDropdownOpen]. Read from the server after the send lands (see
  /// ScoreGainService) rather than assumed — the old confirmation showed a
  /// hardcoded "+10" that matched no rule in the scoring system.
  final sentGain = <String, ScoreGain>{};
  final pingedBack = <String, bool>{};
  String? replyDetailId;

  /// Reply whose photo is open full-screen. Set the moment a reply finishes
  /// hold-to-reveal, so the photo they sent is the first thing you see.
  String? photoViewId;
  String replyDraft = '';
  final _replyCtrl = TextEditingController();

  /// Active Group Wall threads (real, from `my_group_walls()`) and each
  /// one's member slots (real, from `get_group_wall()`), keyed by threadId
  /// — replaces the single hardcoded kGroupWall/kWallGroup/kWallPrompt.
  var wallThreads = <WallThread>[];
  final wallSlots = <String, List<WallSlot>>{};

  /// The viewer's COMBINED score (`users.total_score`), despite the field
  /// name — kept as `pingScore` only because a dozen render sites in this
  /// 7k-line file read it. Was `users.ping_score`, incremented (+25 per
  /// ping sent, +20 per reply sent — see the `send_ping`/`send_group_ping`
  /// RPCs and the `trg_award_ping_reply_score` trigger). Starts at 0 rather
  /// than a fake baseline and is only ever set from a real fetch, in
  /// `_loadRealPingData`.
  int pingScore = 0;

  /// My account's real campus label ('RVCE'/'RVU'), derived server-side from
  /// my own email domain — null for any non-institutional signup. Replaces
  /// the old hardcoded 'CAMPUS · BROWN' header, which showed a fake campus
  /// to every account regardless of how they signed up (explicit request:
  /// outsiders are allowed in now, so this line must not lie to or about
  /// them). Null hides the whole header line, not just the campus word.
  String? _campus;

  /// Optimistic pre-nudge only — every real send already reconciles this
  /// against the true DB value moments later via `_loadRealPingData()`
  /// (every PingService call site below chains `.then((_) =>
  /// _loadRealPingData())`), so this never has to be point-accurate, just
  /// immediate.
  void _bumpScore([int by = 3]) => pingScore += by;

  /// Pings sent from the prompt sheet this session — prepended to SENT so the
  /// dropdown actually does something (the reference's compose just closed).
  final sentExtra = <OutboundPing>[];

  /// How long a hold-to-unblur takes. Lengthened from 1.0s (explicit
  /// request, 2026-10-03: "let the unblurring vibrations be a little more
  /// longer, increase the time") — the native haptic swell runs for exactly
  /// this long, so the hold duration IS the length of the vibration.
  double holdSeconds = 1.4;
  final accent = kCyan;

  // ---- hold ticker ----
  String? holdId;
  double holdP = 0;
  AnimationController? _hold;

  /// Reply photos are a glance, not a gallery: the viewer self-closes after
  /// [_kPhotoSeconds]. Holding anywhere on the photo stops this controller, so
  /// a long look costs a deliberate, visible gesture rather than being free.
  /// Driving the countdown off an AnimationController (not a Timer) means the
  /// progress bar and the remaining time read from one source and stay in sync
  /// across pause/resume.
  AnimationController? _photoTimer;
  static const _kPhotoSeconds = 2;

  /// True while the finger is down on the photo — pauses the countdown and
  /// swaps the hint text.
  bool _photoHeld = false;

  void _precacheReplyPhotos() {
    for (final r in kReplies) {
      if (r.viewedInit || (viewed[r.id] ?? false)) continue;
      for (final url in [r.photoUrl, r.selfieUrl]) {
        if (url == null || url.isEmpty) continue;
        precacheImage(
          CachedNetworkImageProvider(url, maxWidth: 1080),
          context,
        ).catchError((_) {});
      }
    }
  }

  void _openPhoto(String id) {
    photoViewId = id;
    immersiveChrome.value = true; // the photo owns the screen; hide the tab bar
    _photoTimer?.reset();
    // The few-second countdown starts only once the photo is actually on
    // screen (see _photoView's imageBuilder) — never spent on a loading
    // state. Replies without a photo start it right away.
    final r = kReplies.where((x) => x.id == id).firstOrNull;
    if (r == null || r.photoUrl == null) _photoTimer?.forward();
  }

  /// Called by _photoView once the reply photo has rendered.
  void _startPhotoCountdown() {
    final t = _photoTimer;
    if (t == null || t.isAnimating || t.value > 0 || _photoHeld) return;
    t.forward();
  }

  void _closePhoto() {
    _photoTimer?.stop();
    immersiveChrome.value = false;
    setState(() {
      photoViewId = null;
      _photoHeld = false;
    });
  }

  /// The ping's OWN attached photo (`pings.photo_url`, not a reply) — same
  /// one-time countdown viewer as [_openPhoto]/[_closePhoto], reusing the
  /// same [_photoTimer]/[_photoHeld] since only one full-screen photo can
  /// ever be open at a time. Explicit request: this used to render as a
  /// plain, always-visible, indefinitely-re-viewable thumbnail inline in the
  /// card — now it gets the identical glance-then-gone treatment a reply's
  /// photo already had, "the viewing looks like viewing pinged posts".
  String? pingPhotoViewId;

  void _openPingPhoto(String id) {
    pingPhotoViewId = id;
    immersiveChrome.value = true;
    unawaited(PingService.instance.markPingPhotoOpened(id));
    _photoTimer
      ?..reset()
      ..forward();
  }

  /// A group-wall reply opened full screen after its hold-to-reveal — same
  /// one-time countdown viewer as a personal reply ("when holding it, it
  /// shall open full screen, not only in a small area, just like personal
  /// pings"). Viewed once: afterwards its wall tile shows "Viewed".
  WallSlot? wallPhotoSlot;

  void _openWallPhoto(WallSlot slot) {
    wallPhotoSlot = slot;
    immersiveChrome.value = true;
    _photoTimer
      ?..reset()
      ..forward();
  }

  void _closeWallPhoto() {
    _photoTimer?.stop();
    immersiveChrome.value = false;
    setState(() {
      wallPhotoSlot = null;
      _photoHeld = false;
    });
  }

  void _closePingPhoto() {
    _photoTimer?.stop();
    immersiveChrome.value = false;
    setState(() {
      pingPhotoViewId = null;
      _photoHeld = false;
    });
    // The card's own placeholder (locked "photo viewed") only reflects
    // server truth via a fresh load — this view was one-shot the moment it
    // opened (markPingPhotoOpened already fired), so there is nothing left
    // to lose by refreshing now rather than waiting for the next poll.
    unawaited(_loadRealPingData());
  }

  /// Finger down on the photo — freeze the countdown for as long as it stays
  /// there. Resuming rather than restarting keeps the bar honest: a hold buys
  /// you time, it doesn't hand back seconds you already spent.
  void _photoHoldStart() {
    _photoTimer?.stop();
    setState(() => _photoHeld = true);
  }

  void _photoHoldEnd() {
    if (!_photoHeld) return;
    setState(() => _photoHeld = false);
    if (photoViewId != null ||
        pingPhotoViewId != null ||
        wallPhotoSlot != null) {
      _photoTimer?.forward();
    }
  }

  StreamSubscription<AuthState>? _authSub;

  /// Live updates. Without these this screen loaded exactly once and never
  /// again, so a ping you were sent, a reply to a ping you sent, and the
  /// "seen" flip all landed correctly in the database but never showed up
  /// on the other person's device until the app was restarted — which read
  /// as "pings don't work" even though every write was fine.
  ///
  /// Two mechanisms, deliberately:
  ///  * [_pingChannel] — postgres_changes on `pings`/`ping_replies`, so a
  ///    person or group ping/reply appears within a moment of landing.
  ///    Realtime applies RLS per subscriber, which is exactly what we want
  ///    everywhere except the anonymous case below.
  ///  * [_pollTimer] — a slow backstop. An ANONYMOUS ping's receiver
  ///    deliberately cannot SELECT that row (that's what keeps sender_id
  ///    unreadable), so no realtime event ever reaches them for it. The
  ///    poll goes through ping_inbox(), the masked read path, so anonymous
  ///    pings still surface promptly without weakening the masking.
  RealtimeChannel? _pingChannel;
  Timer? _pollTimer;

  /// Coalesces bursts (a group fan-out is N inserts at once) into one
  /// reload instead of N.
  Timer? _reloadDebounce;

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 350), () {
      // The Friends feed's top row (replies / your turn / who to ping)
      // has no live channel of its own — this page is alive from launch,
      // so its channel tells that row too. Without it a ping that arrived
      // while you sat on the feed only showed up after a pull-to-refresh.
      pingInboxChanged.value++;
      // Skip while Ping isn't the visible tab — see pingTabActive's own
      // doc. pingTabActive's own listener (initState below) fires a fresh
      // reload the moment the tab is opened again, so this is a deferral,
      // not a dropped update.
      if (mounted && pingTabActive.value) unawaited(_loadRealPingData());
    });
  }

  void _subscribeToPingChanges() {
    _pingChannel?.unsubscribe();
    _pingChannel = supabase
        .channel('ping_live_${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pings',
          callback: (_) => _scheduleReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ping_replies',
          callback: (_) => _scheduleReload(),
        )
        .subscribe();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Engine up before the first ping/hold, so the first buzz isn't late.
    unawaited(warmHaptics());
    _photoTimer =
        AnimationController(
            vsync: this,
            duration: const Duration(seconds: _kPhotoSeconds),
          )
          ..addListener(() => setState(() {}))
          ..addStatusListener((st) {
            if (st != AnimationStatus.completed) return;
            if (photoViewId != null) _closePhoto();
            if (pingPhotoViewId != null) _closePingPhoto();
            if (wallPhotoSlot != null) _closeWallPhoto();
          });
    unawaited(_loadRealPingData());
    // Covers launching straight onto the Ping tab — _onPingTabActiveChanged
    // only fires on a CHANGE, which never happens if Ping was already the
    // active tab before this State existed.
    if (pingTabActive.value) notifState.markPingsRead();
    _subscribeToPingChanges();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 20),
      // Skip while Ping isn't the visible tab — see pingTabActive's own
      // doc for why this poll otherwise ran forever in the background.
      (_) {
        if (pingTabActive.value) unawaited(_loadRealPingData());
      },
    );
    // Catches up the instant the tab is actually opened — the poll/
    // realtime reload above are skipped the whole time it wasn't, so this
    // is what keeps "switch to Ping" from ever showing stale data.
    pingTabActive.addListener(_onPingTabActiveChanged);
    pingFocusRequest.addListener(_onPingFocusRequested);
    groupWallAnswerRequest.addListener(_onGroupAnswerRequested);
    // A notification tap can arrive before this screen's first
    // _loadRealPingData() has ever run (PingScreen is built eagerly at
    // launch, per this file's own initState doc below) — check for an
    // already-pending request rather than only reacting to future ones.
    unawaited(_onPingFocusRequested());
    // PingScreen is one of MainShell's IndexedStack children, built (and
    // initState'd) eagerly at app launch regardless of which tab is
    // visible — found via direct verification that the very first
    // _loadRealPingData() call can race Supabase's own session restore and
    // hit CurrentUserService's "no signed-in user" StateError, after which
    // nothing ever retried and this screen was stuck on fixture data for
    // the rest of the session. `initialSession` (a locally-restored session
    // becoming available — the actual event that fires on this race, NOT
    // `signedIn`, which is only for a fresh interactive sign-in) or
    // `signedIn` both mean "a session exists now that maybe didn't a moment
    // ago" — reload on either, closing the gap without touching
    // CurrentUserService itself.
    _authSub = supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.initialSession ||
          state.event == AuthChangeEvent.signedIn) {
        unawaited(_loadRealPingData());
        // A new session means a new RLS identity — the old channel was
        // subscribed as whoever was signed in before.
        _subscribeToPingChanges();
      }
    });
  }

  /// Coming back from the background is the other moment the on-screen data
  /// is reliably stale — realtime drops its socket while suspended.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Resubscribe unconditionally — the socket really did drop, and it's
      // cheap regardless of which tab is on screen. The reload itself is
      // gated the same as the poll/realtime path above: wasted if Ping
      // isn't visible, and pingTabActive's own listener covers it the
      // moment it becomes visible again.
      if (pingTabActive.value) unawaited(_loadRealPingData());
      _subscribeToPingChanges();
    }
  }

  /// Loads real friends/pings/sent-pings/replies (person origin only — see
  /// this file's deviation #5 doc) and replaces the fixture globals in
  /// place. Runs on mount, again on every SIGNED_IN auth event (see
  /// initState's own doc), and again after every real send/reply so the
  /// lists reflect what actually landed. PingService's own methods already
  /// swallow their errors into `[]`; the only thing that can still throw
  /// here is CurrentUserService.resolveId() when no session exists yet, in
  /// which case there's simply nothing to load — leave the fixture globals
  /// as they are and let the next SIGNED_IN event retry.
  /// Every caller's entry point: the page load, then the RealMoji
  /// reactions for whatever it brought in (reply cards, wall answers and
  /// 1:1 pings), so faces show without an extra tap.
  Future<void> _loadRealPingData() async {
    await _loadRealPingDataCore();
    if (!mounted) return;
    final replyIds = <String>{
      for (final r in kReplies) r.id,
      for (final slots in wallSlots.values)
        for (final sl in slots)
          if (sl.replyId != null) sl.replyId!,
      // MY OWN replies too — the photo I sent someone can be reacted to,
      // and those faces show under REACTIONS TO YOU (reported 2026-10-04).
      for (final p in kToReply)
        for (final r in p.myReplies)
          if (r.id != null) r.id!,
    };
    final pingIds = <String>{
      for (final p in kToReply)
        if (!p.isGroup) p.id,
    };
    unawaited(
      _loadPingRealmojis(
        replyIds: replyIds.toList(),
        pingIds: pingIds.toList(),
      ),
    );
    unawaited(_loadMyReplyReactions());
  }

  Future<void> _loadMyReplyReactions() async {
    final rows = await PingRealmojiService.instance.fetchMyReplyReactions();
    if (!mounted) return;
    setState(() => _myReplyReactions = rows);
  }

  Future<void> _loadRealPingDataCore() async {
    List<Object?> results;
    int? realPingScore;
    try {
      final meId = await CurrentUserService.instance.resolveId();
      // Standalone, not in the Future.wait below (whose results are read
      // positionally everywhere below it — inserting a slot there would
      // mean renumbering every index). Fetched once; campus never changes.
      if (_campus == null) {
        unawaited(
          supabase
              .from('users')
              .select('campus')
              .eq('id', meId)
              .maybeSingle()
              .then((row) {
                if (mounted)
                  setState(() => _campus = row?['campus'] as String? ?? '');
              })
              .catchError((_) {}),
        );
      }
      // Started at app launch by prefetchPingData() when possible, so the
      // first open of this tab doesn't wait on the network at all.
      final prefetched = _pingPrefetch;
      _pingPrefetch = null;
      results =
          await (prefetched?.catchError((_) => _pingBatch(meId)) ??
              _pingBatch(meId));
      realPingScore = results[10] as int?;
    } catch (_) {
      // No session yet — see this method's own doc.
      return;
    }
    if (!mounted) return;

    // CircleService/GroupService still swallow errors into `[]` — real
    // emptiness there just means an honest empty strip, no overlay reads
    // off either list, so there's no crash risk to guard against. The four
    // PingService fetches below are different: `null` means "the request
    // failed", and the fix is to keep whatever was already on screen rather
    // than let a dropped packet wipe a real inbox down to nothing.
    final friends = results[0] as List<Map<String, dynamic>>;
    final toReply = results[1] as List<InboundPingRow>?;
    final sent = results[2] as List<OutboundPingRow>?;
    final replies = results[3] as List<ReceivedReplyRow>?;
    final myGroups = results[4] as List<Map<String, dynamic>>;
    final walls = results[5] as List<WallThread>?;
    final streaks = results[6] as Map<String, int>;
    final communityMembers = results[7] as List<CommunityMember>;
    final pinnedIds = results[8] as Set<String>;
    final groupOverview =
        results[9] as Map<String, ({int streak, int activity, int rank})>;

    // One fetchMembers() per group for the chip's people-count + overlapping
    // avatar tints — small N (a handful of groups per user), so a fan-out of
    // plain requests here is simpler than a bespoke aggregate RPC for what's
    // a decorative chip.
    //
    // BUG FIX (explicit report — "opens empty, loads a few seconds later,
    // shall be instant"): these two batches are independent (neither reads
    // the other's result) but used to run sequentially — `await
    // Future.wait([...members])` fully completing before the wall-slots
    // Future.wait even started, serializing two round trips that could
    // overlap. Starting both Future.wait calls before awaiting either
    // fires every underlying request concurrently — a real reduction in
    // wall-clock time, not just a loading-state cosmetic fix.
    final memberListsFuture = Future.wait([
      for (final g in myGroups)
        GroupService.instance.fetchMembers(g['id'] as String),
    ]);
    final slotListsFuture = Future.wait([
      for (final t in walls ?? const <WallThread>[])
        PingService.instance.fetchWall(t.threadId),
    ]);
    final memberLists = await memberListsFuture;
    final slotLists = await slotListsFuture;
    if (!mounted) return;

    setState(() {
      if (realPingScore != null) pingScore = realPingScore;
      // Server data is fresh now — drop the optimistic like overrides, or
      // a tile I once tapped would stay frozen at that moment's count and
      // never show anyone else's likes arriving (live via like_count).
      reactions.clear();

      // Always replaced, even with an empty list — a user with zero real
      // friends sees an honest empty strip (_friendStrip's own empty-state
      // branch), never the Naomi/Theo/Priya demo row left standing in for
      // "no data yet". This app is meant to read as real; a demo name that
      // never goes away because a real fetch came back empty is exactly the
      // kind of thing that breaks that.
      // Who I CAN'T ping right now: a 1:1 ping of mine to them is still
      // open and unanswered, so send_ping would refuse with
      // PING_ALREADY_OPEN. They drop out of the strip entirely (explicit
      // request, 2026-10-03: "for ping error cannot be pinged, don't
      // include them in the list after they are pinged, and again when
      // they can be pinged include them") and come back on their own: the
      // ping's window closing is exactly what frees them, and fetchSent
      // only ever returns unexpired rows, so the next 20s poll re-adds
      // them with no extra bookkeeping.
      //
      // A null `sent` means that one request failed — keep everyone rather
      // than hiding the whole strip on a dropped packet.
      // Blocked until the ping CLOSES, replied or not — that is what
      // send_ping enforces since 2026-10-06 (see openPingReceiverIds). With
      // `!o.replied` in this test someone who had answered came back to the
      // strip, and tapping them failed with "already pinged".
      final blockedByOpenPing = sent == null
          ? <String>{}
          : openPingReceiverIds(sent);
      // One set for every "can I ping them right now?" check on the page.
      _openSentTo = blockedByOpenPing;

      // Same rule for GROUPS (explicit request, 2026-10-03: "the group
      // accounts shall not be seen if they cannot be pinged, just like
      // personal ones"). A group chip drops out while a group ping of mine
      // to it is still open — fetchSent only returns unexpired rows, so the
      // window closing is what brings it back. A group with nobody else in
      // it is hidden too: send_group_ping refuses that outright ("Waiting
      // for members to join this group"), so it was never pingable.
      final blockedGroupIds = <String>{
        if (sent != null)
          for (final o in sent)
            if (o.isGroup && o.groupId != null && !o.replied) o.groupId!,
      };

      kFriends = [
        for (final f in friends)
          if (!_openSentTo.contains(f['id'] as String))
            Friend(
              f['id'] as String,
              (f['name'] as String?) ?? 'someone',
              ((f['name'] as String?)?.isNotEmpty == true
                      ? (f['name'] as String)[0]
                      : '?')
                  .toUpperCase(),
              (f['id'] as String).hashCode.abs() % kEarth.length,
              // Real pairwise streak — consecutive days an exchange with
              // this person actually closed (my_ping_streaks RPC). 0 when
              // we've never completed one, never a fabricated number.
              streaks[f['id'] as String] ?? 0,
              avatarUrl: f['profile_photo_url'] as String?,
            ),
      ];

      // Strip order (explicit request): the people you actually keep a ping
      // going with read first, so the strip doesn't bury a live streak
      // behind whoever the friends fetch happened to return first.
      //   1. pinned (highest streak first within the tier)
      //   2. ongoing streak, no pin (highest streak first)
      //   3. everyone else, original fetch order preserved
      // Tiering rather than one combined score keeps "pinned" absolute — a
      // pinned person with a cold streak still outranks a hot non-pinned
      // one, which is what pinning them was for.
      int tierOf(Friend f) {
        if (pinnedIds.contains(f.id)) return 0;
        if (f.streak > 0) return 1;
        return 2;
      }

      final originalOrder = {
        for (var i = 0; i < kFriends.length; i++) kFriends[i].id: i,
      };
      kFriends.sort((a, b) {
        final t = tierOf(a).compareTo(tierOf(b));
        if (t != 0) return t;
        if (tierOf(a) != 2) {
          final s = b.streak.compareTo(a.streak);
          if (s != 0) return s;
        }
        return (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0);
      });

      kCommunityMembers = communityMembers;

      kGroups = [
        for (var i = 0; i < myGroups.length; i++)
          if (memberLists[i].length >= 2 &&
              !blockedGroupIds.contains(myGroups[i]['id'] as String))
            PingGroup(
              myGroups[i]['id'] as String,
              (myGroups[i]['name'] as String?) ?? 'Group',
              memberLists[i].length,
              [
                for (final m in memberLists[i].take(3))
                  (m['user_id'] as String).hashCode.abs() % kEarth.length,
              ],
              iconUrl: myGroups[i]['icon_url'] as String?,
              streak: groupOverview[myGroups[i]['id']]?.streak ?? 0,
            ),
      ];
      // Most active group first (explicit request); groups the overview
      // didn't rank keep their fetch order after the ranked ones.
      final groupOrder = {
        for (var i = 0; i < kGroups.length; i++) kGroups[i].id: i,
      };
      kGroups.sort((a, b) {
        final ra = groupOverview[a.id]?.rank ?? 1 << 20;
        final rb = groupOverview[b.id]?.rank ?? 1 << 20;
        if (ra != rb) return ra.compareTo(rb);
        return groupOrder[a.id]!.compareTo(groupOrder[b.id]!);
      });

      // toReply/sent/replies/walls are only replaced when the fetch actually
      // succeeded — a `null` (the request failed; see PingService's own doc
      // on why that's distinct from a real empty list) leaves whatever was
      // already on screen exactly as it was, rather than blanking a real
      // inbox because one request dropped a packet.
      if (toReply != null) {
        kToReply = [
          for (final p in toReply)
            InboundPing(
              p.id,
              p.senderName,
              p.senderName.isNotEmpty ? p.senderName[0].toUpperCase() : '?',
              p.prompt.trim().isNotEmpty
                  ? p.prompt
                  : p.isGroup
                  ? '${p.senderName}: ${pingGreeting(p.id)}'
                  : pingGreeting(p.id),
              _windowLeftLabel(p.expiresAt),
              (p.senderId ?? p.id).hashCode.abs() % kEarth.length,
              isGroup: p.isGroup,
              isAnon: p.isAnon,
              groupCount: p.isGroup ? p.groupSize : null,
              threadId: p.threadId,
              senderId: p.senderId,
              photoUrl: p.photoUrl,
              photoOpenedAt: p.photoOpenedAt,
              myReplies: p.myReplies,
              promptless: p.prompt.trim().isEmpty,
              sentAt: p.sentAt,
            ),
        ];

        // Rehydrate the reveal state from the server.
        //
        // `revealed` is an in-memory map, so before this EVERY relaunch
        // re-blurred pings the user had already held to reveal, and the
        // hold-to-reveal had to be repeated from scratch. `seen_at` is
        // written by markSeen at the instant of the reveal (see
        // finishHold), which makes it the durable record of it — and a
        // more accurate base for the "window open · Xh to send more"
        // countdown than the DateTime.now() finishHold stamps locally.
        //
        // putIfAbsent, not []=, so a reveal from this session always wins
        // over a server timestamp that may lag it by a round-trip.
        for (final p in toReply) {
          final seenAt = p.seenAt;
          if (seenAt != null) revealed.putIfAbsent(p.id, () => seenAt);
        }

        // Nothing is "reopened" on relaunch any more: there is no expanded
        // composer card to restore into. A revealed ping comes back as the
        // standard compact card — Ping back + camera, one fixed size
        // (explicit request, 2026-10-03: "people shall not see the add
        // photo drop down at all").
      }

      if (sent != null) {
        // _openSentTo is derived once, above, where the friends strip and
        // the group chips are filtered by it.
        kSent = [
          for (final o in sent)
            OutboundPing(
              o.id,
              o.receiverName,
              o.receiverName.isNotEmpty ? o.receiverName[0].toUpperCase() : '?',
              o.prompt.trim().isEmpty ? kPromptlessOutbound : o.prompt,
              o.seen,
              // Group and promptless pings stay independent SENT rows (each
              // reply lands on its own, no "0 of N replied" grid); only
              // prompted multi-sends group into a multi card.
              threadId: (o.isGroup || o.prompt.trim().isEmpty)
                  ? null
                  : o.threadId,
              avatarUrl: o.receiverAvatarUrl,
              replied: o.replied,
            ),
        ];
      }

      if (replies != null) {
        kReplies = [
          for (final r in replies)
            InboundReply(
              r.replyId,
              r.replierName,
              r.prompt.trim().isEmpty ? kPromptlessReplyTo : r.prompt,
              // Empty, not a literal "photo only" placeholder — a photo
              // reply with no caption now renders the actual photo, so a
              // synthetic caption would just print those two words across
              // it. Every render site below guards on isNotEmpty.
              r.body ?? '',
              _relativeTime(r.createdAt),
              r.viewed,
              r.pingBackAvailable ? _pingBackLabel(r.viewedAt) : null,
              replierId: r.replierId,
              isAnon: r.isAnon,
              groupName: r.groupName,
              photoUrl: r.photoUrl,
              videoUrl: r.videoUrl,
              videoMs: r.videoMs,
              selfieUrl: r.selfieUrl,
              reactionCount: r.reactionCount,
              myReaction: r.myReaction,
              pingId: r.pingId,
              threadId: r.threadId,
            ),
        ];
        // Download every unopened reply's photo now, while it's still
        // blurred, so the viewer opens straight onto the real photo instead
        // of a loading placeholder (explicit report: "a blue page" covered
        // the few seconds the photo is shown).
        _precacheReplyPhotos();
      }

      if (walls != null) {
        wallThreads = walls;
        wallSlots.clear();
        for (var i = 0; i < walls.length; i++) {
          // A single wall's own fetch can fail independently of the others
          // (it's a separate request per thread) — keep that one thread's
          // previously-known slots rather than dropping it to an empty
          // mosaic.
          final slots = slotLists[i];
          if (slots != null) {
            wallSlots[walls[i].threadId] = slots;
          }
        }
      }

      // A background reload can drop the row an open overlay is showing
      // (expired, or the sender deleted it) — close cleanly instead of
      // leaving `build()`'s guard above silently skip it forever with the
      // overlay's own dismiss controls now unreachable.
      if (replyDetailId != null &&
          !kReplies.any((r) => r.id == replyDetailId)) {
        replyDetailId = null;
      }
      if (photoViewId != null && !kReplies.any((r) => r.id == photoViewId)) {
        photoViewId = null;
        immersiveChrome.value = false;
      }

      _firstLoadPending = false;
    });
    _markVisiblePingsSeen();
  }

  /// Pings already reported as seen this session.
  final _seenSent = <String>{};

  /// An incoming ping has no reveal step any more, so being on screen in
  /// the open Ping tab IS seeing it — which is what tells the sender it
  /// was opened and starts its 6-hour window (pings.expires_at). The
  /// hold-to-unblur used to do this (finishHold's ping branch).
  void _markVisiblePingsSeen() {
    if (!mounted || !pingTabActive.value) return;
    for (final p in kToReply) {
      if (_seenSent.add(p.id)) unawaited(PingService.instance.markSeen(p.id));
    }
  }

  String _windowLeftLabel(DateTime expiresAt) {
    final ms = expiresAt.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 'window closed';
    final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000;
    return h > 0 ? '${h}h left to reply' : '${m}m left to reply';
  }

  /// The "Ping them back?" countdown on a reply — was a hardcoded
  /// '24h' (the window's old fixed length, not a real countdown, so it
  /// stayed pinned at "24h" whether 1 minute or 23 hours were actually
  /// left). Now a real remaining-time readout for the 48h window (see
  /// kPingBackWindow).
  String _pingBackLabel(DateTime? viewedAt) {
    if (viewedAt == null) return '';
    final remaining = viewedAt.add(kPingBackWindow).difference(DateTime.now());
    if (remaining.isNegative) return 'closing';
    if (remaining.inDays >= 1) return '${remaining.inDays}d';
    if (remaining.inHours >= 1) return '${remaining.inHours}h';
    return '${remaining.inMinutes}m';
  }

  String _relativeTime(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return d.inDays == 1 ? 'yesterday' : '${d.inDays}d ago';
    return 'last week';
  }

  void startHold(String id, bool isPing, {double? seconds}) {
    _hold?.dispose();
    _hold =
        AnimationController(
            vsync: this,
            duration: Duration(
              milliseconds: ((seconds ?? holdSeconds) * 1000).round(),
            ),
          )
          ..addListener(() {
            _holdHaptics.update(_hold!.value);
            setState(() => holdP = _hold!.value);
          })
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) {
              _holdHaptics.finish();
              finishHold(id, isPing);
            }
          });
    _holdHaptics.start(
      Duration(milliseconds: ((seconds ?? holdSeconds) * 1000).round()),
    );
    setState(() {
      holdId = id;
      holdP = 0;
    });
    _hold!.forward();
  }

  /// Rising ticks while holding to unblur — see core/ping_haptics.dart.
  final _holdHaptics = HoldHaptics();

  void endHold() {
    if (_hold != null && _hold!.value < 1) {
      _hold!.stop();
      // Lifting the finger stops the swell mid-way rather than letting it
      // play out — the buzz has to track the gesture.
      _holdHaptics.cancel();
      setState(() {
        holdId = null;
        holdP = 0;
      });
    }
  }

  void finishHold(String id, bool isPing) {
    _holdHaptics.cancel();
    setState(() {
      holdId = null;
      holdP = 0;
      if (isPing) {
        revealed[id] = DateTime.now();
        // EVERY kind of ping reveals into the same compact card now —
        // prompted, promptless, group, anonymous (explicit request,
        // 2026-10-03: "when unblurred at first all shall appear like that
        // with ping back option in the same box"). Nothing auto-opens the
        // full composer any more: the card's own arrow drops it open, so
        // the ping, its time and Ping back never leave the screen.
        final match = kToReply.where((p) => p.id == id);
        if (match.isNotEmpty &&
            (match.first.photoUrl ?? '').isNotEmpty &&
            match.first.photoOpenedAt == null) {
          // They sent a photo with it: unblurring opens the photo itself,
          // full screen, and closing it lands back on the compact card —
          // not on a "Photo viewed" placeholder inside a composer
          // (explicit report, 2026-10-03, with a screenshot of exactly
          // that).
          _openPingPhoto(id);
        }
        // Best-effort — a no-op for any non-UUID seed/group/wall id (the
        // service swallows the resulting error), a real write for a real
        // ping.id. Marks it "seen" from the sender's perspective.
        unawaited(PingService.instance.markSeen(id));
        notifState.markPingsRead();
      } else {
        viewed[id] = true;
        // A revealed reply opens straight into its own full-screen photo
        // viewer (_photoView) — but a wall tile reveals in place (the tile
        // itself becomes the photo, see _wallTile's "seen" branch), so this
        // only fires for a REPLIES-section id, never a wall one.
        if (kReplies.any((r) => r.id == id)) {
          _openPhoto(id);
          unawaited(PingService.instance.markViewed(id));
        } else if (wallSlots.values.any(
          (s) => s.any((sl) => sl.replyId == id),
        )) {
          unawaited(PingService.instance.markWallReplyOpened(id));
          // Group reply: open it full screen, once — like a personal reply.
          final slot = wallSlots.values
              .expand((s) => s)
              .firstWhere((sl) => sl.replyId == id);
          _openWallPhoto(slot);
        }
      }
    });
  }

  /// Consumes [pingFocusRequest] the moment it's set (a ping/photoReply
  /// notification tap; see MainShell._onOpenPingNotif) or, called from
  /// initState, catches one that was already pending before this screen's
  /// first frame. Waits for a fresh load before looking the id up — the
  /// caller may switch tabs into a PingPage that hasn't fetched anything
  /// yet — then reveals that ping's card exactly the way holding it in the
  /// feed does ([_toReplyItem]'s revealed branch). A group
  /// ping is just another row in [kToReply] (see its own doc on why group
  /// and person pings share one list), so no separate wall lookup is
  /// needed. If the ping isn't found — already answered and aged out of
  /// "to reply", or the fetch raced and lost — this degrades to exactly
  /// where the tab switch alone would have left it.
  /// One key per wall card, so a fresh group ping can scroll to its wall.
  final Map<String, GlobalKey> _wallKeys = {};

  /// Thread ids whose asker-attached photo I've tapped to reveal in
  /// [_wallPhotoPingBack], this session. Local-only, like every other blur
  /// toggle on this page — the photo was already visible to the whole
  /// group before this feature existed, so re-blurring it between app
  /// opens would be a change in privacy this ping never had, not a bug fix.
  final Set<String> _wallPhotoRevealed = {};

  /// Which Group Wall card is expanded — at most one at a time (explicit
  /// request, 2026-10-01: "only one group wall shall be open at once,
  /// others shall be in shrinked [collapsed] stay as of initially").
  /// Null = every wall collapsed, which is the starting state; tapping a
  /// wall's header sets this to its threadId, which both expands it and
  /// collapses whichever other one was open (only one id can match).
  String? _openWallId;

  /// See [groupWallAnswerRequest]. Cleared only after the reload, so
  /// MainShell's own listener still sees the id and switches tabs.
  Future<void> _onGroupAnswerRequested() async {
    final groupId = groupWallAnswerRequest.value;
    if (groupId == null) return;
    // The sender just saw the points card drop in (ping_prompt_sheet's
    // reward overlay, ~1.5s on the root overlay) — the camera waits it out
    // rather than opening underneath it.
    final minWait = Future<void>.delayed(const Duration(milliseconds: 1900));
    await _loadRealPingData();
    if (groupWallAnswerRequest.value == groupId) {
      groupWallAnswerRequest.value = null;
    }
    if (!mounted) return;
    final walls = wallThreads.where((t) => t.groupId == groupId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (walls.isEmpty) return;
    await _openWallFlow(walls.first, before: minWait);
  }

  /// True when a group ping needs no crafted reply at all — a promptless
  /// ask ("pinged the group 👋") or one where the asker attached their own
  /// photo (explicit request: "if i have pinged using a photo... no need
  /// to reply again... ping back option for other users to immediately
  /// ping back"). Every place that used to gate on "promptless" alone now
  /// goes through this — a photo-only ask gets exactly the same zero-
  /// pressure treatment as a promptless one.
  bool _wallSkipsReply(WallThread t) =>
      t.prompt.trim().isEmpty || (t.photoUrl ?? '').isNotEmpty;

  /// The one group-ping flow (explicit request, "always the same"): scroll to
  /// the group's wall and, if I haven't answered yet, open the camera for my
  /// photo — posting it unlocks the wall right there. Used when I send a
  /// group ping, and as the landing spot AFTER I've answered one I received —
  /// a group ping's card still opens the same reply composer a person ping
  /// does (ping-back pill included; see _toReplyItem), and only once that
  /// reply/ping-back succeeds does this run, same as the pre-existing
  /// _expandedCard send handler already did for a full camera/text reply
  /// (explicit correction: "after ping ging back or replying them via the
  /// camera or sending a photo the group wall opens as such").
  Future<void> _openWallFlow(WallThread t, {Future<void>? before}) async {
    // Expand it before scrolling to it — landing on a collapsed card right
    // after sending/answering a group ping would hide the very thing this
    // flow is trying to show.
    if (mounted && _openWallId != t.threadId) {
      setState(() => _openWallId = t.threadId);
    }
    await WidgetsBinding.instance.endOfFrame;
    final ctx = _wallKeys[t.threadId]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
    // Already answered (e.g. a second tap) — the wall itself is the answer.
    if (!mounted || t.unlocked || t.myPingId == null) return;
    // Nothing to answer with a camera — the wall's own "Ping back" is
    // right there (zero pressure).
    if (_wallSkipsReply(t)) return;
    if (before != null) await before;
    if (!mounted) return;
    await _openWallCamera(t);
  }

  Future<void> _onPingFocusRequested() async {
    final id = pingFocusRequest.value;
    if (id == null) return;
    pingFocusRequest.value = null;
    await _loadRealPingData();
    if (!mounted) return;
    // Group-wall notifications carry the wall's thread id rather than a
    // ping id — accept either, so a group ping opens its own card too.
    final match = kToReply.where((p) => p.id == id || p.threadId == id);
    // A GROUP ping follows the group flow: its wall, then my photo.
    final threadId = match.isNotEmpty ? match.first.threadId : id;
    final wall = wallThreads.where((t) => t.threadId == threadId);
    if (wall.isNotEmpty && (match.isEmpty || match.first.isGroup)) {
      await _openWallFlow(wall.first);
      return;
    }
    if (match.isNotEmpty) {
      // Explicit request, 2026-09-29 ("opening ping notification of
      // someone else shall open directly camera"): a notification tap
      // skips the expanded card entirely and goes straight to the shutter
      // — snap, and it sends itself, no caption step. Opening the SAME
      // card by hand (not from a notification) still expands it first, so
      // that path keeps its caption option exactly as it was.
      // A promptless ping just reveals its card (Ping back is one tap
      // there, and its camera button is the photo answer) rather than
      // opening the old composer, which no longer exists.
      if (match.first.promptless) {
        setState(() => revealed[match.first.id] = DateTime.now());
      } else {
        unawaited(_quickReplyFromNotification(match.first));
      }
    }
  }

  /// The camera-first fast lane for replying to an incoming ping, reachable
  /// ONLY from tapping its notification (see [_onPingFocusRequested] — a
  /// hand-tapped card still goes through the normal expand → capture →
  /// caption → Send flow in [_expandedCard]/[_openCamera]).
  ///
  /// User's own framing: "tapping an incoming Ping notification should
  /// bypass the app's home screen completely and open the camera
  /// viewfinder immediately... snap the picture in one tap, and it flies
  /// back. Total time spent: less than 3 seconds." MainShell already lands
  /// on this screen and focuses the right card (see pingFocusRequest's own
  /// doc); this is the rest of it — no expanded card to read, no caption to
  /// type, the photo IS the reply.
  Future<void> _quickReplyFromNotification(InboundPing p) async {
    // Same guard _expandedCard's own Send button uses — a block that
    // landed after the notification was sent must still be honoured.
    final senderId = p.senderId;
    if (senderId != null &&
        await BlockService.instance.isBlockedWith(senderId)) {
      if (mounted) {
        showPingToast(context, "You can't reply to this ping.");
      }
      return;
    }
    if (!mounted) return;
    final capture = await showModalBottomSheet<PingCapture?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PingCameraScreen(recipientName: p.senderName),
    );
    // Backed out of the camera — same as never having tapped the
    // notification's fast lane; the card is still there to answer by hand.
    if (capture == null || !mounted) return;

    final overlay = Overlay.of(context);
    final streakBefore = _streakWith(p.senderId);
    // Stamped before the write, same ordering every other reward overlay
    // in this file uses.
    final mark = ScoreGainService.mark();

    Future<void> send() async {
      // Hold-to-record video answer (2026-10-06): upload the clip and send
      // it as the reply — no selfie inset, there is no second lens shot.
      final video = capture.video;
      if (video != null) {
        final videoUrl = await StorageService.uploadPingVideo(
          file: File(video.path),
          pingId: p.id,
        );
        if (videoUrl == null) {
          throw StateError('Video upload failed');
        }
        await PingService.instance.reply(
          pingId: p.id,
          videoUrl: videoUrl,
          videoMs: capture.videoMs,
        );
        return;
      }
      final photoUrl = await StorageService.uploadPingPhoto(
        file: File(capture.photo.path),
        pingId: p.id,
      );
      if (photoUrl == null) {
        throw StateError('Photo upload failed');
      }
      String? selfieUrl;
      final selfie = capture.selfie;
      if (selfie != null) {
        // Best-effort — a missing selfie inset is cosmetic; the reply
        // itself must not be blocked on it.
        selfieUrl = await StorageService.uploadPingSelfie(
          file: File(selfie.path),
          pingId: p.id,
        );
      }
      await PingService.instance.reply(
        pingId: p.id,
        photoUrl: photoUrl,
        selfieUrl: selfieUrl,
      );
    }

    // The reward buzz fires NOW, with the tap — it used to wait for the
    // upload and the insert to finish, which felt like a lag (explicit
    // report, 2026-10-03: "after clicking send the vibration has a time
    // lag"). A failed send still says so with its own error toast.
    unawaited(pingReward());
    // The card leaves TO REPLY the moment the shot is taken (explicit
    // request, 2026-10-03: "sending photo shall immediately make it
    // disappear from to reply"). Recording the reply locally is what makes
    // _alreadyReplied true; the upload runs behind it, and a failure puts
    // the card back.
    setState(() {
      _bumpScore();
      (sentReplies[p.id] ??= []).add('photo only');
    });
    final write = send();
    // Same "same drop down as the anon post" reward surface every other
    // ping reply in this file uses.
    showScoreRewardOverlay(
      overlay: overlay,
      large: true,
      loadGain: () async {
        try {
          await write;
        } catch (_) {
          return null;
        }
        return ScoreGainService.instance.since(mark);
      },
    );
    write
        .then((_) async {
          if (!mounted) return;
          await _loadRealPingData();
          if (!p.isGroup) {
            _announceStreak(p.senderId, p.senderName, streakBefore, 'Sent ✓');
          }
          // Group ping: same flow as every other group ping — my photo is
          // in, so land on the (now open) wall next.
          if (!mounted || !p.isGroup) return;
          final wall = wallThreads.where((t) => t.threadId == p.threadId);
          if (wall.isNotEmpty) await _openWallFlow(wall.first);
        })
        .catchError((Object e) {
          if (!mounted) return;
          // Nothing went out — put the card back so it can be answered.
          setState(() {
            sentReplies[p.id]?.remove('photo only');
            if (sentReplies[p.id]?.isEmpty ?? false) sentReplies.remove(p.id);
          });
          showPingToast(
            context,
            "Couldn't send that photo — try again.",
            isError: true,
          );
        });
  }

  /// See [pingTabActive]'s own doc — the poll/realtime reload are skipped
  /// while Ping isn't on screen, so this is what makes switching TO it
  /// never show data that's up to 20s (or more) stale.
  void _onPingTabActiveChanged() {
    if (pingTabActive.value) {
      unawaited(_loadRealPingData());
      // The badge is real unread-count data (unreadPings) but nothing ever
      // cleared it by opening the tab (explicit report, 2026-10-02: "the 9+
      // and notifications aren't changing at all").
      notifState.markPingsRead();
      return;
    }
    // LEAVING the tab deliberately changes NOTHING.
    //
    // A revealed ping stays revealed ("if i go to home page and come back
    // the ping to reply is again blurred — it shall not be blurred"), so
    // coming back lands on the same cards, not a fresh set of blurs.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hold?.dispose();
    _photoTimer?.dispose();
    _authSub?.cancel();
    _reloadDebounce?.cancel();
    _pollTimer?.cancel();
    _pingChannel?.unsubscribe();
    _replyCtrl.dispose();
    pingFocusRequest.removeListener(_onPingFocusRequested);
    groupWallAnswerRequest.removeListener(_onGroupAnswerRequested);
    pingTabActive.removeListener(_onPingTabActiveChanged);
    super.dispose();
  }

  String windowLeft(DateTime at) {
    final ms = at
        .add(const Duration(hours: 3))
        .difference(DateTime.now())
        .inMilliseconds;
    if (ms <= 0) return 'window closed';
    final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// The one prompt-picker used everywhere a ping goes out (deviation #1 —
  /// replaces the reference's inline compose sheet).
  ///
  /// Exactly one of [groupId] (a real group ping, fanned out via
  /// PingService.sendGroupPing), [pingBackPingId] (ping-backing an
  /// anonymous sender — the server resolves who from the ping itself, since
  /// the caller can't), or [targetId] (a real person, [anon] or not) should
  /// be set for a real write; all three come from kFriends/kGroups/
  /// kToReply/kReplies, now loaded for real from CircleService/
  /// GroupService/PingService. When none are set (e.g. the still-local
  /// _createGroupThenPing flow, which doesn't create a real group), the
  /// send stays exactly as local-only as it always was.
  /// A group only I have joined (everyone else still invited) can't be
  /// pinged — send_group_ping refuses it server-side too.
  bool _groupWaitingForMembers(String groupId) {
    for (final g in kGroups) {
      if (g.id == groupId) return g.count < 2;
    }
    return false;
  }

  /// Pings [receiverId] right now — no sheet, no prompt (user decision,
  /// 2026-09-30: "no prompt for ping in friends feed and ping page, except
  /// Dip... pinging a person directly pings him, with a drop down saying
  /// pinged X"). Sends prompt '' ; the receiver's card offers ping back /
  /// photo / text. The existing rules still apply server-side — 5 per day,
  /// one open ping per person, blocks — and each refusal says why.
  ///
  /// [pingBack]: this answers someone who pinged / replied to me — sent via
  /// send_ping_back so their push reads "X pinged you back" (explicit
  /// request, 2026-10-02).
  /// Ping sends in flight — a second tap on the same face is ignored
  /// rather than queued (explicit report, 2026-10-03: "the things are
  /// slow, I am clicking it several times"). Cleared on completion.
  final Set<String> _pingInFlight = {};

  Future<void> _pingNow(
    String receiverId,
    String name, {
    bool pingBack = false,
  }) async {
    if (!_pingInFlight.add(receiverId)) return;
    // Pinging someone and pinging them back feel the SAME — one thud
    // either way (explicit request, 2026-10-03). The bigger reward buzz is
    // for actually answering with a photo or words.
    unawaited(pingThud());
    final before = _streakWith(receiverId);
    // Everything the eye needs happens NOW, before the network: the face
    // leaves the strip (it can't be pinged again until the window closes,
    // so it would vanish on the next load anyway) and the toast drops in.
    // The old order waited for the insert AND a full reload first, which
    // is what read as "slow" and drew repeat taps.
    final removed = <int, Friend>{};
    setState(() {
      for (var i = kFriends.length - 1; i >= 0; i--) {
        if (kFriends[i].id == receiverId) {
          removed[i] = kFriends.removeAt(i);
        }
      }
      _openSentTo.add(receiverId);
    });
    showPingToast(context, pingBack ? 'Pinged $name back ✓' : 'Pinged $name ✓');
    try {
      if (pingBack) {
        await PingService.instance.sendPingBack(receiverId);
      } else {
        await PingService.instance.send(receiverId: receiverId, prompt: '');
      }
      if (!mounted) return;
      await _loadRealPingData();
      if (!mounted) return;
      // Only worth saying if the streak actually moved — the "Pinged X"
      // confirmation already went out above.
      final after = _streakWith(receiverId);
      if (after > before) {
        _announceStreak(receiverId, name, before, '');
      }
    } on Object catch (e) {
      if (!mounted) return;
      // Put the face (and its loop row) back — it was never pinged.
      setState(() {
        _openSentTo.remove(receiverId);
        final entries = removed.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final e in entries) {
          kFriends.insert(e.key.clamp(0, kFriends.length), e.value);
        }
      });
      showPingToast(
        context,
        e is PingLimitExceeded ||
                e is PingAlreadyOpen ||
                e is PingSelfNotAllowed ||
                e is PingBlocked
            ? e.toString()
            : "Couldn't ping $name.",
        isError: true,
      );
    } finally {
      _pingInFlight.remove(receiverId);
    }
  }

  /// Pings a whole group right now, no prompt. Same rules as ever
  /// server-side (members only, not while nobody else has joined, the daily
  /// limit). Then the usual group flow: scroll to its wall.
  Future<void> _pingGroupNow(String groupId, String name) async {
    if (_groupWaitingForMembers(groupId)) {
      showPingToast(context, 'Waiting for members to join $name');
      return;
    }
    unawaited(pingThud());
    // Same instant feedback as a person: the chip leaves the strip and the
    // toast drops now, not after the round trip.
    final removed = <int, PingGroup>{};
    setState(() {
      for (var i = kGroups.length - 1; i >= 0; i--) {
        if (kGroups[i].id == groupId) removed[i] = kGroups.removeAt(i);
      }
    });
    showPingToast(context, 'Pinged $name ✓');
    try {
      final count = await PingService.instance.sendGroupPing(
        groupId: groupId,
        prompt: '',
      );
      if (!mounted) return;
      if (count == 0) {
        showPingToast(context, 'No one else to ping yet');
      } else {
        groupWallAnswerRequest.value = groupId;
      }
    } on Object catch (e) {
      if (!mounted) return;
      // Nothing went out — put the chip back.
      setState(() {
        final entries = removed.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final en in entries) {
          kGroups.insert(en.key.clamp(0, kGroups.length), en.value);
        }
      });
      showPingToast(
        context,
        e is PingLimitExceeded || e is PingGroupWaitingForMembers
            ? e.toString()
            : "Couldn't ping $name.",
        isError: true,
      );
    }
  }

  /// One-tap answer on a promptless group wall — a '👋' wall reply, which
  /// unlocks the wall like any answer.
  Future<void> _wallPingBack(WallThread t) async {
    final myPingId = t.myPingId;
    if (myPingId == null) return;
    // A ping back feels like a ping, not like a full reply (explicit
    // request, 2026-10-03) — same thud either way.
    unawaited(pingThud());
    try {
      await PingService.instance.replyToWall(
        pingId: myPingId,
        body: kPingBackBody,
      );
    } catch (_) {
      if (mounted) showPingToast(context, "Couldn't ping back.", isError: true);
      return;
    }
    if (!mounted) return;
    setState(_bumpScore);
    await _loadRealPingData();
    if (mounted) showPingToast(context, 'Pinged ${t.groupName} back ✓');
  }

  /// My ping streak with [userId], as last loaded (my_ping_streaks via
  /// kFriends). 0 when unknown or not a friend.
  int _streakWith(String? userId) {
    if (userId == null) return 0;
    for (final f in kFriends) {
      if (f.id == userId) return f.streak;
    }
    return 0;
  }

  /// Right after a reply (ping back, photo or text) lands and the page has
  /// reloaded: "Started a streak" / "Streak … increased to N" when it went
  /// up, else [fallback] — the blue-hemmed ping toast (explicit request,
  /// 2026-10-02: "it shall say started a streak or streak increased 2 like
  /// thing"), not the green glass one used before.
  void _announceStreak(
    String? userId,
    String name,
    int before,
    String fallback,
  ) {
    if (!mounted) return;
    final after = _streakWith(userId);
    final text = before <= 0 && after > 0
        // No 🔥 here: a text toast can only show the orange emoji, and
        // every streak flame in the app is the blue one now.
        ? 'Started a streak with $name'
        : after > before
        ? 'Streak with $name is now $after'
        : fallback;
    if (text.isEmpty) return;
    showPingToast(context, text);
  }

  /// Ping back an ANONYMOUS ping without learning who sent it — the
  /// server resolves the target from the ping id (ping_back_anonymous).
  /// Same one-tap shape, same thud, same instant toast as the named path
  /// (explicit request, 2026-10-03: Ping back on every type of ping).
  Future<void> _pingBackAnon(InboundPing p) async {
    if (!_pingInFlight.add(p.id)) return;
    unawaited(pingThud());
    setState(() => pingedBack[p.id] = true);
    showPingToast(context, 'Pinged back ✓');
    try {
      await PingService.instance.pingBackAnonymous(pingId: p.id, prompt: '');
      if (mounted) await _loadRealPingData();
    } catch (_) {
      if (!mounted) return;
      setState(() => pingedBack.remove(p.id));
      showPingToast(context, "Couldn't ping back.", isError: true);
    } finally {
      _pingInFlight.remove(p.id);
    }
  }

  /// The one-tap answer to a promptless ping — a '👋' text reply, which
  /// closes the ping (counts for the streak) and reaches the sender as
  /// "X pinged you back".
  Future<void> _pingBackReply(InboundPing p) async {
    if (!_pingInFlight.add(p.id)) return;
    final senderId = p.senderId;
    // Ping back == the same single thud as sending a ping (explicit
    // request, 2026-10-03). The reward swell is kept for a real reply
    // (photo/words).
    unawaited(pingThud());
    final before = _streakWith(senderId);
    // EVERYTHING VISIBLE HAPPENS NOW (explicit report, 2026-10-03: "when
    // clicked ping back the things aren't functioning properly —
    // immediately they shall be pinged and that person shall not be seen
    // again there"). Recording the reply locally makes _alreadyReplied
    // true, which drops this ping out of _waitingToReply, so the card is
    // gone on the same frame as the tap. The block check and the write run
    // behind it, and a failure puts the card back.
    setState(() {
      _bumpScore();
      (sentReplies[p.id] ??= []).add(kPingBackBody);
      pingedBack[p.id] = true;
    });
    showPingToast(
      context,
      p.isGroup ? 'Pinged the group back ✓' : 'Pinged ${p.senderName} back ✓',
    );

    void undo() {
      if (!mounted) return;
      setState(() {
        sentReplies[p.id]?.remove(kPingBackBody);
        if (sentReplies[p.id]?.isEmpty ?? false) sentReplies.remove(p.id);
        pingedBack.remove(p.id);
      });
    }

    try {
      if (senderId != null &&
          await BlockService.instance.isBlockedWith(senderId)) {
        undo();
        if (mounted) {
          showPingToast(
            context,
            "You can't reply to this ping.",
            isError: true,
          );
        }
        return;
      }
      await PingService.instance.reply(pingId: p.id, body: kPingBackBody);
    } catch (_) {
      undo();
      if (mounted) showPingToast(context, "Couldn't ping back.", isError: true);
      return;
    } finally {
      _pingInFlight.remove(p.id);
    }

    if (!mounted) return;
    await _loadRealPingData();
    if (!mounted) return;
    if (p.isGroup) {
      // Same as a full camera/text reply (see _expandedCard's own send
      // handler): a group ping's flow ends on its now-open wall, whether I
      // answered with a photo or just pinged back (explicit request: "after
      // pinging back or replying... the group wall opens").
      final wall = wallThreads.where((t) => t.threadId == p.threadId);
      if (wall.isNotEmpty) await _openWallFlow(wall.first);
      return;
    }
    // The "Pinged X back" confirmation already went out above — only speak
    // again if the streak actually moved.
    if (_streakWith(senderId) > before) {
      _announceStreak(senderId, p.senderName, before, '');
    }
  }

  Future<void> openPromptSheet(
    String targetName, {
    bool anon = false,
    String? targetId,
    String? groupId,
    String? pingBackPingId,
  }) {
    if (groupId != null && _groupWaitingForMembers(groupId)) {
      showPingToast(context, 'Waiting for members to join $targetName');
      return Future.value();
    }
    return showPingPromptSheet(
      context,
      targetName: targetName,
      // The Ping page's own prompt set, separately editable from the
      // friends-feed one — and the group set when pinging a whole group.
      // See PingContext's own doc.
      pingContext: anon
          ? PingContext.anonymous
          : (groupId != null ? PingContext.group : PingContext.pingPage),
      glass: true,
      heightFraction: 0.62,
      roundedTopOnly: true,
      onSentPrompt: (prompt, {photoUrl}) {
        if (!mounted) return null;
        // Captured so both the success and error paths below can find and
        // remove exactly this optimistic tile — it used to be inserted and
        // never cleared either way: a successful send left it sitting
        // alongside the real kSent row it now duplicates, and a failed one
        // left it behind as a permanent phantom "sent" tile despite the
        // error SnackBar telling the user it didn't go through.
        final extraId = 'x${DateTime.now().microsecondsSinceEpoch}';
        setState(() {
          _bumpScore();
          sentExtra.insert(
            0,
            OutboundPing(
              extraId,
              targetName,
              targetName.isEmpty ? '?' : targetName[0].toUpperCase(),
              prompt,
              false,
            ),
          );
        });

        void removeExtra() {
          if (mounted) {
            setState(() => sentExtra.removeWhere((p) => p.id == extraId));
          }
        }

        // Rethrows after toasting (Never, not Null): a failed send must
        // never let the reward overlay open claiming "+0" — see
        // score_reward_dropdown.dart's _run, which treats any exception out
        // of onSentPrompt as "nothing to celebrate" and shows nothing at
        // all. Explicit report: "if the ping was unsuccessful... the score
        // card shall not open and show zero point".
        Never showError(Object e) {
          removeExtra();
          // _NothingToPing already put its own, more specific message on
          // screen (e.g. "No one else to ping yet") right before throwing —
          // this generic toast would otherwise stack a second, confusing
          // "Couldn't send that ping." on top of it.
          if (e is! _NothingToPing && mounted) {
            showPingToast(
              context, // Each carries a real reason worth showing — a rate
              // limit, an already-open ping and when it frees up, a
              // self-ping attempt, a block either direction, or a
              // ping-back already spent on this original ping.
              // Anything else stays generic.
              e is PingLimitExceeded ||
                      e is PingAlreadyOpen ||
                      e is PingSelfNotAllowed ||
                      e is PingBlocked ||
                      e is PingBackAlreadyUsed
                  ? e.toString()
                  : "Couldn't send that ping.",
            );
          }
          throw e;
        }

        // Each branch RETURNS its future. onSentPrompt is a FutureOr and the
        // sheet awaits it before reading what the ping earned — a fire-and-
        // forget `.then()` here (which is what this was) meant the score was
        // read before the `pings` row existed, so the read came back +0 and
        // the reward never appeared. Reported as "there is no drop down for
        // pinging anyone".
        if (groupId != null) {
          // A real group — fans out to every member (see PingService's own
          // doc on why the sender is included when anonymous).
          //
          // BUG FIX (explicit report — "for group pings in the dropdown
          // isn't giving any points"): this comment used to claim group
          // sends "pay nothing by design" because award_ping_sent_score's
          // TRIGGER skips group_id IS NOT NULL rows — true, but irrelevant:
          // send_group_ping has its own direct `ping_score + 25` update,
          // completely separate from that trigger, and it really does fire
          // (once per SEND, not once per fan-out row — verified live: a
          // 3-member group still only paid 25, not 50). The score was never
          // missing. What WAS missing is that send_group_ping never called
          // log_score_event, so ScoreGainService.since() — what this
          // branch's shared reward overlay in ping_prompt_sheet.dart's
          // _send() reads afterward — always saw 0 rows in score_events and
          // correctly rendered nothing for a real, non-zero gain. Fixed
          // server-side (20260926000000_group_ping_sent_score_event.sql);
          // no client change needed here, since _send() already wraps
          // EVERY onSentPrompt branch in the same overlay generically.
          return PingService.instance
              .sendGroupPing(groupId: groupId, prompt: prompt, anonymous: anon)
              .then((count) {
                if (!mounted) return;
                removeExtra();
                showPingToast(
                  context,
                  count > 0
                      ? 'Pinged $count member${count == 1 ? '' : 's'}'
                      : 'No one else to ping yet',
                );
                // Same flow as every group ping: post mine, then the wall.
                if (count > 0) {
                  groupWallAnswerRequest.value = groupId;
                } else {
                  // Nobody was actually pinged — nothing to reward, same
                  // rule as every other zero-send case. The snackbar above
                  // already said "No one else to ping yet"; this sentinel
                  // (caught by showError below) only tells the reward
                  // overlay to stay shut, without a second toast on top.
                  throw const _NothingToPing();
                }
              })
              .catchError(showError);
        } else if (pingBackPingId != null) {
          // Ping-backing the sender of an anonymous ping I already replied
          // to — the server resolves who that is; I never do.
          //
          // _loadRealPingData() is fire-and-forget (not chained via .then),
          // matching the reply-flow's own pattern below. This used to be
          // `.then((_) => _loadRealPingData()).then((_) => removeExtra())`,
          // which is what this function RETURNS — and _send() in
          // ping_prompt_sheet.dart awaits exactly that return value before
          // reading ScoreGainService.since(mark) for the reward overlay.
          // The full page refetch (8+ parallel requests, then two more
          // nested Future.waits) is unrelated to what the ping earned, so
          // gating the overlay on it made a real +25/+20 arrive so late it
          // was easy to miss entirely — reported as "isn't displaying
          // points". The write itself (and its trigger-fired score row) is
          // already committed by the time this .then fires; removeExtra()
          // no longer needs to wait on the refetch either.
          return PingService.instance
              .pingBackAnonymous(
                pingId: pingBackPingId,
                prompt: prompt,
                anonymous: anon,
              )
              .then((_) {
                unawaited(_loadRealPingData());
                removeExtra();
              })
              .catchError(showError);
        } else if (targetId != null) {
          // A real person, named or anonymous — anon just flips the flag
          // now, rather than skipping the write entirely (that used to
          // silently drop every anonymous ping on the floor).
          //
          // Pre-checked client-side so a blocked send fails fast with the
          // same specific message send_ping's own server-side rejection
          // now maps to (PingBlocked, above) — rather than waiting on a
          // round trip just to hit that same rejection. The server check
          // (send_ping's own, plus the RESTRICTIVE policies in
          // 20260920230100_ping_block_enforcement.sql) is what actually
          // enforces this; this is purely a faster, clearer failure for
          // the common case, not a second source of truth.
          return BlockService.instance.isBlockedWith(targetId).then((blocked) {
            if (blocked) return showError(const PingBlocked());
            // Same fire-and-forget fix as pingBackPingId above — see that
            // branch's own doc for the full reasoning.
            return PingService.instance
                .send(receiverId: targetId, prompt: prompt, anonymous: anon)
                .then((_) {
                  unawaited(_loadRealPingData());
                  removeExtra();
                })
                .catchError(showError);
          });
        }
        // No target of any kind (e.g. a still-loading group chip) — nothing
        // was actually sent, so the optimistic tile shouldn't linger as if
        // it was, and nothing was earned either.
        removeExtra();
        throw StateError('no target to ping');
      },
    );
  }

  /// Receivers I currently hold an open (unexpired) 1:1 ping to — they
  /// can't be pinged again until it closes. Filled from fetchSent on every
  /// load.
  Set<String> _openSentTo = {};

  @override
  Widget build(BuildContext ctx) {
    final s = Scale(MediaQuery.of(ctx).size.width);
    final safeTop = MediaQuery.of(ctx).padding.top;
    final safeBottom = MediaQuery.of(ctx).padding.bottom;

    // A background reload can drop the row an open photo viewer belongs to.
    // The overlay then vanishes mid-hold, the finger's release never reaches
    // it, and the page was left in immersive mode with a stopped countdown.
    // Close it properly instead.
    final orphanedPhoto =
        (photoViewId != null && !kReplies.any((r) => r.id == photoViewId)) ||
        (pingPhotoViewId != null &&
            !kToReply.any((p) => p.id == pingPhotoViewId));
    if (orphanedPhoto) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (photoViewId != null && !kReplies.any((r) => r.id == photoViewId)) {
          _closePhoto();
        }
        if (pingPhotoViewId != null &&
            !kToReply.any((p) => p.id == pingPhotoViewId)) {
          _closePingPhoto();
        }
      });
    }

    return Stack(
      children: [
        const _Ambient(),
        Positioned.fill(
          // Pull-to-refresh: re-runs the same fetch initState does, so a
          // ping someone sent you while this tab was already open shows up
          // without leaving and coming back.
          child: RefreshIndicator(
            onRefresh: _loadRealPingData,
            color: Colors.white,
            backgroundColor: const Color(0xFF141418),
            child: SingleChildScrollView(
              // AlwaysScrollable so a short page (few pings) can still be
              // overscrolled far enough to trigger the indicator.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: safeTop + s(12),
                bottom: safeBottom + s(46),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(s),
                  _pingSomeone(s),
                  // BUG FIX (explicit report — "opens empty, loads a few
                  // seconds later, shall be instant"): see
                  // _firstLoadPending's own doc. While the first
                  // _loadRealPingData() is still in flight, show a plain
                  // loading placeholder here instead of every section's own
                  // "0 waiting"/empty look, which read as though there was
                  // simply nothing rather than a fetch still in progress.
                  if (_firstLoadPending)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: s(60)),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: kCyan,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    _toReplySection(s),
                    _repliesSection(s),
                    _myReplyReactionsSection(s),
                    // One card per multi-person send — every recipient's
                    // reply fills its own slot in the same box.
                    for (final t in _multiThreadIds) _multiCard(s, t),
                    _sentSection(s),
                  ],
                  Padding(
                    padding: EdgeInsets.only(
                      left: s(22),
                      right: s(22),
                      top: s(6),
                    ),
                    child: Center(
                      child: Text(
                        'that’s everything · no feed, no streaks',
                        style: ts(s, weight: 400, size: 10.5, color: txt(.2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Guarded on the row still existing, not just the id being set — a
        // background reload (realtime/poll) can replace kReplies out from
        // under an open overlay (e.g. the row expired, or a fetch failure
        // used to come back as an indistinguishable empty list — see
        // PingService's own doc on why that no longer happens). Silently
        // closing beats _detail/_photoView's old unguarded firstWhere(),
        // which threw and blanked the whole screen.
        if (replyDetailId != null && kReplies.any((r) => r.id == replyDetailId))
          _detail(s),
        if (photoViewId != null && kReplies.any((r) => r.id == photoViewId))
          _photoView(s),
        if (pingPhotoViewId != null &&
            kToReply.any((p) => p.id == pingPhotoViewId))
          _pingPhotoView(s),
        if (wallPhotoSlot != null) _wallPhotoView(s, wallPhotoSlot!),
      ],
    );
  }

  // ---------- HEADER ----------
  Widget _header(Scale s) {
    // The shared 7-level ladder, not this page's own three hand-written
    // thresholds (700/400 "Deeply Present"/"Showing Up"/"Getting Started")
    // — that was a third competing tier model on top of ScoreTier and
    // kAnonTiers, all describing the same user.
    final tierLabel = tierInfoForScore(pingScore).title;
    final tierColor = pingScore >= 700
        ? kGround
        : pingScore >= 300
        ? txt(.85)
        : txt(.5);
    final tierBg = pingScore >= 700
        ? kCyan
        : pingScore >= 300
        ? w(.08)
        : Colors.transparent;
    final tierBorder = pingScore >= 700
        ? kCyan
        : pingScore >= 300
        ? w(.18)
        : w(.14);
    return Padding(
      padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Real campus only (never the old 'BROWN' fake-for-everyone
              // mock) — absent entirely for a non-institutional account,
              // not just blank, since outsiders are allowed in now.
              if ((_campus ?? '').isNotEmpty) ...[
                Text(
                  'CAMPUS · ${_campus!}',
                  style: ts(s, weight: 500, size: 10, em: .22, color: txt(.34)),
                ),
                SizedBox(height: s(5)),
              ],
              Text(
                'Ping',
                style: ts(
                  s,
                  weight: 800,
                  size: 28,
                  lh: 1.15,
                  em: -.03,
                  color: kText,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$pingScore',
                    style: ts(
                      s,
                      weight: 800,
                      size: 21,
                      lh: 1,
                      em: -.02,
                      color: kText,
                    ),
                  ),
                  SizedBox(width: s(5)),
                  Text(
                    'score',
                    style: ts(s, weight: 400, size: 10, color: txt(.34)),
                  ),
                ],
              ),
              SizedBox(height: s(5)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: s(9), vertical: s(3)),
                decoration: BoxDecoration(
                  color: tierBg,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: tierBorder, width: 1),
                ),
                child: Text(
                  tierLabel,
                  style: ts(
                    s,
                    weight: 500,
                    size: 10,
                    em: .04,
                    color: tierColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- PING SOMEONE ----------
  // The two horizontal rows run edge to edge (explicit report: the page's
  // side margins clipped them 22pt short of the screen, reading as a strip
  // blocking the rest of the row). Only the header keeps the margins; the
  // rows carry them as scroll padding instead, so they line up at rest and
  // scroll fully off both edges.
  Widget _pingSomeone(Scale s) => Padding(
    padding: EdgeInsets.only(bottom: s(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(10)),
          child: Text(
            'PING SOMEONE',
            style: ts(s, weight: 500, size: 11, em: .18, color: txt(.4)),
          ),
        ),
        SizedBox(
          height: s(84),
          child: kFriends.isEmpty
              ? Center(
                  child: Text(
                    'Add people to your Friends circle to ping them',
                    style: ts(s, weight: 400, size: 12.5, color: txt(.4)),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: s(22)),
                  children: [
                    for (final f in kFriends) ...[
                      _friendTile(s, f),
                      SizedBox(width: s(14)),
                    ],
                  ],
                ),
        ),
        // The community-members row that used to sit here moved to the
        // "Pinned" panel, under "Pin someone" — explicit correction:
        // "remove from your community bar in the ping page... below pin
        // someone shall be the list of all the members of the community
        // the user has joined". kCommunityMembers is still loaded here and
        // read by that panel.
        SizedBox(height: s(14)),
        // Edge to edge like the friend row (the old trailing fade, added
        // to soften the margin's hard cut, read as a blocking strip itself).
        SizedBox(
          height: s(46),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: s(22)),
            // No "New group" chip here any more (explicit request,
            // 2026-10-03: "remove new group thing") — this row is just the
            // groups you can ping right now.
            children: [
              for (final g in kGroups) ...[
                _groupChip(s, g),
                SizedBox(width: s(10)),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _friendTile(Scale s, Friend f) => SpringTap(
    // Tapping a DP pings that person right now, no picker in between
    // (explicit request, 2026-10-02: "no multiple people selecting and
    // pinging now... clicking on their dp pings them automatically").
    onTap: () => _pingNow(f.id, f.who),
    child: SizedBox(
      width: s(56),
      child: Column(
        children: [
          SizedBox(
            width: s(52),
            height: s(52),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: s(52),
                  height: s(52),
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: g160(
                      kEarth[f.tintIndex][0],
                      kEarth[f.tintIndex][1],
                    ),
                    border: Border.all(color: w(.14), width: 1),
                  ),
                  // Real DP when there is one; the initial+tint circle is
                  // the fallback, not the default. See Friend.avatarUrl.
                  // The gradient stays as the backdrop so a slow/failed
                  // image load never flashes an empty hole.
                  child: (f.avatarUrl == null || f.avatarUrl!.isEmpty)
                      ? Text(
                          f.initial,
                          style: ts(
                            s,
                            weight: 500,
                            size: 16,
                            color: kDarkOnCyan,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: f.avatarUrl!,
                          fit: BoxFit.cover,
                          width: s(52),
                          height: s(52),
                          memCacheWidth: 160,
                          placeholder: (_, _) => Text(
                            f.initial,
                            style: ts(
                              s,
                              weight: 500,
                              size: 16,
                              color: kDarkOnCyan,
                            ),
                          ),
                          errorWidget: (_, _, _) => Text(
                            f.initial,
                            style: ts(
                              s,
                              weight: 500,
                              size: 16,
                              color: kDarkOnCyan,
                            ),
                          ),
                        ),
                ),
                // Hidden entirely at 0 — blueFlameStreak renders nothing
                // for a zero streak, which left this decorated container
                // drawing as an empty ghost pill on every friend without
                // one. Reported as "there is no blue flame at all": the
                // data is genuinely 0 for both, but the empty outline
                // still showed.
                if (f.streak > 0)
                  // VARIANT 1A treatment — "in the ping page use the 1a
                  // design for showing the streak". From the Profile Card
                  // handoff (i ui designs/non implemented/README.md): the
                  // badge sits DIRECTLY ON the photo's bottom-right corner
                  // with NO background — "emoji sits directly over the
                  // photo", inset (right: 2, bottom: 2), not hanging off the
                  // edge on a pill.
                  //
                  // What this replaces: a dark pill Container (kGround fill,
                  // 100-radius, 1px border) wrapping the flame, hung OUTSIDE
                  // the avatar at -3/-3. That chrome is what made the streak
                  // read as a blue circular badge with a number rather than
                  // a flame — reported with a screenshot of exactly that.
                  //
                  // BLUE flame, not the 🔥 emoji: an emoji glyph renders in
                  // its own fixed orange and cannot be tinted, so the
                  // one-to-one ping streak was showing warm on the very page
                  // the streak belongs to. Explicit rule: "everywhere the
                  // flame related to ping streaks shall be blue... even in
                  // page." blueFlameStreak also centres the count INSIDE the
                  // flame ("align the number to the center in the fire").
                  //
                  // DEVIATION from 1A's own ratio, stated rather than
                  // silently absorbed: 1A's badge box is 31% of its 168px
                  // photo (52px), which at this 52px avatar would be ~16px —
                  // below blueFlameStreak's 11px number floor, so the count
                  // would fill the whole flame and stop reading as one. Held
                  // at 22 so the number inside stays legible; 1A's static
                  // 👍 carries no number and has no such constraint.
                  Positioned(
                    bottom: s(2),
                    right: s(2),
                    child: PV2Icons.blueFlameStreak(f.streak, flameSize: s(22)),
                  ),
              ],
            ),
          ),
          SizedBox(height: s(6)),
          // Whole name, shrunk to fit — never "…" (explicit request,
          // 2026-10-02). New usernames are capped at 10 so this rarely
          // needs to shrink at all.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              f.who,
              maxLines: 1,
              softWrap: false,
              style: ts(s, weight: 400, size: 10.5, color: txt(.55)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _groupChip(Scale s, PingGroup g) => SpringTap(
    // Instant, promptless group ping (2026-09-30).
    onTap: () => _pingGroupNow(g.id, g.name),
    child: Container(
      padding: EdgeInsets.only(
        left: s(10),
        top: s(8),
        right: s(14),
        bottom: s(8),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: w(.04),
        border: Border.all(color: w(.1), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if ((g.iconUrl ?? '').isNotEmpty)
            // Round, matching the tint-circle fallback this replaces —
            // reverted after a wrong first read of "not square kind of
            // thing" as "make it square"; it meant the opposite.
            Container(
              width: s(24),
              height: s(24),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kGround, width: 1.5),
              ),
              child: CachedNetworkImage(
                imageUrl: g.iconUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                errorWidget: (_, _, _) => ColoredBox(color: w(.1)),
              ),
            )
          else
            SizedBox(
              width: s(24) + s(11) * (g.tintIndices.length - 1),
              height: s(24),
              child: Stack(
                children: [
                  for (int i = 0; i < g.tintIndices.length; i++)
                    Positioned(
                      left: s(11) * i,
                      child: Container(
                        width: s(24),
                        height: s(24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: g160(
                            kEarth[g.tintIndices[i]][0],
                            kEarth[g.tintIndices[i]][1],
                          ),
                          border: Border.all(color: kGround, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          SizedBox(width: s(10)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                g.name,
                style: ts(s, weight: 500, size: 12, color: txt(.88)),
              ),
              SizedBox(height: s(1)),
              Text(
                g.count < 2 ? 'waiting for members' : '${g.count} people',
                style: ts(s, weight: 400, size: 9.5, color: txt(.34)),
              ),
            ],
          ),
          // My streak with this group — same blue flame as a friend's.
          if (g.streak > 0) ...[
            SizedBox(width: s(10)),
            PV2Icons.blueFlameStreak(g.streak, flameSize: s(20)),
          ],
        ],
      ),
    ),
  );

  // ---------- TO REPLY ----------
  /// Only pings still WAITING on a reply. Already-answered ones used to stay
  /// here as a collapsed "You replied" card ("why is the you-replied thing
  /// showing in To Reply"); they leave this section the moment you reply —
  /// the conversation continues under Replies.
  List<InboundPing> get _waitingToReply => [
    for (final p in kToReply)
      if (!_alreadyReplied(p)) p,
  ];

  /// TO REPLY — only pings people/groups sent YOU, split into People and
  /// Groups (explicit request: "groups and people separate, and only those
  /// who pinged you").
  Widget _toReplySection(Scale s) {
    final waiting = _waitingToReply;
    if (waiting.isEmpty) return const SizedBox.shrink();
    final people = [
      for (final p in waiting)
        if (!p.isGroup) p,
    ];
    final groups = [
      for (final p in waiting)
        if (p.isGroup) p,
    ];

    Widget sub(String label, List<InboundPing> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: s(24), right: s(22), bottom: s(8)),
          child: Text(
            label,
            style: ts(s, weight: 500, size: 9.5, em: .16, color: txt(.4)),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(18)),
          child: Column(
            children: [
              for (int i = 0; i < list.length; i++) ...[
                _toReplyItem(s, list[i]),
                if (i < list.length - 1) SizedBox(height: s(12)),
              ],
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TO REPLY',
                style: ts(s, weight: 500, size: 11, em: .18, color: txt(.72)),
              ),
              Text(
                '${waiting.length} waiting',
                style: ts(s, weight: 400, size: 11, color: txt(.3)),
              ),
            ],
          ),
        ),
        if (people.isNotEmpty) sub('PEOPLE', people),
        if (groups.isNotEmpty) sub('GROUPS', groups),
        SizedBox(height: s(12)),
      ],
    );
  }

  /// One box at a time — expanded REPLACES the row, never stacks below it.
  /// True the instant a reply is sent (this session) or was already sent
  /// per the server (myReplies, survives a restart) — a ping now takes
  /// exactly one reply, so its card never reopens the composer again.
  bool _alreadyReplied(InboundPing p) =>
      (sentReplies[p.id]?.isNotEmpty ?? false) || p.myReplies.isNotEmpty;

  Widget _toReplyItem(Scale s, InboundPing p) {
    // A group ping opens the SAME card a person ping does (explicit
    // clarification: "the group's ping shall also appear like this, with
    // ping back button" — any earlier instinct to divert it straight to
    // the wall on tap was wrong). The wall is where the flow ENDS, once a
    // reply or ping-back actually lands — see _pingBackReply's and
    // _expandedCard's send handler's own "the flow ends on its now-open
    // wall" tail.
    if (_alreadyReplied(p)) return _repliedCollapsed(s, p);
    // No hold-to-unblur on an incoming ping any more (explicit request,
    // 2026-10-07: "when someone pings no need of unblurring, it shall be
    // visible, and when clicked on it they can view the image"). Every ping
    // shows as its plain card straight away; a photo it carries opens from
    // the card's own photo button (see _pingPhotoButton). The blurred,
    // hold-anywhere row this used to start as is gone.
    return _revealedCollapsed(s, p);
  }

  /// The sender's name is already the line above, so a promptless card
  /// doesn't repeat it.
  // No hand emoji on a plain ping-back any more — reserved for an actual
  // photo reply (explicit request, 2026-10-02: "no need of showing that
  // hand emoji in replies ... only show when if they have sent a photo").
  /// What a card actually says.
  ///
  /// A promptless ping used to read a flat "pinged you". It now shows the
  /// cheerful time-of-day greeting the ping already carries (explicit
  /// request, 2026-10-03: "if pinged, let it not be just ping — include an
  /// early morning / a cheerful ping like those words, it shall fit in the
  /// space, first letter capital"). That text comes from pingGreeting() —
  /// "Good morning ☀️", "Hey, what's up?", "Still up? 🌙" — picked by the
  /// ping's own id, so it is short, capitalised and stable per ping. It was
  /// being computed and stored in p.prompt all along and then thrown away
  /// here.
  String _cardLine(InboundPing p) {
    if (!p.promptless) return p.prompt;
    if ((p.photoUrl ?? '').isNotEmpty) {
      return p.isGroup ? 'Sent the group a photo' : 'Sent you a photo';
    }
    // A group's promptless prompt is stored as "Name: greeting" — the name
    // is already the line above, so show just the greeting.
    final line = p.isGroup && p.prompt.contains(': ')
        ? p.prompt.split(': ').skip(1).join(': ')
        : p.prompt;
    final text = line.trim();
    if (text.isEmpty) return p.isGroup ? 'Pinged the group' : 'Pinged you';
    return text;
  }

  Widget _revealedCollapsed(Scale s, InboundPing p) => GestureDetector(
    // BUG FIX (reported: "once opened to reply section it can't be opened
    // again"). This had no `behavior`, so it defaulted to
    // HitTestBehavior.deferToChild — only the actually-painted parts of the
    // Glass card took the tap, and the padding//gaps around its text (most
    // of the card's area) silently swallowed it. Closing the expanded card
    // therefore left a row that only reopened if you happened to hit a
    // glyph. Opaque makes the whole card the target, which is what it
    // always looked like it was.
    behavior: HitTestBehavior.opaque,
    // The card itself opens nothing on a tap — both actions are its own
    // buttons (Ping back, and the camera for a photo answer). A LONG-PRESS
    // on a one-to-one ping reacts to it with a RealMoji (explicit request,
    // 2026-10-03: "for personal one to one pings as well let it be there").
    onLongPress: p.isGroup
        ? null
        : () {
            HapticFeedback.selectionClick();
            showPingRealmojiPicker(
              context,
              pingId: p.id,
              onReacted: () => _loadPingRealmojis(pingIds: [p.id]),
            );
          },
    child: Glass(
      radius: r4(s, 26, 14, 30, 10),
      gradient: g150(kCyan.withValues(alpha: .08), w(.03)),
      border: Border.all(color: kCyan.withValues(alpha: .28), width: 1),
      shadow: [
        BoxShadow(color: blk(.3), blurRadius: s(24), offset: Offset(0, s(6))),
      ],
      // Matches the mockup (explicit request, 2026-10-03, "keeping the box
      // design same, adjust it to this; no need of drop down"):
      //
      //   (avatar)  batman                        [Ping back] (📷)
      //             1h left · anon · "the message"
      //
      // The drop-down is gone. The camera button goes straight to the
      // viewfinder and sends the shot as the reply ("clicking camera
      // directly opens the camera and posting it"), so a photo answer is
      // two taps: camera, shutter.
      child: Padding(
        padding: EdgeInsets.fromLTRB(s(12), s(11), s(11), s(11)),
        child: Row(
          children: [
            avatarCircle(
              s,
              size: 38,
              fontSize: 14,
              initial: p.initial,
              tintIndex: p.tintIndex,
              isAnon: p.isAnon,
            ),
            SizedBox(width: s(11)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(s, weight: 650, size: 14.5, color: kText),
                        ),
                      ),
                      // My RealMoji on this ping, once I've reacted.
                      if ((_pingRealmojis[p.id] ?? const []).isNotEmpty) ...[
                        SizedBox(width: s(6)),
                        PingRealmojiStack(
                          reactions: _pingRealmojis[p.id]!,
                          size: s(17),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: s(2)),
                  // ONE line, always — so every ping card is the same
                  // standard size (explicit request, 2026-10-03: "let all
                  // pings be this size, standard, no changing"). A long
                  // message ends in "…" rather than growing the card.
                  Text(
                    _cardMeta(p),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: ts(
                      s,
                      weight: 400,
                      size: 11.5,
                      lh: 1.3,
                      color: txt(.5),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: s(8)),
            // The photo they sent with the ping: a tap opens it. (It used
            // to open by itself at the end of the hold-to-unblur.)
            if ((p.photoUrl ?? '').isNotEmpty) ...[
              _pingPhotoButton(s, p),
              SizedBox(width: s(7)),
            ],
            // PING BACK on every kind of ping — prompted, promptless,
            // group, anonymous. An anonymous ping has no real id on this
            // side, so it routes through ping_back_anonymous; the button
            // reads the same either way.
            _smallPingBackPill(
              s,
              () => (p.isAnon || p.senderId == null)
                  ? _pingBackAnon(p)
                  : _pingBackReply(p),
            ),
            SizedBox(width: s(7)),
            SpringTap(
              onTap: () => _quickReplyFromNotification(p),
              child: Container(
                width: s(32),
                height: s(32),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(s(11)),
                  color: w(.04),
                  border: Border.all(color: w(.16), width: 1),
                ),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: s(16),
                  color: txt(.85),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// "Photo" on a ping that came with one — tap to see it full screen.
  /// It is still a one-time view (mark_ping_photo_opened burns it on the
  /// server the moment it opens), so afterwards this reads "Viewed" and
  /// does nothing.
  Widget _pingPhotoButton(Scale s, InboundPing p) {
    final viewed = p.photoOpenedAt != null;
    return SpringTap(
      onTap: viewed
          ? () => showPingToast(context, 'You already viewed this photo.')
          : () {
              unawaited(pingThud());
              setState(() => _openPingPhoto(p.id));
            },
      child: Container(
        height: s(32),
        padding: EdgeInsets.symmetric(horizontal: s(10)),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s(11)),
          gradient: viewed ? null : g180(kCyan, kCyanDeep),
          color: viewed ? w(.04) : null,
          border: viewed ? Border.all(color: w(.12), width: 1) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              viewed ? Icons.check_rounded : Icons.image_rounded,
              size: s(14),
              color: viewed ? txt(.4) : kGround,
            ),
            SizedBox(width: s(5)),
            Text(
              viewed ? 'Viewed' : 'Photo',
              style: ts(
                s,
                weight: 600,
                size: 11.5,
                color: viewed ? txt(.4) : kGround,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The line under the name: time, then "anon" if it is one, then the
  /// message itself in quotes — "1h left · anon · \"hey! how was your
  /// day?\"" (the mockup's own format).
  String _cardMeta(InboundPing p) {
    final parts = <String>[
      p.time.replaceAll(' to reply', ''),
      if (p.isAnon) 'anon',
    ];
    final line = _cardLine(p).trim();
    if (line.isNotEmpty) parts.add('"$line"');
    return parts.join(' · ');
  }

  /// A ping I've already answered — one reply is all it takes (explicit
  /// request, 2026-09-30), so this replaces the composer for good instead
  /// of reopening it. Not tappable: there is nothing left to do here.
  Widget _repliedCollapsed(Scale s, InboundPing p) => Glass(
    radius: r4(s, 26, 14, 30, 10),
    gradient: g150(w(.05), w(.02)),
    border: Border.all(color: w(.1), width: 1),
    shadow: [
      BoxShadow(color: blk(.3), blurRadius: s(24), offset: Offset(0, s(6))),
    ],
    child: Padding(
      padding: EdgeInsets.fromLTRB(s(18), s(17), s(20), s(17)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatarCircle(
            s,
            size: 36,
            fontSize: 13,
            initial: p.initial,
            tintIndex: p.tintIndex,
            isAnon: p.isAnon,
          ),
          SizedBox(width: s(13)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.senderName,
                  style: ts(s, weight: 500, size: 13, color: txt(.62)),
                ),
                SizedBox(height: s(5)),
                Text(
                  _cardLine(p),
                  style: ts(s, weight: 500, size: 16, lh: 1.35, color: kText),
                ),
                SizedBox(height: s(9)),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: s(14),
                      color: kCyan.withValues(alpha: .75),
                    ),
                    SizedBox(width: s(6)),
                    Text(
                      'You replied',
                      style: ts(
                        s,
                        weight: 500,
                        size: 11.5,
                        color: kCyan.withValues(alpha: .75),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// Compact "Ping back" pill — deliberately small (explicit request,
  /// 2026-09-30: "not such a big ping back").
  Widget _smallPingBackPill(Scale s, VoidCallback onTap) => SpringTap(
    onTap: onTap,
    child: Container(
      // Sized to sit on the name line (explicit request, 2026-10-03:
      // "move the ping back and the drop down symbol up and reduce the
      // size").
      padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(6)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: kCyan,
      ),
      child: Text(
        'Ping back',
        style: ts(s, weight: 600, size: 11.5, color: kDarkOnCyan),
      ),
    ),
  );

  // ---------- REPLIES ----------
  /// REPLIES only ever lists replies you haven't opened yet. The moment one
  /// is revealed you see the photo (see [_photoView]) and the row is gone for
  /// good — the photo is not re-openable from here. (The OPEN LOOPS rows
  /// that used to offer "Your turn with X" afterwards were removed on
  /// request, 2026-10-07; pinging them again starts from Ping Someone.)
  // Every reply for the whole reply window stays listed here, revealed or
  // not — someone can send several photos before the window closes (see
  // PingService.fetchToReply's own doc on why the ping stays answerable the
  // whole time), and each one should show up as its own "X replied" row for
  // as long as the ping itself is live. Revealing one used to remove it
  // from this list permanently, which meant a second, third, fourth reply
  // from the same person had nothing to show for it beyond the first.
  /// REACTIONS TO YOUR REPLIES — who reacted to a photo or message I sent
  /// back. Its own section because a ping only lives 6 hours: once it
  /// expires, the reply leaves every other list and its reactions had
  /// nowhere left to be seen (reported 2026-10-04). Rows here are driven by
  /// the REACTION's age (7 days), not the ping's.
  Widget _myReplyReactionsSection(Scale s) {
    final rows = _myReplyReactions;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(8)),
          child: Row(
            children: [
              Text(
                'REACTIONS TO YOU',
                style: ts(s, weight: 500, size: 11, em: .18, color: txt(.4)),
              ),
              const Spacer(),
              Text(
                '${rows.length}',
                style: ts(s, weight: 500, size: 11, color: txt(.3)),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                _myReplyReactionRow(s, rows[i]),
                if (i < rows.length - 1) SizedBox(height: s(10)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _myReplyReactionRow(Scale s, MyReplyReactions r) {
    final who = r.reactions.length == 1
        ? r.reactions.first.name
        : '${r.reactions.length} people';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showPingRealmojiReactors(context, r.reactions),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: s(14), vertical: s(11)),
        decoration: BoxDecoration(
          borderRadius: r4(s, 20, 10, 22, 12),
          color: kSurface2,
          border: Border.all(color: w(.05), width: 1),
        ),
        child: Row(
          children: [
            // What they reacted to: the photo I sent, or a words bubble.
            ClipRRect(
              borderRadius: BorderRadius.circular(s(9)),
              child: SizedBox(
                width: s(38),
                height: s(38),
                child: r.isPhoto && (r.photoUrl ?? '').isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: r.photoUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                        errorWidget: (_, _, _) => ColoredBox(color: w(.07)),
                      )
                    : ColoredBox(
                        color: w(.07),
                        child: Icon(
                          r.isPhoto
                              ? Icons.photo_rounded
                              : Icons.chat_bubble_rounded,
                          size: s(16),
                          color: txt(.5),
                        ),
                      ),
              ),
            ),
            SizedBox(width: s(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$who reacted',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(s, weight: 600, size: 13.5, color: kText),
                  ),
                  SizedBox(height: s(2)),
                  Text(
                    r.isGroup
                        ? 'on your answer in ${r.otherName}'
                        : 'on what you sent ${r.otherName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(s, weight: 400, size: 10.5, color: txt(.36)),
                  ),
                ],
              ),
            ),
            SizedBox(width: s(10)),
            PingRealmojiStack(reactions: r.reactions, size: s(24)),
          ],
        ),
      ),
    );
  }

  Widget _repliesSection(Scale s) {
    // A reply is shown ONCE. Opening it removes it from this list for
    // good — explicit request: "after seeing the replies it shall go away,
    // vanish, not seeable again". `viewed` is the in-session map and
    // `viewedInit` is ping_replies.viewed from the server (written by
    // PingService.markViewed the instant it's revealed), so a reply opened
    // in a previous session never comes back either.
    //
    // OPEN LOOPS ("Your turn with X" rows for an already-seen reply) was
    // removed on request, 2026-10-07 — pinging that person again starts
    // from the Ping Someone strip.
    final multi = _multiThreadIds;
    final unseen = kReplies
        .where((r) => !(viewed[r.id] ?? r.viewedInit))
        // A multi-person send's replies live in its card (_multiCard).
        .where((r) => !multi.contains(r.threadId))
        .toList();
    // The group walls live in here too, under the same heading (explicit
    // request + choice, 2026-10-03: merge the group wall into REPLIES) —
    // people's replies first, then each group's wall card. A wall is a
    // reply surface as well: it's where the group's answers land.
    final walls = _visibleWalls;
    if (unseen.isEmpty && walls.isEmpty) return const SizedBox.shrink();
    final unreadCount = unseen.length;
    // UNBLUR ONCE (explicit request, 2026-10-07): the first reply a person
    // sends on a ping is the hold-to-unblur moment; once one of theirs on
    // that ping has been opened, the rest are plain "X replied" rows that
    // open on a tap. See unlockedReplyGroups.
    final unlocked = unlockedReplyGroups<InboundReply>(
      kReplies,
      pingIdOf: (r) => r.pingId,
      replierIdOf: (r) => r.replierId,
      isViewed: (r) => viewed[r.id] ?? r.viewedInit,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REPLIES',
                style: ts(s, weight: 500, size: 11, em: .18, color: txt(.55)),
              ),
              if (unreadCount > 0)
                Text(
                  unreadCount == 1 ? '1 new' : '$unreadCount new',
                  style: ts(s, weight: 400, size: 10, color: txt(.3)),
                ),
            ],
          ),
        ),
        if (unseen.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              left: s(22),
              right: s(22),
              bottom: walls.isEmpty ? s(30) : s(14),
            ),
            child: Column(
              children: [
                for (int i = 0; i < unseen.length; i++) ...[
                  unlocked.contains(
                        replyGroupKey(unseen[i].pingId, unseen[i].replierId),
                      )
                      ? _openableReply(s, unseen[i])
                      : _unviewedReply(s, unseen[i]),
                  if (i < unseen.length - 1) SizedBox(height: s(12)),
                ],
              ],
            ),
          ),
        for (final t in walls) _groupWall(s, t),
      ],
    );
  }

  /// Opens a reply that no longer needs the hold (see _openableReply): a
  /// thud under the finger, then the same viewer the hold lands on.
  void _openReplyByTap(InboundReply r) {
    unawaited(pingThud());
    setState(() {
      viewed[r.id] = true;
      _openPhoto(r.id);
    });
    unawaited(PingService.instance.markViewed(r.id));
  }

  /// A new reply from someone whose first reply on this ping I've already
  /// unblurred: their name, a "replied" mark, and a tap opens it — no hold.
  /// (The replier is always a real, named person, even on a ping that was
  /// sent anonymously: only a ping's SENDER is ever hidden.)
  Widget _openableReply(Scale s, InboundReply r) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _openReplyByTap(r),
    child: Glass(
      radius: r4(s, 26, 14, 30, 10),
      gradient: g150(kCyan.withValues(alpha: .09), w(.03)),
      border: Border.all(color: kCyan.withValues(alpha: .3), width: 1),
      shadow: [
        BoxShadow(color: blk(.3), blurRadius: s(24), offset: Offset(0, s(6))),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: s(18), vertical: s(15)),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                avatarCircle(
                  s,
                  size: 36,
                  fontSize: 13,
                  initial: r.who.isNotEmpty ? r.who[0].toUpperCase() : '?',
                  tintIndex: r.replierId.hashCode.abs() % kEarth.length,
                  isAnon: false,
                ),
                // The "they replied" mark.
                Positioned(
                  right: -s(4),
                  bottom: -s(3),
                  child: Container(
                    width: s(16),
                    height: s(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: g180(kCyan, kCyanDeep),
                      border: Border.all(color: kGround, width: 1.5),
                    ),
                    child: Icon(
                      Icons.reply_rounded,
                      size: s(10),
                      color: kGround,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(width: s(13)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${r.who} replied',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(s, weight: 600, size: 14, color: kText),
                  ),
                  SizedBox(height: s(3)),
                  Text(
                    (r.photoUrl ?? '').isNotEmpty || (r.videoUrl ?? '').isNotEmpty
                        ? 'Tap to open'
                        : 'Tap to read',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(s, weight: 400, size: 12, color: txt(.45)),
                  ),
                ],
              ),
            ),
            Text(
              r.when,
              style: ts(s, weight: 400, size: 10.5, color: txt(.32)),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _unviewedReply(Scale s, InboundReply r) {
    final active = holdId == r.id;
    final pr = active ? holdP : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => startHold(r.id, false),
      onTapUp: (_) => endHold(),
      onTapCancel: endHold,
      child: Glass(
        radius: r4(s, 26, 14, 30, 10),
        gradient: g150(w(.07), w(.03)),
        border: Border.all(color: w(.1), width: 1),
        blurSigma: 11,
        shadow: active
            ? [
                BoxShadow(
                  color: blk(.45),
                  blurRadius: s(40),
                  offset: Offset(0, s(10)),
                ),
                BoxShadow(
                  color: kCyan.withValues(alpha: .1 + .25 * pr),
                  blurRadius: s(18 + 30 * pr),
                ),
              ]
            : [
                BoxShadow(
                  color: blk(.3),
                  blurRadius: s(24),
                  offset: Offset(0, s(6)),
                ),
              ],
        // Same shape as an incoming ping card (_blurredRow): hold anywhere,
        // progress as a bottom hairline, full-width text, just a time.
        // 👋 only when they sent a photo; a plain ping back reads "pinged
        // you back" (explicit request, 2026-10-02).
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: s(18),
                top: s(17),
                right: s(18),
                bottom: active ? s(10) : s(17),
              ),
                child: Row(
                  children: [
                    avatarCircle(
                      s,
                      size: 36,
                      fontSize: 13,
                      initial: r.who.isNotEmpty ? r.who[0].toUpperCase() : '?',
                      tintIndex: r.replierId.hashCode.abs() % kEarth.length,
                      isAnon: false,
                    ),
                    SizedBox(width: s(13)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            r.who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(
                              s,
                              weight: 500,
                              size: 13,
                              color: txt(.62),
                            ),
                          ),
                          SizedBox(height: s(5)),
                          Text(
                            r.photoUrl != null
                                ? 'sent you a photo 👋'
                                : r.body.trim() == kPingBackBody
                                ? 'pinged you back'
                                : 'replied to ${r.prompt}',
                            style: ts(
                              s,
                              weight: 500,
                              size: 16,
                              lh: 1.35,
                              color: kText,
                            ),
                          ),
                          SizedBox(height: s(6)),
                          Text(
                            r.when,
                            style: ts(
                              s,
                              weight: 400,
                              size: 11.5,
                              color: kCyan.withValues(alpha: .75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ),
            if (active)
              Padding(
                padding: EdgeInsets.fromLTRB(s(18), 0, s(18), s(14)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                    height: s(3),
                    child: Stack(
                      children: [
                        DecoratedBox(decoration: BoxDecoration(color: w(.08))),
                        FractionallySizedBox(
                          widthFactor: pr,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: kCyan),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- GROUP WALL ----------
  // Updated design (.dc.html): a single card — overlapping member stack,
  // Locked/Open badge, progress bar, then either the "your turn" composer
  // (locked) or the answer tiles (unlocked), and a PING THE GROUP footer.
  // One of these renders per active thread (see the `for` loop in `build`)
  // — real data from my_group_walls()/get_group_wall(), not the single
  // hardcoded kGroupWall this used to read.
  /// Which Group Wall cards render, in order (explicit requests,
  /// 2026-10-03):
  ///
  ///  * **Only after I've answered.** A group ping I still owe a reply to
  ///    lives in TO REPLY, and only there — its wall appears once my own
  ///    answer (photo, text or ping back) has landed. Walls that never
  ///    need a reply ([_wallSkipsReply] — promptless / photo asks) show
  ///    straight away, since there is nothing to owe.
  ///  * **One wall per group**, newest first — a group that pinged twice
  ///    shows only its latest thread, not two stacked cards.
  List<WallThread> get _visibleWalls {
    final sorted = [...wallThreads]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final out = <WallThread>[];
    final seenGroups = <String>{};
    for (final t in sorted) {
      final slots = wallSlots[t.threadId] ?? const [];
      final mineAnswered = slots.any((sl) => sl.isMe && sl.answered);
      if (!mineAnswered && !_wallSkipsReply(t)) continue;
      if (!seenGroups.add(t.groupId)) continue;
      out.add(t);
    }
    return out;
  }

  Widget _groupWall(Scale s, WallThread t) {
    final slots = wallSlots[t.threadId] ?? const [];
    final answered = t.answered;
    final total = t.total;
    final opened = slots.where((sl) => sl.answered && sl.opened).length;
    final locked = !t.unlocked;
    final expanded = _openWallId == t.threadId;
    // Promptless or photo-attached: no reply ever required (see
    // _wallSkipsReply's own doc) — those threads skip the "answer to
    // unlock" composer entirely in favour of [_wallPhotoPingBack].
    final skipsReply = _wallSkipsReply(t);
    final mineAnswered = slots.any((sl) => sl.isMe && sl.answered);
    final meta = locked && !skipsReply
        ? '$answered of $total answered · post yours to see the rest'
        : '$answered of $total answered · $opened opened';

    return Column(
      key: _wallKeys.putIfAbsent(t.threadId, GlobalKey.new),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The "GROUP WALL" label used to repeat above every card; it is
        // now rendered ONCE for the whole section (see build).
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
          child: ClipRRect(
            borderRadius: r4(s, 28, 12, 30, 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: g160(const Color(0xFF16161A), kSurface1),
                border: Border.all(color: w(.1), width: 1),
                borderRadius: r4(s, 28, 12, 30, 16),
                boxShadow: [
                  BoxShadow(
                    color: blk(.35),
                    blurRadius: s(40),
                    offset: Offset(0, s(14)),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _wallHeader(
                    s,
                    t,
                    slots,
                    locked: locked,
                    meta: meta,
                    answered: answered,
                    total: total,
                    expanded: expanded,
                    onToggle: () => setState(
                      () => _openWallId = expanded ? null : t.threadId,
                    ),
                  ),
                  // Collapsed by default — the header above already shows
                  // who's in it and how many have replied (`meta`); the
                  // composer/tiles/ping-group only render for the one
                  // expanded wall.
                  if (expanded) ...[
                    if (skipsReply) ...[
                      // No reply ever required — the asker's photo (if any)
                      // plus an immediate Ping Back, nothing else (explicit
                      // request: "no need to reply again... ping back option
                      // for other users to immediately ping back").
                      if (!mineAnswered) _wallPhotoPingBack(s, t),
                    ] else if (locked)
                      _wallComposer(s, t),
                    // Promptless/photo: who pinged back shows even while
                    // locked.
                    if (!locked || skipsReply) _wallTiles(s, t, slots),
                    // The "Ask everyone something" footer is gone (explicit
                    // request, 2026-10-03: "group wall 'ask everyone
                    // something' still includes the group prompt — remove
                    // that section"). Pinging a group is the group chip in
                    // PING SOMEONE now, promptless like every other ping.
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One member circle: real DP when they have one, initial+tint when they
  /// don't. Shared by the wall header's overlapping stack and the "ping the
  /// group" member row so the two can't drift apart — both previously drew
  /// initials unconditionally even though `get_group_wall` has always
  /// returned `memberAvatarUrl`. The tint gradient stays underneath as the
  /// backdrop, so a slow or failed image load degrades to the initial
  /// rather than flashing an empty hole.
  Widget _memberAvatar(
    Scale s, {
    required double size,
    required String name,
    required String? avatarUrl,
    required int tintIndex,
    required Color ringColor,
    required double ringWidth,
    required double initialSize,
  }) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fallback = Text(
      initial,
      style: ts(
        s,
        weight: 500,
        size: initialSize,
        color: const Color(0xB80B0B0D),
      ),
    );
    return Container(
      width: s(size),
      height: s(size),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: g160(kEarth[tintIndex][0], kEarth[tintIndex][1]),
        border: Border.all(color: ringColor, width: ringWidth),
      ),
      child: (avatarUrl == null || avatarUrl.isEmpty)
          ? fallback
          : CachedNetworkImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              width: s(size),
              height: s(size),
              memCacheWidth: 120,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }

  Widget _wallHeader(
    Scale s,
    WallThread t,
    List<WallSlot> slots, {
    required bool locked,
    required String meta,
    required int answered,
    required int total,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    final badgeColor = locked ? txt(.6) : kCyan;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Container(
        padding: EdgeInsets.only(
          left: s(16),
          top: s(15),
          right: s(16),
          bottom: s(14),
        ),
        decoration: BoxDecoration(
          // Collapsed cards keep the same bottom hairline a few lines below
          // already drew when expanded content followed it — an empty card
          // otherwise looked like its border had gone missing.
          border: expanded ? Border(bottom: BorderSide(color: w(.07))) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The group's own DP when it has one — a real group photo
                // reads as the group far better than a stack of member
                // initials. Falls back to the overlapping member stack
                // below when groups.icon_url is null, which is also what
                // every group had before my_group_walls started returning
                // it (migration 20260921010000).
                if (t.groupIconUrl != null && t.groupIconUrl!.isNotEmpty)
                  Container(
                    width: s(34),
                    height: s(34),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: w(.06),
                      border: Border.all(color: w(.14), width: 1),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: t.groupIconUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 120,
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  )
                else
                  // overlapping member stack
                  SizedBox(
                    height: s(30),
                    width: s(30) + s(19) * (math.max(slots.length, 1) - 1),
                    child: Stack(
                      children: [
                        for (int i = 0; i < slots.length; i++)
                          Positioned(
                            left: s(19) * i,
                            child: _memberAvatar(
                              s,
                              size: 30,
                              name: slots[i].memberName,
                              avatarUrl: slots[i].memberAvatarUrl,
                              tintIndex: i % kEarth.length,
                              ringColor: const Color(0xFF16161A),
                              ringWidth: 2,
                              initialSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(width: s(11)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.groupName,
                        style: ts(
                          s,
                          weight: 600,
                          size: 13.5,
                          em: -.01,
                          color: kText,
                        ),
                      ),
                      SizedBox(height: s(1)),
                      Text(
                        '$total people · ${_relativeTime(t.createdAt)}'
                        '${t.anonymous ? ' · asked by ${t.askedBy}' : ''}',
                        style: ts(s, weight: 400, size: 10, color: txt(.34)),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: s(8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: s(10),
                    vertical: s(5),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    color: locked ? w(.05) : kCyan.withValues(alpha: .1),
                    border: Border.all(
                      color: locked ? w(.12) : kCyan.withValues(alpha: .24),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: s(5),
                        height: s(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: badgeColor,
                          boxShadow: [
                            BoxShadow(color: badgeColor, blurRadius: s(8)),
                          ],
                        ),
                      ),
                      SizedBox(width: s(5)),
                      Text(
                        locked ? 'Locked' : 'Open',
                        style: ts(
                          s,
                          weight: 500,
                          size: 9.5,
                          color: locked ? txt(.6) : kCyan.withValues(alpha: .9),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: s(8)),
                // Which way it folds — the one visual hint that this whole
                // card is tappable, and which state it's in right now.
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: s(20),
                    color: txt(.4),
                  ),
                ),
              ],
            ),
            // The group prompt line that sat under the members' DPs is gone
            // too (explicit request, 2026-10-03: "remove that [group
            // prompt] section, and as well below DPs") — the wall is the
            // answers, not the question.
            // The asker's own attached photo is NOT shown here any more
            // (explicit request: "don't include the photo above [that] i
            // have sent"). It still exists — see [_wallPhotoPingBack], which
            // shows it with an immediate Ping Back action, right below the
            // tiles rather than duplicated in this header.
            SizedBox(height: s(11)),
            // progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: SizedBox(
                height: s(5),
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: w(.06))),
                    FractionallySizedBox(
                      widthFactor: total == 0 ? 0 : answered / total,
                      heightFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: g90(kCyan, kCyanLite),
                          boxShadow: [
                            BoxShadow(
                              color: kCyan.withValues(alpha: .5),
                              blurRadius: s(12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: s(5)),
            Text(meta, style: ts(s, weight: 400, size: 9.5, color: txt(.34))),
          ],
        ),
      ),
    );
  }

  /// A promptless or photo-attached group ping: nothing to craft a reply
  /// to, so instead of [_wallComposer]'s "answer to unlock" camera this
  /// shows the asker's own photo (if they sent one — blurred until tapped,
  /// same one-glance privacy every other ping photo gets, just not a
  /// strict one-time countdown, since the whole group could already see it
  /// before this screen existed) with an immediate Ping Back action right
  /// there (explicit request: "no need to reply again... here shall be a
  /// ping back option for other users to immediately ping back").
  Widget _wallPhotoPingBack(Scale s, WallThread t) {
    final hasPhoto = (t.photoUrl ?? '').isNotEmpty;
    final revealed = _wallPhotoRevealed.contains(t.threadId);
    return Padding(
      padding: EdgeInsets.fromLTRB(s(16), s(14), s(16), s(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPhoto) ...[
            GestureDetector(
              onTap: revealed
                  ? null
                  : () => setState(() => _wallPhotoRevealed.add(t.threadId)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(s(14)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (revealed)
                        CachedNetworkImage(
                          imageUrl: t.photoUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 900,
                          errorWidget: (_, _, _) => ColoredBox(color: w(.06)),
                        )
                      else ...[
                        ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 22,
                            sigmaY: 22,
                          ),
                          child: CachedNetworkImage(
                            imageUrl: t.photoUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 120,
                            errorWidget: (_, _, _) => ColoredBox(color: w(.06)),
                          ),
                        ),
                        Container(color: Colors.black.withValues(alpha: .25)),
                        Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: s(14),
                              vertical: s(9),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .45),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.visibility_outlined,
                                  size: s(14),
                                  color: txt(.85),
                                ),
                                SizedBox(width: s(7)),
                                Text(
                                  'tap to view',
                                  style: ts(
                                    s,
                                    weight: 500,
                                    size: 11.5,
                                    color: txt(.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: s(12)),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  hasPhoto
                      ? 'No reply needed — just ping back'
                      : 'Your turn — no reply needed, just ping back',
                  style: ts(s, weight: 500, size: 12, color: txt(.55)),
                ),
              ),
              SizedBox(width: s(10)),
              _smallPingBackPill(s, () => _wallPingBack(t)),
            ],
          ),
        ],
      ),
    );
  }

  /// Locked state — "your turn" composer. Posting here unlocks the wall.
  Widget _wallComposer(Scale s, WallThread t) {
    final key = 'wall:${t.threadId}';
    final cap = captured[key] ?? false;
    final canPost = cap || replyDraft.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: s(16),
        top: s(14),
        right: s(16),
        bottom: s(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: s(22),
                height: s(22),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kCyan.withValues(alpha: .14),
                  border: Border.all(
                    color: kCyan.withValues(alpha: .3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '↑',
                  style: ts(s, weight: 500, size: 11, lh: 1, color: kCyan),
                ),
              ),
              SizedBox(width: s(8)),
              Expanded(
                child: Text(
                  'Your turn — answer to unlock everyone’s',
                  style: ts(s, weight: 500, size: 12, color: txt(.9)),
                ),
              ),
            ],
          ),
          SizedBox(height: s(11)),
          // Promptless group ping: one tap answers (and unlocks the wall);
          // a photo or a line below still work.
          if (t.prompt.trim().isEmpty && t.myPingId != null) ...[
            Align(
              alignment: Alignment.centerRight,
              child: _smallPingBackPill(s, () => _wallPingBack(t)),
            ),
            SizedBox(height: s(11)),
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: () => _openWallCamera(t),
                  // Same shape as _expandedCard's photo drop zone (see its own
                  // doc, above): a CustomPaint(_DashedBorder) frame used to
                  // wrap this box in BOTH states, including once captured,
                  // while the captured state also filled the same rounded
                  // rect with its own solid Container — an outer dashed square
                  // around an inner solid square, same size, read as "two
                  // nested boxes". The dashed frame now belongs only to the
                  // empty "add photo" placeholder.
                  child: !cap
                      ? CustomPaint(
                          painter: _DashedBorder(color: w(.2), radius: s(16)),
                          child: Container(
                            width: s(96),
                            height: s(120),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(s(16)),
                              color: w(.03),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: s(38),
                                  height: s(38),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: w(.24),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    '+',
                                    style: ts(
                                      s,
                                      weight: 300,
                                      size: 20,
                                      lh: 1,
                                      color: txt(.65),
                                    ),
                                  ),
                                ),
                                SizedBox(height: s(7)),
                                Text(
                                  'add photo',
                                  style: ts(
                                    s,
                                    weight: 400,
                                    size: 9.5,
                                    color: txt(.34),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          width: s(96),
                          height: s(120),
                          alignment: Alignment.center,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(s(16)),
                            color: w(.03),
                            border: Border.all(
                              color: kCyan.withValues(alpha: .4),
                              width: 1.5,
                            ),
                          ),
                          // The actual shot, instantly, from the local
                          // file — with the check badged on top.
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (capturedVideoUrl[key] != null)
                                // A hold-to-record answer — play the clip
                                // in the drop zone, don't try to decode it
                                // as a still (2026-10-06).
                                AppVideo(
                                  url: capturedVideoUrl[key],
                                  durationMs: capturedVideoMs[key],
                                  showDuration: false,
                                  fit: BoxFit.cover,
                                )
                              else if (capturedLocalPath[key] != null)
                                Image.file(
                                  File(capturedLocalPath[key]!),
                                  fit: BoxFit.cover,
                                  cacheWidth: 300,
                                  gaplessPlayback: true,
                                ),
                              Align(
                                alignment: capturedLocalPath[key] != null
                                    ? Alignment.topRight
                                    : Alignment.center,
                                child: Padding(
                                  padding: EdgeInsets.all(s(5)),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: kCyan,
                                    size: s(
                                      capturedLocalPath[key] != null ? 18 : 26,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                SizedBox(width: s(11)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Post to the wall — only members who’ve answered can '
                        'see it.',
                        style: ts(
                          s,
                          weight: 400,
                          size: 11,
                          lh: 1.5,
                          color: txt(.42),
                        ),
                      ),
                      SizedBox(height: s(9)),
                      Container(
                        padding: EdgeInsets.only(
                          left: s(13),
                          top: s(4),
                          right: s(5),
                          bottom: s(4),
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: w(.05),
                          border: Border.all(color: w(.1), width: 1),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _replyCtrl,
                                onChanged: (v) =>
                                    setState(() => replyDraft = v),
                                // Same full-page typing as the personal reply
                                // composer above.
                                minLines: 1,
                                maxLines: 6,
                                maxLength: kPingReplyMaxChars,
                                keyboardType: TextInputType.multiline,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: ts(
                                  s,
                                  weight: 400,
                                  size: 12.5,
                                  color: kText,
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  hintText: 'say something…',
                                  hintStyle: ts(
                                    s,
                                    weight: 400,
                                    size: 12.5,
                                    color: txt(.4),
                                  ),
                                ),
                              ),
                            ),
                            _replyCounter(s),
                            ScoreRewardAnchor(
                              open: sentDropdownOpen[key] ?? false,
                              gain: sentGain[key],
                              onDismissed: () {
                                if (mounted) {
                                  setState(() => sentDropdownOpen[key] = false);
                                }
                              },
                              fallbackLabel: 'Posted',
                              child: GestureDetector(
                                onTap: (!canPost || _wallSending.contains(key))
                                    ? null
                                    : () async {
                                        final draft = replyDraft.trim();
                                        // Wait for an in-flight upload
                                        // rather than posting photo-less.
                                        final hadShot = captured[key] ?? false;
                                        final photoUrl =
                                            capturedPhotoUrl[key] ??
                                            (hadShot
                                                ? await _photoUploads[key]
                                                : null);
                                        if (!mounted) return;
                                        if (hadShot && photoUrl == null) {
                                          showGlassToast(
                                            context,
                                            "Couldn't upload that photo — try again.",
                                            isError: true,
                                          );
                                          return;
                                        }
                                        final selfieUrl =
                                            capturedSelfieUrl[key];
                                        final myPingId = t.myPingId;
                                        // Without a slot of our own there is
                                        // nothing to post against. This used
                                        // to fall through to the optimistic
                                        // setState below and clear the draft
                                        // anyway, so the post vanished, the
                                        // wall never unlocked, and you could
                                        // keep "replying" forever.
                                        if (myPingId == null) {
                                          showGlassToast(
                                            context,
                                            "Couldn't post to the wall.",
                                            isError: true,
                                          );
                                          return;
                                        }
                                        final restoreDraft = draft;
                                        setState(() {
                                          _wallSending.add(key);
                                          _bumpScore();
                                          (sentReplies[key] ??= []).add(
                                            draft.isEmpty
                                                ? 'photo only'
                                                : draft,
                                          );
                                          final localShot =
                                              capturedLocalPath[key];
                                          if (photoUrl != null &&
                                              localShot != null) {
                                            _myWallLocalPhoto[photoUrl] =
                                                localShot;
                                          }
                                          captured[key] = false;
                                          capturedPhotoUrl.remove(key);
                                          capturedSelfieUrl.remove(key);
                                          capturedLocalPath.remove(key);
                                          capturedVideoUrl.remove(key);
                                          capturedVideoMs.remove(key);
                                          _photoUploads.remove(key);
                                          replyDraft = '';
                                        });
                                        _replyCtrl.clear();
                                        {
                                          final mark = ScoreGainService.mark();
                                          final write = PingService.instance
                                              .replyToWall(
                                                pingId: myPingId,
                                                photoUrl: photoUrl,
                                                videoUrl:
                                                    capturedVideoUrl[key],
                                                videoMs: capturedVideoMs[key],
                                                selfieUrl: selfieUrl,
                                                body: draft.isEmpty
                                                    ? null
                                                    : draft,
                                              );
                                          // Buzz on the tap (no lag).
                                          unawaited(pingReward());
                                          // The same large points dropdown a
                                          // personal ping reply and an anon
                                          // post open — explicit request:
                                          // answering a group ping "shall be
                                          // like all other score cards,
                                          // showing points in a drop down".
                                          // Used to open only the small
                                          // anchored ScoreRewardAnchor chip.
                                          showScoreRewardOverlay(
                                            overlay: Overlay.of(context),
                                            large: true,
                                            loadGain: () async {
                                              try {
                                                await write;
                                              } catch (_) {
                                                return null;
                                              }
                                              return ScoreGainService.instance
                                                  .since(mark);
                                            },
                                          );
                                          write
                                              .then((_) async {
                                                if (mounted) {
                                                  setState(
                                                    () => _wallSending.remove(
                                                      key,
                                                    ),
                                                  );
                                                }
                                                return _loadRealPingData();
                                              })
                                              .catchError((Object e) {
                                                if (!mounted) return;
                                                // The server's own refusal
                                                // (enforce_group_ping_reply_once)
                                                // is the one case this reverts
                                                // AND explains rather than just
                                                // reverting silently — everything
                                                // else keeps the old generic
                                                // message, since it covers
                                                // network/timeout failures too.
                                                final alreadyReplied = e
                                                    .toString()
                                                    .contains(
                                                      "already replied",
                                                    );
                                                setState(() {
                                                  _wallSending.remove(key);
                                                  // Undo the optimistic post —
                                                  // it did NOT actually land, so
                                                  // the wall composer must not
                                                  // keep showing it as sent.
                                                  sentReplies[key]?.remove(
                                                    restoreDraft.isEmpty
                                                        ? 'photo only'
                                                        : restoreDraft,
                                                  );
                                                });
                                                showGlassToast(
                                                  context,
                                                  alreadyReplied
                                                      ? "You've already replied to this group ping."
                                                      : "Couldn't post to the wall.",
                                                  isError: true,
                                                );
                                              });
                                        }
                                      },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: s(14),
                                    vertical: s(8),
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(100),
                                    gradient: canPost
                                        ? g180(kCyan, kCyanDeep)
                                        : null,
                                    color: canPost ? null : w(.07),
                                    boxShadow: canPost
                                        ? [
                                            BoxShadow(
                                              color: kCyan.withValues(
                                                alpha: .3,
                                              ),
                                              blurRadius: s(22),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    'Post',
                                    style: ts(
                                      s,
                                      weight: 500,
                                      size: 11.5,
                                      color: canPost ? kGround : txt(.4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWallCamera(WallThread t) async {
    final capture = await showModalBottomSheet<PingCapture?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PingCameraScreen(recipientName: t.groupName),
    );
    if (capture == null || !mounted) return;
    final key = 'wall:${t.threadId}';
    setState(() {
      captured[key] = true;
      capturedLocalPath[key] = capture.photo.path;
    });

    final myPingId = t.myPingId;
    if (myPingId != null && capture.isVideo) {
      // Hold-to-record answer on a wall (2026-10-06): a clip, no selfie.
      final videoUrl = await StorageService.uploadPingVideo(
        file: File(capture.video!.path),
        pingId: myPingId,
      );
      if (mounted && videoUrl != null) {
        setState(() {
          capturedVideoUrl[key] = videoUrl;
          if (capture.videoMs != null) capturedVideoMs[key] = capture.videoMs!;
        });
      }
      return;
    }
    if (myPingId != null) {
      final upload = StorageService.uploadPingPhoto(
        file: File(capture.photo.path),
        pingId: myPingId,
      );
      _photoUploads[key] = upload;
      final url = await upload;
      if (mounted && url != null) setState(() => capturedPhotoUrl[key] = url);

      final selfie = capture.selfie;
      if (selfie != null) {
        final selfieUrl = await StorageService.uploadPingSelfie(
          file: File(selfie.path),
          pingId: myPingId,
        );
        if (mounted && selfieUrl != null) {
          setState(() => capturedSelfieUrl[key] = selfieUrl);
        }
      }
    }
  }

  /// Unlocked state — the answer tiles.
  /// Remaining characters, shown only once the limit is close enough to
  /// matter — a counter sitting at "260 left" on an empty field is noise.
  /// Explicit request: "in text reply correctly format how many words can
  /// be typed".
  Widget _replyCounter(Scale s) {
    final left = kPingReplyMaxChars - replyDraft.characters.length;
    if (left > 40) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(right: s(6)),
      child: Text(
        '$left',
        style: ts(
          s,
          weight: 500,
          size: 11,
          color: left <= 0 ? const Color(0xFFFF6B6B) : txt(.45),
        ),
      ),
    );
  }

  // One horizontal strip of answer cards (explicit request, 2026-10-03:
  // "let the group wall be a horizontal scrollable card, not 4 cards") —
  // it used to page through 2x2 grids of four. Each answer is its own
  // portrait card, and a big group just scrolls further. The strip's
  // padding lives INSIDE the list, so the first and last cards line up
  // with the wall's edges at rest and still scroll fully off both sides.
  Widget _wallTiles(Scale s, WallThread t, List<WallSlot> slots) => Padding(
    padding: EdgeInsets.only(top: s(14), bottom: s(16)),
    child: SizedBox(
      height: s(158),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: s(16)),
        itemCount: slots.length,
        separatorBuilder: (_, _) => SizedBox(width: s(10)),
        itemBuilder: (_, i) =>
            SizedBox(width: s(116), child: _wallTile(s, t, slots[i])),
      ),
    ),
  );

  /// The tile's background — the real reply photo when there is one
  /// (`CachedNetworkImage`, falling back to the tint while it loads or on
  /// error), or the existing tint+hatch placeholder for a text-only reply.
  /// A member's tint is derived from their id, same pattern as every other
  /// tinted avatar in this file (e.g. _loadRealPingData's kFriends mapping).
  Widget _wallTileBackground(WallSlot slot) {
    final tintIndex = slot.memberId.hashCode.abs() % kEarth.length;
    final tint = g160(kEarth[tintIndex][0], kEarth[tintIndex][1]);
    // My own just-posted photo: draw the local file, never the tint while
    // the network copy downloads (that was the blue flash after posting).
    final local = slot.isMe ? _myWallLocalPhoto[slot.photoUrl] : null;
    if (local != null) {
      return Image.file(
        File(local),
        fit: BoxFit.cover,
        cacheWidth: 480,
        gaplessPlayback: true,
      );
    }
    if (slot.photoUrl != null) {
      return CachedNetworkImage(
        imageUrl: slot.photoUrl!,
        fit: BoxFit.cover,
        memCacheWidth: 480,
        placeholder: (_, _) =>
            DecoratedBox(decoration: BoxDecoration(gradient: tint)),
        errorWidget: (_, _, _) =>
            DecoratedBox(decoration: BoxDecoration(gradient: tint)),
      );
    }
    return DecoratedBox(decoration: BoxDecoration(gradient: tint));
  }

  /// A wall answer card, with the RealMoji faces of whoever reacted to it
  /// pinned in its corner — the "see those reactions" half of the request,
  /// visible to the whole group. Tapping the faces opens who reacted.
  Widget _wallTile(Scale s, WallThread t, WallSlot slot) {
    final body = _wallTileBody(s, t, slot);
    final id = slot.replyId;
    final rx = id == null ? null : _pingRealmojis[id];
    if (rx == null || rx.isEmpty) return body;
    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        Positioned(
          left: s(6),
          bottom: s(6),
          child: PingRealmojiStack(reactions: rx, size: s(20)),
        ),
      ],
    );
  }

  Widget _wallTileBody(Scale s, WallThread t, WallSlot slot) {
    final radius = BorderRadius.circular(s(16));

    // pending — this member hasn't answered. Redesigned from a bare dashed
    // outline (explicit report: "the boxes look quite empty") into a
    // blurred hint of who's missing, same visual family as the "locked" and
    // "viewed" tiles just below.
    if (!slot.answered) {
      final tintIndex = slot.memberId.hashCode.abs() % kEarth.length;
      final hasAvatar = (slot.memberAvatarUrl ?? '').isNotEmpty;
      final tile = ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // My own pending slot is solid black (explicit request: "let my
            // turn be not like blurred let it be black only") — other
            // members' pending slots keep the blurred-avatar hint.
            if (slot.isMe)
              const ColoredBox(color: Colors.black)
            else if (hasAvatar)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: CachedNetworkImage(
                  imageUrl: slot.memberAvatarUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 120,
                  errorWidget: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: g160(
                        kEarth[tintIndex][0],
                        kEarth[tintIndex][1],
                      ),
                    ),
                  ),
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: g160(kEarth[tintIndex][0], kEarth[tintIndex][1]),
                ),
              ),
            if (!slot.isMe)
              Container(color: Colors.black.withValues(alpha: .45)),
            CustomPaint(
              painter: _DashedBorder(color: w(.16), width: 1, radius: s(16)),
            ),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: s(8)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "+" only on your own slot — a hint there's something
                    // to tap here, not just a status.
                    if (slot.isMe)
                      Container(
                        width: s(34),
                        height: s(34),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: w(.4), width: 1.5),
                        ),
                        child: Text(
                          '+',
                          style: ts(
                            s,
                            weight: 300,
                            size: 20,
                            lh: 1,
                            color: txt(.85),
                          ),
                        ),
                      )
                    else
                      Icon(
                        Icons.hourglass_empty_rounded,
                        size: s(16),
                        color: txt(.55),
                      ),
                    SizedBox(height: s(8)),
                    Text(
                      slot.isMe ? 'your turn' : 'waiting for',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(s, weight: 400, size: 8.5, color: txt(.55)),
                    ),
                    if (!slot.isMe)
                      Text(
                        slot.memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(s, weight: 600, size: 11.5, color: txt(.9)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      // Only the viewer's own pending slot is actionable — someone else's
      // tile has nothing this viewer could tap to fix. A skips-reply
      // thread's own slot pings back in one tap, same as the box above the
      // grid — no camera needed (see _wallSkipsReply's own doc).
      return slot.isMe
          ? GestureDetector(
              onTap: () =>
                  _wallSkipsReply(t) ? _wallPingBack(t) : _openWallCamera(t),
              child: tile,
            )
          : tile;
    }

    // A locked wall gets `answered: true` but no reply payload at all (the
    // gate is enforced server-side, not just hidden by this widget) —
    // render the same tinted-but-unreadable look as "hidden", minus the
    // hold-to-reveal affordance, since there is nothing this viewer's own
    // hold could ever unlock here.
    if (slot.replyId == null) {
      return ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _wallTileBackground(slot),
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(color: Colors.black.withValues(alpha: .28)),
            ),
            Center(
              child: Text(
                slot.memberName,
                style: ts(s, weight: 500, size: 11.5, color: txt(.75)),
              ),
            ),
          ],
        ),
      );
    }

    // A one-tap ping back has nothing to reveal — the slot just says so.
    if (slot.replyKind == 'text' && slot.replyBody?.trim() == kPingBackBody) {
      final tintIndex = slot.memberId.hashCode.abs() % kEarth.length;
      return ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: g160(kEarth[tintIndex][0], kEarth[tintIndex][1]),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: .25)),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: s(8)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatarCircle(
                      s,
                      size: 36,
                      fontSize: 13,
                      initial: slot.isMe
                          ? 'Y'
                          : (slot.memberName.isNotEmpty
                                ? slot.memberName[0].toUpperCase()
                                : '?'),
                      tintIndex: tintIndex,
                      isAnon: false,
                    ),
                    SizedBox(height: s(6)),
                    Text(
                      slot.isMe ? 'You' : slot.memberName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(s, weight: 600, size: 12, color: txt(.9)),
                    ),
                    SizedBox(height: s(2)),
                    Text(
                      'pinged back',
                      style: ts(s, weight: 400, size: 10.5, color: txt(.6)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final revealId = slot.replyId!;
    // YOUR OWN reply is never hidden from you — you wrote it, there is
    // nothing to reveal. It also has to be unconditional rather than
    // relying on the opened-state below: mark_wall_reply_opened() writes
    // a ping_reply_views row, but nothing ever recorded one for your own
    // tile, so `slot.opened` stayed false forever and the tile fell back
    // to "hold to reveal" on every return to the page — reported as
    // "i am able to open the already opened pings". Verified against live
    // data: every group-wall reply for this account was its own author's,
    // and none had a view row.
    final seen = slot.isMe || (viewed[revealId] ?? slot.opened);
    final active = holdId == revealId;
    final pr = active ? holdP : 0.0;

    // Someone else's reply, already viewed: it was shown ONCE, full screen
    // (_wallPhotoView), so the tile now just says so and never shows the
    // photo again ("after viewing it ... it shall be told you already
    // viewed"). Your own reply (below) stays visible to you.
    if (seen && !slot.isMe) {
      final tintIndex = slot.memberId.hashCode.abs() % kEarth.length;
      return ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: g160(kEarth[tintIndex][0], kEarth[tintIndex][1]),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: .35)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_outlined, size: s(20), color: txt(.7)),
                  SizedBox(height: s(6)),
                  Text(
                    'Viewed',
                    style: ts(s, weight: 600, size: 12, color: txt(.85)),
                  ),
                  SizedBox(height: s(2)),
                  Text(
                    slot.memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(s, weight: 400, size: 10.5, color: txt(.55)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // shown — your own reply, always visible to you
    if (seen) {
      final hasPhoto = slot.photoUrl != null;
      final tile = ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _wallTileBackground(slot),
            if (!hasPhoto)
              CustomPaint(painter: HatchPainter(s(9), w(.08), w(.02))),
            // Only a camera reply has a selfie half — see
            // InboundReply.selfieUrl's own doc (same rule as _photoView).
            if (slot.selfieUrl != null)
              Positioned(
                top: s(9),
                left: s(9),
                child: Container(
                  width: s(30),
                  height: s(38),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s(7)),
                    border: Border.all(color: w(.45), width: 1.5),
                    color: w(.08),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: slot.selfieUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 120,
                  ),
                ),
              ),
            // Heart reaction — explicit request: on a group wall, anyone who
            // has ANSWERED the thread may react to another member's tile
            // (never their own — hence !slot.isMe here; the server enforces
            // the same rule, this is belt-and-suspenders so a stale client
            // never even shows the tappable state on your own tile). Own
            // GestureDetector, not the tile's: the tile itself intentionally
            // has NO gesture (a revealed reply is terminal, see the doc a
            // few lines below), so this must not make the whole tile tappable.
            // My OWN tile: read-only heart + how many liked it. It used to
            // show nothing, so likes on your answer were invisible on the
            // wall. Count only (no likers), same as everyone else sees.
            if (slot.isMe && slot.reactionCount > 0)
              Positioned(
                top: s(9),
                right: s(9),
                child: Container(
                  height: s(24),
                  padding: EdgeInsets.symmetric(horizontal: s(8)),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s(12)),
                    color: Colors.black.withValues(alpha: .38),
                    border: Border.all(
                      color: const Color(0x80FF5C86),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: s(12),
                        color: const Color(0xFFFF5C86),
                      ),
                      SizedBox(width: s(3)),
                      Text(
                        '${slot.reactionCount}',
                        style: ts(
                          s,
                          weight: 600,
                          size: 9.5,
                          color: const Color(0xFFFF5C86),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!slot.isMe)
              Positioned(
                top: s(9),
                right: s(9),
                child: Builder(
                  builder: (context) {
                    final rx =
                        reactions[revealId] ??
                        (mine: slot.myReaction, count: slot.reactionCount);
                    return GestureDetector(
                      onTap: () => _toggleReaction(
                        revealId,
                        initialMine: slot.myReaction,
                        initialCount: slot.reactionCount,
                      ),
                      child: Container(
                        height: s(24),
                        padding: EdgeInsets.symmetric(
                          horizontal: s(rx.count > 0 ? 8 : 0),
                        ),
                        constraints: BoxConstraints(minWidth: s(24)),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(s(12)),
                          color: Colors.black.withValues(alpha: .38),
                          border: Border.all(color: w(.2), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              rx.mine
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: s(12),
                              color: rx.mine
                                  ? const Color(0xFFFF5C86)
                                  : Colors.white.withValues(alpha: .85),
                            ),
                            if (rx.count > 0) ...[
                              SizedBox(width: s(3)),
                              Text(
                                '${rx.count}',
                                style: ts(
                                  s,
                                  weight: 600,
                                  size: 9.5,
                                  color: rx.mine
                                      ? const Color(0xFFFF5C86)
                                      : Colors.white.withValues(alpha: .85),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            // No "↗ open" affordance, and no tap handler on the tile itself:
            // a ping reply is opened ONCE. After the hold-to-reveal it is
            // shown in place permanently and cannot be re-opened — that
            // one-shot reveal is the product rule, not an oversight.
            //
            // An earlier pass here read the orphaned ↗ glyph as a missing
            // handler and wired it to openPhotoLightbox. That was the
            // wrong reading: the glyph was the leftover, not the gesture.
            // Both are gone now.
            Positioned(
              left: s(10),
              right: s(10),
              bottom: s(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    slot.memberName,
                    style: ts(s, weight: 500, size: 11, color: txt(.95)),
                  ),
                  if (slot.replyBody != null && slot.replyBody!.isNotEmpty) ...[
                    SizedBox(height: s(3)),
                    Text(
                      slot.replyBody!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ts(
                        s,
                        weight: 400,
                        size: 10.5,
                        lh: 1.35,
                        color: txt(.72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
      // Intentionally NO gesture — see the note above the Positioned
      // block: a revealed reply is terminal, it cannot be re-opened.
      return tile;
    }

    // hidden — hold to reveal. A short hold opens the reply straight into
    // the full-screen viewer (_openWallPhoto via finishHold); the tile
    // itself stays blurred instead of un-blurring in the small box first —
    // "holding it shall open full screen immediately".
    return GestureDetector(
      onTapDown: (_) => startHold(revealId, false, seconds: 0.25),
      onTapUp: (_) => endHold(),
      onTapCancel: endHold,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _wallTileBackground(slot),
            BackdropFilter(
              // Peaks around 22px (was ~4.5px) — enough to actually hide a
              // real photo/face, not just soften a flat placeholder
              // gradient the way the pre-photo version only needed to.
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                color: Colors.black.withValues(alpha: .2),
                child: slot.photoUrl == null
                    ? CustomPaint(painter: HatchPainter(s(8), w(.07), w(.02)))
                    : null,
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: s(36),
                    height: s(36),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size(s(36), s(36)),
                          painter: RingPainter(pr, accent),
                        ),
                        Container(
                          width: s(6),
                          height: s(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: txt(.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: s(8)),
                  Text(
                    slot.memberName,
                    style: ts(s, weight: 500, size: 11.5, color: txt(.9)),
                  ),
                  Text(
                    active
                        ? (pr < .99 ? 'keep holding' : 'opening')
                        : 'hold to reveal',
                    style: ts(
                      s,
                      weight: 400,
                      size: 8.5,
                      color: active ? kCyan.withValues(alpha: .85) : txt(.28),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- SENT ----------
  /// Threads I sent to 2+ people (send_ping_multi), newest first — each
  /// renders as one [_multiCard] instead of separate SENT rows and REPLIES
  /// cards. Explicit request: "everybody's replies come there itself, in the
  /// same box". Only I see the card; replies stay private per recipient.
  List<String> get _multiThreadIds {
    final counts = <String, int>{};
    final order = <String>[];
    for (final o in kSent) {
      final t = o.threadId;
      if (t == null) continue;
      if (!counts.containsKey(t)) order.add(t);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return [
      for (final t in order)
        if (counts[t]! >= 2) t,
    ];
  }

  Widget _multiCard(Scale s, String threadId) {
    final pings = kSent.where((o) => o.threadId == threadId).toList();
    final repliesByPing = <String, List<InboundReply>>{};
    for (final r in kReplies) {
      if (r.threadId == threadId) (repliesByPing[r.pingId] ??= []).add(r);
    }
    final answered = pings.where((o) => repliesByPing.containsKey(o.id)).length;
    return Padding(
      padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
      child: Glass(
        radius: r4(s, 26, 14, 30, 10),
        gradient: g150(w(.07), w(.03)),
        border: Border.all(color: w(.1), width: 1),
        blurSigma: 11,
        shadow: [
          BoxShadow(color: blk(.3), blurRadius: s(24), offset: Offset(0, s(6))),
        ],
        child: Padding(
          padding: EdgeInsets.all(s(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    pings.first.prompt == kPromptlessOutbound
                        ? 'YOU PINGED ${pings.length}'
                        : 'YOU ASKED ${pings.length}',
                    style: ts(
                      s,
                      weight: 500,
                      size: 11,
                      em: .18,
                      color: txt(.55),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$answered of ${pings.length} replied',
                    style: ts(
                      s,
                      weight: 400,
                      size: 10.5,
                      color: answered > 0
                          ? kCyan.withValues(alpha: .72)
                          : txt(.3),
                    ),
                  ),
                ],
              ),
              // A promptless multi-ping has nothing to repeat here.
              if (pings.first.prompt != kPromptlessOutbound) ...[
                SizedBox(height: s(6)),
                Text(
                  pings.first.prompt,
                  style: ts(s, weight: 500, size: 16, lh: 1.35, color: kText),
                ),
              ],
              SizedBox(height: s(14)),
              LayoutBuilder(
                builder: (context, c) {
                  final gap = s(8);
                  final perRow = pings.length <= 4 ? 2 : 3;
                  final side = (c.maxWidth - gap * (perRow - 1)) / perRow;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final o in pings)
                        SizedBox(
                          width: side,
                          height: side,
                          child: _multiSlot(
                            s,
                            o,
                            repliesByPing[o.id] ?? const [],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One recipient's slot: their avatar while waiting, a blurred
  /// hold-to-reveal tile once they reply (same hold as a REPLIES card), and
  /// the reply itself after it's been seen — it stays in the box until the
  /// ping's window closes instead of vanishing like a REPLIES card.
  Widget _multiSlot(Scale s, OutboundPing o, List<InboundReply> replies) {
    final radius = BorderRadius.circular(s(16));
    final name = Text(
      o.who,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ts(s, weight: 500, size: 11.5, color: Colors.white),
    );

    if (replies.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: kSurface2,
          border: Border.all(color: w(.06), width: 1),
        ),
        padding: EdgeInsets.all(s(10)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipOval(
              child: SizedBox(
                width: s(44),
                height: s(44),
                child: o.avatarUrl == null
                    ? ColoredBox(
                        color: w(.08),
                        child: Center(
                          child: Text(
                            o.initial,
                            style: ts(s, weight: 500, size: 15, color: txt(.6)),
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: o.avatarUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 160,
                      ),
              ),
            ),
            SizedBox(height: s(8)),
            Text(
              o.who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(s, weight: 400, size: 11.5, color: txt(.62)),
            ),
            SizedBox(height: s(2)),
            Text(
              o.seen ? 'seen · waiting…' : 'waiting…',
              style: ts(
                s,
                weight: 400,
                size: 10,
                color: o.seen ? kCyan.withValues(alpha: .6) : txt(.28),
              ),
            ),
          ],
        ),
      );
    }

    // First unopened reply gets the hold; once all are opened, show the
    // newest one.
    final unopened = replies.where((r) => !(viewed[r.id] ?? r.viewedInit));
    final r = unopened.isNotEmpty ? unopened.last : replies.first;
    final isOpen = unopened.isEmpty;
    final active = holdId == r.id;
    final pr = active ? holdP : 0.0;

    final content = r.photoUrl != null
        ? CachedNetworkImage(
            imageUrl: r.photoUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 400,
          )
        : Container(
            color: kSurface2,
            alignment: Alignment.center,
            padding: EdgeInsets.all(s(12)),
            child: Text(
              r.body,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ts(s, weight: 500, size: 13, lh: 1.3, color: kText),
            ),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isOpen ? () => _openPhoto(r.id) : null,
      onTapDown: isOpen ? null : (_) => startHold(r.id, false),
      onTapUp: isOpen ? null : (_) => endHold(),
      onTapCancel: isOpen ? null : endHold,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: isOpen ? w(.08) : kCyan.withValues(alpha: .25 + .5 * pr),
            width: 1,
          ),
          boxShadow: isOpen
              ? null
              : [
                  BoxShadow(
                    color: kCyan.withValues(alpha: .08 + .25 * pr),
                    blurRadius: s(10 + 20 * pr),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isOpen)
                content
              else
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 14 * (1 - pr),
                    sigmaY: 14 * (1 - pr),
                  ),
                  child: content,
                ),
              // Name strip, legible over any photo.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(s(10), s(14), s(10), s(8)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, blk(.6)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: name),
                      if (replies.length > 1)
                        Text(
                          '${replies.length}',
                          style: ts(s, weight: 500, size: 10.5, color: txt(.8)),
                        ),
                    ],
                  ),
                ),
              ),
              if (!isOpen)
                Center(
                  child: Text(
                    'hold to see',
                    style: ts(s, weight: 500, size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sentSection(Scale s) {
    final multi = _multiThreadIds;
    final all = [
      ...sentExtra,
      ...kSent.where((o) => !multi.contains(o.threadId)),
    ];
    // Everything sent is shown in multi cards — no empty SENT header.
    if (all.isEmpty && kSent.isNotEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(8)),
          child: Text(
            'SENT',
            style: ts(s, weight: 500, size: 11, em: .18, color: txt(.4)),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: s(22), right: s(22), bottom: s(30)),
          child: Column(
            children: [
              for (int i = 0; i < all.length; i++) ...[
                _sentRow(s, all[i]),
                if (i < all.length - 1) SizedBox(height: s(13)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sentRow(Scale s, OutboundPing o) {
    // Explicit request: a reply I've hearted should be visible right here on
    // the compact SENT row, not only inside the full-screen reply viewer.
    // "Unlimited within the window" (ping_page.dart's own doc on replying)
    // means more than one reply can exist for the same sent ping, so this
    // checks whether I reacted to ANY of them, not just the newest — the
    // live `reactions` map takes priority over each reply's own last-loaded
    // myReaction, same optimistic-then-server-corrected rule _toggleReaction
    // already uses everywhere else.
    final iReacted = kReplies.any((r) {
      if (r.pingId != o.id) return false;
      return (reactions[r.id] ?? (mine: r.myReaction, count: r.reactionCount))
          .mine;
    });
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(14)),
      decoration: BoxDecoration(
        borderRadius: r4(s, 20, 10, 22, 12),
        color: kSurface2,
        border: Border.all(color: w(.05), width: 1),
      ),
      child: Row(
        children: [
          CustomPaint(
            painter: _DashedBorder(color: w(.16), width: 1, radius: s(14)),
            child: SizedBox(
              width: s(28),
              height: s(28),
              child: Center(
                child: Text(
                  o.initial,
                  style: ts(s, weight: 400, size: 10, color: txt(.4)),
                ),
              ),
            ),
          ),
          SizedBox(width: s(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'to ${o.who}',
                  style: ts(s, weight: 400, size: 11, color: txt(.32)),
                ),
                SizedBox(height: s(3)),
                Text(
                  o.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(s, weight: 400, size: 14, lh: 1.3, color: txt(.62)),
                ),
              ],
            ),
          ),
          SizedBox(width: s(12)),
          if (iReacted) ...[
            Icon(
              Icons.favorite_rounded,
              size: s(13),
              color: const Color(0xFFFF5C86),
            ),
            SizedBox(width: s(8)),
          ],
          if (o.seen)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseDot(size: s(5)),
                SizedBox(width: s(6)),
                Text(
                  'Seen',
                  style: ts(
                    s,
                    weight: 400,
                    size: 10.5,
                    color: kCyan.withValues(alpha: .72),
                  ),
                ),
              ],
            )
          else
            Text(
              'Delivered',
              style: ts(s, weight: 400, size: 10.5, color: txt(.24)),
            ),
        ],
      ),
    );
  }

  /// What a plain ping-back (body is the 👋 sentinel, no words typed) shows
  /// in [_photoView] in place of a photo or TextPingCard — a quiet "X
  /// pinged you back" panel, no hand emoji. The viewer's own "Ping X back"
  /// CTA sits right below this.
  Widget _pingBackNotice(Scale s, InboundReply r) => DecoratedBox(
    decoration: const BoxDecoration(color: Color(0xFF08080A)),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatarCircle(
            s,
            size: 64,
            fontSize: 22,
            initial: r.who.isNotEmpty ? r.who[0].toUpperCase() : '?',
            tintIndex: r.replierId.hashCode.abs() % kEarth.length,
            isAnon: false,
          ),
          SizedBox(height: s(16)),
          Text(
            '${r.who} pinged you back',
            textAlign: TextAlign.center,
            style: ts(s, weight: 600, size: 20, color: kText),
          ),
        ],
      ),
    ),
  );

  // ---------- REPLY PHOTO (opens the instant a reply is revealed) ----------
  Widget _photoView(Scale s) {
    final r = kReplies.firstWhere((x) => x.id == photoViewId);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final alreadyPinged = pingedBack[r.id] ?? false;

    return Positioned.fill(
      child: _SlideUp(
        child: Container(
          color: kGround,
          child: Column(
            children: [
              // header — who + when, close
              Padding(
                padding: EdgeInsets.only(
                  left: s(18),
                  top: safeTop + s(8),
                  right: s(18),
                  bottom: s(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            r.isAnon ? 'Someone replied' : '${r.who} replied',
                            style: ts(
                              s,
                              weight: 600,
                              size: 15,
                              color: r.isAnon ? clay(.85) : kText,
                            ),
                          ),
                          SizedBox(height: s(2)),
                          Text(
                            're: ${r.prompt}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(
                              s,
                              weight: 400,
                              size: 10.5,
                              color: txt(.32),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: s(10)),
                    GestureDetector(
                      onTap: _closePhoto,
                      child: Container(
                        width: s(34),
                        height: s(34),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: w(.06),
                          border: Border.all(color: w(.1), width: 1),
                        ),
                        child: Text(
                          '×',
                          style: ts(
                            s,
                            weight: 400,
                            size: 15,
                            lh: 1,
                            color: txt(.8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // the photo they sent — full-bleed, with their selfie inset.
              // Press and hold anywhere on it to freeze the countdown.
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: s(18)),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _photoHoldStart(),
                    onTapUp: (_) => _photoHoldEnd(),
                    onTapCancel: _photoHoldEnd,
                    onLongPressStart: (_) => _photoHoldStart(),
                    onLongPressEnd: (_) => _photoHoldEnd(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(s(20)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // The actual photo they replied with. Until this was
                          // wired up, revealing a reply showed a gradient
                          // placeholder and nothing else — the photo was
                          // uploaded and stored correctly, it just never got
                          // rendered, so "reply with a photo" appeared not to
                          // deliver anything. The gradient stays as the
                          // loading/error state, and as the whole treatment
                          // for a text-only reply (which has no photo).
                          // A hold-to-record video answer plays here; a
                          // photo reply is unchanged (2026-10-06).
                          if (r.videoUrl != null)
                            AppVideo(
                              url: r.videoUrl,
                              durationMs: r.videoMs,
                              autoPlay: true,
                              fit: BoxFit.cover,
                            )
                          else if (r.photoUrl != null)
                            CachedNetworkImage(
                              memCacheWidth: 1080,
                              imageUrl: r.photoUrl!,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                              // No fade — the photo appears the moment it's
                              // ready — and the countdown starts only then.
                              fadeInDuration: Duration.zero,
                              imageBuilder: (context, image) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _startPhotoCountdown(),
                                );
                                return Image(
                                  image: image,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.medium,
                                );
                              },
                              // Plain black while loading — the old cyan
                              // gradient read as "a blue page" over the
                              // reply (explicit report).
                              placeholder: (_, _) => const ColoredBox(
                                color: Colors.black,
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (_, _, _) => DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: g160(
                                    kCyan.withValues(alpha: .14),
                                    const Color(0x1FB08968),
                                  ),
                                ),
                              ),
                            )
                          // A plain ping back (body is just the 👋 sentinel)
                          // gets a quiet "X pinged you back" panel, not the
                          // loud TextPingCard treatment — no hand emoji here
                          // (explicit request, 2026-10-02: only show it when
                          // they actually sent a photo). The "Ping back" CTA
                          // below already answers it.
                          else if (r.body.trim() == kPingBackBody)
                            _pingBackNotice(s, r)
                          // A words-only reply gets its own card rather than
                          // the photo placeholder — see TextPingCard. The
                          // gradient+hatch below stays for the genuinely
                          // empty case (no photo AND no words), which is what
                          // it was always meant to cover.
                          else if (r.body.trim().isNotEmpty)
                            TextPingCard(text: r.body, scale: s(1))
                          else ...[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: g160(
                                  kCyan.withValues(alpha: .14),
                                  const Color(0x1FB08968),
                                ),
                              ),
                            ),
                            CustomPaint(
                              painter: HatchPainter(s(10), w(.09), w(.03)),
                            ),
                          ],
                          // Only a camera reply has a selfie half — see
                          // InboundReply.selfieUrl's own doc. Sized larger
                          // than the other three inset sites (96x120 vs
                          // 30-44 wide) since this is the full-bleed viewer,
                          // matching the design's own PiP proportion (roughly
                          // a fifth of the card's width — Ping_Page_LATEST
                          // .dc.html's 60x76 PiP against a 280-wide card).
                          if (r.selfieUrl != null)
                            Positioned(
                              top: s(12),
                              left: s(12),
                              child: Container(
                                width: s(96),
                                height: s(120),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(s(16)),
                                  border: Border.all(color: w(.5), width: 1.5),
                                  color: w(.08),
                                  boxShadow: [
                                    BoxShadow(
                                      color: blk(.4),
                                      blurRadius: s(16),
                                      offset: Offset(0, s(4)),
                                    ),
                                  ],
                                ),
                                child: CachedNetworkImage(
                                  imageUrl: r.selfieUrl!,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 240,
                                ),
                              ),
                            ),
                          // Their words over the PHOTO — only when there is
                          // a photo to lay them over. Without a photo the
                          // words are the card itself (TextPingCard above),
                          // and rendering them here too printed them twice.
                          if (r.body.isNotEmpty && r.photoUrl != null)
                            Positioned(
                              left: s(14),
                              right: s(14),
                              bottom: s(14),
                              child: Text(
                                r.body,
                                style: ts(
                                  s,
                                  weight: 400,
                                  size: 13.5,
                                  lh: 1.5,
                                  color: txt(.92),
                                ),
                              ),
                            ),
                          // Who reacted, on the photo itself — tapping opens
                          // the full list with their selfies. Reported
                          // 2026-10-04: reactions on a photo sent via ping
                          // couldn't be seen anywhere.
                          if ((_pingRealmojis[r.id] ?? const []).isNotEmpty)
                            Positioned(
                              right: s(14),
                              bottom: s(14),
                              child: PingRealmojiStack(
                                reactions: _pingRealmojis[r.id]!,
                                size: s(26),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ---- countdown: how long the photo stays up ----
              Padding(
                padding: EdgeInsets.only(left: s(18), top: s(10), right: s(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: SizedBox(
                        height: s(3),
                        child: LinearProgressIndicator(
                          // Drains left-to-right as the seconds go, and simply
                          // stops mid-drain while held.
                          value: 1 - (_photoTimer?.value ?? 0),
                          backgroundColor: w(.07),
                          valueColor: AlwaysStoppedAnimation(
                            _photoHeld ? kCyanLite : kCyan,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: s(7)),
                    Text(
                      _photoHeld
                          ? 'holding — release to let it go'
                          : 'hold anywhere on the photo to keep looking',
                      textAlign: TextAlign.center,
                      style: ts(
                        s,
                        weight: 400,
                        size: 10.5,
                        color: _photoHeld
                            ? kCyan.withValues(alpha: .8)
                            : txt(.3),
                      ),
                    ),
                  ],
                ),
              ),

              // ---- below the photo: heart + ping back ----
              Padding(
                padding: EdgeInsets.only(
                  left: s(18),
                  top: s(14),
                  right: s(18),
                  bottom: safeBottom + s(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: !alreadyPinged
                          ? SpringTap(
                              onTap: () async {
                                // Ping back without leaving the photo: freeze
                                // the countdown, open the prompt over it, and
                                // only then let the viewer go. Closing first
                                // (as this used to) yanked their photo away
                                // mid-decision.
                                _photoTimer?.stop();
                                setState(() {
                                  _bumpScore();
                                  pingedBack[r.id] = true;
                                });
                                if (r.isAnon) {
                                  await openPromptSheet(
                                    r.who,
                                    anon: true,
                                    targetId: r.replierId,
                                  );
                                } else {
                                  await _pingNow(
                                    r.replierId,
                                    r.who,
                                    pingBack: true,
                                  );
                                }
                                if (mounted && photoViewId != null)
                                  _closePhoto();
                              },
                              child: Container(
                                alignment: Alignment.center,
                                padding: EdgeInsets.symmetric(vertical: s(13)),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(100),
                                  gradient: g180(kCyanLite, kCyan),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kCyan.withValues(alpha: .34),
                                      blurRadius: s(24),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  r.isAnon
                                      ? 'Ping them back'
                                      : 'Ping ${r.who} back',
                                  style: ts(
                                    s,
                                    weight: 600,
                                    size: 13,
                                    color: kGround,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              alignment: Alignment.center,
                              padding: EdgeInsets.symmetric(vertical: s(12)),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100),
                                color: w(.04),
                                border: Border.all(color: w(.08), width: 1),
                              ),
                              child: Text(
                                'pinged back',
                                style: ts(
                                  s,
                                  weight: 500,
                                  size: 12,
                                  color: txt(.4),
                                ),
                              ),
                            ),
                    ),
                    // ONE reaction button, right of Ping back: it opens the
                    // RealMoji tray, and the heart is the tray's first chip
                    // (explicit request, 2026-10-03: "the heart shall be
                    // inside the RealMoji thing, not a separate widget").
                    // For a 1:1 reply only the ping's sender may react; the
                    // replier is notified (toggle_ping_reply_reaction /
                    // ping_realmoji_reactions RLS are the real gates).
                    ...[
                      SizedBox(width: s(10)),
                      Builder(
                        builder: (context) {
                          final rx =
                              reactions[r.id] ??
                              (mine: r.myReaction, count: r.reactionCount);
                          return _realmojiButton(
                            s,
                            replyId: r.id,
                            heartMine: rx.mine,
                            onHeart: () => _toggleReaction(
                              r.id,
                              initialMine: r.myReaction,
                              initialCount: r.reactionCount,
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// RealMoji reactions on Ping targets, loaded with the page (see
  /// _loadPingRealmojis). Keyed by reply id or ping id.
  final Map<String, List<PingRealmoji>> _pingRealmojis = {};

  /// A hold-to-record clip captured for a group wall answer, keyed like
  /// [captured] (`wall:<threadId>`) — uploaded on capture, attached on send.
  final Map<String, String> capturedVideoUrl = {};
  final Map<String, int> capturedVideoMs = {};

  /// Reactions people left on the replies I SENT (my_ping_reply_reactions).
  /// Kept separate from [_pingRealmojis] because these outlive the ping: a
  /// ping expires 6h after it's sent, which used to take the only view of
  /// its reactions with it (reported 2026-10-04: "people aren't able to view
  /// the reactions for their ping replies").
  List<MyReplyReactions> _myReplyReactions = const [];

  /// The ONE reaction button (explicit request, 2026-10-03: "the heart
  /// shall be inside the RealMoji thing, not a separate widget"). It opens
  /// the friends-feed RealMoji tray, whose first chip IS the heart. The
  /// button wears my current reaction: my RealMoji face, else a filled
  /// heart, else a plain add-reaction icon.
  ///
  /// While the tray is open the photo's one-time countdown is PAUSED
  /// ("when selecting a RealMoji the loading photo shall stop") and
  /// resumes when it closes — picking a reaction no longer costs you the
  /// photo.
  Widget _realmojiButton(
    Scale s, {
    String? replyId,
    String? pingId,
    bool heartMine = false,
    VoidCallback? onHeart,
  }) {
    final key = replyId ?? pingId!;
    final mine = (_pingRealmojis[key] ?? const <PingRealmoji>[])
        .where((r) => r.isMine)
        .firstOrNull;
    return GestureDetector(
      onTap: () async {
        final wasRunning = _photoTimer?.isAnimating ?? false;
        _photoTimer?.stop();
        await showPingRealmojiPicker(
          context,
          replyId: replyId,
          pingId: pingId,
          onHeart: onHeart,
          heartLiked: heartMine,
          onReacted: () =>
              _loadPingRealmojis(replyIds: [?replyId], pingIds: [?pingId]),
        );
        if (!mounted) return;
        // Resume only if a photo is still up and it was counting down.
        final photoStillOpen =
            photoViewId != null ||
            wallPhotoSlot != null ||
            pingPhotoViewId != null;
        if (wasRunning && photoStillOpen && !_photoHeld) {
          _photoTimer?.forward();
        }
      },
      child: Container(
        height: s(44),
        width: s(44),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: w(.06),
          border: Border.all(
            color: mine != null
                ? kCyan.withValues(alpha: .7)
                : heartMine
                ? const Color(0xFFFF5C86).withValues(alpha: .7)
                : w(.1),
            width: 1,
          ),
        ),
        child: mine != null
            ? PingRealmojiFace(r: mine, size: s(36))
            : heartMine
            ? Icon(
                Icons.favorite_rounded,
                size: s(18),
                color: const Color(0xFFFF5C86),
              )
            : Icon(Icons.add_reaction_outlined, size: s(18), color: txt(.75)),
      ),
    );
  }

  /// Fetches RealMoji reactions for these targets and merges them into
  /// [_pingRealmojis]. Best-effort: a failed fetch leaves what's there.
  Future<void> _loadPingRealmojis({
    List<String> replyIds = const [],
    List<String> pingIds = const [],
  }) async {
    if (replyIds.isEmpty && pingIds.isEmpty) return;
    try {
      final rows = await PingRealmojiService.instance.fetchFor(
        replyIds: replyIds,
        pingIds: pingIds,
      );
      if (!mounted) return;
      setState(() {
        for (final id in [...replyIds, ...pingIds]) {
          _pingRealmojis[id] = const [];
        }
        for (final r in rows) {
          final k = r.replyId ?? r.pingId;
          if (k == null) continue;
          _pingRealmojis[k] = [...?_pingRealmojis[k], r];
        }
      });
    } catch (_) {}
  }

  // ---------- PING'S OWN PHOTO (one-time view) ----------
  /// Explicit request: an asker's attached photo (`pings.photo_url`) now
  /// gets the exact same glance-then-gone treatment [_photoView] gives a
  /// reply's photo — full-bleed, hold-to-freeze countdown, closes and stays
  /// closed (mark_ping_photo_opened is durable server state, not just this
  /// session). Deliberately simpler than [_photoView]: no heart (reactions
  /// are reply-photo-only per the request that introduced them) and no
  /// ping-back button (that lives on the card itself, not inside the
  /// viewer — this is the thing you're about to reply TO, not a reply).
  Widget _pingPhotoView(Scale s) {
    final p = kToReply.firstWhere((x) => x.id == pingPhotoViewId);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Positioned.fill(
      child: _SlideUp(
        child: Container(
          color: kGround,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: s(18),
                  top: safeTop + s(8),
                  right: s(18),
                  bottom: s(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.isAnon
                                ? 'Someone pinged you'
                                : '${p.senderName} pinged you',
                            style: ts(
                              s,
                              weight: 600,
                              size: 15,
                              color: p.isAnon ? clay(.85) : kText,
                            ),
                          ),
                          SizedBox(height: s(2)),
                          Text(
                            p.prompt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ts(
                              s,
                              weight: 400,
                              size: 10.5,
                              color: txt(.32),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: s(10)),
                    GestureDetector(
                      onTap: _closePingPhoto,
                      child: Container(
                        width: s(34),
                        height: s(34),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: w(.06),
                          border: Border.all(color: w(.1), width: 1),
                        ),
                        child: Text(
                          '×',
                          style: ts(
                            s,
                            weight: 400,
                            size: 15,
                            lh: 1,
                            color: txt(.8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: s(18)),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _photoHoldStart(),
                    onTapUp: (_) => _photoHoldEnd(),
                    onTapCancel: _photoHoldEnd,
                    onLongPressStart: (_) => _photoHoldStart(),
                    onLongPressEnd: (_) => _photoHoldEnd(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(s(20)),
                      child: isVideoUrl(p.photoUrl)
                          // A ping that carries a clip plays it (2026-10-06).
                          ? AppVideo(
                              url: p.photoUrl,
                              autoPlay: true,
                              fit: BoxFit.cover,
                            )
                          : p.photoUrl != null
                          ? CachedNetworkImage(
                              memCacheWidth: 1080,
                              imageUrl: p.photoUrl!,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                              placeholder: (_, _) => DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: g160(
                                    kCyan.withValues(alpha: .14),
                                    const Color(0x1FB08968),
                                  ),
                                ),
                              ),
                              errorWidget: (_, _, _) => DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: g160(
                                    kCyan.withValues(alpha: .14),
                                    const Color(0x1FB08968),
                                  ),
                                ),
                              ),
                            )
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: g160(
                                  kCyan.withValues(alpha: .14),
                                  const Color(0x1FB08968),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: s(18),
                  top: s(10),
                  right: s(18),
                  bottom: safeBottom + s(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: SizedBox(
                        height: s(3),
                        child: LinearProgressIndicator(
                          value: 1 - (_photoTimer?.value ?? 0),
                          backgroundColor: w(.07),
                          valueColor: AlwaysStoppedAnimation(
                            _photoHeld ? kCyanLite : kCyan,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: s(7)),
                    Text(
                      _photoHeld
                          ? 'holding — release to let it go'
                          : 'hold anywhere on the photo to keep looking',
                      textAlign: TextAlign.center,
                      style: ts(
                        s,
                        weight: 400,
                        size: 10.5,
                        color: _photoHeld
                            ? kCyan.withValues(alpha: .8)
                            : txt(.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- GROUP REPLY (full screen, one time) ----------
  Widget _wallPhotoView(Scale s, WallSlot slot) {
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final replyId = slot.replyId;
    final hasPhoto = slot.photoUrl != null;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: g160(kCyan.withValues(alpha: .14), const Color(0x1FB08968)),
      ),
    );

    return Positioned.fill(
      child: _SlideUp(
        child: Container(
          color: kGround,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: s(18),
                  top: safeTop + s(8),
                  right: s(18),
                  bottom: s(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${slot.memberName} replied',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(s, weight: 600, size: 15, color: kText),
                      ),
                    ),
                    SizedBox(width: s(10)),
                    GestureDetector(
                      onTap: _closeWallPhoto,
                      child: Container(
                        width: s(34),
                        height: s(34),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: w(.06),
                          border: Border.all(color: w(.1), width: 1),
                        ),
                        child: Text(
                          '×',
                          style: ts(
                            s,
                            weight: 400,
                            size: 15,
                            lh: 1,
                            color: txt(.8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: s(18)),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _photoHoldStart(),
                    onTapUp: (_) => _photoHoldEnd(),
                    onTapCancel: _photoHoldEnd,
                    onLongPressStart: (_) => _photoHoldStart(),
                    onLongPressEnd: (_) => _photoHoldEnd(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(s(20)),
                      child: hasPhoto
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  memCacheWidth: 1080,
                                  imageUrl: slot.photoUrl!,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.medium,
                                  placeholder: (_, _) => placeholder,
                                  errorWidget: (_, _, _) => placeholder,
                                ),
                                if (slot.selfieUrl != null)
                                  Positioned(
                                    top: s(12),
                                    left: s(12),
                                    child: Container(
                                      width: s(74),
                                      height: s(96),
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          s(12),
                                        ),
                                        border: Border.all(
                                          color: w(.6),
                                          width: 2,
                                        ),
                                      ),
                                      child: CachedNetworkImage(
                                        imageUrl: slot.selfieUrl!,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 240,
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                placeholder,
                                Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(s(24)),
                                    child: TextPingCard(
                                      text:
                                          (slot.replyBody ?? '').trim().isEmpty
                                          ? '…'
                                          : slot.replyBody!,
                                      scale: s(1),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              if (hasPhoto && (slot.replyBody ?? '').trim().isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(s(18), s(10), s(18), 0),
                  child: Text(
                    slot.replyBody!,
                    textAlign: TextAlign.center,
                    style: ts(s, weight: 400, size: 13, color: txt(.85)),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(
                  left: s(18),
                  top: s(10),
                  right: s(18),
                  bottom: safeBottom + s(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Heart: the tile no longer shows the reply after this,
                    // so the like lives here (same rule as the wall: never
                    // on your own reply; the server enforces it too).
                    // ONE reaction button — the RealMoji tray, heart
                    // inside it (explicit request, 2026-10-03).
                    if (replyId != null && !slot.isMe)
                      Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: s(10)),
                          child: Builder(
                            builder: (context) {
                              final rx =
                                  reactions[replyId] ??
                                  (
                                    mine: slot.myReaction,
                                    count: slot.reactionCount,
                                  );
                              return _realmojiButton(
                                s,
                                replyId: replyId,
                                heartMine: rx.mine,
                                onHeart: () => _toggleReaction(
                                  replyId,
                                  initialMine: slot.myReaction,
                                  initialCount: slot.reactionCount,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: SizedBox(
                        height: s(3),
                        child: LinearProgressIndicator(
                          value: 1 - (_photoTimer?.value ?? 0),
                          backgroundColor: w(.07),
                          valueColor: AlwaysStoppedAnimation(
                            _photoHeld ? kCyanLite : kCyan,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: s(7)),
                    Text(
                      _photoHeld
                          ? 'holding — release to let it go'
                          : 'one-time view · hold anywhere to keep looking',
                      textAlign: TextAlign.center,
                      style: ts(
                        s,
                        weight: 400,
                        size: 10.5,
                        color: _photoHeld
                            ? kCyan.withValues(alpha: .8)
                            : txt(.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- REPLY DETAIL ----------
  Widget _detail(Scale s) {
    final r = kReplies.firstWhere((x) => x.id == replyDetailId);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Positioned.fill(
      child: _SlideUp(
        child: Container(
          color: kGround,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.only(
                          left: s(18),
                          top: safeTop + s(8),
                          right: s(18),
                          bottom: s(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => replyDetailId = null),
                              child: Container(
                                width: s(34),
                                height: s(34),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: w(.06),
                                  border: Border.all(color: w(.1), width: 1),
                                ),
                                child: Text(
                                  '‹',
                                  style: ts(
                                    s,
                                    weight: 400,
                                    size: 17,
                                    lh: 1,
                                    color: txt(.8),
                                  ),
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                Text(
                                  r.who,
                                  style: ts(
                                    s,
                                    weight: 600,
                                    size: 14,
                                    color: kText,
                                  ),
                                ),
                                SizedBox(height: s(2)),
                                Text(
                                  r.when,
                                  style: ts(
                                    s,
                                    weight: 400,
                                    size: 10,
                                    color: txt(.34),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(width: s(34), height: s(34)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: s(22),
                          top: s(8),
                          right: s(22),
                          bottom: s(18),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: s(150),
                              child: AspectRatio(
                                aspectRatio: 3 / 4,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(s(18)),
                                  child: Stack(
                                    children: [
                                      // Words-only reply -> the same black
                                      // TextPingCard the full-bleed viewer
                                      // uses, at this thumbnail's scale, so
                                      // the two surfaces agree. Anything
                                      // else keeps the gradient+hatch.
                                      if (r.photoUrl == null &&
                                          r.body.trim().isNotEmpty)
                                        Positioned.fill(
                                          child: TextPingCard(
                                            text: r.body,
                                            scale: s(0.5),
                                          ),
                                        )
                                      else ...[
                                        Positioned.fill(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: g160(
                                                kCyan.withValues(alpha: .14),
                                                const Color(0x1FB08968),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: HatchPainter(
                                              s(9),
                                              w(.09),
                                              w(.03),
                                            ),
                                          ),
                                        ),
                                      ],
                                      // Only a camera reply has a selfie
                                      // half — see InboundReply.selfieUrl's
                                      // own doc.
                                      if (r.selfieUrl != null)
                                        Positioned(
                                          top: s(9),
                                          left: s(9),
                                          child: Container(
                                            width: s(44),
                                            height: s(56),
                                            clipBehavior: Clip.antiAlias,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(s(10)),
                                              border: Border.all(
                                                color: w(.5),
                                                width: 1.5,
                                              ),
                                              color: w(.08),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: blk(.4),
                                                  blurRadius: s(14),
                                                  offset: Offset(0, s(4)),
                                                ),
                                              ],
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: r.selfieUrl!,
                                              fit: BoxFit.cover,
                                              memCacheWidth: 180,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: s(12)),
                            Text(
                              're: ${r.prompt}',
                              style: ts(
                                s,
                                weight: 400,
                                size: 10.5,
                                color: txt(.32),
                              ),
                            ),
                            SizedBox(height: s(8)),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: s(280)),
                              child: Text(
                                r.body,
                                textAlign: TextAlign.center,
                                style: ts(
                                  s,
                                  weight: 400,
                                  size: 15,
                                  lh: 1.6,
                                  color: txt(.85),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.only(
                          left: s(22),
                          top: s(14),
                          right: s(22),
                          bottom: s(24),
                        ),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: w(.07))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  'Comments',
                                  style: ts(
                                    s,
                                    weight: 600,
                                    size: 14,
                                    color: kText,
                                  ),
                                ),
                                SizedBox(width: s(8)),
                                Text(
                                  '1',
                                  style: ts(
                                    s,
                                    weight: 400,
                                    size: 11,
                                    color: txt(.32),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: s(12)),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: s(30),
                                  height: s(30),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: g160(kEarth[4][0], kEarth[4][1]),
                                  ),
                                ),
                                SizedBox(width: s(10)),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          'nonoka',
                                          style: ts(
                                            s,
                                            weight: 500,
                                            size: 12.5,
                                            color: kText,
                                          ),
                                        ),
                                        SizedBox(width: s(7)),
                                        Text(
                                          '2h ago',
                                          style: ts(
                                            s,
                                            weight: 400,
                                            size: 9.5,
                                            color: txt(.3),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: s(3)),
                                    Text(
                                      'this is so real',
                                      style: ts(
                                        s,
                                        weight: 400,
                                        size: 13.5,
                                        lh: 1.4,
                                        color: txt(.78),
                                      ),
                                    ),
                                    SizedBox(height: s(3)),
                                    Text(
                                      'Reply',
                                      style: ts(
                                        s,
                                        weight: 400,
                                        size: 10.5,
                                        color: txt(.32),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  left: s(16),
                  top: s(12),
                  right: s(16),
                  bottom: safeBottom + s(20),
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: w(.06))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: s(16),
                          vertical: s(11),
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: w(.05),
                          border: Border.all(color: w(.1), width: 1),
                        ),
                        child: Text(
                          'Add a comment…',
                          style: ts(s, weight: 400, size: 13.5, color: txt(.4)),
                        ),
                      ),
                    ),
                    SizedBox(width: s(10)),
                    Container(
                      width: s(38),
                      height: s(38),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: g180(kCyan, kCyanDeep),
                      ),
                      child: Text('💬', style: TextStyle(fontSize: s(15))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- ambient background: three slow drifting radial blobs ----
class _Ambient extends StatefulWidget {
  const _Ambient();
  @override
  State<_Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<_Ambient> with TickerProviderStateMixin {
  late final a = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);
  late final b = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  )..repeat(reverse: true);
  late final c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  )..repeat(reverse: true);

  @override
  void dispose() {
    a.dispose();
    b.dispose();
    c.dispose();
    super.dispose();
  }

  Widget blob(
    Animation<double> ctl,
    Offset from,
    Offset to,
    double size,
    Color color,
  ) => AnimatedBuilder(
    animation: ctl,
    builder: (_, _) {
      final o = Offset.lerp(from, to, Curves.easeInOut.transform(ctl.value))!;
      return Positioned(
        left: o.dx,
        top: o.dy,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, Colors.transparent],
                stops: const [0, .68],
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext ctx) => Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: kGround),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            blob(
              a,
              const Offset(-90, -140),
              const Offset(-72, -162),
              340,
              kCyan.withValues(alpha: .16),
            ),
            blob(
              b,
              const Offset(280, 220),
              const Offset(256, 236),
              320,
              kCyan.withValues(alpha: .15),
            ),
            blob(
              c,
              const Offset(40, 620),
              const Offset(58, 598),
              300,
              const Color(0xFFB08968).withValues(alpha: .10),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---- entrance animation for the detail overlay ----
class _SlideUp extends StatefulWidget {
  final Widget child;
  const _SlideUp({required this.child});
  @override
  State<_SlideUp> createState() => _SlideUpState();
}

class _SlideUpState extends State<_SlideUp>
    with SingleTickerProviderStateMixin {
  late final ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: ctl,
    builder: (_, child) {
      final t = Curves.easeOut.transform(ctl.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * MediaQuery.of(c).size.height * .04),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

// ============================================================================
// New-group flow
//
// Two steps in one sheet, then hands off to the prompt picker:
//   1. pick members  ("WHO'S IN · n PICKED")
//   2. name the group
//   → sheet closes, the ping prompt sheet opens for the new group
//
// Visual language follows the design's own compose-sheet member picker
// (.dc.html): pill chips, cyan when picked, glass sheet chrome.
// ============================================================================

class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet();
  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final picked = <String>{};
  final nameCtrl = TextEditingController();
  bool naming = false;

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  String get _defaultName {
    final names = kFriends
        .where((f) => picked.contains(f.id))
        .map((f) => f.who.split(' ').first)
        .toList();
    if (names.length <= 2) return names.join(' & ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final s = Scale(MediaQuery.of(context).size.width);
    final bottomPad =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    final canNext = picked.length >= 2;
    final canCreate = nameCtrl.text.trim().isNotEmpty || picked.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D12).withValues(alpha: .92),
              border: Border.all(color: w(.12), width: 1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // grab handle
                Padding(
                  padding: EdgeInsets.only(top: s(12), bottom: s(6)),
                  child: Center(
                    child: Container(
                      width: s(36),
                      height: s(4),
                      decoration: BoxDecoration(
                        color: w(.16),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                // header
                Padding(
                  padding: EdgeInsets.fromLTRB(s(18), s(6), s(14), s(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              naming ? 'Name the group' : 'New group',
                              style: ts(s, weight: 600, size: 15, color: kText),
                            ),
                            SizedBox(height: s(2)),
                            Text(
                              naming
                                  ? '${picked.length} people · you can change this later'
                                  : 'Pick who’s in — at least 2',
                              style: ts(
                                s,
                                weight: 400,
                                size: 11.5,
                                color: txt(.42),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => naming
                            ? setState(() => naming = false)
                            : Navigator.of(context).pop(),
                        child: Container(
                          width: s(28),
                          height: s(28),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: w(.06),
                            border: Border.all(color: w(.1), width: 1),
                          ),
                          child: Text(
                            naming ? '‹' : '×',
                            style: ts(
                              s,
                              weight: 400,
                              size: naming ? 15 : 13,
                              lh: 1,
                              color: txt(.7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: w(.07)),

                if (!naming) ...[
                  // ---- step 1: pick members ----
                  Padding(
                    padding: EdgeInsets.fromLTRB(s(16), s(14), s(16), s(10)),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'WHO’S IN · ${picked.length} PICKED',
                        style: ts(
                          s,
                          weight: 400,
                          size: 10,
                          em: .1,
                          color: txt(.34),
                        ),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: s(240)),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: s(16)),
                      child: Wrap(
                        spacing: s(7),
                        runSpacing: s(7),
                        children: [
                          for (final f in kFriends)
                            GestureDetector(
                              onTap: () => setState(() {
                                picked.contains(f.id)
                                    ? picked.remove(f.id)
                                    : picked.add(f.id);
                              }),
                              child: Container(
                                padding: EdgeInsets.only(
                                  left: s(7),
                                  top: s(6),
                                  right: s(12),
                                  bottom: s(6),
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(100),
                                  color: picked.contains(f.id)
                                      ? kCyan.withValues(alpha: .14)
                                      : w(.04),
                                  border: Border.all(
                                    color: picked.contains(f.id)
                                        ? kCyan.withValues(alpha: .4)
                                        : w(.1),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: s(20),
                                      height: s(20),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: g160(
                                          kEarth[f.tintIndex][0],
                                          kEarth[f.tintIndex][1],
                                        ),
                                      ),
                                      child: Text(
                                        f.initial,
                                        style: ts(
                                          s,
                                          weight: 500,
                                          size: 9,
                                          color: kDarkOnCyan,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: s(7)),
                                    Text(
                                      f.who,
                                      style: ts(
                                        s,
                                        weight: 400,
                                        size: 11.5,
                                        color: picked.contains(f.id)
                                            ? kText
                                            : txt(.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(s(16), s(14), s(16), s(18)),
                    child: GestureDetector(
                      onTap: !canNext
                          ? null
                          : () => setState(() {
                              naming = true;
                              nameCtrl.text = _defaultName;
                            }),
                      child: Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(vertical: s(13)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: canNext ? g180(kCyan, kCyanDeep) : null,
                          color: canNext ? null : w(.07),
                          boxShadow: canNext
                              ? [
                                  BoxShadow(
                                    color: kCyan.withValues(alpha: .3),
                                    blurRadius: s(24),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          canNext
                              ? 'Next · ${picked.length} picked'
                              : 'Pick at least 2',
                          style: ts(
                            s,
                            weight: 600,
                            size: 13,
                            color: canNext ? kGround : txt(.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // ---- step 2: name the group ----
                  Padding(
                    padding: EdgeInsets.fromLTRB(s(16), s(16), s(16), s(12)),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: s(16),
                        vertical: s(4),
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        color: w(.05),
                        border: Border.all(
                          color: kCyan.withValues(alpha: .3),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        style: ts(s, weight: 500, size: 14, color: kText),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          hintText: 'Group name…',
                          hintStyle: ts(
                            s,
                            weight: 400,
                            size: 14,
                            color: txt(.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // picked members preview
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: s(16)),
                    child: Row(
                      children: [
                        SizedBox(
                          height: s(26),
                          width: s(26) + s(16) * (picked.length - 1),
                          child: Stack(
                            children: [
                              for (int i = 0; i < picked.length; i++)
                                Positioned(
                                  left: s(16) * i,
                                  child: Builder(
                                    builder: (_) {
                                      // kFriends can be replaced by a
                                      // background reload while this sheet
                                      // is open — a picked id that's no
                                      // longer present just renders nothing
                                      // rather than throwing.
                                      Friend? f;
                                      for (final x in kFriends) {
                                        if (x.id == picked.elementAt(i)) {
                                          f = x;
                                          break;
                                        }
                                      }
                                      if (f == null)
                                        return const SizedBox.shrink();
                                      return Container(
                                        width: s(26),
                                        height: s(26),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: g160(
                                            kEarth[f.tintIndex][0],
                                            kEarth[f.tintIndex][1],
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFF0D0D12),
                                            width: 2,
                                          ),
                                        ),
                                        child: Text(
                                          f.initial,
                                          style: ts(
                                            s,
                                            weight: 500,
                                            size: 10,
                                            color: kDarkOnCyan,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: s(10)),
                        Text(
                          '${picked.length} people',
                          style: ts(s, weight: 400, size: 11, color: txt(.34)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(s(16), s(16), s(16), s(18)),
                    child: GestureDetector(
                      onTap: !canCreate
                          ? null
                          : () => Navigator.of(context).pop((
                              name: nameCtrl.text.trim().isEmpty
                                  ? _defaultName
                                  : nameCtrl.text.trim(),
                              memberIds: picked.toList(),
                            )),
                      child: Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(vertical: s(13)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: canCreate ? g180(kCyan, kCyanDeep) : null,
                          color: canCreate ? null : w(.07),
                          boxShadow: canCreate
                              ? [
                                  BoxShadow(
                                    color: kCyan.withValues(alpha: .3),
                                    blurRadius: s(24),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          'Create & ping',
                          style: ts(
                            s,
                            weight: 600,
                            size: 13,
                            color: canCreate ? kGround : txt(.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<List<Object?>>? _pingPrefetch;

/// Kicks off the Ping page's first load at app launch (MainShell), so the
/// data is already in hand when the tab is opened.
void prefetchPingData() {
  if (_pingPrefetch != null) return;
  _pingPrefetch = CurrentUserService.instance
      .resolveId()
      .then(_pingBatch)
      .catchError((Object e) {
        _pingPrefetch = null;
        throw e;
      });
}

/// Everything the Ping page needs, all at once. Index 10 is total_score —
/// the ONE combined score the Anon page and profile also show.
Future<List<Object?>> _pingBatch(String meId) => Future.wait<Object?>([
  // "Ping someone" = the people in MY Friends circle.
  CircleService.instance.fetchFriendsCircleUsers(),
  PingService.instance.fetchToReply(),
  PingService.instance.fetchSent(),
  PingService.instance.fetchReplies(),
  GroupService.instance.fetchMyGroups(),
  PingService.instance.fetchWalls(),
  PingService.instance.fetchStreaks(),
  CommunityService.instance.fetchMyCommunityMembers(),
  // Only used to ORDER the strip (pinned first).
  PostAuthorPinService.instance.pinnedIds().catchError((_) => <String>{}),
  GroupService.instance.fetchMyGroupPingOverview(),
  supabase
      .from('users')
      .select('total_score')
      .eq('id', meId)
      .maybeSingle()
      .then((row) => (row?['total_score'] as num?)?.toInt()),
]);
