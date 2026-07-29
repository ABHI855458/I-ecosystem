import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../shared/score_tier.dart';
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

  void _openNewPingSheet() {
    showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PingSendSheet(),
    ).then((name) {
      if (name != null && mounted) showPingSentToast(context, name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topPad + 4),
          _MyScoreHeader(),
          _SendPingButton(onTap: _openNewPingSheet),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _PingTabBar(controller: _tabCtrl),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _EveryonePingTab(bottomPad: bottomPad),
                _GroupPingTab(bottomPad: bottomPad),
                _AnonPingTab(bottomPad: bottomPad),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented tab bar
// ---------------------------------------------------------------------------

class _PingTabBar extends StatelessWidget {
  const _PingTabBar({required this.controller});

  final TabController controller;

  static const _labels = ['Everyone', 'Group', 'Anonymous'];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          height: 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
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
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
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
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// SUBTAB 1 — Everyone: 1-on-1 ping cards
// ---------------------------------------------------------------------------

class _EveryonePingTab extends StatefulWidget {
  const _EveryonePingTab({required this.bottomPad});

  final double bottomPad;

  @override
  State<_EveryonePingTab> createState() => _EveryonePingTabState();
}

class _EveryonePingTabState extends State<_EveryonePingTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerCtrl;
  late List<PingItem> _pendingPings;
  String? _nudgeName;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + _pings.length * 80),
    )..forward();
    _pendingPings = [
      const PingItem(
        senderName: 'alex_xyz',
        avatarColor: Color(0xFF2A3040),
        timeAgo: '2m ago',
        prompt: 'Show me your view 👀',
      ),
      const PingItem(
        senderName: 'study_bug',
        avatarColor: Color(0xFF1E2A28),
        timeAgo: '18m ago',
        prompt: 'What are you doing right now?',
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) showViewerToast(context, 'jordan_23', isLive: false);
      });
      Future.delayed(const Duration(seconds: 7), () {
        if (mounted) showViewerToast(context, 'alex_xyz', isLive: true);
      });
    });
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  void _openReceived(BuildContext context, PingItem ping) async {
    final messenger = ScaffoldMessenger.of(context);
    final replied = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => _PingReceiveScreen(ping: ping),
      ),
    );
    if (!mounted) return;
    setState(() {
      _pendingPings.removeWhere((p) => p.senderName == ping.senderName);
    });
    if (replied != true) {
      setState(() => _nudgeName = ping.senderName);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Ping gone. Sender notified you opened it.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF2A1A1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final extraCount = _pendingPings.isEmpty ? 0 : _pendingPings.length + 1;

    return Column(
      children: [
        if (_nudgeName != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: GestureDetector(
              onTap: () {
                showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _PingBackSheet(recipientName: _nudgeName!),
                ).then((sent) {
                  if (sent == true && mounted) setState(() => _nudgeName = null);
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF405DE6).withValues(alpha: 0.18),
                      const Color(0xFFE1306C).withValues(alpha: 0.18),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF833AB4).withValues(alpha: 0.40),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.refresh_rounded, color: AppColors.coral, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '↻ Ping back $_nudgeName',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.coral,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _nudgeName = null),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _staggerCtrl.forward(from: 0);
              await Future<void>.delayed(const Duration(milliseconds: 600));
            },
            color: AppColors.coral,
            backgroundColor: const Color(0xFF1A1A1D),
            child: ListView.builder(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPad + 88),
              itemCount: extraCount + _pings.length,
        itemBuilder: (context, i) {
          // ── Received pings section ───────────────────────────────
          if (_pendingPings.isNotEmpty) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 0, 10),
                child: Text(
                  'received pings',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              );
            }
            if (i <= _pendingPings.length) {
              final ping = _pendingPings[i - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HoldToOpenPingCard(
                  ping: ping,
                  onOpened: () => _openReceived(context, ping),
                ),
              );
            }
          }

          // ── Regular pings with stagger ───────────────────────────
          final pingIdx = i - extraCount;
          final start =
              (pingIdx * 80) / (_staggerCtrl.duration!.inMilliseconds);
          final end = math.min(start + 0.5, 1.0);
          final interval = Interval(start, end, curve: Curves.easeOut);
          final anim =
              CurvedAnimation(parent: _staggerCtrl, curve: interval);
          final slide = Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(anim);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: slide,
                child: _EveryonePingCard(ping: _pings[pingIdx]),
              ),
            ),
          );
        },
      ),
    ),
        ),
      ],
    );
  }
}

