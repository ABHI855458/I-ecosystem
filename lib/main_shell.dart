import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/constants.dart';
import 'features/composer/composer_screen.dart';
import 'features/community/community_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/ping/ping_screen.dart';
import 'features/ping/ping_view_sheet.dart';
import 'features/profile/profile_screen.dart';
import 'shared/glass_notif_card.dart';
import 'shared/score_tier.dart';
import 'shared/tab_bar_icons.dart';

// Bottom tab bar geometry — the tab bar's own, unchanged position. Used
// on EVERY tab (Home/Ping/Community/Profile — see the AnimatedPositioned
// below, which wraps the single IndexedStack all four tabs share), never
// anon-specific. Do not derive these FROM anything else (the peek strip
// derives from these, not the other way around — see anonymous_tab.dart).
const double kTabBarHeight = 56.0;
const double kTabBarBottomOffset = 24.0;
const double kTabBarBottomOffsetCompact = 16.0;

// Extra lift applied ONLY to the bar's own position below (not to
// kTabBarBottomOffset itself, which the Anonymous feed's peek strip, the
// ping FAB, and the notification overlay all also read) — opens a gap
// between the bar and the peek strip's top edge without moving or
// resizing anything else.
const double _tabBarExtraLift = 10.0;

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _compact = false;
  bool _scrollHideEnabled = false;

  // Whether the Home tab's own Anonymous sub-page (vs its Everyone/Friends
  // sub-page — see HomeScreen's PageView) is currently active. Only the
  // Anonymous sub-page keeps the tab bar's original floating position; every
  // other page (Everyone/Friends, Ping, Community, Profile) uses the lower,
  // Instagram-style position instead — see _tabBarBottom in build().
  // Defaults true to match HomeScreen's own default (_tabIndex starts at 0).
  bool _isHomeAnonActive = true;

  late final AnimationController _bannerCtrl;
  late final Animation<Offset> _bannerSlide;
  AppNotif? _lastBannerNotif;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(
        onOpenCamera: _openComposer,
        onAnonActiveChanged: (v) {
          if (v != _isHomeAnonActive) setState(() => _isHomeAnonActive = v);
        },
      ),
      const PingScreen(),
      const CommunityScreen(),
      const ProfileScreen(),
    ];
    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bannerSlide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _bannerCtrl, curve: Curves.easeOutCubic));

    notifState.onGoHome = () => setState(() => _currentIndex = 0);
    notifState.onGoPing = () => setState(() => _currentIndex = 1);
    notifState.onGoCommunity = () => setState(() => _currentIndex = 2);
    notifState.onGoProfile = () => setState(() => _currentIndex = 3);
    notifState.onGoLeaderboard = () => setState(() => _currentIndex = 3);
    notifState.onOpenPingNotif = _onOpenPingNotif;

    notifState.addListener(_onNotifChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _scrollHideEnabled = true);
      });
    });
  }

  @override
  void dispose() {
    notifState.removeListener(_onNotifChanged);
    _bannerCtrl.dispose();
    super.dispose();
  }

  void _onNotifChanged() {
    if (notifState.bannerVisible) {
      _lastBannerNotif = notifState.bannerNotif;
      _bannerCtrl.forward(from: 0);
      if (mounted) setState(() {});
    } else {
      _bannerCtrl.reverse().then((_) {
        if (mounted) setState(() => _lastBannerNotif = null);
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_scrollHideEnabled) return false;
    // Compact state is a pure function of scroll offset — only setState
    // when the derived boolean actually flips, not on every scroll tick.
    final shouldCompact = notification.metrics.pixels > 40;
    if (shouldCompact != _compact) {
      setState(() => _compact = shouldCompact);
    }
    return false;
  }

  void _onOpenPingNotif(AppNotif notif) {
    setState(() => _currentIndex = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPingViewSheet(
        context,
        senderName: notif.senderName.isNotEmpty ? notif.senderName : 'someone',
        type: notif.type == NotifType.photoReply
            ? PingViewType.photo
            : PingViewType.text,
        promptText: notif.body,
        avatarColor: notif.avatarColor,
      );
    });
  }

  void _openComposer() {
    Navigator.of(context).push(openCameraRoute(isAnonymous: _isHomeAnonActive));
  }

  void _openPingSendSheet() {
    HapticFeedback.mediumImpact();
    showPingChoiceSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final unreadHome = notifState.unreadHome;
    final unreadPings = notifState.unreadPings;
    final communityBadge = notifState.communityBadge;
    final totalUnread = notifState.totalUnread;

    // Anonymous keeps its original floating position (unchanged). Every
    // other page — Everyone/Friends, Ping, Community, Profile — sits flush
    // against the safe area instead, Instagram-style, with no extra
    // floating offset/lift.
    final showAnonTabBarPosition = _currentIndex == 0 && _isHomeAnonActive;
    final tabBarBottom = showAnonTabBarPosition
        ? bottomPad + (_compact ? kTabBarBottomOffsetCompact : kTabBarBottomOffset) + _tabBarExtraLift
        : bottomPad;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Tab content ──────────────────────────────────────────────
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
          ),

          // ── Anon score (top-right) — page-level entry point, shown on
          // the Ping/Community/Profile tabs only. On the Home tab it lives
          // INSIDE HomeScreen's own header instead (see _SlimHeader) — it
          // needs to collapse/reappear with that feed's own scroll-driven
          // chrome, which this MainShell-level overlay can't do since it
          // sits above HomeScreen and never sees its scroll position.
          //
          // The bell (notifications) icon and the '+' (reaction-preset-
          // manager) icon that used to sit alongside this — top-left and
          // top-right respectively — are REMOVED from here: both are now
          // Home-only (_SlimHeader's own copies), per explicit requirement
          // that neither appear on any other screen (Ping, Camera/
          // Composer, Community, Profile, Group Profile, Settings). No
          // layout adjustment needed beyond deleting them — these are
          // Positioned overlays in a Stack, not Row/Column siblings, so
          // removing them reserves no space to begin with; nothing shifts.
          if (_currentIndex != 0)
            Positioned(
              top: topPad + 8,
              right: 16,
              child: ValueListenableBuilder<int>(
                valueListenable: ViewerScoreService.instance.score,
                builder: (context, score, _) => _AnonScoreBadge(score: score),
              ),
            ),

          // ── Bottom nav — floating frosted-glass pill, centered ───────
          AnimatedPositioned(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 340),
            curve: const Cubic(0.4, 0.14, 0.3, 1.0),
            left: 0,
            right: 0,
            // Anonymous only: bottomPad + kTabBarBottomOffset/Compact (24/16)
            // + _tabBarExtraLift, floating clear of its peek strip (see
            // anonymous_tab.dart, which reads those same constants —
            // unchanged, still Anonymous-only, still not derived from
            // tabBarBottom). Every other page: tabBarBottom == bottomPad
            // alone, flush against the safe area, Instagram-style.
            bottom: tabBarBottom,
            child: Center(
              child: _BottomNav(
                currentIndex: _currentIndex,
                compact: _compact,
                unreadHome: unreadHome,
                unreadPings: unreadPings,
                communityBadge: communityBadge,
                totalUnread: totalUnread,
                onTabSelected: (i) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _currentIndex = i;
                    _compact = false;
                  });
                },
                onComposerOpen: _openComposer,
              ),
            ),
          ),

          // ── Floating ping FAB — bottom-right, ping tab only ─────────
          if (_currentIndex == 1)
            Positioned(
              right: 16,
              bottom: tabBarBottom + kTabBarHeight + 12,
              child: GestureDetector(
                onTap: _openPingSendSheet,
                child: _PingFAB(),
              ),
            ),

          // ── Glass notification — right side, above bottom nav ────────
          GlassNotifOverlay(
            bottomOffset: tabBarBottom + kTabBarHeight + 12,
          ),

          // ── Notification banner — drops down from the top ────────────
          if (_lastBannerNotif != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SlideTransition(
                position: _bannerSlide,
                child: NotifBanner(
                  notif: _lastBannerNotif!,
                  onDismiss: notifState.dismissBanner,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating frosted-glass pill — 5 tabs (Home, Ping, Camera, Community,
// Profile). Camera is a fixed 44x44 circle, never part of the tab index —
// tapping it opens the composer, same as before.
// ---------------------------------------------------------------------------

List<double> _saturationMatrix(double s) {
  const lumR = 0.213, lumG = 0.715, lumB = 0.072;
  return <double>[
    lumR + (1 - lumR) * s, lumG - lumG * s, lumB - lumB * s, 0, 0,
    lumR - lumR * s, lumG + (1 - lumG) * s, lumB - lumB * s, 0, 0,
    lumR - lumR * s, lumG - lumG * s, lumB + (1 - lumB) * s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.compact,
    required this.unreadHome,
    required this.unreadPings,
    required this.communityBadge,
    required this.totalUnread,
    required this.onTabSelected,
    required this.onComposerOpen,
  });

  final int currentIndex;
  final bool compact;
  final int unreadHome;
  final int unreadPings;
  final bool communityBadge;
  final int totalUnread;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onComposerOpen;

  static const double _widthResting = 286.0;
  static const double _widthCompact = 246.0;
  static const double _heightResting = 56.0;
  static const double _heightCompact = 48.0;
  static const EdgeInsets _paddingResting = EdgeInsets.fromLTRB(8, 5, 8, 5);
  static const EdgeInsets _paddingCompact = EdgeInsets.fromLTRB(7, 4, 7, 4);
  static const double _iconSizeResting = 22.0;
  static const double _iconSizeCompact = 20.0;
  static const Curve _curve = Cubic(0.4, 0.14, 0.3, 1.0);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 340);
    final width = compact ? _widthCompact : _widthResting;
    final height = compact ? _heightCompact : _heightResting;
    final padding = compact ? _paddingCompact : _paddingResting;
    final iconSize = compact ? _iconSizeCompact : _iconSizeResting;
    const radius = 999.0;

    return AnimatedContainer(
      duration: duration,
      curve: _curve,
      width: width,
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.55),
            blurRadius: 44,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ColorFilter.matrix(_saturationMatrix(1.7)),
            inner: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          ),
          child: AnimatedContainer(
            duration: duration,
            curve: _curve,
            padding: padding,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(24, 22, 20, 0.55),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.10),
                width: 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.home,
                        isActive: currentIndex == 0,
                        iconSize: iconSize,
                        badge: unreadHome,
                        onTap: () => onTabSelected(0),
                      ),
                    ),
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.ping,
                        isActive: currentIndex == 1,
                        iconSize: iconSize,
                        badge: unreadPings,
                        onTap: () => onTabSelected(1),
                      ),
                    ),
                    // Placeholder — preserves the camera's horizontal
                    // space in the flex layout; the real camera circle is
                    // rendered as an overlaid Stack child below so it can
                    // stay a true fixed 44x44 regardless of bar height.
                    const SizedBox(width: 44),
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.community,
                        isActive: currentIndex == 2,
                        iconSize: iconSize,
                        hasDot: communityBadge,
                        onTap: () => onTabSelected(2),
                      ),
                    ),
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.profile,
                        isActive: currentIndex == 3,
                        iconSize: iconSize,
                        badge: totalUnread,
                        onTap: () => onTabSelected(3),
                      ),
                    ),
                  ],
                ),
                _CameraTab(iconSize: iconSize, onTap: onComposerOpen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A single flex tab — Home / Ping / Community / Profile
// ---------------------------------------------------------------------------

class _NavTab extends StatefulWidget {
  const _NavTab({
    required this.glyph,
    required this.isActive,
    required this.iconSize,
    required this.onTap,
    this.badge = 0,
    this.hasDot = false,
  });

  final TabGlyph glyph;
  final bool isActive;
  final double iconSize;
  final VoidCallback onTap;
  final int badge;
  final bool hasDot;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _pressed = false;

  static const _pressDuration = Duration(milliseconds: 220);
  static const _activeColor = Colors.white;
  static const _restingColor = Color.fromRGBO(255, 255, 255, 0.45);
  static const _activeBg = Color.fromRGBO(255, 255, 255, 0.13);

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Ping always stays outline — it never fills, even when active.
    final fillable = widget.glyph != TabGlyph.ping;
    final color = widget.isActive ? _activeColor : _restingColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: _pressDuration,
        curve: Curves.ease,
        child: AnimatedContainer(
          duration: _pressDuration,
          curve: Curves.ease,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isActive ? _activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: widget.iconSize, end: widget.iconSize),
                duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 340),
                curve: const Cubic(0.4, 0.14, 0.3, 1.0),
                builder: (context, size, _) => TabBarIcon(
                  glyph: widget.glyph,
                  size: size,
                  color: color,
                  filled: fillable && widget.isActive,
                ),
              ),
              if (widget.badge > 0)
                Positioned(
                  right: -8,
                  top: -6,
                  child: _NavBadge(count: widget.badge),
                ),
              if (widget.hasDot && widget.badge == 0)
                Positioned(
                  right: -5,
                  top: -4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3B30),
                      shape: BoxShape.circle,
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
// Camera tab — fixed 44x44 circle, level with the other tabs, own glass
// surface + feathered halo shadow. Icon always outline, always white.
// ---------------------------------------------------------------------------

