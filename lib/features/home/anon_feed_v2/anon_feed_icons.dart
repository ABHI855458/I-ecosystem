import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// The 17 icons (§15.2, I1–I17) as CustomPainters — zero icon-font/library
// dependency, per spec §15.2 ("None come from an icon library"). Each
// painter's viewBox is documented on the class; callers size the painter's
// CustomPaint to the icon's design px × anonScale(context), NOT to the
// viewBox — Flutter's Canvas coordinate space is scaled to fill `size` via
// the same viewBox-to-size ratio Canvas.drawPath naturally provides once
// the paths below are authored in viewBox units and the CustomPaint is
// sized to the icon's real (viewBox-proportional) design size.
// ---------------------------------------------------------------------------

Paint _stroke(Color color, double width, {StrokeCap cap = StrokeCap.round, StrokeJoin join = StrokeJoin.round}) =>
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = cap
      ..strokeJoin = join;

Paint _fill(Color color) => Paint()..color = color..style = PaintingStyle.fill;

/// Scales a painter authored against [viewBox] to actually fill the given
/// canvas [size] — every path below is written in viewBox units.
void _withViewBox(Canvas canvas, Size size, Size viewBox, void Function(Canvas) draw) {
  canvas.save();
  canvas.scale(size.width / viewBox.width, size.height / viewBox.height);
  draw(canvas);
  canvas.restore();
}

// I1 — Paper-plane (send). viewBox 0 0 24 24. stroke per call site (1.9 in
// prompt bar / composer, 2.0 in ping sheet's send button — pass explicitly).
class PaperPlanePainter extends CustomPainter {
  const PaperPlanePainter({required this.color, this.strokeWidth = 1.9});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(24, 24), (c) {
      final path = Path()
        ..moveTo(21.5, 2.5)
        ..lineTo(2.5, 10)
        ..lineTo(10, 12.6)
        ..lineTo(13, 21)
        ..lineTo(21.5, 2.5)
        ..close();
      c.drawPath(path, _stroke(color, strokeWidth, join: StrokeJoin.round));
    });
  }

  @override
  bool shouldRepaint(covariant PaperPlanePainter old) => old.color != color || old.strokeWidth != strokeWidth;
}

// I2 — Chevron-right (on-photo count pill). viewBox 0 0 18 18. stroke 2.4.
class ChevronRightPainter extends CustomPainter {
  const ChevronRightPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(18, 18), (c) {
      final path = Path()..moveTo(6.5, 4)..lineTo(12, 9)..lineTo(6.5, 14);
      c.drawPath(path, _stroke(color, 2.4));
    });
  }

  @override
  bool shouldRepaint(covariant ChevronRightPainter old) => old.color != color;
}

// I3 — Ping stick-figure (app's "i" mark). viewBox 0 0 19 20. Used both as
// the card's tray ping icon (disc + inner ring + figure, stroke 0.95) and
// the ping sheet header glyph (figure only, cyan, stroke 1.7) — two modes.
class PingFigurePainter extends CustomPainter {
  const PingFigurePainter({
    required this.strokeColor,
    this.strokeWidth = 1.7,
    this.discFill,
    this.discRingColor,
  });

  final Color strokeColor;
  final double strokeWidth;

  /// When set, draws the white disc + inner ring behind the figure (§7.8A
  /// tray usage). Null for the plain-figure ping-sheet usage (§11).
  final Color? discFill;
  final Color? discRingColor;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(19, 20), (c) {
      if (discFill != null) {
        c.drawCircle(const Offset(9.5, 10), 9.5, _fill(discFill!));
        if (discRingColor != null) {
          c.drawCircle(const Offset(9.5, 10), 8.85, _stroke(discRingColor!, 0.95));
        }
      }
      final s = _stroke(strokeColor, strokeWidth);
      c.drawCircle(const Offset(9.5, 5.75), 1.75, s);
      c.drawPath(Path()..moveTo(9.5, 7.5)..lineTo(9.5, 12.5), s);
      c.drawPath(Path()..moveTo(6.2, 8.5)..lineTo(9.5, 10.3)..lineTo(12.8, 8.5), s);
      c.drawPath(Path()..moveTo(6.5, 16.1)..lineTo(9.5, 12.5)..lineTo(12.5, 16.1), s);
    });
  }

  @override
  bool shouldRepaint(covariant PingFigurePainter old) =>
      old.strokeColor != strokeColor || old.discFill != discFill || old.discRingColor != discRingColor;
}

