import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'constants.dart';

/// Frosted glass container — wrap any widget for the glass effect.
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.borderRadius = 20.0,
    this.blur = 24.0,
    this.opacity = 0.10,
    this.borderOpacity = 0.15,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final double borderOpacity;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Instagram gradient button decoration.
BoxDecoration instaGradientDecoration({double radius = 14}) => BoxDecoration(
  gradient: AppColors.instaGradient,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF833AB4).withValues(alpha: 0.40),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ],
);

/// Glass surface decoration (frosted).
BoxDecoration glassDecoration({double radius = 14}) => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.10),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
);

// ---------------------------------------------------------------------------
// Toasts — they DROP DOWN FROM THE TOP (explicit request, 2026-10-03: "let
// the notification drop from up, not down").
//
// These used to be floating SnackBars pinned above the tab bar at the
// bottom. SnackBar cannot be moved to the top (its position is baked into
// ScaffoldMessenger), so both toasts are now Overlay entries with their own
// slide-down animation, which also means they float over the tab bar,
// sheets and full-screen viewers rather than under them.
// ---------------------------------------------------------------------------

/// How long a toast stays once it has finished dropping in.
const _kToastHold = Duration(seconds: 3);
const _kToastHoldError = Duration(seconds: 5);

OverlayEntry? _currentToast;

void _showTopToast(
  BuildContext context,
  Widget child, {
  required Duration duration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  // One at a time — a second toast replaces the first rather than stacking.
  _currentToast?.remove();
  _currentToast = null;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TopToast(
      duration: duration,
      onDone: () {
        if (_currentToast == entry) _currentToast = null;
        if (entry.mounted) entry.remove();
      },
      child: child,
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.child,
    required this.duration,
    required this.onDone,
  });

  final Widget child;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) {
      widget.onDone();
      return;
    }
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final curved = CurvedAnimation(
      parent: _c,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      top: top + 8,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: Material(
            color: Colors.transparent,
            // Swipe up or tap to dismiss early.
            child: GestureDetector(
              onTap: _dismiss,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < 0) _dismiss();
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A toast in the app's standard frosted-glass style. Pass [actionLabel] +
/// [onAction] for a recoverable-error toast with a retry button.
void showGlassToast(
  BuildContext context,
  String message, {
  bool isError = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _showTopToast(
    context,
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassBox(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.redAccent : Colors.greenAccent,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    duration: isError ? _kToastHoldError : _kToastHold,
  );
}

/// The Ping page's toast — a black, fully rounded pill with a cyan edge and
/// glow, matching the Ping tab's own blue-on-black look (explicit request:
/// the notice after pinging someone should look like the Ping page).
void showPingToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  const cyan = Color(0xFF29D3E8);
  final accent = isError ? const Color(0xFFFF6B7A) : cyan;
  _showTopToast(
    context,
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            // Themed glow (explicit request, 2026-10-03: "give
            // notification a little the same themed glow like thing") —
            // the same cyan bloom the Ping page's own cards carry: a wide
            // soft halo, a tighter bright one, and a black drop so the
            // pill still reads against a light photo behind it.
            color: const Color(0xF20B0B0D),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: accent.withValues(alpha: 0.7), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.34),
                blurRadius: 34,
                spreadRadius: 1,
              ),
              BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 10),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline_rounded : Icons.check_rounded,
                color: accent,
                size: 17,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    duration: isError ? const Duration(seconds: 4) : const Duration(seconds: 2),
  );
}
