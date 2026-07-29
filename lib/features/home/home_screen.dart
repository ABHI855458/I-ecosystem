import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../screens/feed/everyone_feed_screen.dart';
import '../composer/composer_screen.dart';
import 'anonymous_tab.dart';

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenCamera});

  final VoidCallback? onOpenCamera;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pageController = PageController();
  int _tabIndex = 0;
  double _collapseProgress = 0.0;
  bool _cameraTriggered = false;
  String _selectedCommunity = 'All';

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    if (_tabIndex == index) return;
    setState(() {
      _tabIndex = index;
      _collapseProgress = 0.0;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _openCamera() {
    if (widget.onOpenCamera != null) {
      widget.onOpenCamera!();
    } else {
      Navigator.of(context).push(openCameraRoute());
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final pixels = notification.metrics.pixels.clamp(0.0, double.infinity);
      final progress = (pixels / 120.0).clamp(0.0, 1.0);
      if ((progress - _collapseProgress).abs() > 0.005) {
        setState(() => _collapseProgress = progress);
      }
    }

    // Pull-down-to-camera: iOS overscroll (pixels go negative)
    if (!_cameraTriggered &&
        notification is ScrollUpdateNotification &&
        notification.metrics.pixels < -80) {
      _cameraTriggered = true;
      _openCamera();
    }
    // Pull-down-to-camera: Android overscroll notification
    if (!_cameraTriggered &&
        notification is OverscrollNotification &&
        notification.overscroll > 80) {
      _cameraTriggered = true;
      _openCamera();
    }
    if (notification is ScrollEndNotification) {
      _cameraTriggered = false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topPadding + 4),
          _SlimHeader(
            activeTab: _tabIndex,
            onTabSwitch: _switchTab,
            collapseProgress: _collapseProgress,
            selectedCommunity: _selectedCommunity,
            onCommunityChanged: (c) => setState(() => _selectedCommunity = c),
            onRespondTap: _openCamera,
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() {
                  _tabIndex = i;
                  _collapseProgress = 0.0;
                }),
                children: [
                  AnonymousTab(
                    selectedCommunity: _selectedCommunity,
                    onScrollProgress: (p) =>
                        setState(() => _collapseProgress = p),
                  ),
                  const EveryoneFeedScreen(),
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
// Collapsing header
// ---------------------------------------------------------------------------

class _SlimHeader extends StatefulWidget {
  const _SlimHeader({
    required this.activeTab,
    required this.onTabSwitch,
    required this.collapseProgress,
    required this.selectedCommunity,
    required this.onCommunityChanged,
    required this.onRespondTap,
  });

  final int activeTab;
  final ValueChanged<int> onTabSwitch;
  final double collapseProgress;
  final String selectedCommunity;
  final ValueChanged<String> onCommunityChanged;
  final VoidCallback onRespondTap;

  @override
  State<_SlimHeader> createState() => _SlimHeaderState();
}

class _SlimHeaderState extends State<_SlimHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  static const _activeNow = 234;
  static const _pills = ['All', 'Campus', 'CSE', '3rd Year', 'Photography'];
  static const _dailyPrompt =
      "What's something you've never told anyone here?";
  static const _handle = 'silent_storm';

  // Everyone only: toggle tucks away once scrolled into posts, reappears
  // back at the top — same collapse feel as the Wall strip. Anonymous
  // keeps the toggle always visible/unchanged. Tracked as its own bit of
  // state (with an enter/exit gap) rather than a plain `t > threshold`
  // expression — recomputing straight off the raw scroll position flickered
  // every time `t` hovered near the cutoff.
  bool _toggleHidden = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_SlimHeader old) {
    super.didUpdateWidget(old);
    _updateToggleHidden();
  }

  void _updateToggleHidden() {
    if (widget.activeTab != 1) {
      if (_toggleHidden) setState(() => _toggleHidden = false);
      return;
    }
    final t = widget.collapseProgress;
    if (t > 0.25 && !_toggleHidden) {
      setState(() => _toggleHidden = true);
    } else if (t < 0.08 && _toggleHidden) {
      setState(() => _toggleHidden = false);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.collapseProgress;
    final rowOpacity = (1.0 - t / 0.65).clamp(0.0, 1.0);
    final rowHFactor = (1.0 - t / 0.80).clamp(0.0, 1.0);
    final toggleHidden = _toggleHidden;

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tab toggle
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: toggleHidden
                  ? const SizedBox.shrink()
                  : Center(
                      child: _FeedToggle(
                        activeIndex: widget.activeTab,
                        onToggle: widget.onTabSwitch,
                      ),
                    ),
            ),
            if (widget.activeTab == 0) ...[
              // Identity row (collapses on scroll)
              ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: rowHFactor,
                  child: Opacity(
                    opacity: rowOpacity,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1A1A22),
                              border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.50),
                                width: 1.5,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.person_outline,
                                size: 13,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Anonymous • CSE',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          AnimatedBuilder(
                            animation: _pulseAnim,
                            builder: (ctx2, _) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Color.fromRGBO(
                                        255, 255, 255, _pulseAnim.value),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$_activeNow active',
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
                  ),
                ),
              ),

              // Community pills — always visible
              const SizedBox(height: 10),
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _pills.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (_, i) {
                    final active = widget.selectedCommunity == _pills[i];
                    return GestureDetector(
                      onTap: () => widget.onCommunityChanged(_pills[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? Colors.white : const Color(0xFF1C1C24),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          _pills[i],
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: active
                                ? Colors.black
                                : Colors.white.withValues(alpha: 0.75),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Prompt composer — full box collapses to slim strip on scroll
              const SizedBox(height: 10),
              _buildPromptComposer(t),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPromptComposer(double t) {
    // Full box fades+shrinks as t goes 0→1
    final fullHFactor = (1.0 - t * 1.4).clamp(0.0, 1.0);
    final fullOpacity = (1.0 - t * 1.8).clamp(0.0, 1.0);
    // Slim strip fades in after half-collapse
    final slimOpacity = ((t - 0.55) * 3.0).clamp(0.0, 1.0);

    return Stack(
      children: [
        // Slim strip underneath (revealed when full collapses)
        Opacity(
          opacity: slimOpacity,
          child: GestureDetector(
            onTap: widget.onRespondTap,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF111116),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dailyPrompt,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                        decoration: TextDecoration.none,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.black, size: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Full composer on top (collapses away on scroll)
        ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: fullHFactor,
            child: Opacity(
              opacity: fullOpacity,
              child: GestureDetector(
                onTap: widget.onRespondTap,
                child: _buildFullComposer(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullComposer() {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: Colors.white.withValues(alpha: 0.18),
        radius: 12,
        dashWidth: 5,
        dashGap: 5,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E14),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle row
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A1A22),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.40),
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.person_outline,
                      size: 11,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _handle,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Prompt text
            Text(
              _dailyPrompt,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.50),
                height: 1.4,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 10),
            // Action row
            Row(
              children: [
                _ComposerChip(label: '+ vibe'),
                const SizedBox(width: 6),
                _ComposerChip(label: 'community'),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onRespondTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Respond →',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
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
// Feed toggle
// ---------------------------------------------------------------------------

class _FeedToggle extends StatelessWidget {
  const _FeedToggle({required this.activeIndex, required this.onToggle});

  final int activeIndex;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFE1306C).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE1306C).withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToggleChip(
                label: 'Anonymous',
                active: activeIndex == 0,
                onTap: () => onToggle(0),
              ),
              _ToggleChip(
                label: 'Everyone',
                active: activeIndex == 1,
                onTap: () => onToggle(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        height: double.infinity,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE1306C).withValues(alpha: 0.85) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFFE1306C).withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composer action chip
// ---------------------------------------------------------------------------

class _ComposerChip extends StatelessWidget {
  const _ComposerChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C24),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.60),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashed border painter
// ---------------------------------------------------------------------------

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashGap,
  });

  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rect);
    final pathMetrics = path.computeMetrics();

    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end =
            math.min(distance + dashWidth, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, end),
          paint,
        );
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dashWidth != dashWidth ||
      old.dashGap != dashGap;
}