// I4 — Real-moji smiley + plus badge. viewBox 0 0 22 19. §7.8B.
class RealmojiButtonPainter extends CustomPainter {
  const RealmojiButtonPainter({required this.discColor, required this.inkColor});
  final Color discColor;
  final Color inkColor;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(22, 19), (c) {
      c.drawCircle(const Offset(9.5, 9.5), 9.5, _fill(discColor));
      final ink = _fill(inkColor);
      c.drawCircle(const Offset(6.6, 7.7), 1.35, ink);
      c.drawCircle(const Offset(12.4, 7.7), 1.35, ink);
      c.drawPath(
        Path()
          ..moveTo(6.2, 11.6)
          ..cubicTo(7.5, 14.2, 11.5, 14.2, 12.8, 11.6),
        _stroke(inkColor, 1.7),
      );
      c.drawCircle(const Offset(18.3, 3.4), 3.7, _fill(discColor));
      final plusStroke = _stroke(inkColor, 1.6);
      c.drawPath(Path()..moveTo(18.3, 1.5)..lineTo(18.3, 5.3), plusStroke);
      c.drawPath(Path()..moveTo(16.4, 3.4)..lineTo(20.2, 3.4), plusStroke);
    });
  }

  @override
  bool shouldRepaint(covariant RealmojiButtonPainter old) =>
      old.discColor != discColor || old.inkColor != inkColor;
}

// I5 — Arrow-right (replies link). viewBox 0 0 20 20. stroke 2.2.
class ArrowRightPainter extends CustomPainter {
  const ArrowRightPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(20, 20), (c) {
      final path = Path()
        ..moveTo(4, 10)
        ..lineTo(15, 10)
        ..moveTo(10.5, 5.5)
        ..lineTo(15, 10)
        ..lineTo(10.5, 14.5);
      c.drawPath(path, _stroke(color, 2.2));
    });
  }

  @override
  bool shouldRepaint(covariant ArrowRightPainter old) => old.color != color;
}

// I6 — Three-dot overflow. viewBox 0 0 20 20. filled.
class ThreeDotPainter extends CustomPainter {
  const ThreeDotPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(20, 20), (c) {
      final f = _fill(color);
      for (final y in [4.0, 10.0, 16.0]) {
        c.drawCircle(Offset(10, y), 1.7, f);
      }
    });
  }

  @override
  bool shouldRepaint(covariant ThreeDotPainter old) => old.color != color;
}

// I7 — Chevron-up (peek panel). viewBox 0 0 18 18. stroke 2.2.
class ChevronUpPainter extends CustomPainter {
  const ChevronUpPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(18, 18), (c) {
      final path = Path()..moveTo(4, 11.5)..lineTo(9, 5.5)..lineTo(14, 11.5);
      c.drawPath(path, _stroke(color, 2.2));
    });
  }

  @override
  bool shouldRepaint(covariant ChevronUpPainter old) => old.color != color;
}

// I8 — Star (peek score). viewBox 0 0 24 24. filled, accentCyan.
class StarPainter extends CustomPainter {
  const StarPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(24, 24), (c) {
      final path = Path()
        ..moveTo(12, 1.5)
        ..lineTo(15.1, 8.6)
        ..lineTo(22.8, 9.3)
        ..lineTo(16.9, 14.4)
        ..lineTo(18.7, 22)
        ..lineTo(12, 17.9)
        ..lineTo(5.3, 22)
        ..lineTo(7.1, 14.4)
        ..lineTo(1.2, 9.3)
        ..lineTo(8.9, 8.6)
        ..close();
      c.drawPath(path, _fill(color));
    });
  }

  @override
  bool shouldRepaint(covariant StarPainter old) => old.color != color;
}

