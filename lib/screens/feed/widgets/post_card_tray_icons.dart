import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Tray icon glyphs for the Anonymous feed's post card (Post Card
// Implementation Spec section 4) — the stick-figure (ping) and reaction
// (smiley+plus) icons are each a self-contained glyph (the "button" IS the
// glyph — the spec's own circle is part of the icon artwork, not a separate
// chip/container drawn around it), ported 1:1 from the spec's SVG markup as
// CustomPainters so they scale exactly with AnonPostCardGeometry's
// S-derived, non-square icon boxes (19×20 / 22×19 at S=1).
//
// TrayHitTarget keeps the tap target accessible (>=44x44, per the spec's
// own note) WITHOUT changing the glyph's layout footprint — the icons sit
// at pixel-exact tray positions (right inset / gap / top inset), so padding
// the visible box would silently shift them off spec. Instead the oversized
// tap area is a Positioned sibling that overflows the tightly-sized box via
// Clip.none, which affects hit-testing only, never layout.
// ---------------------------------------------------------------------------

/// Shared switch between a call site's existing "surface" chrome (light
/// circle + glyph, unchanged look) and the spec's "glyph" look (the icon's
/// own artwork IS the whole button, no extra container). Used by
/// PostPingButton and PostReactionButton (post_card_shared.dart) — both
/// default to [surface] so every existing call site (Friends/Everyone feed,
/// TextPostCard) is untouched; only PhotoPostCard's tray (Anonymous feed)
/// opts into [glyph].
enum TrayIconVisualStyle { surface, glyph }

class TrayHitTarget extends StatelessWidget {
  const TrayHitTarget({
    super.key,
    required this.width,
    required this.height,
    required this.onTap,
    required this.child,
  });

  final double width;
  final double height;
  final VoidCallback onTap;
  final Widget child;

  static const double _minHit = 44.0;

  @override
  Widget build(BuildContext context) {
    final hitW = width < _minHit ? _minHit : width;
    final hitH = height < _minHit ? _minHit : height;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            left: (width - hitW) / 2,
            top: (height - hitH) / 2,
            width: hitW,
            height: hitH,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ping icon — spec section 4.1: thin circle outline with a stick figure
/// inside (open round head, straight torso, arms/legs in a V). View box
/// 19×20 — ported point-for-point from the spec's SVG, EXCEPT stroke color:
/// the spec's reference is white-on-photo (the tray floats over a photo
/// that extends behind it), but this app's tray apron is the card's own
/// white surface (PhotoPostCard's outer DecoratedBox), not photo content —
/// white-on-white would be invisible there. Recolored to black per the
/// spec's own "adapt colors to match the app's icon set" allowance; stroke
/// width/geometry/proportions are unchanged.
class StickFigureGlyphPainter extends CustomPainter {
  const StickFigureGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 19, size.height / 20);
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.95
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(const Offset(9.5, 10), 8.85, paint);
    canvas.drawCircle(const Offset(9.5, 5.75), 1.75, paint);
    canvas.drawLine(const Offset(9.5, 7.5), const Offset(9.5, 12.5), paint);
    canvas.drawPath(
      Path()
        ..moveTo(6.2, 8.5)
        ..lineTo(9.5, 10.3)
        ..lineTo(12.8, 8.5),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(6.5, 16.1)
        ..lineTo(9.5, 12.5)
        ..lineTo(12.5, 16.1),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Reaction (add-a-reaction) icon — spec section 4.2: solid black circle,
/// minimal white smiley (two dot eyes + a small curved mouth — NOT a wide
/// arc following the circle's own edge, which reads as an arch over the
/// eyes rather than a smile, per the spec's own note), plus a white "+"
/// badge on its own black knockout circle top-right. View box 22×19.
class ReactionGlyphPainter extends CustomPainter {
  const ReactionGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 22, size.height / 19);
    final fillBlack = Paint()..color = Colors.black;
    final fillWhite = Paint()..color = Colors.white;
    final strokeWhite = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(const Offset(9.5, 9.5), 9.5, fillBlack);
    canvas.drawCircle(const Offset(6.7, 7.9), 1.15, fillWhite);
    canvas.drawCircle(const Offset(12.3, 7.9), 1.15, fillWhite);
    canvas.drawPath(
      Path()
        ..moveTo(6.1, 11.9)
        ..cubicTo(7.4, 14.1, 11.6, 14.1, 12.9, 11.9),
      strokeWhite,
    );

    canvas.drawCircle(const Offset(18.1, 3.6), 3.9, fillBlack);
    canvas.drawLine(
      const Offset(18.1, 1.5),
      const Offset(18.1, 5.7),
      strokeWhite,
    );
    canvas.drawLine(
      const Offset(16.0, 3.6),
      const Offset(20.2, 3.6),
      strokeWhite,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
