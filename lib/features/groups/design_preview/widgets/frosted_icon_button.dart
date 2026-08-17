import 'dart:ui';
import 'package:flutter/material.dart';

/// Circular frosted-glass icon button — 1a's nav chevron/overflow-dots
/// (34pt, rgba(0,0,0,.4)) and the post-card-style action rail (44pt,
/// rgba(0,0,0,.45)), both blur(8px) per the design spec's "Frosted glass"
/// token. Distinct from lib/core/glass.dart's GlassBox, which is tinted
/// white — this needs the spec's black tint, so it's its own small widget
/// rather than a GlassBox wrapper.
class FrostedIconButton extends StatelessWidget {
  const FrostedIconButton({
    super.key,
    required this.child,
    this.size = 34,
    this.opacity = 0.4,
    this.blur = 8,
    this.onTap,
  });

  final Widget child;
  final double size;
  final double opacity;
  final double blur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
