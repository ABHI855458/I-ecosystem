import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../shared/score_tier.dart';
import '../notifications/notifications_screen.dart';
import 'ping_reveal_screen.dart';

// ---------------------------------------------------------------------------
// Enums + Data models
// ---------------------------------------------------------------------------

enum _MsgType { text, photo, voice }

class _PingEntry {
  const _PingEntry({
    required this.username,
    required this.time,
    required this.streakDays,
    required this.isPhoto,
    this.photoColor = const Color(0xFF1A2030),
    this.textReply = '',
    this.hasUnrevealedReply = false,
    this.replyPhotoColor = const Color(0xFF1A2030),
    this.replyPhotoColors = const [],
  });

  final String username;
  final String time;
  final int streakDays;
  final bool isPhoto;
  final Color photoColor;
  final String textReply;
  final bool hasUnrevealedReply;
  final Color replyPhotoColor;
  final List<Color> replyPhotoColors;
}

class _GroupEntry {
  const _GroupEntry({
    required this.name,
    required this.memberNames,
    required this.replyColors,
    required this.prompt,
  });

  final String name;
  final List<String> memberNames;
  final List<Color> replyColors;
  final String prompt;
}

class _AnonMessage {
  const _AnonMessage({
    this.type = _MsgType.text,
    required this.isMe,
    required this.time,
    this.text = '',
    this.photoColor = const Color(0xFF1A2030),
    this.voiceSecs = 0,
  });

  final _MsgType type;
  final bool isMe;
  final String time;
  final String text;
  final Color photoColor;
  final int voiceSecs;
}

class _AnonThread {
  const _AnonThread({
    required this.handle,
    required this.originalPost,
    required this.messages,
  });

  final String handle;
  final String originalPost;
  final List<_AnonMessage> messages;
}

// ---------------------------------------------------------------------------
// Dummy data
// ---------------------------------------------------------------------------

const _pings = [
  _PingEntry(
    username: 'alex_xyz',
    time: '2h',
    streakDays: 7,
    isPhoto: true,
    photoColor: Color(0xFF2A3040),
    hasUnrevealedReply: true,
    replyPhotoColor: Color(0xFF3A2050),
    replyPhotoColors: [
      Color(0xFF3A2050),
      Color(0xFF204060),
      Color(0xFF503020),
    ],
  ),
  _PingEntry(
    username: 'jordan_23',
    time: '4h',
    streakDays: 3,
    isPhoto: true,
    photoColor: Color(0xFF30281A),
    hasUnrevealedReply: true,
    replyPhotoColor: Color(0xFF2A1830),
    replyPhotoColors: [
      Color(0xFF2A1830),
      Color(0xFF1A3828),
    ],
  ),
  _PingEntry(
    username: 'study_bug',
    time: '1h',
    streakDays: 1,
    isPhoto: false,
    textReply: 'honestly yeah, every single day. it never gets easier',
  ),
  _PingEntry(
    username: 'sunset_chaser',
    time: '3h',
    streakDays: 12,
    isPhoto: true,
    photoColor: Color(0xFF382818),
  ),
  _PingEntry(
    username: 'coffee_talk',
    time: '5h',
    streakDays: 2,
    isPhoto: true,
    photoColor: Color(0xFF182030),
  ),
];

const _groups = [
  _GroupEntry(
    name: 'The Squad',
    memberNames: ['alex_xyz', 'jordan_23', 'study_bug', 'sunset_chaser'],
    replyColors: [
      Color(0xFF2A3040),
      Color(0xFF30281A),
      Color(0xFF1E2A28),
      Color(0xFF382818),
    ],
    prompt: 'Show us where you are right now',
  ),
  _GroupEntry(
    name: 'Study Crew',
    memberNames: ['study_bug', 'coffee_talk', 'library_mode'],
    replyColors: [
      Color(0xFF1E2A28),
      Color(0xFF182030),
      Color(0xFF1A2830),
    ],
    prompt: 'What are you studying today?',
  ),
  _GroupEntry(
    name: 'Fest Gang',
    memberNames: [
      'alex_xyz',
      'jordan_23',
      'fest_vibes',
      'campus_life',
      'sunset_chaser',
    ],
    replyColors: [
      Color(0xFF2A3040),
      Color(0xFF30281A),
      Color(0xFF1E3028),
      Color(0xFF3A2A10),
      Color(0xFF382818),
    ],
    prompt: 'Best moment from yesterday?',
  ),
];

