import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum MemoryLayoutId {
  tripleHorizontal,
  unequalSplit,
  verticalColumn,
  polaroidStack,
  tornPaper,
  retroScrapbook,
  filmNegative,
  perforatedFilm,
  abstractBlob,
  geometricWave,
  floralFrame,
  goldenGlitter,
}

enum SlotShape { rect, polaroid, blob1, blob2, blob3, pillWave1, pillWave2, waveCurve }

enum SlotBorderStyle { none, solidCream, tornWhite, dark, metalGold }

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class SlotBorder {
  const SlotBorder({this.style = SlotBorderStyle.none, this.width = 0, this.color});
  final SlotBorderStyle style;
  final double width;
  final Color? color;

  static const none = SlotBorder();
  static const cream = SlotBorder(style: SlotBorderStyle.solidCream, width: 6, color: Color(0xFFF5F1E8));
  static const torn = SlotBorder(style: SlotBorderStyle.tornWhite, width: 8, color: Colors.white);
  static const dark = SlotBorder(style: SlotBorderStyle.dark, width: 4, color: Color(0xFF1a1a1a));
  static const gold = SlotBorder(style: SlotBorderStyle.metalGold, width: 6, color: Color(0xFFFFD700));
}

class LayoutSlot {
  const LayoutSlot({
    required this.xPct,
    required this.yPct,
    required this.wPct,
    required this.hPct,
    this.shape = SlotShape.rect,
    this.rotationDeg = 0,
    this.zIndex = 0,
    this.border = SlotBorder.none,
    this.cornerRadius = 0,
    this.borderColor,
    this.borderWidth = 0,
  });

  final double xPct, yPct, wPct, hPct;
  final SlotShape shape;
  final double rotationDeg;
  final int zIndex;
  final SlotBorder border;
  final double cornerRadius;
  final Color? borderColor;
  final double borderWidth;
}

class LayoutBackground {
  const LayoutBackground({
    required this.color,
    this.gradient,
    this.hasNoise = false,
    this.hasDots = false,
  });
  final Color color;
  final Gradient? gradient;
  final bool hasNoise;
  final bool hasDots;

  static const black = LayoutBackground(color: Color(0xFF000000));
  static const darkGrey = LayoutBackground(color: Color(0xFF1a1a1a));
  static const darkGrey2 = LayoutBackground(color: Color(0xFF2a2a2a));
  static const veryDark = LayoutBackground(color: Color(0xFF0f0f0f));
  static const offWhite = LayoutBackground(color: Color(0xFFF5F1E8));
  static const deepGreen = LayoutBackground(color: Color(0xFF1a4d2e));
  static const concrete = LayoutBackground(color: Color(0xFF4a4a4a), hasNoise: true);
  static const teal = LayoutBackground(color: Color(0xFF20b2aa));
  static const darkGrey3 = LayoutBackground(color: Color(0xFF3a3a3a));
}

class MemoryLayout {
  const MemoryLayout({
    required this.id,
    required this.name,
    required this.category,
    required this.background,
    required this.slots,
    this.gap = 0,
    this.description = '',
  });

  final MemoryLayoutId id;
  final String name;
  final String category;
  final LayoutBackground background;
  final List<LayoutSlot> slots;
  final double gap;
  final String description;

  int get maxPhotos => slots.length;
}

// ---------------------------------------------------------------------------
// 12 Layout definitions
// ---------------------------------------------------------------------------