class _EveryonePingCard extends StatelessWidget {
  const _EveryonePingCard({required this.ping});

  final _PingEntry ping;

  Future<void> _sendReply(BuildContext context) async {
    HapticFeedback.lightImpact();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PingBackSheet(recipientName: ping.username),
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Replied to ${ping.username}!',
            style: GoogleFonts.inter(color: AppColors.onPrimary),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                ScoreGlowAvatar(username: ping.username, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            ping.username,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          TierBadge(score: scoreForUser(ping.username)),
                        ],
                      ),
                      Text(
                        ping.time,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (ping.hasUnrevealedReply)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => _PingRepliesFeedScreen(
                      senderName: ping.username,
                      replies: ping.replyPhotoColors.isNotEmpty
                          ? ping.replyPhotoColors
                          : [ping.replyPhotoColor],
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 110,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Blurred photo background
                        Container(color: ping.replyPhotoColor),
                        // Blur overlay
                        Container(
                          color: Colors.black.withValues(alpha: 0.42),
                        ),
                        // CTA
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fingerprint,
                                color: AppColors.coral,
                                size: 28,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap to see their reply',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'tap to reveal',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.50),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Coral border
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.coral.withValues(alpha: 0.40),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ping.isPhoto
                  ? AspectRatio(
                      aspectRatio: 1.4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(color: ping.photoColor),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        ping.textReply,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '${ping.streakDays}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _sendReply(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          'Ping Back',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.more_horiz, color: AppColors.textMuted, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SUBTAB 2 — Group pings
// ---------------------------------------------------------------------------

class _GroupPingTab extends StatelessWidget {
  const _GroupPingTab({required this.bottomPad});

  final double bottomPad;

  void _createGroup(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateGroupSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad + 88),
        children: [
          GestureDetector(
            onTap: () => _createGroup(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Start a group ping',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Invite 2–5 friends to share a moment',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'active groups',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        for (final group in _groups) ...[
          _GroupCard(group: group),
          const SizedBox(height: 14),
        ],
      ],
    ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final _GroupEntry group;

  @override
  Widget build(BuildContext context) {
    final previewCount = math.min(group.replyColors.length, 4);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _GroupDetailView(group: group),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  _StackedAvatars(names: group.memberNames),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          group.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${group.memberNames.length} members',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                '"${group.prompt}"',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(
                children: [
                  for (int i = 0; i < previewCount; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i < previewCount - 1 ? 5 : 0,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(color: group.replyColors[i]),
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

class _AnonPingTab extends StatelessWidget {
  const _AnonPingTab({required this.bottomPad});

  final double bottomPad;

  void _openAnonPing(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewPingSheet(anonMode: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async =>
          Future<void>.delayed(const Duration(milliseconds: 600)),
      color: AppColors.primary,
      backgroundColor: const Color(0xFF1A1A1D),
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad + 88),
        children: [
          // Anonymous ping CTA card
          GestureDetector(
            onTap: () => _openAnonPing(context),
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF6B5CE7).withValues(alpha: 0.40),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B5CE7).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('👁️', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Send an anonymous ping',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'They\'ll see the prompt, not who sent it',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          for (int i = 0; i < _anonThreads.length; i++) ...[
            _AnonThreadCard(thread: _anonThreads[i]),
            if (i < _anonThreads.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _AnonThreadCard extends StatelessWidget {
  const _AnonThreadCard({required this.thread});

  final _AnonThread thread;

  String _previewText(_AnonMessage msg) {
    switch (msg.type) {
      case _MsgType.photo:
        return '📷 Photo';
      case _MsgType.voice:
        return '🎤 Voice note';
      case _MsgType.text:
        return msg.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = thread.messages;
    final preview = msgs.length > 2 ? msgs.sublist(msgs.length - 2) : msgs;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _AnonThreadView(thread: thread),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Original post
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      thread.handle,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      thread.originalPost,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // Message preview bubbles
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final msg in preview)
                    Align(
                      alignment: msg.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        constraints: const BoxConstraints(maxWidth: 240),
                        decoration: BoxDecoration(
                          color: msg.isMe
                              ? AppColors.primary.withValues(alpha: 0.18)
                              : AppColors.background,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(msg.isMe ? 12 : 2),
                            bottomRight: Radius.circular(msg.isMe ? 2 : 12),
                          ),
                          border: Border.all(
                            color: msg.isMe
                                ? AppColors.primary.withValues(alpha: 0.28)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          _previewText(msg),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: msg.type != _MsgType.text
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Row(
                children: [
                  Text(
                    '${thread.messages.length} messages',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      'Reveal',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
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
}

// ---------------------------------------------------------------------------
// Anon thread detail view
// ---------------------------------------------------------------------------

class _AnonThreadView extends StatefulWidget {
  const _AnonThreadView({required this.thread});

  final _AnonThread thread;

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
// _MyScoreHeader — glow ring + score + tier + progress toward next tier
// ---------------------------------------------------------------------------

const _kMyScore = 230; // abhishek_patel → Prominent tier

class _MyScoreHeader extends StatelessWidget {
  const _MyScoreHeader();

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(_kMyScore);
    final progress = tierProgressToNext(_kMyScore);
    final toNext = pointsToNextTier(_kMyScore) ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          ScoreGlowRing(
            score: _kMyScore,
            size: 46,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2E2A52),
              ),
              child: Center(
                child: Text(
                  'AP',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_kMyScore',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  TierBadge(score: _kMyScore),
                ],
              ),
              Text(
                info.title,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: info.color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '~$toNext to next',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(info.color),
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
// _SendPingButton — big prominent coral CTA above tab bar
// ---------------------------------------------------------------------------

class _SendPingButton extends StatefulWidget {
  const _SendPingButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_SendPingButton> createState() => _SendPingButtonState();
}

class _SendPingButtonState extends State<_SendPingButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF833AB4).withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'SEND A PING',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HoldToOpenPingCard — 2s hold-to-open with circular progress ring
// ---------------------------------------------------------------------------

class _HoldToOpenPingCard extends StatelessWidget {
  const _HoldToOpenPingCard({required this.ping, required this.onOpened});

  final PingItem ping;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onOpened();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.coral.withValues(alpha: 0.40)),
        ),
        child: Row(
          children: [
            // Mystery blurred avatar
            ClipOval(
              child: SizedBox(
                width: 46,
                height: 46,
                child: Container(
                  color: ping.avatarColor,
                  child: Center(
                    child: Icon(
                      Icons.notifications_active_rounded,
                      color: AppColors.coral.withValues(alpha: 0.80),
                      size: 22,
                    ),
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
                    'Someone pinged you',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to open · ${ping.timeAgo}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: AppColors.coral,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Open',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
  int _secondsRemaining = 3 * 3600; // 3 hours from open
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _countdownTimer?.cancel();
        // Time's up — ping gone
        setState(() => _canLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(false);
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  String get _timerLabel {
    final h = _secondsRemaining ~/ 3600;
    final m = (_secondsRemaining % 3600) ~/ 60;
    final s = _secondsRemaining % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} remaining';
  }

  Color get _timerColor {
    if (_secondsRemaining < 300) return AppColors.coral; // < 5 min → red
    if (_secondsRemaining < 1800) return const Color(0xFFFFB800); // < 30 min → amber
    return Colors.white.withValues(alpha: 0.55);
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
          'This ping is gone forever. The sender will see you opened it.',
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

            // ── Top bar: [X close] ... [timer] ────────────────────────────
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
                  const Spacer(),
                  // 3-hour countdown
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _timerColor.withValues(alpha: 0.40),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 11,
                          color: _timerColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _timerLabel,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: _timerColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
                    'from ${widget.ping.senderName}',
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
    Navigator.of(context).pop(personName);
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
