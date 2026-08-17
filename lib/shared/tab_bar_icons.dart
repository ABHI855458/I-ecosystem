import 'package:flutter/material.dart';

/// Glyphs for the bottom tab bar. Path geometry below is transcribed
/// 1:1 from the design handoff's 24x24 viewBox SVG path data.
enum TabGlyph { home, ping, camera, community, profile }

const double _kStrokeWidth = 1.75;

class TabBarIcon extends StatelessWidget {
  const TabBarIcon({
    super.key,
    required this.glyph,
    required this.size,
    required this.color,
    this.filled = false,
  });

  final TabGlyph glyph;
  final double size;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final CustomPainter painter = switch (glyph) {
      TabGlyph.home => _HomeIconPainter(color: color, filled: filled),
      TabGlyph.ping => _PingIconPainter(color: color),
      TabGlyph.camera => _CameraIconPainter(color: color),
      TabGlyph.community => _CommunityIconPainter(color: color, filled: filled),
      TabGlyph.profile => _ProfileIconPainter(color: color, filled: filled),
    };
    return CustomPaint(size: Size.square(size), painter: painter);
  }
}

Paint _strokePaint(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = _kStrokeWidth
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fillPaint(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.fill;

// M3.4 10.9 12 3.9l8.6 7v8.5a1.1 1.1 0 0 1-1.1 1.1h-4.7v-6.2H9.2v6.2H4.5a1.1 1.1 0 0 1-1.1-1.1z
class _HomeIconPainter extends CustomPainter {
  const _HomeIconPainter({required this.color, required this.filled});
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    final path = Path()
      ..moveTo(3.4, 10.9)
      ..lineTo(12, 3.9)
      ..lineTo(20.6, 10.9)
      ..lineTo(20.6, 19.4)
      ..arcToPoint(const Offset(19.5, 20.5),
          radius: const Radius.circular(1.1), clockwise: true)
      ..lineTo(14.8, 20.5)
      ..lineTo(14.8, 14.3)
      ..lineTo(9.2, 14.3)
      ..lineTo(9.2, 20.5)
      ..lineTo(4.5, 20.5)
      ..arcToPoint(const Offset(3.4, 19.4),
          radius: const Radius.circular(1.1), clockwise: true)
      ..close();

    canvas.drawPath(path, filled ? _fillPaint(color) : _strokePaint(color));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HomeIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.filled != filled;
}

// M12 3.2a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z M12 8.4v5.4
// M7.2 9.6 12 12.6l4.8-3 M12 13.4 8.4 20.8 M12 13.4l3.6 7.4
class _PingIconPainter extends CustomPainter {
  const _PingIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);
    final paint = _strokePaint(color);

    canvas.drawCircle(const Offset(12, 5.7), 2.5, paint);
    canvas.drawLine(const Offset(12, 8.4), const Offset(12, 13.8), paint);
    canvas.drawPath(
      Path()
        ..moveTo(7.2, 9.6)
        ..lineTo(12, 12.6)
        ..lineTo(16.8, 9.6),
      paint,
    );
    canvas.drawLine(const Offset(12, 13.4), const Offset(8.4, 20.8), paint);
    canvas.drawLine(const Offset(12, 13.4), const Offset(15.6, 20.8), paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PingIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// M4 8.4h3.2L8.9 5.6h6.2l1.7 2.8H20a1.4 1.4 0 0 1 1.4 1.4v8.2A1.4 1.4 0 0 1 20 19.4H4a1.4 1.4 0 0 1-1.4-1.4V9.8A1.4 1.4 0 0 1 4 8.4z
// M12 17a3.4 3.4 0 1 0 0-6.8 3.4 3.4 0 0 0 0 6.8z
class _CameraIconPainter extends CustomPainter {
  const _CameraIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);
    final paint = _strokePaint(color);

    final body = Path()
      ..moveTo(4, 8.4)
      ..lineTo(7.2, 8.4)
      ..lineTo(8.9, 5.6)
      ..lineTo(15.1, 5.6)
      ..lineTo(16.8, 8.4)
      ..lineTo(20, 8.4)
      ..arcToPoint(const Offset(21.4, 9.8),
          radius: const Radius.circular(1.4), clockwise: true)
      ..lineTo(21.4, 18.0)
      ..arcToPoint(const Offset(20, 19.4),
          radius: const Radius.circular(1.4), clockwise: true)
      ..lineTo(4, 19.4)
      ..arcToPoint(const Offset(2.6, 18.0),
          radius: const Radius.circular(1.4), clockwise: true)
      ..lineTo(2.6, 9.8)
      ..arcToPoint(const Offset(4, 8.4),
          radius: const Radius.circular(1.4), clockwise: true)
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawCircle(const Offset(12, 13.6), 3.4, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CameraIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// M12 12.2a3.7 3.7 0 1 0 0-7.4 3.7 3.7 0 0 0 0 7.4z
// M4.8 20.4c.9-3.4 3.6-5.2 7.2-5.2s6.3 1.8 7.2 5.2
class _ProfileIconPainter extends CustomPainter {
  const _ProfileIconPainter({required this.color, required this.filled});
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    final head = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 8.5), radius: 3.7));
    final body = Path()
      ..moveTo(4.8, 20.4)
      ..cubicTo(5.7, 17.0, 8.4, 15.2, 12, 15.2)
      ..cubicTo(15.6, 15.2, 18.3, 17.0, 19.2, 20.4);

    if (filled) {
      final paint = _fillPaint(color);
      canvas.drawPath(head, paint);
      canvas.drawPath(Path.from(body)..close(), paint);
    } else {
      final paint = _strokePaint(color);
      canvas.drawPath(head, paint);
      canvas.drawPath(body, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProfileIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.filled != filled;
}

// circle: cx9.2 cy9.4 r3.4 (fills when active)
// M16.4 7.2a2.8 2.8 0 0 1 0 5.6
// M3.2 19.4c.6-2.9 2.9-4.6 5.8-4.6s5.2 1.7 5.8 4.6
// M17.2 15.2c2 .6 3.3 2.1 3.7 4.2
class _CommunityIconPainter extends CustomPainter {
  const _CommunityIconPainter({required this.color, required this.filled});
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);
    final strokePaint = _strokePaint(color);

    canvas.drawCircle(const Offset(9.2, 9.4), 3.4,
        filled ? _fillPaint(color) : strokePaint);

    final headArc = Path()..moveTo(16.4, 7.2);
    headArc.arcToPoint(const Offset(16.4, 12.8),
        radius: const Radius.circular(2.8), clockwise: true);
    canvas.drawPath(headArc, strokePaint);

    canvas.drawPath(
      Path()
        ..moveTo(3.2, 19.4)
        ..cubicTo(3.8, 16.5, 6.1, 14.8, 9.0, 14.8)
        ..cubicTo(11.9, 14.8, 14.2, 16.5, 14.8, 19.4),
      strokePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(17.2, 15.2)
        ..cubicTo(19.2, 15.8, 20.5, 17.3, 20.9, 19.4),
      strokePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CommunityIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.filled != filled;
}