class _CameraTab extends StatefulWidget {
  const _CameraTab({required this.iconSize, required this.onTap});

  final double iconSize;
  final VoidCallback onTap;

  @override
  State<_CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<_CameraTab> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.ease,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(18, 17, 16, 0.32),
                spreadRadius: 5,
              ),
              BoxShadow(
                color: Color.fromRGBO(18, 17, 16, 0.28),
                blurRadius: 14,
                spreadRadius: 8,
              ),
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.4),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.compose(
                outer: ColorFilter.matrix(_saturationMatrix(1.8)),
                inner: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color.fromRGBO(255, 255, 255, 0.18),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.2),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: widget.iconSize, end: widget.iconSize),
                      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 340),
                      curve: const Cubic(0.4, 0.14, 0.3, 1.0),
                      builder: (context, size, _) => TabBarIcon(
                        glyph: TabGlyph.camera,
                        size: size,
                        color: Colors.white,
                        filled: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anon score badge — the viewing user's OWN score/tier, a compact dark
// glass pill matching the bell icon's own visual language. Deliberately
// lighter-weight than the per-post ScoreGlowRing treatment (see
// shared/score_tier.dart) — a full glow ring next to a 36px bell would
// overwhelm this small a header slot, so tier is communicated via the
// star glyph + number color instead.
// ---------------------------------------------------------------------------

class _AnonScoreBadge extends StatelessWidget {
  const _AnonScoreBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(score);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 14, color: info.color),
          const SizedBox(width: 5),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: info.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small red badge
// ---------------------------------------------------------------------------

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating ping FAB — gradient circle, bottom-right, ping tab only
// ---------------------------------------------------------------------------

class _PingFAB extends StatefulWidget {
  @override
  State<_PingFAB> createState() => _PingFABState();
}

class _PingFABState extends State<_PingFAB>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.40, end: 0.80).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF833AB4).withValues(alpha: _pulseAnim.value * 0.65),
              blurRadius: 28,
              spreadRadius: 3,
            ),
          ],
        ),
        child: const Icon(
          Icons.notifications_active_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