// I9 — Home. viewBox 0 0 22 22. filled.
class HomeIconPainter extends CustomPainter {
  const HomeIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(22, 22), (c) {
      final path = Path()
        ..moveTo(3, 10.5)
        ..lineTo(11, 4)
        ..lineTo(19, 10.5)
        ..lineTo(19, 18)
        ..cubicTo(19, 18.55, 18.55, 19, 18, 19)
        ..lineTo(4, 19)
        ..cubicTo(3.45, 19, 3, 18.55, 3, 18)
        ..close();
      c.drawPath(path, _fill(color));
    });
  }

  @override
  bool shouldRepaint(covariant HomeIconPainter old) => old.color != color;
}

// I10 — Camera. viewBox 0 0 24 22. stroke 1.8.
class CameraIconPainter extends CustomPainter {
  const CameraIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(24, 22), (c) {
      final s = _stroke(color, 1.8);
      c.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(1.5, 5, 21, 14.5), const Radius.circular(3.4)),
        s,
      );
      c.drawPath(
        Path()
          ..moveTo(8, 5)
          ..lineTo(10, 2)
          ..lineTo(14, 2)
          ..lineTo(16, 5),
        s,
      );
      c.drawCircle(const Offset(12, 12.2), 4.5, s);
    });
  }

  @override
  bool shouldRepaint(covariant CameraIconPainter old) => old.color != color;
}

// I11 — Community (two people). viewBox 0 0 22 18. stroke 1.6.
class CommunityIconPainter extends CustomPainter {
  const CommunityIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(22, 18), (c) {
      final s = _stroke(color, 1.6);
      c.drawCircle(const Offset(7.6, 5.2), 3, s);
      c.drawCircle(const Offset(15.2, 6.4), 2.4, s);
      c.drawPath(
        Path()
          ..moveTo(1.6, 16.4)
          ..cubicTo(1.6, 12.2, 4.2, 10.2, 7.6, 10.2)
          ..cubicTo(10.6, 10.2, 12.9, 11.7, 13.5, 14.6),
        s,
      );
      c.drawPath(
        Path()
          ..moveTo(13.9, 16)
          ..cubicTo(13.9, 12.9, 15.9, 11.4, 18.3, 11.4)
          ..cubicTo(20.3, 11.4, 20.4, 12.9, 20.4, 15.6),
        s,
      );
    });
  }

  @override
  bool shouldRepaint(covariant CommunityIconPainter old) => old.color != color;
}

// I12 — Profile. viewBox 0 0 18 20. stroke 1.6.
class ProfileIconPainter extends CustomPainter {
  const ProfileIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(18, 20), (c) {
      final s = _stroke(color, 1.6);
      c.drawCircle(const Offset(9, 5), 4, s);
      c.drawPath(
        Path()
          ..moveTo(1.5, 19)
          ..cubicTo(1.5, 13.8, 4.8, 11.5, 9, 11.5)
          ..cubicTo(13.2, 11.5, 16.5, 13.8, 16.5, 19),
        s,
      );
    });
  }

  @override
  bool shouldRepaint(covariant ProfileIconPainter old) => old.color != color;
}

// I13 — Checkmark (selected ping radio). viewBox 0 0 12 12. stroke 2.2.
class CheckmarkPainter extends CustomPainter {
  const CheckmarkPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(12, 12), (c) {
      final path = Path()..moveTo(2, 6.2)..lineTo(4.6, 8.8)..lineTo(10, 3.4);
      c.drawPath(path, _stroke(color, 2.2));
    });
  }

  @override
  bool shouldRepaint(covariant CheckmarkPainter old) => old.color != color;
}

