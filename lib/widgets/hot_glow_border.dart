import 'package:flutter/material.dart';

/// Pulsing glow border for a "hot" card — same technique as the ping
/// button's cyan glow in `anonymous_tab.dart`'s `_GlowPingButton`
/// (animated BoxShadow/border alpha), generalized to wrap arbitrary
/// card-shaped content instead of a small circular button.
class HotGlowBorder extends StatefulWidget {
  const HotGlowBorder({
    super.key,
    required this.child,
    required this.hot,
    this.borderRadius = 24,
    this.color = const Color(0xFFFFB020),
  });

  final Widget child;
  final bool hot;
  final double borderRadius;
  final Color color;

  @override
  State<HotGlowBorder> createState() => _HotGlowBorderState();
}

class _HotGlowBorderState extends State<HotGlowBorder> with SingleTickerProviderStateMixin {
  // Only allocated (and only ticks) while actually hot — most cards never
  // are, so most cards should never pay for a running AnimationController.
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.hot) _startGlow();
  }

  @override
  void didUpdateWidget(covariant HotGlowBorder old) {
    super.didUpdateWidget(old);
    if (widget.hot && _ctrl == null) {
      _startGlow();
    } else if (!widget.hot && _ctrl != null) {
      _stopGlow();
    }
  }

  void _startGlow() {
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  void _stopGlow() {
    _ctrl?.dispose();
    _ctrl = null;
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (!widget.hot || ctrl == null) return widget.child;
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final t = ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.55 + 0.25 * t),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.28 + 0.20 * t),
                blurRadius: 14 + 8 * t,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: widget.child,
      ),
    );
  }
}