class MemoryLayouts {
  static const List<MemoryLayout> all = [
    // 1 – Triple Horizontal
    MemoryLayout(
      id: MemoryLayoutId.tripleHorizontal,
      name: 'Triple Stack',
      category: 'Structural',
      background: LayoutBackground.black,
      gap: 8,
      slots: [
        LayoutSlot(xPct: 0.02, yPct: 0.01, wPct: 0.96, hPct: 0.31),
        LayoutSlot(xPct: 0.02, yPct: 0.345, wPct: 0.96, hPct: 0.31),
        LayoutSlot(xPct: 0.02, yPct: 0.68, wPct: 0.96, hPct: 0.31),
      ],
    ),

    // 2 – Unequal Split
    MemoryLayout(
      id: MemoryLayoutId.unequalSplit,
      name: 'Feature Split',
      category: 'Structural',
      background: LayoutBackground.black,
      gap: 8,
      slots: [
        LayoutSlot(xPct: 0.02, yPct: 0.01, wPct: 0.96, hPct: 0.46),
        LayoutSlot(xPct: 0.02, yPct: 0.49, wPct: 0.46, hPct: 0.49),
        LayoutSlot(xPct: 0.52, yPct: 0.49, wPct: 0.46, hPct: 0.49),
      ],
    ),

    // 3 – Vertical Column
    MemoryLayout(
      id: MemoryLayoutId.verticalColumn,
      name: 'Column',
      category: 'Structural',
      background: LayoutBackground.darkGrey,
      slots: [
        LayoutSlot(xPct: 0.10, yPct: 0.08, wPct: 0.80, hPct: 0.24, cornerRadius: 12),
        LayoutSlot(xPct: 0.10, yPct: 0.38, wPct: 0.80, hPct: 0.24, cornerRadius: 12),
        LayoutSlot(xPct: 0.10, yPct: 0.68, wPct: 0.80, hPct: 0.24, cornerRadius: 12),
      ],
    ),

    // 4 – Polaroid Stack
    MemoryLayout(
      id: MemoryLayoutId.polaroidStack,
      name: 'Polaroid Stack',
      category: 'Artistic',
      background: LayoutBackground.deepGreen,
      slots: [
        LayoutSlot(xPct: 0.10, yPct: 0.30, wPct: 0.50, hPct: 0.45, shape: SlotShape.polaroid, rotationDeg: -8, zIndex: 1),
        LayoutSlot(xPct: 0.05, yPct: 0.10, wPct: 0.45, hPct: 0.40, shape: SlotShape.polaroid, rotationDeg: 5, zIndex: 3),
        LayoutSlot(xPct: 0.50, yPct: 0.05, wPct: 0.44, hPct: 0.38, shape: SlotShape.polaroid, rotationDeg: -3, zIndex: 2),
        LayoutSlot(xPct: 0.54, yPct: 0.52, wPct: 0.40, hPct: 0.35, shape: SlotShape.polaroid, rotationDeg: 12, zIndex: 1),
      ],
    ),

    // 5 – Torn Paper
    MemoryLayout(
      id: MemoryLayoutId.tornPaper,
      name: 'Torn Paper',
      category: 'Artistic',
      background: LayoutBackground.darkGrey2,
      slots: [
        LayoutSlot(xPct: 0.05, yPct: 0.05, wPct: 0.45, hPct: 0.43, border: SlotBorder.torn, rotationDeg: -2, zIndex: 2),
        LayoutSlot(xPct: 0.50, yPct: 0.10, wPct: 0.45, hPct: 0.38, border: SlotBorder.torn, rotationDeg: 3, zIndex: 1),
        LayoutSlot(xPct: 0.10, yPct: 0.52, wPct: 0.45, hPct: 0.43, border: SlotBorder.torn, rotationDeg: 1, zIndex: 3),
        LayoutSlot(xPct: 0.55, yPct: 0.55, wPct: 0.40, hPct: 0.38, border: SlotBorder.torn, rotationDeg: -4, zIndex: 2),
      ],
    ),

    // 6 – Retro Scrapbook
    MemoryLayout(
      id: MemoryLayoutId.retroScrapbook,
      name: 'Scrapbook',
      category: 'Artistic',
      background: LayoutBackground.offWhite,
      slots: [
        LayoutSlot(xPct: 0.08, yPct: 0.13, wPct: 0.84, hPct: 0.21, border: SlotBorder.cream),
        LayoutSlot(xPct: 0.08, yPct: 0.40, wPct: 0.84, hPct: 0.21, border: SlotBorder.cream),
        LayoutSlot(xPct: 0.08, yPct: 0.67, wPct: 0.84, hPct: 0.21, border: SlotBorder.cream),
      ],
    ),

    // 7 – Film Negative Strip
    MemoryLayout(
      id: MemoryLayoutId.filmNegative,
      name: 'Film Strip',
      category: 'Artistic',
      background: LayoutBackground.veryDark,
      slots: [
        LayoutSlot(xPct: 0.15, yPct: 0.08, wPct: 0.70, hPct: 0.18, border: SlotBorder.dark),
        LayoutSlot(xPct: 0.15, yPct: 0.31, wPct: 0.70, hPct: 0.18, border: SlotBorder.dark),
        LayoutSlot(xPct: 0.15, yPct: 0.54, wPct: 0.70, hPct: 0.18, border: SlotBorder.dark),
        LayoutSlot(xPct: 0.15, yPct: 0.77, wPct: 0.70, hPct: 0.18, border: SlotBorder.dark),
      ],
    ),

    // 8 – Perforated Film Roll
    MemoryLayout(
      id: MemoryLayoutId.perforatedFilm,
      name: 'Film Roll',
      category: 'Artistic',
      background: LayoutBackground.concrete,
      slots: [
        LayoutSlot(xPct: 0.12, yPct: 0.14, wPct: 0.76, hPct: 0.21),
        LayoutSlot(xPct: 0.12, yPct: 0.40, wPct: 0.76, hPct: 0.21),
        LayoutSlot(xPct: 0.12, yPct: 0.66, wPct: 0.76, hPct: 0.21),
      ],
    ),

    // 9 – Abstract Blobs
    MemoryLayout(
      id: MemoryLayoutId.abstractBlob,
      name: 'Blob Shapes',
      category: 'Organic',
      background: LayoutBackground.darkGrey3,
      slots: [
        LayoutSlot(xPct: 0.05, yPct: 0.10, wPct: 0.42, hPct: 0.33, shape: SlotShape.blob1),
        LayoutSlot(xPct: 0.55, yPct: 0.05, wPct: 0.42, hPct: 0.38, shape: SlotShape.blob2, rotationDeg: 15),
        LayoutSlot(xPct: 0.18, yPct: 0.53, wPct: 0.62, hPct: 0.38, shape: SlotShape.blob3, rotationDeg: -8),
      ],
    ),

    // 10 – Geometric Wave
    MemoryLayout(
      id: MemoryLayoutId.geometricWave,
      name: 'Wave Shapes',
      category: 'Organic',
      background: LayoutBackground.darkGrey2,
      slots: [
        LayoutSlot(xPct: 0.08, yPct: 0.14, wPct: 0.36, hPct: 0.30, shape: SlotShape.pillWave1, borderColor: Color(0xFFFFD700), borderWidth: 8),
        LayoutSlot(xPct: 0.56, yPct: 0.10, wPct: 0.38, hPct: 0.34, shape: SlotShape.pillWave2, borderColor: Color(0xFFFF1493), borderWidth: 8),
        LayoutSlot(xPct: 0.24, yPct: 0.58, wPct: 0.52, hPct: 0.34, shape: SlotShape.waveCurve, borderColor: Color(0xFF0066FF), borderWidth: 8),
      ],
    ),

    // 11 – Floral Frame
    MemoryLayout(
      id: MemoryLayoutId.floralFrame,
      name: 'Floral',
      category: 'Organic',
      background: LayoutBackground.teal,
      slots: [
        LayoutSlot(xPct: 0.12, yPct: 0.11, wPct: 0.76, hPct: 0.21),
        LayoutSlot(xPct: 0.12, yPct: 0.38, wPct: 0.76, hPct: 0.21),
        LayoutSlot(xPct: 0.12, yPct: 0.65, wPct: 0.76, hPct: 0.21),
      ],
    ),

    // 12 – Golden Glitter
    MemoryLayout(
      id: MemoryLayoutId.goldenGlitter,
      name: 'Gold Glitter',
      category: 'Organic',
      background: LayoutBackground.darkGrey,
      slots: [
        LayoutSlot(xPct: 0.10, yPct: 0.06, wPct: 0.80, hPct: 0.20, cornerRadius: 16, border: SlotBorder.gold),
        LayoutSlot(xPct: 0.10, yPct: 0.32, wPct: 0.80, hPct: 0.20, cornerRadius: 16, border: SlotBorder.gold),
        LayoutSlot(xPct: 0.10, yPct: 0.58, wPct: 0.80, hPct: 0.20, cornerRadius: 16, border: SlotBorder.gold),
        LayoutSlot(xPct: 0.25, yPct: 0.84, wPct: 0.50, hPct: 0.10, cornerRadius: 16, border: SlotBorder.gold),
      ],
    ),
  ];