// I14 — Block (circle-slash). viewBox 0 0 22 22. stroke 1.7.
class BlockIconPainter extends CustomPainter {
  const BlockIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(22, 22), (c) {
      final s = _stroke(color, 1.7);
      c.drawCircle(const Offset(11, 11), 8.4, s);
      c.drawPath(Path()..moveTo(5.1, 5.1)..lineTo(16.9, 16.9), s);
    });
  }

  @override
  bool shouldRepaint(covariant BlockIconPainter old) => old.color != color;
}

// I15 — Report (flag). viewBox 0 0 22 22. pole stroke 1.8, flag stroke 1.7.
class ReportIconPainter extends CustomPainter {
  const ReportIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(22, 22), (c) {
      c.drawPath(Path()..moveTo(4.5, 3.5)..lineTo(4.5, 19), _stroke(color, 1.8));
      final flag = Path()
        ..moveTo(4.5, 4.4)
        ..lineTo(16.6, 4.4)
        ..lineTo(14.3, 8.6)
        ..lineTo(16.6, 12.8)
        ..lineTo(4.5, 12.8)
        ..close();
      c.drawPath(flag, _stroke(color, 1.7));
    });
  }

  @override
  bool shouldRepaint(covariant ReportIconPainter old) => old.color != color;
}

// I16 — Show-fewer (arrow-down to line). viewBox 0 0 22 22. stroke 1.7.
class ShowFewerIconPainter extends CustomPainter {
  const ShowFewerIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(22, 22), (c) {
      final s = _stroke(color, 1.7);
      c.drawPath(
        Path()
          ..moveTo(11, 2.6)
          ..lineTo(11, 13.4)
          ..moveTo(6.6, 9)
          ..lineTo(11, 13.4)
          ..lineTo(15.4, 9),
        s,
      );
      c.drawPath(Path()..moveTo(3.6, 17.4)..lineTo(18.4, 17.4), s);
    });
  }

  @override
  bool shouldRepaint(covariant ShowFewerIconPainter old) => old.color != color;
}

// I17 — Persona glyph. viewBox 0 0 24 24. stroke 2.4. 4 abstract variants
// (ring / triangle / crescent / diamond) chosen deterministically per
// persona, per §7.4 ("an abstract persona glyph... never a real photo").
enum PersonaGlyphShape { ring, triangle, crescent, diamond }

class PersonaGlyphPainter extends CustomPainter {
  const PersonaGlyphPainter({required this.shape, required this.color});
  final PersonaGlyphShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _withViewBox(canvas, size, const Size(24, 24), (c) {
      // 2.8, up from 2.4 — a hair thicker, since the fix for the glyph's
      // real problem (near-invisible on its own fill, see
      // AnonFeedColors.personaGlyphInk) is contrast, and a touch more
      // weight helps a small painted line hold up at this size too.
      final s = _stroke(color, 2.8);
      switch (shape) {
        case PersonaGlyphShape.ring:
          c.drawCircle(const Offset(12, 12), 7, s);
        case PersonaGlyphShape.triangle:
          c.drawPath(
            Path()
              ..moveTo(12, 4)
              ..lineTo(20, 19)
              ..lineTo(4, 19)
              ..close(),
            s,
          );
        case PersonaGlyphShape.crescent:
          final outer = Path()..addOval(const Rect.fromLTWH(5, 5, 14, 14));
          final inner = Path()..addOval(const Rect.fromLTWH(9, 3, 14, 14));
          c.drawPath(Path.combine(PathOperation.difference, outer, inner), _fill(color));
        case PersonaGlyphShape.diamond:
          c.drawPath(
            Path()
              ..moveTo(12, 4)
              ..lineTo(20, 12)
              ..lineTo(12, 20)
              ..lineTo(4, 12)
              ..close(),
            s,
          );
      }
    });
  }

  @override
  bool shouldRepaint(covariant PersonaGlyphPainter old) => old.shape != shape || old.color != color;
}

PersonaGlyphShape personaGlyphFor(String seed) =>
    PersonaGlyphShape.values[seed.hashCode.abs() % PersonaGlyphShape.values.length];
