import 'dart:math';
import 'package:flutter/material.dart';
import '../models/collage_layout.dart';

/// Paints a single positioned decoration instance (as opposed to the legacy
/// [DecorationPainter], which scatters a whole-canvas pattern). Used for the
/// Collage Studio styles' `decorations` list.
class SingleDecorationPainter extends CustomPainter {
  final DecorationKind kind;
  final Color color;
  const SingleDecorationPainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case DecorationKind.doodleCircle:
        _doodleCircle(canvas, size);
        break;
      case DecorationKind.doodleDashes:
        _doodleDashes(canvas, size);
        break;
      case DecorationKind.hearts:
        _hearts(canvas, size);
        break;
      case DecorationKind.sparkle:
        _sparkle(canvas, size);
        break;
      case DecorationKind.daisy:
        _daisy(canvas, size);
        break;
      case DecorationKind.brushLine:
        _brushLine(canvas, size);
        break;
      case DecorationKind.filmSprockets:
        _filmSprockets(canvas, size);
        break;
    }
  }

  void _doodleCircle(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.shortestSide * 0.045
      ..strokeCap = StrokeCap.round;
    final r = s.shortestSide / 2;
    final center = Offset(s.width / 2, s.height / 2);
    final path = Path();
    const wobblePts = 24;
    for (int i = 0; i <= wobblePts; i++) {
      final a = (i / wobblePts) * 2 * pi;
      final wobble = 1 + sin(a * 3) * 0.04;
      final o = Offset(center.dx + cos(a) * r * wobble, center.dy + sin(a) * r * wobble);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    c.drawPath(path, p);
  }

  void _doodleDashes(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final count = 2 + (s.width.toInt() % 2); // 2-3 strokes
    final gap = s.height / (count + 1);
    for (int i = 1; i <= count; i++) {
      final y = gap * i;
      c.drawLine(Offset(s.width * 0.15, y), Offset(s.width * 0.85, y), p);
    }
  }

  void _hearts(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.shortestSide * 0.06
      ..strokeCap = StrokeCap.round;
    _heart(c, Offset(s.width * 0.38, s.height * 0.5), s.shortestSide * 0.32, p);
    _heart(c, Offset(s.width * 0.62, s.height * 0.46), s.shortestSide * 0.28, p);
  }

  void _heart(Canvas c, Offset ctr, double size, Paint p) {
    final path = Path();
    path.moveTo(ctr.dx, ctr.dy + size * 0.3);
    path.cubicTo(ctr.dx - size, ctr.dy - size * 0.5, ctr.dx - size * 0.4,
        ctr.dy - size, ctr.dx, ctr.dy - size * 0.3);
    path.cubicTo(ctr.dx + size * 0.4, ctr.dy - size, ctr.dx + size,
        ctr.dy - size * 0.5, ctr.dx, ctr.dy + size * 0.3);
    c.drawPath(path, p);
  }

  void _sparkle(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.shortestSide * 0.05
      ..strokeCap = StrokeCap.round;
    final ctr = Offset(s.width / 2, s.height / 2);
    final r = s.shortestSide / 2;
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final a = (pi / 2) * i;
      path.moveTo(ctr.dx, ctr.dy);
      path.lineTo(ctr.dx + cos(a) * r, ctr.dy + sin(a) * r);
    }
    c.drawPath(path, p);
  }

  void _daisy(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final r = s.shortestSide * 0.32;
    final petal = Paint()..color = color;
    for (int i = 0; i < 8; i++) {
      final a = (pi / 4) * i;
      final o = Offset(ctr.dx + cos(a) * r, ctr.dy + sin(a) * r);
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(a);
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 0.85, height: r * 0.45), petal);
      c.restore();
    }
    c.drawCircle(ctr, r * 0.45, Paint()..color = const Color(0xFFF5B301));
  }

  void _brushLine(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(0, s.height / 2), Offset(s.width, s.height / 2), p);
  }

  void _filmSprockets(Canvas c, Size s) {
    final p = Paint()..color = color.withValues(alpha: 0.85);
    const holeW = 6.0, holeH = 8.0, gap = 14.0;
    for (double x = 0; x < s.width - holeW; x += gap) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, holeW, holeH), const Radius.circular(2)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SingleDecorationPainter old) =>
      old.kind != kind || old.color != color;
}
