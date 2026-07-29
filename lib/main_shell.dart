import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _navShrunk = false;
  bool _scrollHideEnabled = false;

  late final AnimationController _bannerCtrl;
  late final Animation<Offset> _bannerSlide;
  AppNotif? _lastBannerNotif;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(onOpenCamera: _openComposer),
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
    // UserScrollNotification reflects the user's drag *intent*, updated
    // once per gesture direction change — unlike per-frame scrollDelta it
    // isn't corrupted by a PageView's snap-back settle animation on a
    // partial drag (which was making the shrink look like it never fired).
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse && !_navShrunk) {
        setState(() => _navShrunk = true);
      } else if (notification.direction == ScrollDirection.forward && _navShrunk) {
        setState(() => _navShrunk = false);
      }
    } else if (notification is ScrollEndNotification) {
      // Always restore at the very top
      if (notification.metrics.pixels <= 10 && _navShrunk) {
        setState(() => _navShrunk = false);
      }
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
    Navigator.of(context).push(openCameraRoute());
  }

  void _openPingSendSheet() {
    HapticFeedback.mediumImpact();
    showPingChoiceSheet(context);
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final unreadHome = notifState.unreadHome;
    final unreadPings = notifState.unreadPings;
    final communityBadge = notifState.communityBadge;
    final totalUnread = notifState.totalUnread;

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

          // ── Bell icon (top-right) ────────────────────────────────────
          Positioned(
            top: topPad + 8,
            right: 16,
            child: GestureDetector(
              onTap: _openNotifications,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A20).withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (totalUnread > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.background,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            totalUnread > 9 ? '9+' : '$totalUnread',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Bottom nav — floating rounded liquid-glass pill ─────────
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPad + 4,
            child: _BottomNav(
              currentIndex: _currentIndex,
              shrunk: _navShrunk,
              unreadHome: unreadHome,
              unreadPings: unreadPings,
              communityBadge: communityBadge,
              totalUnread: totalUnread,
              onTabSelected: (i) {
                HapticFeedback.lightImpact();
                setState(() {
                  _currentIndex = i;
                  _navShrunk = false;
                });
              },
              onComposerOpen: _openComposer,
            ),
          ),

          // ── Floating ping FAB — bottom-right, ping tab only ─────────
          if (_currentIndex == 1)
            Positioned(
              right: 16,
              bottom: bottomPad + 4 + _BottomNav._kBarHeight + 12,
              child: GestureDetector(
                onTap: _openPingSendSheet,
                child: _PingFAB(),
              ),
            ),

          // ── Glass notification — right side, above bottom nav ────────
          GlassNotifOverlay(
            bottomOffset: bottomPad + 4 + _BottomNav._kBarHeight + 12,
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
// Flat bottom nav — full-width, anchored, frosted glass (Instagram-style)
// ---------------------------------------------------------------------------

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.shrunk,
    required this.unreadHome,
    required this.unreadPings,
    required this.communityBadge,
    required this.totalUnread,
    required this.onTabSelected,
    required this.onComposerOpen,
  });

  final int currentIndex;
  final bool shrunk;
  final int unreadHome;
  final int unreadPings;
  final bool communityBadge;
  final int totalUnread;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onComposerOpen;

  static const _kBarHeight = 56.0;
  static const _kBarHeightShrunk = 36.0;

  // App tab index (0..3) → row slot (0..4). Slot 2 = camera (not a tab).
  static int _rowSlot(int idx) => idx < 2 ? idx : idx + 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final W = constraints.maxWidth;
        return _buildBar(W);
      },
    );
  }

  Widget _buildBar(double W) {
    final itemW = W / 5;
    final slot = _rowSlot(currentIndex);
    final barH = shrunk ? _kBarHeightShrunk : _kBarHeight;
    final iconSz = shrunk ? 20.0 : 24.0;
    final cameraSz = shrunk ? 22.0 : 26.0;
    final radius = barH / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D11).withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: shrunk ? 0.08 : 0.14),
              width: 0.75,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: barH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Sliding active-tab highlight pill — hidden when shrunk
                    if (!shrunk)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        left: slot * itemW + itemW * 0.14,
                        top: (_kBarHeight - 36) / 2,
                        width: itemW * 0.72,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    // Icons row
                    Row(
                      children: [
                        _BottomTab(
                          icon: Icons.home_outlined,
                          activeIcon: Icons.home_rounded,
                          isActive: currentIndex == 0,
                          badge: unreadHome,
                          iconSize: iconSz,
                          onTap: () => onTabSelected(0),
                        ),
                        _BottomTab(
                          icon: Icons.notifications_outlined,
                          activeIcon: Icons.notifications_rounded,
                          isActive: currentIndex == 1,
                          badge: unreadPings,
                          iconSize: iconSz,
                          onTap: () => onTabSelected(1),
                        ),
                        // Camera — compose action, center slot
                        Expanded(
                          child: GestureDetector(
                            onTap: onComposerOpen,
                            behavior: HitTestBehavior.opaque,
                            child: Center(
                              child: AnimatedScale(
                                scale: shrunk ? 0.82 : 1.0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                child: Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white.withValues(alpha: 0.70),
                                  size: cameraSz,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _BottomTab(
                          icon: Icons.people_outline,
                          activeIcon: Icons.people,
                          isActive: currentIndex == 2,
                          hasDot: communityBadge,
                          iconSize: iconSz,
                          onTap: () => onTabSelected(2),
                        ),
                        _ProfileBottomTab(
                          isActive: currentIndex == 3,
                          totalUnread: totalUnread,
                          shrunk: shrunk,
                          onTap: () => onTabSelected(3),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Individual bottom tab — icon + optional badge
// ---------------------------------------------------------------------------

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.onTap,
    this.badge = 0,
    this.hasDot = false,
    this.iconSize = 24.0,
  });

  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final VoidCallback onTap;
  final int badge;
  final bool hasDot;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedScale(
                scale: iconSize / 24.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: Icon(
                  isActive ? activeIcon : icon,
                  color: isActive
                      ? const Color(0xFFE1306C)
                      : Colors.white.withValues(alpha: 0.40),
                  size: 24,
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: -8,
                  top: -6,
                  child: _NavBadge(count: badge),
                ),
              if (hasDot && badge == 0)
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
// Profile avatar tab
// ---------------------------------------------------------------------------

class _ProfileBottomTab extends StatelessWidget {
  const _ProfileBottomTab({
    required this.isActive,
    required this.totalUnread,
    required this.shrunk,
    required this.onTap,
  });

  final bool isActive;
  final int totalUnread;
  final bool shrunk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedScale(
            scale: shrunk ? 0.82 : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2E2A52),
                  border: Border.all(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.30),
                    width: isActive ? 2.0 : 1.0,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'AP',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              if (totalUnread > 0)
                Positioned(
                  right: -7,
                  top: -5,
                  child: _NavBadge(count: totalUnread),
                ),
            ],
          ),
          ), // AnimatedScale
        ),
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
