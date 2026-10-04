import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ping_visual_kit.dart' show pingCyan;

// ---------------------------------------------------------------------------
// HoldToRevealBlur — the single canonical hold-to-reveal gesture for the
// Ping feature. Consolidates 3 previously-duplicate hand-rolled versions
// (ping_screen.dart's _UnrevealedPhotoReply and _ReplyFeedPage, and
// ping_view_sheet.dart's _HoldArea+_RingPainter) into one shared widget —
// see design-refs/no implemented/Ping Page.dc.html's "Hold-to-reveal
// gesture" section for the spec this follows.
//
// The caller owns [revealed] (once true, this widget never re-blurs — that
// was already the real behavior in all 3 predecessors, just not formalized
// in one place) and is notified via [onRevealed] the instant the hold
// completes.
// ---------------------------------------------------------------------------

class HoldToRevealBlur extends StatefulWidget {
  const HoldToRevealBlur({
    super.key,
    required this.child,
    required this.revealed,
    required this.onRevealed,
    this.holdDuration = const Duration(milliseconds: 1000),
    this.blurSigma = 4.5,
    this.rightAnchoredWidth,
    this.ringSize = 42,
    this.dotOpacity = 0.65,
    this.showHint = true,
  });

  /// The content this gesture reveals — rendered blurred/dimmed until
  /// [revealed], then shown clean underneath this widget's ring overlay.
  final Widget child;

  final bool revealed;
  final VoidCallback onRevealed;
  final Duration holdDuration;

  /// Max Flutter blur sigma at 0% hold progress. CSS spec is `blur(9px)`;
  /// Flutter sigma = CSS px ÷ 2 (COLORS_AND_SHAPES.md §2.7), so 4.5 here
  /// reproduces the same visual blur, not 9.
  final double blurSigma;

  /// 42 in rows (default), 36 on Group Wall tiles — the arc is always
  /// [pingCyan] and the center dot is always neutral white; per
  /// THEME_CORRECTIONS.md Defect 5, identity/origin color never touches
  /// the ring.
  final double ringSize;

  /// Center-dot alpha: `.65` on rows, `.75` on tiles.
  final double dotOpacity;

  /// When set, the ring+hint sit in a fixed-width zone pinned to the right
  /// edge (spec §7a's 90-wide hold zone) instead of centered across the
  /// whole widget — used by the wide To-Reply/Reply rows. Null (default)
  /// centers the ring in the middle of the widget, for square surfaces like
  /// Group Wall tiles where that's the correct spec'd position.
  final double? rightAnchoredWidth;

  /// False hides the "hold Ns to reveal" caption beneath the ring, leaving
  /// just the ring+dot. For a compact inline use (a blurred name inside a
  /// sentence, e.g. notifications_screen.dart's BlurredActorLine) where the
  /// surrounding text's own line height has no room for a second line of
  /// caption underneath — including it there overflowed the row by exactly
  /// the caption's own height. Every existing caller (Ping's own rows/
  /// tiles) keeps the caption, since it's the one thing that tells a
  /// first-time user what the gesture even is; only a caller with no room
  /// for it needs to turn it off.
  final bool showHint;

  @override
  State<HoldToRevealBlur> createState() => _HoldToRevealBlurState();
}

class _HoldToRevealBlurState extends State<HoldToRevealBlur>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _holding = false;
  int _lastHapticSecond = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addListener(_onProgress)
      ..addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onProgress);
    _ctrl.dispose();
    super.dispose();
  }

  void _onProgress() {
    if (widget.revealed) return;
    final totalSecs = widget.holdDuration.inMilliseconds / 1000;
    final sec = (_ctrl.value * totalSecs).floor();
    if (sec > _lastHapticSecond && sec > 0) {
      _lastHapticSecond = sec;
      HapticFeedback.lightImpact();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !widget.revealed) {
      HapticFeedback.heavyImpact();
      widget.onRevealed();
    }
  }

  void _startHold() {
    if (widget.revealed) return;
    setState(() => _holding = true);
    _lastHapticSecond = 0;
    HapticFeedback.selectionClick();
    _ctrl.forward(from: _ctrl.value);
  }

  void _endHold() {
    if (widget.revealed) return;
    setState(() => _holding = false);
    _lastHapticSecond = -1;
    _ctrl.reverse();
  }

  String _hint(double progress) {
    if (widget.revealed) return '';
    if (progress >= 0.999) return 'opening';
    if (_holding) return 'keep holding';
    final secs = (widget.holdDuration.inMilliseconds / 1000).ceil();
    return 'hold ${secs}s to reveal';
  }

  /// Idle `white(.28)`; holding/complete `cyan(.85)` — THEME_CORRECTIONS.md
  /// Defect 6.
  Color _hintColor() => _holding ? pingCyan.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.28);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _endHold(),
      onLongPressCancel: _endHold,
      // No onTap here — once revealed, _startHold/_endHold's own
      // `if (widget.revealed) return;` guards make every long-press
      // callback inert, and reopening an already-revealed row into its
      // expanded card (per spec) is the CALLER's own GestureDetector
      // wrapping this widget, not something this shared blur/ring layer
      // needs to know about.
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final progress = widget.revealed ? 1.0 : _ctrl.value;
          final blurSigma = widget.revealed
              ? 0.0
              : widget.blurSigma * (1.0 - progress);
          return Stack(
            fit: StackFit.passthrough,
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: widget.child,
              ),
              if (!widget.revealed)
                _positionHoldZone(
                  child: IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: widget.ringSize,
                            height: widget.ringSize,
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                // Glow layer: inset -10, cyan(.12+.40p) blur (10+26p).
                                Positioned(
                                  left: -10,
                                  top: -10,
                                  right: -10,
                                  bottom: -10,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: pingCyan.withValues(alpha: 0.12 + 0.40 * progress),
                                          blurRadius: 10 + 26 * progress,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                CustomPaint(
                                  size: Size.square(widget.ringSize),
                                  painter: _ConicRingPainter(
                                    progress: progress,
                                    color: pingCyan,
                                  ),
                                ),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: widget.dotOpacity),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.showHint) ...[
                            const SizedBox(height: 6),
                            Text(
                              _hint(progress),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 8.5,
                                color: _hintColor(),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _positionHoldZone({required Widget child}) {
    final w = widget.rightAnchoredWidth;
    if (w == null) return Positioned.fill(child: child);
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: w,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.0)],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Conic-gradient reveal ring — plain dot at center (no lock icon, per
/// spec), arc fills clockwise from the top as hold progress increases.
class _ConicRingPainter extends CustomPainter {
  const _ConicRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // strokeWidth = 0.08 × diameter (COLORS_AND_SHAPES.md §2.3/§2.4).
    final strokeWidth = size.width * 0.08;
    final radius = size.width / 2 - strokeWidth / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.09)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963267948966, // -π/2, start at top
      progress * 6.283185307179586, // progress * 2π
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ConicRingPainter old) =>
      old.progress != progress || old.color != color;
}
