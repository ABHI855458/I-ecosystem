import 'dart:math';
import 'package:flutter/material.dart';

class DecorationPainter extends CustomPainter {
  final String type;
  const DecorationPainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case 'sprockets': _sprockets(canvas, size); break;
      case 'daisies':   _daisies(canvas, size);   break;
      case 'glitter':   _glitter(canvas, size);   break;
      case 'hearts':    _hearts(canvas, size);    break;
      case 'dots':      _dots(canvas, size);      break;
      case 'scrapbook': _scrapbook(canvas, size); break;
      default: break;
    }
  }

  void _sprockets(Canvas c, Size s) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.85);
    const holeW = 6.0, holeH = 8.0, gap = 14.0;
    for (double y = 8; y < s.height - holeH; y += gap) {
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(6, y, holeW, holeH), const Radius.circular(2)), p);
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(s.width - 12, y, holeW, holeH), const Radius.circular(2)), p);
    }
    final tp = TextPainter(
      text: const TextSpan(
        text: '▶ 52  400   STILL 4527',
        style: TextStyle(color: Colors.white70, fontSize: 9, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(18, s.height - 16));
  }

  void _daisies(Canvas c, Size s) {
    final positions = [
      Offset(20, 20),
      Offset(s.width / 2, 12),
      Offset(s.width - 20, 20),
      Offset(20, s.height - 20),
      Offset(s.width / 2, s.height - 12),
      Offset(s.width - 20, s.height - 20),
    ];
    for (final pos in positions) {
      _daisy(c, pos, 10);
    }
  }

  void _daisy(Canvas c, Offset center, double r) {
    final petal = Paint()..color = Colors.white;
    for (int i = 0; i < 6; i++) {
      final a = (pi / 3) * i;
      final o = Offset(center.dx + cos(a) * r, center.dy + sin(a) * r);
      c.drawCircle(o, r * 0.55, petal);
    }
    c.drawCircle(center, r * 0.5, Paint()..color = const Color(0xFFFFD700));
  }

  void _glitter(Canvas c, Size s) {
    final rnd = Random(7);
    final p = Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.85);
    for (int i = 0; i < 60; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
      final r = rnd.nextDouble() * 2 + 1;
      _star(c, o, r * 2, p);
    }
  }

  void _star(Canvas c, Offset ctr, double r, Paint p) {
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final a = (pi / 2) * i;
      path.moveTo(ctr.dx, ctr.dy);
      path.lineTo(ctr.dx + cos(a) * r, ctr.dy + sin(a) * r);
    }
    c.drawPath(
      path,
      Paint()
        ..color = p.color
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  void _hearts(Canvas c, Size s) {
    final rnd = Random(3);
    final p = Paint()
      ..color = const Color(0xFFFF1493).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 0; i < 8; i++) {
      final o = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height);
      _heart(c, o, rnd.nextDouble() * 8 + 8, p);
    }
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

  void _dots(Canvas c, Size s) {
    final rnd = Random(11);
    final p = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (int i = 0; i < 40; i++) {
      c.drawCircle(
        Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height),
        rnd.nextDouble() * 2 + 1.5,
        p,
      );
    }
  }

  void _scrapbook(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    _star(c, const Offset(24, 24), 10, p);
    for (final inset in [10.0, 14.0]) {
      c.drawRect(
        Rect.fromLTWH(inset, inset, s.width - inset * 2, s.height - inset * 2),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DecorationPainter old) => old.type != type;
}