  static MemoryLayout byId(MemoryLayoutId id) =>
      all.firstWhere((l) => l.id == id);
}

// ---------------------------------------------------------------------------
// Custom clippers
// ---------------------------------------------------------------------------

class BlobClipper1 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.30, h * 0.05)
      ..cubicTo(w * 0.70, -h * 0.05, w * 1.05, h * 0.25, w * 0.95, h * 0.55)
      ..cubicTo(w * 0.90, h * 0.85, w * 0.55, h * 1.08, w * 0.25, h * 0.95)
      ..cubicTo(-h * 0.10, h * 0.80, -h * 0.08, h * 0.30, w * 0.30, h * 0.05)
      ..close();
  }

  @override
  bool shouldReclip(BlobClipper1 _) => false;
}

class BlobClipper2 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.50, h * 0.02)
      ..cubicTo(w * 0.85, h * 0.02, w * 1.02, h * 0.38, w * 0.90, h * 0.65)
      ..cubicTo(w * 0.78, h * 0.95, w * 0.45, h * 1.05, w * 0.20, h * 0.88)
      ..cubicTo(-w * 0.05, h * 0.72, -w * 0.05, h * 0.35, w * 0.15, h * 0.18)
      ..cubicTo(w * 0.25, h * 0.05, w * 0.35, h * 0.02, w * 0.50, h * 0.02)
      ..close();
  }

  @override
  bool shouldReclip(BlobClipper2 _) => false;
}