const _anonThreads = [
  _AnonThread(
    handle: 'paper_crane42',
    originalPost:
        "Does anyone else feel like they're performing a version of themselves that isn't really them?",
    messages: [
      _AnonMessage(
        text: 'yes, literally every day',
        isMe: false,
        time: '2h',
      ),
      _AnonMessage(
        type: _MsgType.photo,
        isMe: true,
        time: '2h',
        photoColor: Color(0xFF1C2840),
      ),
      _AnonMessage(
        type: _MsgType.voice,
        isMe: false,
        time: '1h',
        voiceSecs: 12,
      ),
      _AnonMessage(
        text: 'that resonated. a lot.',
        isMe: true,
        time: '1h',
      ),
    ],
  ),
  _AnonThread(
    handle: 'velvet_echo19',
    originalPost: "Failed my internals again. Can't tell my parents.",
    messages: [
      _AnonMessage(
        text: 'same boat. failed two this sem',
        isMe: false,
        time: '5h',
      ),
      _AnonMessage(
        text: 'what are you going to do',
        isMe: true,
        time: '4h',
      ),
      _AnonMessage(
        type: _MsgType.photo,
        isMe: false,
        time: '4h',
        photoColor: Color(0xFF281828),
      ),
      _AnonMessage(
        text: 'yeah. one day at a time',
        isMe: true,
        time: '3h',
      ),
      _AnonMessage(text: 'you get it 🙏', isMe: false, time: '2h'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Redesign — shared 3-state model (To Reply / Sent / Replies) layered on
// top of the existing dummy data above. No backend exists for any of this
// (the whole ping feature is mocked), so this is UI-layer bucketing, not a
// new persistence model.
// ---------------------------------------------------------------------------

enum _PingState { toReply, sent, replies }

// ---------------------------------------------------------------------------
// Reply-window helpers — shared by every category's "To Reply" bucket.
// A ping's re-entry window is [sentAt, sentAt + windowHours); once it lapses
// the ping is gone for good (filtered out, not just visually dimmed). This
// mirrors the `pings.expires_at` column already in supabase/schema.sql — see
// PingItem.sentAt/windowHours for the concrete field pairing.
// ---------------------------------------------------------------------------

DateTime _replyWindowExpiresAt(DateTime sentAt, int windowHours) =>
    sentAt.add(Duration(hours: windowHours));

bool _replyWindowExpired(DateTime sentAt, int windowHours) =>
    DateTime.now().isAfter(_replyWindowExpiresAt(sentAt, windowHours));

/// Gentle phrasing on purpose — this is an ambient indicator, not a
/// stressful countdown.
String _windowLabel(DateTime sentAt, int windowHours) {
  final left = _replyWindowExpiresAt(sentAt, windowHours).difference(DateTime.now());
  if (left.isNegative) return 'reply window closed';
  if (left.inHours >= 1) return '${left.inHours}h left to reply';
  if (left.inMinutes >= 1) return '${left.inMinutes}m left to reply';
  return 'reply window closing';
}

/// A reply stays viewable forever once received, but the "Ping Back"
/// shortcut at the top of its row only lasts 24h from the first time it was
/// opened.
bool _pingBackStillAvailable(DateTime? viewedAt) =>
    viewedAt != null && DateTime.now().difference(viewedAt) < const Duration(hours: 24);

/// Friends "Sent" bucket — pings the user sent, awaiting a reply. Mutable
/// (not const) because [seen] flips true once flipped by the demo timer in
/// _FriendsPingTabState, driving both the row's seen indicator and the
/// "your ping was seen" notification. [windowHours] is whatever the sender
/// picked in PingSendSheet (display-only here — the window itself is
/// enforced on the recipient's "To Reply" row).
class _SentPing {
  _SentPing({
    required this.name,
    required this.prompt,
    required this.sentAgo,
    this.windowHours = 6,
  });

  final String name;
  final String prompt;
  final String sentAgo;
  final int windowHours;
  bool seen = false;
}

final _sentFriendPings = [
  _SentPing(
    name: 'coffee_talk',
    prompt: 'What are you studying today?',
    sentAgo: '35m ago',
  ),
  _SentPing(
    name: 'library_mode',
    prompt: 'Show me your view 👀',
    sentAgo: '2h ago',
    windowHours: 12,
  ),
];

/// Friends "Replies" bucket — wraps the static [_PingEntry] dummy data with
/// the mutable view-state the redesign needs: [unrevealed] drives the "NEW"
/// badge/prominent styling, and [viewedAt] (set on first open) drives the
/// 24h "Ping Back" banner via [_pingBackStillAvailable]. Replies never leave
/// this list — viewing one only changes how it's styled, never removes it.
class _ReplyUi {
  _ReplyUi(this.entry) : unrevealed = entry.hasUnrevealedReply;

  final _PingEntry entry;
  bool unrevealed;
  DateTime? viewedAt;

  bool get pingBackAvailable => _pingBackStillAvailable(viewedAt);
}

/// Groups don't carry per-user status in `_GroupEntry`, so each group is
/// assigned a demo bucket + reply-window here. [answered] removes a
/// "To Reply" group once the user has replied to its prompt (same rule as
/// Friends: leaves the bucket on success, not on merely opening it).
/// [viewedAt]/[pingBackAvailable] drive the 24h ping-back banner for
/// "Replies"-bucket groups, same as Friends' [_ReplyUi].
class _GroupUi {
  _GroupUi({
    required this.group,
    required this.state,
    required this.sentAt,
  });

  final _GroupEntry group;
  final _PingState state;
  final DateTime sentAt;
  final int windowHours = 6;
  bool seen = false;
  bool answered = false;
  DateTime? viewedAt;

  bool get pingBackAvailable => _pingBackStillAvailable(viewedAt);
}

final _groupUi = [
  _GroupUi(
    group: _groups[2], // Fest Gang
    state: _PingState.toReply,
    sentAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  _GroupUi(
    group: _groups[1], // Study Crew
    state: _PingState.sent,
    sentAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  _GroupUi(
    group: _groups[0], // The Squad
    state: _PingState.replies,
    sentAt: DateTime.now().subtract(const Duration(hours: 6)),
  ),
];

/// Anonymous threads are ongoing chats rather than single pings, so the
/// bucket is derived from who sent the last message: if they did, it's
/// waiting on the user ("To Reply"); if the user did, it's awaiting them
/// ("Sent") — unless [answered] overrides it (see _AnonThreadView.onReplied).
/// There's no unrevealed/blurred-reply concept in this data, so anon threads
/// never land in "Replies", and there's no per-message seen flag either, so
/// (unlike Friends/Groups) anon "Sent" rows don't show a seen indicator.
class _AnonThreadUi {
  _AnonThreadUi(this.thread) : sentAt = _parseRelativeHours(thread.messages.last.time);

  final _AnonThread thread;
  final DateTime sentAt;
  final int windowHours = 6;
  bool answered = false;

  _PingState get state {
    if (answered) return _PingState.sent;
    return thread.messages.last.isMe ? _PingState.sent : _PingState.toReply;
  }
}

final _anonThreadUi = _anonThreads.map((t) => _AnonThreadUi(t)).toList();

/// Turns dummy relative-time labels like '2h' into an actual DateTime so the
/// reply-window math has something to work from. Falls back to "now" for
/// anything not in that shape (e.g. 'now') — fine for demo data.
DateTime _parseRelativeHours(String label) {
  final match = RegExp(r'^(\d+)h$').firstMatch(label);
  if (match == null) return DateTime.now();
  return DateTime.now().subtract(Duration(hours: int.parse(match.group(1)!)));
}

// ---------------------------------------------------------------------------
// PingScreen
// ---------------------------------------------------------------------------

class PingScreen extends StatefulWidget {
  const PingScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient "living network" layer — behind everything, ignores
          // touches, cross-fades hue as you swipe between categories.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _tabCtrl.animation!,
              builder: (context, _) {
                final v = _tabCtrl.animation!.value.clamp(0.0, 2.0);
                final lo = v.floor().clamp(0, 2);
                final hi = v.ceil().clamp(0, 2);
                final accent =
                    Color.lerp(_categoryAccent(lo), _categoryAccent(hi), v - lo)!;
                return _AmbientBackground(accent: accent);
              },
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: topPad + 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _PingCategoryBar(controller: _tabCtrl),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _FriendsPingTab(bottomPad: bottomPad),
                    _GroupsPingTab(bottomPad: bottomPad),
                    _AnonPingTab(bottomPad: bottomPad),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-category accent — the one deliberate hue "live" on screen at a time
// (used with discipline: one dominant color per category, not all three
// firing at once). Friends=cyan, Groups=electric purple, Anonymous=magenta.
// ---------------------------------------------------------------------------

Color _categoryAccent(int categoryIndex) {
  switch (categoryIndex) {
    case 0:
      return AppColors.neonCyan;
    case 1:
      return AppColors.electricPurple;
    default:
      return AppColors.vibrantMagenta;
  }
}

// ---------------------------------------------------------------------------
// Ambient background — soft glowing "ping streaks" that occasionally
// travel across the screen plus a handful of slow-breathing points,
// suggesting a live network without ever demanding attention. Purely
// decorative: IgnorePointer + its own RepaintBoundary, so its per-frame
// repaint never touches the row list drawn above it. One AnimationController
// driving a few Path/circle draws per frame — cheap enough to stay smooth.
// ---------------------------------------------------------------------------

class _AmbientBackground extends StatefulWidget {
  const _AmbientBackground({required this.accent});
  final Color accent;

  @override
  State<_AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<_AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _AmbientPainter(t: _ctrl.value, accent: widget.accent),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _AmbientStreak {
  const _AmbientStreak(this.start, this.end, this.phase);
  final Offset start; // fractional screen position, 0..1
  final Offset end;
  final double phase; // 0..1 offset into the shared loop
}

// Fixed, hand-placed rather than randomized per-frame — a stable "constellation"
// reads as intentional; regenerating positions every build would look noisy.
const _ambientStreaks = [
  _AmbientStreak(Offset(-0.15, 0.16), Offset(1.15, 0.52), 0.0),
  _AmbientStreak(Offset(1.15, 0.08), Offset(-0.15, 0.42), 0.35),
  _AmbientStreak(Offset(-0.15, 0.78), Offset(1.15, 0.34), 0.62),
  _AmbientStreak(Offset(1.10, 0.90), Offset(0.05, 0.62), 0.85),
];

const _ambientPoints = [
  Offset(0.16, 0.10),
  Offset(0.86, 0.18),
  Offset(0.74, 0.46),
  Offset(0.18, 0.53),
  Offset(0.55, 0.74),
  Offset(0.90, 0.86),
];

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({required this.t, required this.accent});
  final double t;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // Traveling glow streaks — each runs its own lap of the shared loop,
    // fading in/out via a sin envelope so it reads as "occasional," not
    // constant.
    for (final s in _ambientStreaks) {
      final localT = (t + s.phase) % 1.0;
      final envelope = math.sin(localT * math.pi).clamp(0.0, 1.0);
      if (envelope <= 0.02) continue;
      final pos = Offset.lerp(s.start, s.end, localT)!;
      final dir = s.end - s.start;
      final norm = dir.distance == 0 ? const Offset(1, 0) : dir / dir.distance;
      final head = Offset(pos.dx * size.width, pos.dy * size.height);
      final tail = head - Offset(norm.dx, norm.dy) * 90;

      final paint = Paint()
        ..shader = ui.Gradient.linear(
          tail,
          head,
          [accent.withValues(alpha: 0.0), accent.withValues(alpha: 0.30 * envelope)],
        )
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawLine(tail, head, paint);
    }

    // Slow-breathing ping points
    for (int i = 0; i < _ambientPoints.length; i++) {
      final p = _ambientPoints[i];
      final phase = i * 0.9;
      final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 1.4 + phase);
      final center = Offset(p.dx * size.width, p.dy * size.height);
      final radius = 2.5 + breathe * 2.5;
      final alpha = 0.10 + breathe * 0.16;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = accent.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.t != t || old.accent != accent;
}

// ---------------------------------------------------------------------------
// Segmented category bar — Friends / Groups / Anonymous. Frosted glass
// shell (blurred, semi-transparent, subtle white border) with the active
// segment glowing in that category's accent color.
// ---------------------------------------------------------------------------

class _PingCategoryBar extends StatelessWidget {
  const _PingCategoryBar({required this.controller});

  final TabController controller;

  static const _labels = ['Friends', 'Groups', 'Anonymous'];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final accent = _categoryAccent(controller.index);
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                children: [
                  for (int i = 0; i < _labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => controller.animateTo(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: controller.index == i
                                ? accent.withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                            border: controller.index == i
                                ? Border.all(color: accent.withValues(alpha: 0.55))
                                : null,
                            boxShadow: controller.index == i
                                ? [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      spreadRadius: -1,
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _labels[i],
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: controller.index == i
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: controller.index == i
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// SUBTAB 1 — Everyone: 1-on-1 ping cards
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Shared glass-row primitives — used by all three category tabs below.
// Muted palette only: whites/greys/translucency, no hue-based accents.
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          color: Colors.white.withValues(alpha: 0.38),
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Compact frosted-glass row. [prominent] rows (To Reply) sit brighter;
/// everything else (Sent, seen Replies) is quieter — the only difference
/// is opacity/brightness, never color.
class _GlassRow extends StatelessWidget {
  const _GlassRow({
    required this.child,
    this.onTap,
    this.prominent = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: prominent ? 0.09 : 0.045),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: prominent ? 0.16 : 0.10),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact glass affordance for the existing "start a new ping" flows
/// (PingSendSheet / _CreateGroupSheet / _NewPingSheet) — kept intact and
/// reachable per category, just no longer a big gradient CTA.
class _NewPingEntry extends StatelessWidget {
  const _NewPingEntry({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.55)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: Colors.white.withValues(alpha: 0.30)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [glow] adds a colored ring; [pulse] makes that ring breathe (via
/// [_PulseGlow]) rather than sit static — used for prominent/live rows
/// (To Reply, unrevealed Replies) vs. a steady glow for quieter ones (Sent,
/// seen Replies). No glow at all falls back to the plain white ring.
class _PingAvatar extends StatelessWidget {
  const _PingAvatar({
    required this.label,
    this.color,
    this.glow,
    this.pulse = false,
    this.urgent = false,
  });
  final String label;
  final Color? color;
  final Color? glow;
  final bool pulse;

  /// Faster, brighter pulse — used for "NEW"/unrevealed rows so they read
  /// as more alive than a steady "To Reply" glow.
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (color ?? const Color(0xFF1C1C22)).withValues(alpha: 0.90),
        border: Border.all(
          color: glow != null ? glow!.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.14),
          width: glow != null ? 1.4 : 1.0,
        ),
      ),
      child: Center(
        child: Text(
          label.isNotEmpty ? label[0].toUpperCase() : '?',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ),
    );

    final g = glow;
    if (g == null) return avatar;
    if (!pulse) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: g.withValues(alpha: 0.32), blurRadius: 10)],
        ),
        child: avatar,
      );
    }
    return _PulseGlow(
      color: g,
      minAlpha: urgent ? 0.35 : 0.25,
      maxAlpha: urgent ? 0.75 : 0.55,
      blur: urgent ? 18 : 14,
      period: urgent ? const Duration(milliseconds: 1300) : const Duration(milliseconds: 2000),
      child: avatar,
    );
  }
}

/// Breathing glow ring around [child] — one AnimationController per
/// instance, isolated in its own RepaintBoundary so the pulse never forces
/// a repaint outside itself. Cheap enough to run on every row in a section
/// at once without threatening frame time.
class _PulseGlow extends StatefulWidget {
  const _PulseGlow({
    required this.child,
    required this.color,
    this.minAlpha = 0.25,
    this.maxAlpha = 0.60,
    this.blur = 14,
    this.period = const Duration(milliseconds: 2000),
  });

  final Widget child;
  final Color color;
  final double minAlpha;
  final double maxAlpha;
  final double blur;
  final Duration period;

  @override
  State<_PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<_PulseGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period)..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_ctrl.value);
          final alpha = widget.minAlpha + (widget.maxAlpha - widget.minAlpha) * t;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: widget.color.withValues(alpha: alpha), blurRadius: widget.blur, spreadRadius: 1),
              ],
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

Widget _ageText(String label) => Text(
      label,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        color: Colors.white.withValues(alpha: 0.40),
      ),
    );

Widget _seenChip(bool seen) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          seen ? Icons.done_all_rounded : Icons.schedule_rounded,
          size: 12,
          color: Colors.white.withValues(alpha: seen ? 0.55 : 0.30),
        ),
        const SizedBox(width: 4),
        Text(
          seen ? 'seen' : 'unseen',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: Colors.white.withValues(alpha: seen ? 0.55 : 0.30),
          ),
        ),
      ],
    );

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.30),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ExpandableReplyCard — the "To Reply" row. Tapping/holding it no longer
// navigates anywhere: it grows in place into a taller card (identity +
// prompt on top, an inline reply surface filling the rest — camera mock for
// Friends, prompt-picker for Groups, composer for Anonymous). Sending a
// reply does not collapse it, so the user can send as many as they want;
// only the chevron (or the caller expanding a different row, which
// implicitly collapses this one) closes it back to the compact row.
// ---------------------------------------------------------------------------

