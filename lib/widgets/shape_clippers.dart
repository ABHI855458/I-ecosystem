import 'dart:math';
import 'package:flutter/material.dart';
import '../models/photo_slot.dart';

class ShapeClipper extends CustomClipper<Path> {
  final MaskShape shape;
  final int seed;
  ShapeClipper(this.shape, {this.seed = 0});

  @override
  Path getClip(Size s) {
    final w = s.width, h = s.height;
    switch (shape) {
      case MaskShape.circle:
        return Path()..addOval(Rect.fromLTWH(0, 0, w, h));

      case MaskShape.roundedRect:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h), const Radius.circular(16)));

      case MaskShape.pill:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h), Radius.circular(h * 0.5)));

      case MaskShape.polaroid:
        return Path()..addRect(Rect.fromLTWH(0, 0, w, h));

      case MaskShape.blob1:
        return _blob(w, h, [
          const Offset(0.50, 0.02), const Offset(0.95, 0.25),
          const Offset(0.88, 0.75), const Offset(0.50, 0.98),
          const Offset(0.10, 0.72), const Offset(0.06, 0.28),
        ]);

      case MaskShape.blob2:
        return _blob(w, h, [
          const Offset(0.50, 0.05), const Offset(0.92, 0.35),
          const Offset(0.80, 0.90), const Offset(0.35, 0.95),
          const Offset(0.05, 0.60), const Offset(0.15, 0.15),
        ]);

      case MaskShape.blob3:
        return _blob(w, h, [
          const Offset(0.45, 0.03), const Offset(0.98, 0.30),
          const Offset(0.85, 0.80), const Offset(0.45, 0.97),
          const Offset(0.05, 0.78), const Offset(0.10, 0.22),
        ]);

      case MaskShape.wave:
        final p = Path();
        p.moveTo(0, h * 0.15);
        p.quadraticBezierTo(w * 0.25, 0, w * 0.5, h * 0.12);
        p.quadraticBezierTo(w * 0.75, h * 0.24, w, h * 0.10);
        p.lineTo(w, h);
        p.lineTo(0, h);
        p.close();
        return p;

      case MaskShape.rect:
        return Path()..addRect(Rect.fromLTWH(0, 0, w, h));

      case MaskShape.arch:
        final topRadius = min(w / 2, h * 0.9);
        const bottomRadius = 6.0;
        return Path()
          ..addRRect(RRect.fromRectAndCorners(
            Rect.fromLTWH(0, 0, w, h),
            topLeft: Radius.circular(topRadius),
            topRight: Radius.circular(topRadius),
            bottomLeft: const Radius.circular(bottomRadius),
            bottomRight: const Radius.circular(bottomRadius),
          ));

      case MaskShape.squircle:
        return _squircle(w, h);

      case MaskShape.tornPaper:
        return _tornPaper(w, h, seed);
    }
  }

  Path _blob(double w, double h, List<Offset> pts) {
    final p = Path();
    final abs = pts.map((o) => Offset(o.dx * w, o.dy * h)).toList();
    p.moveTo(abs[0].dx, abs[0].dy);
    for (int i = 0; i < abs.length; i++) {
      final curr = abs[i];
      final next = abs[(i + 1) % abs.length];
      final mid = Offset((curr.dx + next.dx) / 2, (curr.dy + next.dy) / 2);
      p.quadraticBezierTo(curr.dx, curr.dy, mid.dx, mid.dy);
    }
    p.close();
    return p;
  }

  /// Continuous-corner superellipse ("squircle"), sampled parametrically.
  Path _squircle(double w, double h) {
    const n = 4.0; // superellipse exponent — 4 reads as an iOS-style squircle
    const steps = 96;
    final a = w / 2, b = h / 2;
    final p = Path();
    for (int i = 0; i <= steps; i++) {
      final t = (i / steps) * 2 * pi;
      final ct = cos(t), st = sin(t);
      final x = a + a * ct.sign * pow(ct.abs(), 2 / n).toDouble();
      final y = b + b * st.sign * pow(st.abs(), 2 / n).toDouble();
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  /// Deterministic jagged torn-paper edge — same seed always produces the
  /// same path so it doesn't flicker across rebuilds.
  Path _tornPaper(double w, double h, int seed) {
    final rnd = Random(seed);
    final points = <Offset>[];

    void jaggedEdge({
      required Offset from,
      required Offset to,
      required int count,
      required double ampFrac,
    }) {
      final amp = min(w, h) * ampFrac;
      for (int i = 0; i <= count; i++) {
        final t = i / count;
        final base = Offset.lerp(from, to, t)!;
        if (i == 0 || i == count) {
          points.add(base);
          continue;
        }
        final dx = to.dx - from.dx, dy = to.dy - from.dy;
        final len = sqrt(dx * dx + dy * dy);
        final nx = len == 0 ? 0.0 : -dy / len;
        final ny = len == 0 ? 0.0 : dx / len;
        final jitter = (rnd.nextDouble() * 2 - 1) * amp;
        points.add(Offset(base.dx + nx * jitter, base.dy + ny * jitter));
      }
    }

    const perEdge = 4; // 4 segments/edge * 4 edges ~= 16 points total
    jaggedEdge(from: const Offset(0, 0), to: Offset(w, 0), count: perEdge, ampFrac: 0.03);
    jaggedEdge(from: Offset(w, 0), to: Offset(w, h), count: perEdge, ampFrac: 0.03);
    jaggedEdge(from: Offset(w, h), to: Offset(0, h), count: perEdge, ampFrac: 0.03);
    jaggedEdge(from: Offset(0, h), to: const Offset(0, 0), count: perEdge, ampFrac: 0.03);

    final p = Path()..moveTo(points.first.dx, points.first.dy);
    for (final pt in points.skip(1)) {
      p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant ShapeClipper old) =>
      old.shape != shape || old.seed != seed;
}