class BlobClipper3 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.15, h * 0.10)
      ..cubicTo(w * 0.40, -h * 0.05, w * 0.78, h * 0.02, w * 0.90, h * 0.30)
      ..cubicTo(w * 1.05, h * 0.60, w * 0.80, h * 1.05, w * 0.50, h * 0.95)
      ..cubicTo(w * 0.22, h * 0.88, -w * 0.05, h * 0.72, w * 0.05, h * 0.45)
      ..cubicTo(w * 0.08, h * 0.28, w * 0.05, h * 0.18, w * 0.15, h * 0.10)
      ..close();
  }

  @override
  bool shouldReclip(BlobClipper3 _) => false;
}

class PillWaveClipper1 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final r = math.min(w, h) * 0.40;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(r),
      ));
  }

  @override
  bool shouldReclip(PillWaveClipper1 _) => false;
}

class PillWaveClipper2 extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.10, 0)
      ..lineTo(w * 0.90, 0)
      ..quadraticBezierTo(w, 0, w, h * 0.10)
      ..lineTo(w, h * 0.90)
      ..quadraticBezierTo(w, h, w * 0.90, h)
      ..lineTo(w * 0.10, h)
      ..quadraticBezierTo(0, h, 0, h * 0.90)
      ..lineTo(0, h * 0.40)
      ..quadraticBezierTo(w * 0.08, h * 0.20, w * 0.10, 0)
      ..close();
  }

  @override
  bool shouldReclip(PillWaveClipper2 _) => false;
}

class WaveCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, h * 0.15)
      ..quadraticBezierTo(w * 0.25, -h * 0.05, w * 0.50, h * 0.10)
      ..quadraticBezierTo(w * 0.75, h * 0.25, w, h * 0.10)
      ..lineTo(w, h * 0.90)
      ..quadraticBezierTo(w * 0.75, h * 1.05, w * 0.50, h * 0.90)
      ..quadraticBezierTo(w * 0.25, h * 0.75, 0, h * 0.90)
      ..close();
  }

  @override
  bool shouldReclip(WaveCurveClipper _) => false;
}

// Torn paper effect clipper (irregular jagged edges)
class TornEdgeClipper extends CustomClipper<Path> {
  TornEdgeClipper({required this.seed});
  final int seed;

  @override
  Path getClip(Size size) {
    final rng = math.Random(seed);
    final w = size.width;
    final h = size.height;
    final path = Path();
    const steps = 12;

    // Top edge (torn)
    path.moveTo(0, rng.nextDouble() * 6);
    for (int i = 1; i <= steps; i++) {
      final x = w * i / steps;
      final y = rng.nextDouble() * 8;
      path.lineTo(x, y);
    }

    // Right edge (torn)
    for (int i = 1; i <= steps; i++) {
      final x = w - rng.nextDouble() * 8;
      final y = h * i / steps;
      path.lineTo(x, y);
    }

    // Bottom edge (torn)
    for (int i = steps - 1; i >= 0; i--) {
      final x = w * i / steps;
      final y = h - rng.nextDouble() * 8;
      path.lineTo(x, y);
    }

    // Left edge (torn)
    for (int i = steps - 1; i >= 0; i--) {
      final x = rng.nextDouble() * 8;
      final y = h * i / steps;
      path.lineTo(x, y);
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(TornEdgeClipper old) => old.seed != seed;
}