class _ExpandableReplyCard extends StatelessWidget {
  const _ExpandableReplyCard({
    required this.expanded,
    required this.accent,
    required this.onExpand,
    required this.onCollapse,
    required this.headerBuilder,
    required this.trailing,
    required this.surfaceBuilder,
  });

  final bool expanded;
  final Color accent;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;

  /// Same identity/prompt content in both states — the caller varies how
  /// it's styled (e.g. blurred + compact vs. plain + larger) based on the
  /// [expanded] flag it's given.
  final Widget Function(bool expanded) headerBuilder;

  /// Window-label + lock ring — collapsed state only.
  final Widget trailing;

  /// The inline camera/prompt/composer surface — expanded state only.
  final WidgetBuilder surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: expanded ? 0.07 : 0.09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: expanded ? 0.55 : 0.30)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: expanded ? 0.28 : 0.12),
                  blurRadius: expanded ? 26 : 12,
                  spreadRadius: expanded ? 1 : 0,
                ),
              ],
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded ? _buildExpanded(context) : _buildCollapsed(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    return GestureDetector(
      key: const ValueKey('collapsed'),
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: Row(
        children: [
          Expanded(child: headerBuilder(false)),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return Column(
      key: const ValueKey('expanded'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: headerBuilder(true)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCollapse,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.keyboard_arrow_up_rounded,
                    color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        surfaceBuilder(context),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline reply surfaces — the "rest of the card" once a To-Reply row is
// expanded. Each is self-contained: it owns its own sent-count/flash
// feedback, never collapses the card, and can be used to send more than
// once. Friends gets the mocked camera treatment already used by
// _PingReceiveScreen (this app has no live CameraController wired to the
// ping-reply flow — PingCameraScreen's real `camera` package usage belongs
// to a different, unrelated flow — so this stays a mock rather than risking
// a camera init failure on simulators with no hardware camera). Groups
// reuses _PingBackSheet's prompt chips inline; Anonymous gets a compact
// text composer.
// ---------------------------------------------------------------------------

class _InlineCameraSurface extends StatefulWidget {
  const _InlineCameraSurface({required this.accent});
  final Color accent;

  @override
  State<_InlineCameraSurface> createState() => _InlineCameraSurfaceState();
}

class _InlineCameraSurfaceState extends State<_InlineCameraSurface> {
  int _sentCount = 0;
  bool _flash = false;

  Future<void> _capture() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _sentCount++;
      _flash = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (mounted) setState(() => _flash = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFF07070A),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 28, color: Colors.white.withValues(alpha: 0.18)),
                        const SizedBox(height: 6),
                        Text(
                          'rear camera',
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10, color: Colors.white.withValues(alpha: 0.16)),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 42,
                      height: 56,
                      color: const Color(0xFF13131A),
                      child: Icon(Icons.face_retouching_natural,
                          size: 16, color: Colors.white.withValues(alpha: 0.18)),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _flash ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Center(
                        child: Icon(Icons.check_circle_rounded,
                            color: widget.accent, size: 34),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _sentCount == 0
                    ? 'tap the shutter to reply'
                    : '$_sentCount sent — send another anytime',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.40)),
              ),
            ),
            GestureDetector(
              onTap: _capture,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: widget.accent.withValues(alpha: 0.70), width: 2),
                  boxShadow: [
                    BoxShadow(color: widget.accent.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineGroupReplySurface extends StatefulWidget {
  const _InlineGroupReplySurface({required this.accent});
  final Color accent;

  @override
  State<_InlineGroupReplySurface> createState() => _InlineGroupReplySurfaceState();
}

class _InlineGroupReplySurfaceState extends State<_InlineGroupReplySurface> {
  int? _selected;
  int _sentCount = 0;

  void _send() {
    if (_selected == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _sentCount++;
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < _kPingBackPrompts.length; i++)
              GestureDetector(
                onTap: () => setState(() => _selected = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selected == i
                        ? widget.accent.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _selected == i
                          ? widget.accent.withValues(alpha: 0.65)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    _kPingBackPrompts[i],
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _selected == i ? Colors.white : Colors.white.withValues(alpha: 0.60),
                      fontWeight: _selected == i ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _sentCount == 0 ? 'pick one to send' : '$_sentCount sent — send another anytime',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.40)),
              ),
            ),
            GestureDetector(
              onTap: _selected == null ? null : _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _selected == null ? Colors.white.withValues(alpha: 0.08) : widget.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.send_rounded,
                        size: 14,
                        color: _selected == null ? Colors.white.withValues(alpha: 0.30) : Colors.black),
                    const SizedBox(width: 6),
                    Text(
                      'Send',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _selected == null ? Colors.white.withValues(alpha: 0.30) : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineAnonComposer extends StatefulWidget {
  const _InlineAnonComposer({required this.accent});
  final Color accent;

  @override
  State<_InlineAnonComposer> createState() => _InlineAnonComposerState();
}

class _InlineAnonComposerState extends State<_InlineAnonComposer> {
  final _ctrl = TextEditingController();
  int _sentCount = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    if (_ctrl.text.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _sentCount++;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.accent.withValues(alpha: 0.30)),
          ),
          child: TextField(
            controller: _ctrl,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Say something back…',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.30)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _sentCount == 0 ? 'stays anonymous' : '$_sentCount sent — send another anytime',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.40)),
              ),
            ),
            GestureDetector(
              onTap: _ctrl.text.trim().isEmpty ? null : _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _ctrl.text.trim().isEmpty
                      ? Colors.white.withValues(alpha: 0.08)
                      : widget.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.send_rounded,
                  size: 16,
                  color: _ctrl.text.trim().isEmpty ? Colors.white.withValues(alpha: 0.30) : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SUBTAB — Friends: 1-on-1 pings, grouped To Reply / Sent / Replies
// ---------------------------------------------------------------------------

class _FriendsPingTab extends StatefulWidget {
  const _FriendsPingTab({required this.bottomPad});

  final double bottomPad;

  @override
  State<_FriendsPingTab> createState() => _FriendsPingTabState();
}

class _FriendsPingTabState extends State<_FriendsPingTab> {
  static const _accent = AppColors.neonCyan;

  late List<PingItem> _toReply;
  late List<_SentPing> _sent;
  late List<_ReplyUi> _replies;
  Timer? _seenTimer;

  // Only one "To Reply" card expanded at a time — expanding a different one
  // implicitly collapses whichever was open.
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _toReply = [
      PingItem(
        senderName: 'alex_xyz',
        avatarColor: const Color(0xFF2A3040),
        timeAgo: '2h ago',
        prompt: 'Show me your view 👀',
        sentAt: DateTime.now().subtract(const Duration(hours: 2)),
        // default 6h window → ~4h left, shown on the row
      ),
      PingItem(
        senderName: 'study_bug',
        avatarColor: const Color(0xFF1E2A28),
        timeAgo: 'yesterday',
        prompt: 'What are you doing right now?',
        sentAt: DateTime.now().subtract(const Duration(hours: 20)),
        windowHours: 24, // sender picked a longer window at send time
      ),
    ];
    _sent = _sentFriendPings;
    _replies = _pings.map((e) => _ReplyUi(e)).toList();

    // Demo of the "seen" mechanic: simulates the recipient opening the
    // first sent ping a few seconds after this screen loads, which flips
    // the row's seen indicator and fires the "your ping was seen"
    // notification via notifState. Captured up front so a newly-sent ping
    // inserted at the top of _sent doesn't hijack the timer.
    final demoTarget = _sent.isNotEmpty ? _sent.first : null;
    if (demoTarget != null) {
      _seenTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted || demoTarget.seen) return;
        setState(() => demoTarget.seen = true);
        notifState.firePingSeen(demoTarget.name);
      });
    }
  }

  @override
  void dispose() {
    _seenTimer?.cancel();
    super.dispose();
  }

  List<PingItem> get _visibleToReply =>
      _toReply.where((p) => !_replyWindowExpired(p.sentAt, p.windowHours)).toList();

  void _toggleExpanded(String id) {
    HapticFeedback.selectionClick();
    setState(() => _expandedId = _expandedId == id ? null : id);
  }

  void _openReply(_ReplyUi r) {
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PingRepliesFeedScreen(
          senderName: r.entry.username,
          replies: r.entry.replyPhotoColors.isNotEmpty
              ? r.entry.replyPhotoColors
              : [r.entry.replyPhotoColor],
        ),
      ),
    )
        .then((_) {
      if (!mounted) return;
      setState(() {
        r.unrevealed = false;
        // First view only — re-opening later doesn't reset the 24h window.
        r.viewedAt ??= DateTime.now();
      });
    });
  }

  void _pingBack(String name) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PingBackSheet(recipientName: name),
    );
  }

  void _openNewPingSheet() {
    showModalBottomSheet<(String, String, int)?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PingSendSheet(),
    ).then((result) {
      if (result == null || !mounted) return;
      final (name, prompt, hours) = result;
      setState(() {
        _sent.insert(
          0,
          _SentPing(name: name, prompt: prompt, sentAgo: 'just now', windowHours: hours),
        );
      });
      showPingSentToast(context, name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleToReply = _visibleToReply;
    final hasAny = visibleToReply.isNotEmpty || _sent.isNotEmpty || _replies.isNotEmpty;

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPad + 24),
      children: [
        _NewPingEntry(
          label: 'Ping a friend',
          icon: Icons.add_rounded,
          onTap: _openNewPingSheet,
        ),
        if (!hasAny) const _EmptyCategory('No pings yet — say hi 👋'),
        if (visibleToReply.isNotEmpty) ...[
          const _SectionLabel('TO REPLY'),
          for (final ping in visibleToReply)
            _ExpandableReplyCard(
              expanded: _expandedId == ping.senderName,
              accent: _accent,
              onExpand: () => _toggleExpanded(ping.senderName),
              onCollapse: () => _toggleExpanded(ping.senderName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ageText(_windowLabel(ping.sentAt, ping.windowHours)),
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: _accent.withValues(alpha: 0.65)),
                ],
              ),
              headerBuilder: (expanded) {
                final blur = expanded ? 0.0 : 8.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PingAvatar(
                      label: ping.senderName,
                      color: ping.avatarColor,
                      glow: _accent,
                      pulse: true,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ping.senderName,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: expanded ? 15 : 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                            child: Text(
                              ping.prompt,
                              style: GoogleFonts.inter(
                                fontSize: expanded ? 13 : 12,
                                color: Colors.white.withValues(alpha: expanded ? 0.75 : 0.55),
                              ),
                              maxLines: expanded ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              surfaceBuilder: (context) => _InlineCameraSurface(accent: _accent),
            ),
          const SizedBox(height: 8),
        ],
        if (_sent.isNotEmpty) ...[
          const _SectionLabel('SENT'),
          for (final s in _sent)
            _GlassRow(
              child: Row(
                children: [
                  _PingAvatar(label: s.name, glow: _accent.withValues(alpha: 0.6)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.name,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.70),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.prompt,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.40),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _seenChip(s.seen),
                      const SizedBox(height: 3),
                      _ageText('${s.sentAgo} · ${s.windowHours}h window'),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (_replies.isNotEmpty) ...[
          const _SectionLabel('REPLIES'),
          for (final r in _replies)
            _GlassRow(
              prominent: r.unrevealed,
              onTap: () => _openReply(r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (r.pingBackAvailable) ...[
                    GestureDetector(
                      onTap: () => _pingBack(r.entry.username),
                      child: Row(
                        children: [
                          Icon(Icons.replay_rounded,
                              size: 13, color: Colors.white.withValues(alpha: 0.55)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ping back available',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.60),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 14, color: Colors.white.withValues(alpha: 0.35)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                    ),
                  ],
                  Row(
                    children: [
                      _PingAvatar(
                        label: r.entry.username,
                        glow: _accent,
                        pulse: r.unrevealed,
                        urgent: r.unrevealed,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  r.entry.username,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                if (r.unrevealed) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'NEW',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white.withValues(alpha: 0.75),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              r.unrevealed
                                  ? 'hold to reveal their reply'
                                  : (r.entry.isPhoto ? 'photo · seen' : r.entry.textReply),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color:
                                    Colors.white.withValues(alpha: r.unrevealed ? 0.55 : 0.35),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SUBTAB 2 — Group pings
// ---------------------------------------------------------------------------

class _GroupsPingTab extends StatefulWidget {
  const _GroupsPingTab({required this.bottomPad});

  final double bottomPad;

  @override
  State<_GroupsPingTab> createState() => _GroupsPingTabState();
}

class _GroupsPingTabState extends State<_GroupsPingTab> {
  static const _accent = AppColors.electricPurple;

  String? _expandedId;

  void _toggleExpanded(String id) {
    HapticFeedback.selectionClick();
    setState(() => _expandedId = _expandedId == id ? null : id);
  }

  void _createGroup() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateGroupSheet(),
    );
  }

  void _openGroup(_GroupUi g) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => _GroupDetailView(group: g.group)))
        .then((_) {
      if (!mounted) return;
      // First view only — starts the 24h "Ping Back" banner window.
      setState(() => g.viewedAt ??= DateTime.now());
    });
  }

  // Groups don't have a dedicated "reply to the daily prompt" screen — the
  // existing prompt-picker sheet (_PingBackSheet) is the closest reusable
  // reply mechanic, so both "To Reply" completion and a Replies-row
  // "Ping Back" tap route here.
  Future<void> _replyToGroup(_GroupUi g) async {
    HapticFeedback.lightImpact();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PingBackSheet(recipientName: g.group.name),
    );
    // Only leaves "To Reply" once actually answered — same rule as Friends.
    if (sent == true && mounted) setState(() => g.answered = true);
  }

  @override
  Widget build(BuildContext context) {
    final toReply = _groupUi
        .where((g) =>
            g.state == _PingState.toReply &&
            !g.answered &&
            !_replyWindowExpired(g.sentAt, g.windowHours))
        .toList();
    final sent = _groupUi.where((g) => g.state == _PingState.sent).toList();
    final replies = _groupUi.where((g) => g.state == _PingState.replies).toList();

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPad + 24),
      children: [
        _NewPingEntry(
          label: 'Start a group ping',
          icon: Icons.group_add_rounded,
          onTap: _createGroup,
        ),
        if (toReply.isEmpty && sent.isEmpty && replies.isEmpty)
          const _EmptyCategory('No group pings yet'),
        if (toReply.isNotEmpty) ...[
          const _SectionLabel('TO REPLY'),
          for (final g in toReply)
            _ExpandableReplyCard(
              expanded: _expandedId == g.group.name,
              accent: _accent,
              onExpand: () => _toggleExpanded(g.group.name),
              onCollapse: () => _toggleExpanded(g.group.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ageText(_windowLabel(g.sentAt, g.windowHours)),
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: _accent.withValues(alpha: 0.65)),
                ],
              ),
              headerBuilder: (expanded) {
                final blur = expanded ? 0.0 : 8.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _StackedAvatars(names: g.group.memberNames),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            g.group.name,
                            style: GoogleFonts.inter(
                              fontSize: expanded ? 15 : 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                            child: Text(
                              '"${g.group.prompt}"',
                              style: GoogleFonts.inter(
                                fontSize: expanded ? 13 : 12,
                                color: Colors.white.withValues(alpha: expanded ? 0.75 : 0.45),
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: expanded ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              surfaceBuilder: (context) => _InlineGroupReplySurface(accent: _accent),
            ),
          const SizedBox(height: 8),
        ],
        if (sent.isNotEmpty) ...[
          const _SectionLabel('SENT'),
          for (final g in sent)
            _GlassRow(
              onTap: () => _openGroup(g),
              child: _groupRowContent(
                g,
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _seenChip(g.seen),
                    const SizedBox(height: 3),
                    _ageText(_windowLabel(g.sentAt, g.windowHours)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (replies.isNotEmpty) ...[
          const _SectionLabel('REPLIES'),
          for (final g in replies)
            _GlassRow(
              onTap: () => _openGroup(g),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (g.pingBackAvailable) ...[
                    GestureDetector(
                      onTap: () => _replyToGroup(g),
                      child: Row(
                        children: [
                          Icon(Icons.replay_rounded,
                              size: 13, color: Colors.white.withValues(alpha: 0.55)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ping back available',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.60),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 14, color: Colors.white.withValues(alpha: 0.35)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                    ),
                  ],
                  _groupRowContent(g),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _groupRowContent(_GroupUi g, {Widget? trailing}) {
    return Row(
      children: [
        _StackedAvatars(names: g.group.memberNames),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                g.group.name,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '"${g.group.prompt}"',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.45),
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }
}

class _GroupDetailView extends StatelessWidget {
  const _GroupDetailView({required this.group});

  final _GroupEntry group;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, topPad + 14, 16, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textPrimary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    group.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${group.memberNames.length} members',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '"${group.prompt}"',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPad + 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.9,
              ),
              itemCount: group.replyColors.length,
              itemBuilder: (context, i) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(color: group.replyColors[i]),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    group.memberNames[i],
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CreateGroupSheet — create a squad + pick prompt
// ---------------------------------------------------------------------------

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet();

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final Set<int> _selected = {};
  int? _promptIdx;

  static const _prompts = [
    'Show us where you are right now 📍',
    'Best moment today? 📸',
    'What are you all doing? 👀',
    'Quick selfie everyone! 🤳',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canCreate =>
      _nameCtrl.text.trim().isNotEmpty &&
      _selected.length >= 2 &&
      _promptIdx != null;

  void _create() {
    if (!_canCreate) return;
    HapticFeedback.mediumImpact();
    final groupName = _nameCtrl.text.trim();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"$groupName" created! Prompt sent to ${_selected.length} friends 🎉',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Create a Group Ping',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              // Group name
              Text(
                'group name',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. "The Squad"',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 14, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.cardSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.60)),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              // People selector
              Text(
                'add people (min 2)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _kPingTargets.length,
                  separatorBuilder: (ctx, idx) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final (name, color) = _kPingTargets[i];
                    final on = _selected.contains(i);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (on) { _selected.remove(i); }
                        else { _selected.add(i); }
                      }),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(
                                color: on
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                name[0].toUpperCase(),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name.length > 9
                                ? '${name.substring(0, 8)}…'
                                : name,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: on
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Prompt picker
              Text(
                'pick a prompt',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < _prompts.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _promptIdx = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: _promptIdx == i
                          ? AppColors.primary.withValues(alpha: 0.14)
                          : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _promptIdx == i
                            ? AppColors.primary.withValues(alpha: 0.45)
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      _prompts[i],
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _promptIdx == i
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: _promptIdx == i
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Create button
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _canCreate ? _create : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 50,
                    decoration: BoxDecoration(
                      color: _canCreate
                          ? AppColors.primary
                          : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Create Group & Send Ping',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: _canCreate
                              ? Colors.white
                              : AppColors.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SUBTAB 3 — Anonymous ping threads
// ---------------------------------------------------------------------------

class _AnonPingTab extends StatefulWidget {
  const _AnonPingTab({required this.bottomPad});

  final double bottomPad;

  @override
  State<_AnonPingTab> createState() => _AnonPingTabState();
}

class _AnonPingTabState extends State<_AnonPingTab> {
  static const _accent = AppColors.vibrantMagenta;

  String? _expandedId;

  void _toggleExpanded(String id) {
    HapticFeedback.selectionClick();
    setState(() => _expandedId = _expandedId == id ? null : id);
  }

  void _openAnonPing() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewPingSheet(anonMode: true),
    );
  }

  void _openThread(_AnonThreadUi u) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => _AnonThreadView(
          thread: u.thread,
          // No reliable "did they send anything" signal from the pop value
          // (the thread view manages its own message list internally), so
          // this fires the moment a reply is actually sent instead.
          onReplied: () => u.answered = true,
        ),
      ),
    )
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final toReply = _anonThreadUi
        .where((u) =>
            u.state == _PingState.toReply && !_replyWindowExpired(u.sentAt, u.windowHours))
        .toList();
    final sent = _anonThreadUi.where((u) => u.state == _PingState.sent).toList();

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPad + 24),
      children: [
        _NewPingEntry(
          label: 'Send an anonymous ping',
          icon: Icons.visibility_off_rounded,
          onTap: _openAnonPing,
        ),
        if (toReply.isEmpty && sent.isEmpty)
          const _EmptyCategory('No anonymous pings yet'),
        if (toReply.isNotEmpty) ...[
          const _SectionLabel('TO REPLY'),
          for (final u in toReply)
            _ExpandableReplyCard(
              expanded: _expandedId == u.thread.handle,
              accent: _accent,
              onExpand: () => _toggleExpanded(u.thread.handle),
              onCollapse: () => _toggleExpanded(u.thread.handle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ageText(_windowLabel(u.sentAt, u.windowHours)),
                  const SizedBox(width: 6),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: _accent.withValues(alpha: 0.65)),
                ],
              ),
              headerBuilder: (expanded) {
                final blur = expanded ? 0.0 : 8.0;
                final last = u.thread.messages.last;
                final preview = last.type == _MsgType.text
                    ? last.text
                    : (last.type == _MsgType.photo ? '📷 Photo' : '🎤 Voice note');
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PingAvatar(label: '?', glow: _accent, pulse: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            u.thread.handle,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: expanded ? 14 : 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 2),
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                            child: Text(
                              preview,
                              style: GoogleFonts.inter(
                                fontSize: expanded ? 13 : 12,
                                color: Colors.white.withValues(alpha: expanded ? 0.70 : 0.45),
                              ),
                              maxLines: expanded ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              surfaceBuilder: (context) => _InlineAnonComposer(accent: _accent),
            ),
          const SizedBox(height: 8),
        ],
        if (sent.isNotEmpty) ...[
          const _SectionLabel('SENT'),
          for (final u in sent)
            _GlassRow(
              onTap: () => _openThread(u),
              child: _anonRowContent(u),
            ),
        ],
      ],
    );
  }

  Widget _anonRowContent(_AnonThreadUi u) {
    final last = u.thread.messages.last;
    final preview = last.type == _MsgType.text
        ? last.text
        : (last.type == _MsgType.photo ? '📷 Photo' : '🎤 Voice note');

    return Row(
      children: [
        _PingAvatar(label: '?', glow: _accent.withValues(alpha: 0.6)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                u.thread.handle,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                preview,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // No per-message "seen" flag exists for anon threads (unlike Friends
        // via NotifState / Groups via _GroupUi.seen), so there's no seen
        // chip here — just a plain age label.
        _ageText('sent ${u.thread.messages.last.time} ago'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Anon thread detail view
// ---------------------------------------------------------------------------

class _AnonThreadView extends StatefulWidget {
  const _AnonThreadView({required this.thread, this.onReplied});

  final _AnonThread thread;

  /// Fires the moment the user actually sends a message in this thread —
  /// used by _AnonPingTab to move the thread out of "To Reply" without
  /// changing this screen's own push/pop mechanics.
  final VoidCallback? onReplied;

  @override
  State<_AnonThreadView> createState() => _AnonThreadViewState();
}

class _AnonThreadViewState extends State<_AnonThreadView> {
  late List<_AnonMessage> _messages;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _revealPending = false;

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.thread.messages);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_AnonMessage(type: _MsgType.text, isMe: true, time: 'now', text: text));
      _textCtrl.clear();
    });
    widget.onReplied?.call();
    _scrollToBottom();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    setState(() {
      _messages.add(const _AnonMessage(
        type: _MsgType.photo,
        isMe: true,
        time: 'now',
        photoColor: Color(0xFF2A3050),
      ));
    });
    widget.onReplied?.call();
    _scrollToBottom();
  }

  void _openVoiceSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VoiceRecordSheet(
        onSend: (int secs) {
          Navigator.of(context).pop();
          setState(() {
            _messages.add(_AnonMessage(
              type: _MsgType.voice,
              isMe: true,
              time: 'now',
              voiceSecs: secs,
            ));
          });
          widget.onReplied?.call();
          _scrollToBottom();
        },
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }

  void _tapReveal() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Reveal identity?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Both you and ${widget.thread.handle} must confirm to reveal each other\'s real names.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              setState(() => _revealPending = true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Reveal sent! Waiting for ${widget.thread.handle}...',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  backgroundColor: AppColors.secondary,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              // Simulate the other side confirming after a short delay
              Future.delayed(const Duration(seconds: 3), () {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${widget.thread.handle} confirmed! Real names revealed 🎉',
                      style: GoogleFonts.inter(color: AppColors.onPrimary),
                    ),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Reveal',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildMessage(_AnonMessage msg) {
    switch (msg.type) {
      case _MsgType.text:
        return _TextBubble(msg: msg);
      case _MsgType.photo:
        return _PhotoBubble(msg: msg);
      case _MsgType.voice:
        return _VoiceBubble(msg: msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: EdgeInsets.fromLTRB(16, topPad + 14, 16, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textPrimary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.thread.handle,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'anon thread',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _tapReveal,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _revealPending
                          ? AppColors.secondary.withValues(alpha: 0.08)
                          : AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      _revealPending ? '⏳ Pending' : '🔓 Reveal',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Original post
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.thread.handle,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.thread.originalPost,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _buildMessage(_messages[i]),
            ),
          ),

          // Reveal button strip
          if (!_revealPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: GestureDetector(
                onTap: _tapReveal,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '🔓  Reveal your identity to ${widget.thread.handle}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_revealPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.20),
                  ),
                ),
                child: Center(
                  child: Text(
                    '⏳  Waiting for ${widget.thread.handle} to confirm reveal...',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

          // Input bar
          Container(
            padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad + 12),
            decoration: const BoxDecoration(
              color: AppColors.cardSurface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                // Camera
                GestureDetector(
                  onTap: _pickPhoto,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.image_outlined,
                      color: AppColors.textMuted,
                      size: 22,
                    ),
                  ),
                ),
                // Mic
                GestureDetector(
                  onTap: _openVoiceSheet,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.mic_none_rounded,
                      color: AppColors.textMuted,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Text field
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _textCtrl,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration.collapsed(
                        hintText: 'Reply anonymously...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send
                GestureDetector(
                  onTap: _sendText,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: AppColors.onPrimary,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble types
// ---------------------------------------------------------------------------

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.msg});

  final _AnonMessage msg;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: msg.isMe
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.cardSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(msg.isMe ? 14 : 2),
            bottomRight: Radius.circular(msg.isMe ? 2 : 14),
          ),
          border: Border.all(
            color: msg.isMe
                ? AppColors.primary.withValues(alpha: 0.28)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              msg.text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              msg.time,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble({required this.msg});

  final _AnonMessage msg;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _FullScreenPhoto(color: msg.photoColor),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          width: 200,
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(msg.isMe ? 14 : 2),
              bottomRight: Radius.circular(msg.isMe ? 2 : 14),
            ),
            border: Border.all(
              color: msg.isMe
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : AppColors.border,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(13),
              topRight: const Radius.circular(13),
              bottomLeft: Radius.circular(msg.isMe ? 13 : 1),
              bottomRight: Radius.circular(msg.isMe ? 1 : 13),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1.4,
                  child: Container(color: msg.photoColor),
                ),
                Container(
                  color: msg.isMe
                      ? AppColors.primary.withValues(alpha: 0.18)
                      : AppColors.cardSurface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    msg.time,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voice message bubble
// ---------------------------------------------------------------------------

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({required this.msg});

  final _AnonMessage msg;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _isPlaying = false;

  static const _barHeights = [0.3, 0.7, 0.5, 0.9, 0.4, 0.8, 0.6, 0.7, 0.4, 0.5, 0.8, 0.3];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  String _formatSecs(int s) => '0:${s.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isMe = widget.msg.isMe;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.cardSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 14),
          ),
          border: Border.all(
            color: isMe
                ? AppColors.primary.withValues(alpha: 0.28)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Play/pause button
                GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Waveform bars
                Expanded(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, child) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final h in _barHeights)
                          Container(
                            width: 3,
                            height: _isPlaying
                                ? math.max(4, h * 22 * (_ctrl.value * 0.6 + 0.4))
                                : (4 + h * 10),
                            decoration: BoxDecoration(
                              color: _isPlaying
                                  ? AppColors.primary
                                  : AppColors.primary.withValues(alpha: 0.50),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Duration
                Text(
                  _formatSecs(widget.msg.voiceSecs),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Modulated badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B3FA0).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF6B3FA0).withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    '🔒 modulated',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: const Color(0xFFB07FE0),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  widget.msg.time,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voice record sheet (modal bottom sheet)
// ---------------------------------------------------------------------------

enum _RecordPhase { recording, preview }

class _VoiceRecordSheet extends StatefulWidget {
  const _VoiceRecordSheet({required this.onSend, required this.onCancel});

  final void Function(int seconds) onSend;
  final VoidCallback onCancel;

  @override
  State<_VoiceRecordSheet> createState() => _VoiceRecordSheetState();
}

class _VoiceRecordSheetState extends State<_VoiceRecordSheet>
    with SingleTickerProviderStateMixin {
  _RecordPhase _phase = _RecordPhase.recording;
  late final AnimationController _waveCtrl;
  int _seconds = 0;
  Timer? _timer;
  bool _previewPlaying = false;

  static const _barHeights = [0.4, 0.8, 0.6, 1.0, 0.5, 0.9, 0.7, 0.8, 0.5, 0.4, 0.9, 0.6, 0.3, 0.7];

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _stopRecording() {
    _timer?.cancel();
    _waveCtrl.stop();
    setState(() => _phase = _RecordPhase.preview);
  }

  void _reRecord() {
    setState(() {
      _phase = _RecordPhase.recording;
      _seconds = 0;
      _previewPlaying = false;
    });
    _waveCtrl.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _togglePreviewPlay() {
    setState(() => _previewPlaying = !_previewPlaying);
    if (_previewPlaying) {
      _waveCtrl.repeat(reverse: true);
    } else {
      _waveCtrl.stop();
      _waveCtrl.reset();
    }
  }

  String _formatSecs(int s) => '0:${s.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPad + 20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: _phase == _RecordPhase.recording
          ? _buildRecording()
          : _buildPreview(),
    );
  }

  Widget _buildRecording() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFFF4444),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Recording  ${_formatSecs(_seconds)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Waveform
        AnimatedBuilder(
          animation: _waveCtrl,
          builder: (context, child) => SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final h in _barHeights)
                  Container(
                    width: 5,
                    height: math.max(6, h * 44 * (_waveCtrl.value * 0.5 + 0.5)),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4444).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Stop button
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _stopRecording,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4444),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stop_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Stop',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Modulated badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF6B3FA0).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF6B3FA0).withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔒', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                'Voice modulated for privacy',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFFB07FE0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Playback row
        Row(
          children: [
            GestureDetector(
              onTap: _togglePreviewPlay,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _previewPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedBuilder(
                animation: _waveCtrl,
                builder: (context, child) => SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (final h in _barHeights)
                        Container(
                          width: 4,
                          height: _previewPlaying
                              ? math.max(4, h * 30 * (_waveCtrl.value * 0.5 + 0.5))
                              : (4 + h * 12),
                          decoration: BoxDecoration(
                            color: _previewPlaying
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatSecs(_seconds),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Actions
        Row(
          children: [
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _reRecord,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      'Re-record',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => widget.onSend(_seconds),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.send_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'Send',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Received ping notification card (ephemeral, tap to open reveal screen)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 26.0;
    const overlap = 12.0;
    final visibleCount = math.min(names.length, 4);
    final totalWidth = avatarSize + (visibleCount - 1) * overlap;

    return SizedBox(
      width: totalWidth,
      height: avatarSize,
      child: Stack(
        children: [
          for (int i = 0; i < visibleCount; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.background,
                  border: Border.all(
                    color: AppColors.cardSurface,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    names[i][0].toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _UnrevealedPhotoReply — blurred photo card with 3s hold-to-reveal
// ---------------------------------------------------------------------------

class _UnrevealedPhotoReply extends StatefulWidget {
  const _UnrevealedPhotoReply({
    required this.username,
    required this.photoColor,
    required this.onPingBack,
  });

  final String username;
  final Color photoColor;
  final VoidCallback onPingBack;

  @override
  State<_UnrevealedPhotoReply> createState() => _UnrevealedPhotoReplyState();
}

class _UnrevealedPhotoReplyState extends State<_UnrevealedPhotoReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _revealed = false;
  bool _holding = false;
  int _lastHapticSecond = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )
      ..addListener(_onHoldProgress)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          HapticFeedback.heavyImpact();
          setState(() => _revealed = true);
        }
      });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onHoldProgress);
    _ctrl.dispose();
    super.dispose();
  }

  void _onHoldProgress() {
    if (_revealed) return;
    final sec = (_ctrl.value * 3).floor();
    if (sec > _lastHapticSecond && sec > 0) {
      _lastHapticSecond = sec;
      HapticFeedback.lightImpact();
    }
  }

  void _startHold() {
    if (_revealed) return;
    setState(() => _holding = true);
    _lastHapticSecond = 0;
    HapticFeedback.selectionClick();
    _ctrl.forward(from: _ctrl.value);
  }

  void _endHold() {
    if (_revealed) return;
    setState(() => _holding = false);
    _lastHapticSecond = -1;
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _endHold(),
      onLongPressCancel: _endHold,
      child: AspectRatio(
        aspectRatio: 1.4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final blurSigma = _revealed
                  ? 0.0
                  : 20.0 * (1.0 - _ctrl.value);
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Photo (blurred until revealed)
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: blurSigma,
                      sigmaY: blurSigma,
                    ),
                    child: Container(color: widget.photoColor),
                  ),

                  // Overlay when not yet revealed
                  if (!_revealed)
                    Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: _ctrl.value,
                                  strokeWidth: 3,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.15),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                ),
                                Icon(
                                  _holding
                                      ? Icons.lock_open_rounded
                                      : Icons.lock_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _holding
                                ? 'Keep holding…'
                                : '${widget.username} sent a photo',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (!_holding)
                            Text(
                              'disappears after 3s',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Revealed: ephemeral badge + PING BACK button
                  if (_revealed) ...[
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ephemeral · 24h',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ),
                    // PING BACK button — slides up after reveal
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: widget.onPingBack,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.90),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 1.0],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'PING BACK',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: AppColors.coral,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                Icons.refresh_rounded,
                                color: AppColors.coral,
                                size: 15,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PingReceiveScreen — full-screen receive: prompt (large) + dual camera
// ---------------------------------------------------------------------------

class _PingReceiveScreen extends StatefulWidget {
  const _PingReceiveScreen({required this.ping});

  final PingItem ping;

  @override
  State<_PingReceiveScreen> createState() => _PingReceiveScreenState();
}

class _PingReceiveScreenState extends State<_PingReceiveScreen> {
  bool _textMode = false;
  bool _canLeave = false;
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _onClose() async {
    final leave = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Leave without replying?',
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          'It\'ll stay in "To Reply" until the window closes — you can come '
          'back anytime before then. The sender will see you opened it.',
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Stay',
              style: GoogleFonts.inter(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Leave',
              style: GoogleFonts.inter(
                color: AppColors.coral,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _canLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    }
  }

  void _onSend() {
    HapticFeedback.heavyImpact();
    setState(() => _canLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onClose();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Main camera mock (full screen) ────────────────────────────
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0A0A0F),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'rear camera',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Top gradient scrim ────────────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              height: size.height * 0.55,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            // ── Top bar: [X close] only — no countdown/time pressure ──────
            Positioned(
              top: topPad + 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _onClose,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Prompt — large, centered, prominent ───────────────────────
            Positioned(
              top: topPad + 72,
              left: 28,
              right: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // Soft re-entry-window indicator instead of a stressful
                    // countdown — see _windowLabel/PingItem.sentAt+windowHours.
                    'from ${widget.ping.senderName} · '
                    '${_windowLabel(widget.ping.sentAt, widget.ping.windowHours)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.50),
                      letterSpacing: 0.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.ping.prompt,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // ── Front camera PiP (top-right, below prompt area) ───────────
            Positioned(
              top: topPad + 185,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: size.width * 0.26,
                  height: size.width * 0.34,
                  color: const Color(0xFF151520),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.face_retouching_natural,
                          size: 22,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'front',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8,
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom controls ───────────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPad + 16,
              child: _textMode ? _buildTextReply() : _buildCameraControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shutter
        GestureDetector(
          onTap: _onSend,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() => _textMode = true),
          child: Text(
            'reply with text instead',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.50),
              decoration: TextDecoration.underline,
              decorationColor: Colors.white.withValues(alpha: 0.30),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextReply() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: TextField(
              controller: _textCtrl,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText: 'Type your reply…',
                hintStyle: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.30),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _textMode = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Camera',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (_textCtrl.text.trim().isEmpty) return;
                  _onSend();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Send',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NewPingSheet — pick person + pick prompt, send a new ping
// ---------------------------------------------------------------------------

const _kPhotoPrompts = [
  'Show me your view 👀',
  'Pic of what you\'re doing? 📸',
  'Send me where you are right now 📍',
  'Selfie? 🤳',
  'Camera check 📸',
  'Drop a selfie 😄',
  'What\'s in front of you?',
  'Show me your world 🌍',
  'Quick pic? 👀',
  'Let me see your face 😊',
];

const _kTextPrompts = [
  'What\'s on your mind?',
  'How are you really?',
  'Say something 💬',
];

const _kAnonPhotoPrompts = [
  'Show me your world (anon) 🌙',
  'Send a pic, stay mysterious 👁️',
  'Show me something real 🌙',
];

const _kPingTargets = [
  ('alex_xyz', Color(0xFF2A3040)),
  ('jordan_23', Color(0xFF30281A)),
  ('study_bug', Color(0xFF1E2A28)),
  ('sunset_chaser', Color(0xFF382818)),
  ('coffee_talk', Color(0xFF182030)),
];

// 'photo' | 'text' | 'anon' | 'custom'
enum _PromptSection { photo, text, anon, custom }

class _NewPingSheet extends StatefulWidget {
  const _NewPingSheet({this.anonMode = false});

  final bool anonMode;

  @override
  State<_NewPingSheet> createState() => _NewPingSheetState();
}

class _NewPingSheetState extends State<_NewPingSheet> {
  int? _selectedPerson;
  _PromptSection _section = _PromptSection.photo;
  int _photoIdx = 0;
  int _textIdx = 0;
  int _anonIdx = 0;
  bool _writeOwn = false;
  final _customCtrl = TextEditingController();
  XFile? _attachedPhoto;

  @override
  void initState() {
    super.initState();
    if (widget.anonMode) _section = _PromptSection.anon;
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
      if (img != null && mounted) setState(() => _attachedPhoto = img);
    } catch (_) {}
  }

  String get _activePrompt {
    if (_writeOwn) return _customCtrl.text.trim();
    return switch (_section) {
      _PromptSection.photo => _kPhotoPrompts[_photoIdx],
      _PromptSection.text => _kTextPrompts[_textIdx],
      _PromptSection.anon => _kAnonPhotoPrompts[_anonIdx],
      _PromptSection.custom => _customCtrl.text.trim(),
    };
  }

  bool get _canSend =>
      _selectedPerson != null &&
      (_writeOwn ? _customCtrl.text.trim().isNotEmpty : true);

  void _send() {
    if (!_canSend) return;
    final person = _kPingTargets[_selectedPerson!].$1;
    final prompt = _activePrompt;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pinged $person · "$prompt"',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _selectPhotoPrompt(int i) =>
      setState(() { _section = _PromptSection.photo; _photoIdx = i; _writeOwn = false; });

  void _selectTextPrompt(int i) =>
      setState(() { _section = _PromptSection.text; _textIdx = i; _writeOwn = false; });

  void _selectAnonPrompt(int i) =>
      setState(() { _section = _PromptSection.anon; _anonIdx = i; _writeOwn = false; });

  void _toggleWriteOwn() =>
      setState(() { _writeOwn = !_writeOwn; });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final personName = _selectedPerson != null
        ? _kPingTargets[_selectedPerson!].$1
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── Title ─────────────────────────────────────────────────
              Row(
                children: [
                  if (personName != null) ...[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kPingTargets[_selectedPerson!].$2,
                      ),
                      child: Center(
                        child: Text(
                          personName[0].toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ping $personName',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ] else
                    Text(
                      'Send a ping',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Person picker ─────────────────────────────────────────
              Text(
                'choose person',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _kPingTargets.length,
                  separatorBuilder: (context, idx) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final (name, color) = _kPingTargets[i];
                    final selected = _selectedPerson == i;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedPerson = i),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                name[0].toUpperCase(),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name.length > 9
                                ? '${name.substring(0, 8)}…'
                                : name,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              // ── Section 1: Ask for a pic ──────────────────────────────
              Row(
                children: [
                  const Text('📸', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    'Ask for a pic',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _kPhotoPrompts.length; i++)
                    _PromptChip(
                      label: _kPhotoPrompts[i],
                      selected: !_writeOwn &&
                          _section == _PromptSection.photo &&
                          _photoIdx == i,
                      onTap: () => _selectPhotoPrompt(i),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Section 2: Just talk ──────────────────────────────────
              Row(
                children: [
                  const Text('💬', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    'Just talk',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _kTextPrompts.length; i++)
                    _PromptChip(
                      label: _kTextPrompts[i],
                      selected: !_writeOwn &&
                          _section == _PromptSection.text &&
                          _textIdx == i,
                      onTap: () => _selectTextPrompt(i),
                      color: AppColors.secondary,
                    ),
                ],
              ),
              if (widget.anonMode) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('👁️', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      'Anonymous',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < _kAnonPhotoPrompts.length; i++)
                      _PromptChip(
                        label: _kAnonPhotoPrompts[i],
                        selected: !_writeOwn &&
                            _section == _PromptSection.anon &&
                            _anonIdx == i,
                        onTap: () => _selectAnonPrompt(i),
                        color: const Color(0xFF6B5CE7),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // ── Write your own ────────────────────────────────────────
              GestureDetector(
                onTap: _toggleWriteOwn,
                child: Row(
                  children: [
                    Icon(
                      _writeOwn
                          ? Icons.edit_rounded
                          : Icons.edit_outlined,
                      size: 14,
                      color: _writeOwn
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Write your own',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _writeOwn
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontWeight: _writeOwn
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_writeOwn) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customCtrl,
                  autofocus: true,
                  maxLength: 60,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. "Show me your pizza 🍕"',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.cardSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: AppColors.primary
                              .withValues(alpha: 0.60)),
                    ),
                    counterStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      color: AppColors.textMuted,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 20),

              // ── Optional photo row ────────────────────────────────────
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _attachedPhoto != null
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _attachedPhoto != null
                              ? AppColors.primary.withValues(alpha: 0.45)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _attachedPhoto != null
                                ? Icons.check_circle_outline_rounded
                                : Icons.camera_alt_outlined,
                            size: 16,
                            color: _attachedPhoto != null
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _attachedPhoto != null
                                ? 'Photo added ✓'
                                : 'Add photo',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _attachedPhoto != null
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              fontWeight: _attachedPhoto != null
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_attachedPhoto != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _attachedPhoto = null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // PING button (right side)
                  GestureDetector(
                    onTap: _canSend ? _send : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: BoxDecoration(
                        color: _canSend
                            ? AppColors.primary
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'PING',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            letterSpacing: 2.5,
                            color: _canSend
                                ? Colors.white
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Reusable prompt chip
class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.16) : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c.withValues(alpha: 0.55) : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: selected ? c : AppColors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PingBackSheet — frosted-glass sheet: prompt chips or typed reply
// ---------------------------------------------------------------------------

const _kPingBackPrompts = [
  'Show me your view 👀',
  'What are you up to? 📸',
  'Selfie time! 🤳',
  'Drop me a vibe 🌙',
  'Quick check-in 💬',
  'React to this 🔥',
];

class _PingBackSheet extends StatefulWidget {
  const _PingBackSheet({required this.recipientName});
  final String recipientName;

  @override
  State<_PingBackSheet> createState() => _PingBackSheetState();
}

class _PingBackSheetState extends State<_PingBackSheet> {
  int? _selectedIdx;
  bool _textMode = false;
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _selectedIdx != null ||
      (_textMode && _textCtrl.text.trim().isNotEmpty);

  void _send() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.09),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  Text(
                    'Ping back ${widget.recipientName}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Pick a prompt or type something',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.48),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Prompt chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < _kPingBackPrompts.length; i++)
                        GestureDetector(
                          onTap: () => setState(() {
                            _selectedIdx = i;
                            _textMode = false;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedIdx == i && !_textMode
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: _selectedIdx == i && !_textMode
                                    ? Colors.white.withValues(alpha: 0.55)
                                    : Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: Text(
                              _kPingBackPrompts[i],
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _selectedIdx == i && !_textMode
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.62),
                                fontWeight: _selectedIdx == i && !_textMode
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // "or" divider
                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.12))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.32),
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.12))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Text toggle
                  GestureDetector(
                    onTap: () => setState(() {
                      _textMode = !_textMode;
                      if (_textMode) _selectedIdx = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _textMode
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _textMode
                              ? Colors.white.withValues(alpha: 0.38)
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded,
                              size: 15,
                              color: _textMode
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.42)),
                          const SizedBox(width: 8),
                          Text(
                            'Type something instead…',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _textMode
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_textMode) ...[
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.20)),
                      ),
                      child: TextField(
                        controller: _textCtrl,
                        autofocus: true,
                        maxLines: 3,
                        minLines: 2,
                        maxLength: 120,
                        style:
                            GoogleFonts.inter(fontSize: 14, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Say something…',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                          counterStyle: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Send button
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _canSend ? _send : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: _canSend
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF405DE6),
                                    Color(0xFF833AB4),
                                    Color(0xFFE1306C),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: _canSend
                              ? null
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.send_rounded,
                                color: _canSend
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.28),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Ping Back',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  color: _canSend
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.28),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PingSendSheet — 85% sheet: people list → prompt picker → camera
// ---------------------------------------------------------------------------

const _kSendPeople = <(String, int, Color)>[
  ('alex_xyz', 342, Color(0xFF2A3040)),
  ('jordan_23', 298, Color(0xFF30281A)),
  ('study_bug', 187, Color(0xFF1E2A28)),
  ('sunset_chaser', 156, Color(0xFF382818)),
  ('coffee_talk', 134, Color(0xFF182030)),
  ('library_mode', 98, Color(0xFF1A2830)),
  ('fest_vibes', 76, Color(0xFF1E3028)),
];

const _kSendPhotoPrompts = <String>[
  'Show me your view 👀',
  'Pic of what you\'re doing? 📸',
  'Send me where you are 📍',
  'Quick selfie? 🤳',
];

class PingSendSheet extends StatefulWidget {
  const PingSendSheet({super.key});

  @override
  State<PingSendSheet> createState() => _PingSendSheetState();
}

class _PingSendSheetState extends State<PingSendSheet> {
  int? _selectedPersonIdx;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Reply window the recipient will get on their "To Reply" row — sender's
  // choice, defaults to 6h (see PingItem.windowHours / supabase's
  // pings.expires_at).
  int _windowHours = 6;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectPerson(int idx) {
    HapticFeedback.selectionClick();
    setState(() => _selectedPersonIdx = idx);
  }

  void _back() => setState(() => _selectedPersonIdx = null);

  void _sendPing(String personName, String prompt) {
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop((personName, prompt, _windowHours));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.85,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: const Border(
          top: BorderSide(color: Color(0x2900D9FF), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                if (_selectedPersonIdx != null) ...[
                  GestureDetector(
                    onTap: _back,
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _selectedPersonIdx == null
                        ? 'Send a Ping'
                        : 'Ping ${_kSendPeople[_selectedPersonIdx!].$1}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: AppColors.textMuted, size: 15),
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),

          // Content
          Expanded(
            child: _selectedPersonIdx == null
                ? _buildPeopleList(bottomPad)
                : _buildPromptPicker(bottomPad),
          ),
        ],
      ),
    );
  }

  Widget _buildPeopleList(double bottomPad) {
    final filtered = _searchQuery.isEmpty
        ? _kSendPeople
        : _kSendPeople
            .where((p) =>
                p.$1.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.35), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search friends…',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
        // People list
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 16),
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final (name, score, color) = filtered[i];
              final idx = _kSendPeople.indexOf(filtered[i]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => _selectPerson(idx),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.09)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15)),
                              ),
                              child: Center(
                                child: Text(
                                  name[0].toUpperCase(),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 16,
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      TierBadge(score: score),
                                      const SizedBox(width: 6),
                                      Text(
                                        'score $score',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          color:
                                              Colors.white.withValues(alpha: 0.38),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPromptPicker(double bottomPad) {
    final name = _kSendPeople[_selectedPersonIdx!].$1;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'reply window',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final h in const [3, 6, 12, 24])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _windowHours = h),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: _windowHours == h
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: _windowHours == h ? 0.30 : 0.12),
                        ),
                      ),
                      child: Text(
                        '${h}h',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: _windowHours == h ? FontWeight.w700 : FontWeight.w400,
                          color: _windowHours == h
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.50),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Pick a prompt to send',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 14),
          for (final prompt in _kSendPhotoPrompts) ...[
            GestureDetector(
              onTap: () => _sendPing(name, prompt),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF833AB4).withValues(alpha: 0.30)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        prompt,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(Icons.send_rounded, color: Color(0xFFE1306C), size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// showPingSentToast — call from stable context AFTER sheet closes
// ---------------------------------------------------------------------------

void showPingSentToast(BuildContext context, String name) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PingSentOverlay(
      message: 'You pinged $name 👀',
      onDismissed: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

void showViewerToast(BuildContext context, String name, {bool isLive = true}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PingSentOverlay(
      message: isLive
          ? '$name is viewing you right now 👀'
          : '$name viewed you while you were away',
      onDismissed: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

// ---------------------------------------------------------------------------
// _PingRepliesFeedScreen — snap-scroll feed of unrevealed photo replies
// ---------------------------------------------------------------------------

// Public factory for screenshots / navigation from outside this file
Widget buildPingRepliesFeedScreen({
  required String senderName,
  required List<Color> replies,
}) => _PingRepliesFeedScreen(senderName: senderName, replies: replies);

class _PingRepliesFeedScreen extends StatefulWidget {
  const _PingRepliesFeedScreen({
    required this.senderName,
    required this.replies,
  });

  final String senderName;
  final List<Color> replies;

  @override
  State<_PingRepliesFeedScreen> createState() => _PingRepliesFeedScreenState();
}

class _PingRepliesFeedScreenState extends State<_PingRepliesFeedScreen> {
  late final PageController _pageCtrl;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.90);
    _pageCtrl.addListener(() {
      final p = (_pageCtrl.page ?? 0).round();
      if (p != _currentPage && mounted) setState(() => _currentPage = p);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _openCamera(BuildContext ctx) {
    showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PingBackSheet(recipientName: widget.senderName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final total = widget.replies.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Top bar
          Container(
            padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.senderName,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$total ${total == 1 ? 'reply' : 'replies'} · hold to reveal',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                // Page dots
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(total, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _currentPage ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      gradient: i == _currentPage
                          ? const LinearGradient(
                              colors: [Color(0xFF833AB4), Color(0xFFE1306C)],
                            )
                          : null,
                      color: i == _currentPage
                          ? null
                          : Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )),
                ),
              ],
            ),
          ),

          // Snap-scroll reply feed
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              clipBehavior: Clip.none,
              itemCount: total,
              itemBuilder: (ctx, i) => Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad + 8),
                child: _ReplyFeedPage(
                  username: widget.senderName,
                  photoColor: widget.replies[i],
                  index: i,
                  total: total,
                  onPingBack: () => _openCamera(ctx),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ReplyFeedPage — full-page blurred photo with 3s hold-to-reveal
// ---------------------------------------------------------------------------

class _ReplyFeedPage extends StatefulWidget {
  const _ReplyFeedPage({
    required this.username,
    required this.photoColor,
    required this.index,
    required this.total,
    required this.onPingBack,
  });

  final String username;
  final Color photoColor;
  final int index;
  final int total;
  final VoidCallback onPingBack;

  @override
  State<_ReplyFeedPage> createState() => _ReplyFeedPageState();
}

class _ReplyFeedPageState extends State<_ReplyFeedPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdCtrl;
  bool _revealed = false;
  bool _holding = false;
  int _lastHapticSecond = -1;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )
      ..addListener(_onProgress)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          HapticFeedback.heavyImpact();
          setState(() => _revealed = true);
        }
      });
  }

  void _onProgress() {
    if (_revealed) return;
    final sec = (_holdCtrl.value * 3).floor();
    if (sec > _lastHapticSecond && sec > 0) {
      _lastHapticSecond = sec;
      HapticFeedback.lightImpact();
    }
  }

  void _startHold() {
    if (_revealed) return;
    setState(() => _holding = true);
    _lastHapticSecond = 0;
    HapticFeedback.selectionClick();
    _holdCtrl.forward(from: _holdCtrl.value);
  }

  void _endHold() {
    if (_revealed) return;
    setState(() => _holding = false);
    _lastHapticSecond = -1;
    _holdCtrl.reverse();
  }

  @override
  void dispose() {
    _holdCtrl.removeListener(_onProgress);
    _holdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: GestureDetector(
        onLongPressStart: (_) => _startHold(),
        onLongPressEnd: (_) => _endHold(),
        onLongPressCancel: _endHold,
        child: AnimatedBuilder(
          animation: _holdCtrl,
          builder: (ctx, _) {
            final blur = _revealed ? 0.0 : 22.0 * (1.0 - _holdCtrl.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                // Photo (blurred until revealed)
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: Container(color: widget.photoColor),
                ),

                // Dark overlay + hold UI (unrevealed)
                if (!_revealed)
                  Container(
                    color: Colors.black.withValues(alpha: 0.42),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: _holdCtrl.value,
                                strokeWidth: 3.5,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.15),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color.lerp(
                                    const Color(0xFF833AB4),
                                    const Color(0xFFE1306C),
                                    _holdCtrl.value,
                                  )!,
                                ),
                              ),
                              Icon(
                                _holding
                                    ? Icons.lock_open_rounded
                                    : Icons.fingerprint,
                                color: Colors.white,
                                size: 26,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _holding
                              ? 'Keep holding…'
                              : '${widget.username} sent a photo',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (!_holding)
                          Text(
                            'hold to reveal · ${widget.index + 1} of ${widget.total}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.50),
                            ),
                          ),
                        if (_holding)
                          const SizedBox(height: 4),
                        if (_holding)
                          Text(
                            '${((1 - _holdCtrl.value) * 3).ceil()}s',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                  ),

                // Top overlays after reveal
                if (_revealed) ...[
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${widget.index + 1} / ${widget.total}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'ephemeral · 24h',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),

                  // PING BACK button overlay at bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.90),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: GestureDetector(
                        onTap: widget.onPingBack,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF405DE6),
                                Color(0xFF833AB4),
                                Color(0xFFE1306C),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF833AB4)
                                    .withValues(alpha: 0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.refresh_rounded,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Ping back reply to ${widget.username}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// showPingChoiceSheet — bell FAB → choose: Group or Anonymous
// ---------------------------------------------------------------------------

void showPingChoiceSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PingChoiceSheet(),
  );
}

class _PingChoiceSheet extends StatelessWidget {
  const _PingChoiceSheet();

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D12).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad + 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Send a ping',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose who you\'re pinging',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _PingChoiceOption(
                    icon: Icons.group_rounded,
                    iconColor: const Color(0xFF405DE6),
                    title: 'Ping a Group',
                    subtitle: 'Pick a squad → one prompt → everyone replies',
                    onTap: () {
                      Navigator.of(context).pop();
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _CreateGroupSheet(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _PingChoiceOption(
                    icon: Icons.visibility_off_rounded,
                    iconColor: const Color(0xFF6B5CE7),
                    title: 'Ping Anonymous',
                    subtitle: 'Mystery prompt — they won\'t know it\'s you',
                    onTap: () {
                      Navigator.of(context).pop();
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _NewPingSheet(anonMode: true),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PingChoiceOption extends StatefulWidget {
  const _PingChoiceOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_PingChoiceOption> createState() => _PingChoiceOptionState();
}

class _PingChoiceOptionState extends State<_PingChoiceOption> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _pressed ? 0.10 : 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: widget.iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.25),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay toast shown after sending a ping
// ---------------------------------------------------------------------------

class _PingSentOverlay extends StatefulWidget {
  const _PingSentOverlay({required this.message, required this.onDismissed});
  final String message;
  final VoidCallback onDismissed;

  @override
  State<_PingSentOverlay> createState() => _PingSentOverlayState();
}

class _PingSentOverlayState extends State<_PingSentOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;
  bool _dismissCalled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300))
      ..forward();
    _slide = Tween<Offset>(
            begin: const Offset(0, -1.8), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 2000), _dismiss);
  }

  void _dismiss() {
    if (_dismissCalled || !mounted) return;
    _dismissCalled = true;
    _ctrl.reverse().whenComplete(widget.onDismissed);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _opacity,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Text(
                        widget.message,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
