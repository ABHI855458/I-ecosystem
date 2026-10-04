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

/// Ping icon for the "surface" (dark-circle button) style — ported literally
/// from the live design source's own SVG (Feed.dc.html): `<svg width="24"
/// height="24" viewBox="0 0 32 32"><circle cx="16" cy="16" r="13.2"
/// stroke="rgba(255,255,255,.9)" stroke-width="1.5"/><circle cx="16"
/// cy="10.6" r="1.9" fill="#fff"/><path d="M10 14.2c1.9.85 3.9 1.28 6 1.28
/// s4.1-.43 6-1.28M16 15.48v3.7M16 19.18l-2.6 4.4M16 19.18l2.6 4.4"
/// stroke="#fff" stroke-width="1.8" stroke-linecap="round"/></svg>` — a
/// cheering figure (curved raised-arms sweep), NOT a straight-limbed stick
/// figure. Distinct from [StickFigureGlyphPainter] above, which is the OLDER
/// 19×20 Anon-tray glyph (no outer ring, black-on-white) — this is what
/// PostPingButton's default `TrayIconVisualStyle.surface` branch paints on
/// its own #131315 circle.
class PingRingGlyphPainter extends CustomPainter {
  const PingRingGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);

    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(const Offset(16, 16), 13.2, ring);

    canvas.drawCircle(const Offset(16, 10.6), 1.9, Paint()..color = Colors.white);

    final body = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // "M10 14.2 c1.9,.85 3.9,1.28 6,1.28 s4.1,-.43 6,-1.28" — the raised-arms
    // shoulder sweep, as two cubics (absolute coords, converted from the
    // SVG's relative c/s commands).
    final arms = Path()
      ..moveTo(10, 14.2)
      ..cubicTo(11.9, 15.05, 13.9, 15.48, 16, 15.48)
      ..cubicTo(18.1, 15.48, 20.1, 15.05, 22, 14.2);
    canvas.drawPath(arms, body);

    canvas.drawLine(const Offset(16, 15.48), const Offset(16, 19.18), body);
    canvas.drawLine(const Offset(16, 19.18), const Offset(13.4, 23.58), body);
    canvas.drawLine(const Offset(16, 19.18), const Offset(18.6, 23.58), body);

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

/// RealMoji idle glyph — ported literally from Feed.dc.html's not-reacted
/// SVG: `<svg width="21" height="21" viewBox="0 0 24 24" stroke="#1a1a1a"
/// stroke-width="1.9"><circle cx="12" cy="12" r="9.2"/><path d="M8.4 14.2
/// c.9 1.2 2.1 1.8 3.6 1.8 s2.7-.6 3.6-1.8"/><circle cx="9" cy="10" r=".9"
/// fill="#1a1a1a"/><circle cx="15" cy="10" r=".9" fill="#1a1a1a"/></svg>` —
/// replaces the generic Icons.sentiment_satisfied_outlined Material icon
/// that was standing in for it on [PostReactionButton]'s white idle circle.
class RealMojiSmileyPainter extends CustomPainter {
  const RealMojiSmileyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final stroke = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(const Offset(12, 12), 9.2, stroke);

    final mouth = Path()
      ..moveTo(8.4, 14.2)
      ..cubicTo(9.3, 15.4, 10.5, 16.0, 12.0, 16.0)
      ..cubicTo(13.5, 16.0, 14.7, 15.4, 15.6, 14.2);
    canvas.drawPath(mouth, stroke);

    final fill = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawCircle(const Offset(9, 10), 0.9, fill);
    canvas.drawCircle(const Offset(15, 10), 0.9, fill);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
