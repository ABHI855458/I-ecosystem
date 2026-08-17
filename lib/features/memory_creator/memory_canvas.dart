import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'memory_layout.dart';

// ---------------------------------------------------------------------------
// Main canvas widget — 9:16 aspect ratio
// ---------------------------------------------------------------------------

class MemoryCanvas extends StatelessWidget {
  const MemoryCanvas({
    super.key,
    required this.layout,
    required this.photos,
    this.onSlotTap,
    this.interactive = true,
    this.showPlaceholders = true,
  });

  final MemoryLayout layout;
  final List<XFile?> photos; // indexed by slot
  final void Function(int slotIndex)? onSlotTap;
  final bool interactive;
  final bool showPlaceholders;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(builder: (_, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return ClipRRect(
          borderRadius: BorderRadius.circular(interactive ? 0 : 12),
          child: Stack(children: [
            // Background
            Positioned.fill(child: _Background(bg: layout.background)),
            // Layout-specific back decorations
            Positioned.fill(child: _BackDecoration(layoutId: layout.id, w: w, h: h)),
            // Photo slots (sorted by zIndex)
            ..._buildSlots(w, h),
            // Layout-specific front decorations
            Positioned.fill(child: _FrontDecoration(layoutId: layout.id, w: w, h: h)),
          ]),
        );
      }),
    );
  }

  List<Widget> _buildSlots(double w, double h) {
    final sorted = [...layout.slots.asMap().entries]
      ..sort((a, b) => a.value.zIndex.compareTo(b.value.zIndex));

    return sorted.map((entry) {
      final idx = entry.key;
      final slot = entry.value;
      final photo = idx < photos.length ? photos[idx] : null;

      final left = slot.xPct * w;
      final top = slot.yPct * h;
      final width = slot.wPct * w;
      final height = slot.hPct * h;

      Widget content = _SlotContent(
        slot: slot,
        photo: photo,
        index: idx,
        showPlaceholders: showPlaceholders,
      );

      // Apply rotation
      if (slot.rotationDeg != 0) {
        content = Transform.rotate(
          angle: slot.rotationDeg * math.pi / 180,
          child: content,
        );
      }

      Widget positionedSlot = Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: interactive && onSlotTap != null
            ? GestureDetector(
                onTap: () => onSlotTap!(idx),
                child: content,
              )
            : content,
      );

      return positionedSlot;
    }).toList();
  }
}

// ---------------------------------------------------------------------------
// Slot content — applies shape mask + photo/placeholder
// ---------------------------------------------------------------------------

class _SlotContent extends StatelessWidget {
  const _SlotContent({
    required this.slot,
    required this.photo,
    required this.index,
    required this.showPlaceholders,
  });

  final LayoutSlot slot;
  final XFile? photo;
  final int index;
  final bool showPlaceholders;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photo != null;

    Widget photoWidget = hasPhoto
        ? Image.file(File(photo!.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity)
        : (showPlaceholders ? _Placeholder(index: index) : const SizedBox.expand());

    // Apply shape mask
    Widget shaped = _applyShape(photoWidget);

    // Apply border/frame
    shaped = _applyBorder(shaped);

    return shaped;
  }

  Widget _applyShape(Widget child) {
    switch (slot.shape) {
      case SlotShape.rect:
        if (slot.cornerRadius > 0) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(slot.cornerRadius),
            child: child,
          );
        }
        return ClipRect(child: child);

      case SlotShape.polaroid:
        return _PolaroidFrame(child: child);

      case SlotShape.blob1:
        return ClipPath(clipper: BlobClipper1(), child: child);

      case SlotShape.blob2:
        return ClipPath(clipper: BlobClipper2(), child: child);

      case SlotShape.blob3:
        return ClipPath(clipper: BlobClipper3(), child: child);

      case SlotShape.pillWave1:
        return ClipPath(clipper: PillWaveClipper1(), child: child);

      case SlotShape.pillWave2:
        return ClipPath(clipper: PillWaveClipper2(), child: child);

      case SlotShape.waveCurve:
        return ClipPath(clipper: WaveCurveClipper(), child: child);
    }
  }

  Widget _applyBorder(Widget child) {
    switch (slot.border.style) {
      case SlotBorderStyle.none:
        if (slot.borderColor != null) {
          // Colored outline border (layouts 10 etc.)
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: slot.borderColor!, width: slot.borderWidth),
              boxShadow: [BoxShadow(color: slot.borderColor!.withValues(alpha: 0.35), blurRadius: 14)],
            ),
            child: child,
          );
        }
        return child;

      case SlotBorderStyle.solidCream:
        return Container(
          padding: EdgeInsets.all(slot.border.width),
          decoration: BoxDecoration(
            color: slot.border.color,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 8, offset: const Offset(2, 3))],
          ),
          child: child,
        );

      case SlotBorderStyle.tornWhite:
        return ClipPath(
          clipper: TornEdgeClipper(seed: index * 17 + 42),
          child: Container(
            padding: EdgeInsets.all(slot.border.width),
            color: Colors.white,
            child: child,
          ),
        );

      case SlotBorderStyle.dark:
        return Container(
          padding: EdgeInsets.all(slot.border.width),
          decoration: BoxDecoration(
            color: slot.border.color,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.50), blurRadius: 4, offset: const Offset(2, 2))],
          ),
          child: child,
        );

      case SlotBorderStyle.metalGold:
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFD700), width: slot.border.width),
            boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.35), blurRadius: 14)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: child,
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Polaroid frame widget
// ---------------------------------------------------------------------------

class _PolaroidFrame extends StatelessWidget {
  const _PolaroidFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.50), blurRadius: 18, offset: const Offset(3, 6))],
      ),
      child: Column(
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: SizedBox.expand(child: child),
            ),
          ),
          Container(
            height: 28,
            color: Colors.white,
            child: Center(
              child: Text(
                'MOMENT',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 7,
                  color: Colors.black38,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Placeholder for empty slot
// ---------------------------------------------------------------------------

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.index});
  final int index;

  static const _colors = [Color(0xFF1A2035), Color(0xFF201A35), Color(0xFF1A3020), Color(0xFF302018)];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _colors[index % _colors.length],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, color: Colors.white.withValues(alpha: 0.35), size: 24),
            const SizedBox(height: 4),
            Text(
              'Tap to add',
              style: GoogleFonts.inter(fontSize: 9, color: Colors.white.withValues(alpha: 0.30)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background
// ---------------------------------------------------------------------------

class _Background extends StatelessWidget {
  const _Background({required this.bg});
  final LayoutBackground bg;

  @override
  Widget build(BuildContext context) {
    if (bg.gradient != null) {
      return Container(
        decoration: BoxDecoration(gradient: bg.gradient),
      );
    }
    return Container(
      color: bg.color,
      child: bg.hasNoise ? CustomPaint(painter: _NoisePainter(), child: const SizedBox.expand()) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Layout-specific back decorations (behind photos)
// ---------------------------------------------------------------------------

class _BackDecoration extends StatelessWidget {
  const _BackDecoration({required this.layoutId, required this.w, required this.h});
  final MemoryLayoutId layoutId;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    switch (layoutId) {
      case MemoryLayoutId.filmNegative:
        return CustomPaint(painter: _SprocketPainter(w: w, h: h), child: const SizedBox.expand());
      case MemoryLayoutId.perforatedFilm:
        return CustomPaint(painter: _FilmStripPainter(w: w, h: h), child: const SizedBox.expand());
      case MemoryLayoutId.retroScrapbook:
        return CustomPaint(painter: _ScrapbookDecorationPainter(w: w, h: h), child: const SizedBox.expand());
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// Layout-specific front decorations (on top of photos)
// ---------------------------------------------------------------------------

class _FrontDecoration extends StatelessWidget {
  const _FrontDecoration({required this.layoutId, required this.w, required this.h});
  final MemoryLayoutId layoutId;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    switch (layoutId) {
      case MemoryLayoutId.filmNegative:
        return Positioned.fill(
          child: IgnorePointer(
            child: Column(
              children: [
                const Spacer(),
                Padding(
                  padding: EdgeInsets.only(left: w * 0.02, bottom: h * 0.01),
                  child: Row(children: [
                    Text('▶ 52 400', style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white38, letterSpacing: 1)),
                    const Spacer(),
                    Text('STILL 4527', style: GoogleFonts.jetBrainsMono(fontSize: 8, color: Colors.white38, letterSpacing: 1)),
                    SizedBox(width: w * 0.02),
                  ]),
                ),
              ],
            ),
          ),
        );
      case MemoryLayoutId.floralFrame:
        return IgnorePointer(
          child: CustomPaint(painter: _DaisyBorderPainter(w: w, h: h), child: const SizedBox.expand()),
        );
      case MemoryLayoutId.goldenGlitter:
        return IgnorePointer(
          child: CustomPaint(painter: _ConfettiPainter(w: w, h: h), child: const SizedBox.expand()),
        );
      case MemoryLayoutId.geometricWave:
        return IgnorePointer(
          child: CustomPaint(painter: _HeartsPainter(w: w, h: h), child: const SizedBox.expand()),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// CustomPainters
// ---------------------------------------------------------------------------

class _NoisePainter extends CustomPainter {
  static final _rng = math.Random(77);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 800; i++) {
      paint.color = Colors.white.withValues(alpha: _rng.nextDouble() * 0.06);
      canvas.drawCircle(
        Offset(_rng.nextDouble() * size.width, _rng.nextDouble() * size.height),
        0.6, paint,
      );
    }
  }

  @override
  bool shouldRepaint(_NoisePainter _) => false;
}

class _SprocketPainter extends CustomPainter {
  _SprocketPainter({required this.w, required this.h});
  final double w, h;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2a2a2a)
      ..style = PaintingStyle.fill;
    const r = 4.0;
    const spacing = 22.0;
    final leftX = w * 0.08;
    final rightX = w * 0.92;
    var y = 16.0;
    while (y < h - 16) {
      canvas.drawCircle(Offset(leftX, y), r, paint);
      canvas.drawCircle(Offset(rightX, y), r, paint);
      y += spacing;
    }
  }

  @override
  bool shouldRepaint(_SprocketPainter _) => false;
}

class _FilmStripPainter extends CustomPainter {
  _FilmStripPainter({required this.w, required this.h});
  final double w, h;

  @override
  void paint(Canvas canvas, Size size) {
    // Diagonal white film strip band
    final stripPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(w * 0.5, h * 0.5);
    canvas.rotate(-5 * math.pi / 180);
    canvas.drawRect(Rect.fromLTWH(-w * 0.7, -h * 0.06, w * 1.4, h * 0.12), stripPaint);

    // Sprocket holes along strip
    final holePaint = Paint()
      ..color = const Color(0xFF4a4a4a)
      ..style = PaintingStyle.fill;
    for (double x = -w * 0.65; x < w * 0.65; x += 20) {
      canvas.drawRect(Rect.fromLTWH(x, -h * 0.055, 8, 8), holePaint);
      canvas.drawRect(Rect.fromLTWH(x, h * 0.035, 8, 8), holePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FilmStripPainter _) => false;
}

class _ScrapbookDecorationPainter extends CustomPainter {
  _ScrapbookDecorationPainter({required this.w, required this.h});
  final double w, h;

  @override
  void paint(Canvas canvas, Size size) {
    final textPaint = Paint()
      ..color = const Color(0xFF1a1a1a).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Outer decorative frame
    final frameRect = Rect.fromLTWH(w * 0.04, h * 0.04, w * 0.92, h * 0.92);
    canvas.drawRect(frameRect, textPaint);
    final innerRect = Rect.fromLTWH(w * 0.06, h * 0.06, w * 0.88, h * 0.88);
    canvas.drawRect(innerRect, textPaint);

    // Star at top-left
    _drawStar(canvas, Offset(w * 0.08, h * 0.07), 8, const Color(0xFF1a1a1a).withValues(alpha: 0.45));
    _drawStar(canvas, Offset(w * 0.92, h * 0.07), 8, const Color(0xFF1a1a1a).withValues(alpha: 0.45));
    _drawStar(canvas, Offset(w * 0.08, h * 0.94), 8, const Color(0xFF1a1a1a).withValues(alpha: 0.45));
    _drawStar(canvas, Offset(w * 0.92, h * 0.94), 8, const Color(0xFF1a1a1a).withValues(alpha: 0.45));
  }

  void _drawStar(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final x = center.dx + math.cos(angle) * size;
      final y = center.dy + math.sin(angle) * size;
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    path.close();
    canvas.drawPath(path, paint);
    // Cross lines
    final linePaint = Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(center.dx, center.dy - size), Offset(center.dx, center.dy + size), linePaint);
    canvas.drawLine(Offset(center.dx - size, center.dy), Offset(center.dx + size, center.dy), linePaint);
  }

  @override
  bool shouldRepaint(_ScrapbookDecorationPainter _) => false;
}

class _DaisyBorderPainter extends CustomPainter {
  _DaisyBorderPainter({required this.w, required this.h});
  final double w, h;

  @override
  void paint(Canvas canvas, Size size) {
    const positions = [
      Offset(0.08, 0.04), Offset(0.50, 0.04), Offset(0.92, 0.04),
      Offset(0.08, 0.96), Offset(0.50, 0.96), Offset(0.92, 0.96),
    ];
    for (final pos in positions) {
      _drawDaisy(canvas, Offset(pos.dx * w, pos.dy * h), 14);
    }
  }

  void _drawDaisy(Canvas canvas, Offset center, double r) {
    final petalPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final centerPaint = Paint()..color = const Color(0xFFFFE066)..style = PaintingStyle.fill;
    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx + math.cos(angle) * r * 0.7, center.dy + math.sin(angle) * r * 0.7),
          width: r * 0.7, height: r * 1.1,
        ),
        petalPaint,
      );
    }
    canvas.drawCircle(center, r * 0.40, centerPaint);
  }

  @override
  bool shouldRepaint(_DaisyBorderPainter _) => false;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.w, required this.h});
  final double w, h;
  static final _rng = math.Random(99);

  @override
  void paint(Canvas canvas, Size size) {
    final goldPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.60)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 40; i++) {
      final x = _rng.nextDouble() * w;
      final y = _rng.nextDouble() * h;
      final sz = 2 + _rng.nextDouble() * 6;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(_rng.nextDouble() * 2 * math.pi);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sz, height: sz * 0.4), goldPaint);
      canvas.restore();
    }

    // Stars
    final starPaint = Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.45)..style = PaintingStyle.fill;
    for (int i = 0; i < 12; i++) {
      final x = (i * 73 % 1) * w + _rng.nextDouble() * 20;
      final y = _rng.nextDouble() * h;
      final r = 2.5 + _rng.nextDouble() * 3;
      _drawStar5(canvas, Offset(x, y), r, starPaint);
    }
  }

  void _drawStar5(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = i * 2 * math.pi / 5 - math.pi / 2;
      final innerAngle = outerAngle + math.pi / 5;
      final ox = center.dx + math.cos(outerAngle) * r;
      final oy = center.dy + math.sin(outerAngle) * r;
      final ix = center.dx + math.cos(innerAngle) * r * 0.4;
      final iy = center.dy + math.sin(innerAngle) * r * 0.4;
      if (i == 0) { path.moveTo(ox, oy); } else { path.lineTo(ox, oy); }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ConfettiPainter _) => false;
}

class _HeartsPainter extends CustomPainter {
  _HeartsPainter({required this.w, required this.h});
  final double w, h;
  static final _rng = math.Random(55);

  @override
  void paint(Canvas canvas, Size size) {
    const colors = [Color(0xFFFF1493), Color(0xFFFFD700), Color(0xFF0066FF), Color(0xFFFF69B4)];
    for (int i = 0; i < 10; i++) {
      final x = _rng.nextDouble() * w;
      final y = _rng.nextDouble() * h;
      final sz = 8 + _rng.nextDouble() * 12;
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      _drawHeart(canvas, Offset(x, y), sz, paint);
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final x = center.dx;
    final y = center.dy;
    final s = size;
    path.moveTo(x, y + s * 0.25);
    path.cubicTo(x - s, y - s * 0.25, x - s, y - s, x, y - s * 0.4);
    path.cubicTo(x + s, y - s, x + s, y - s * 0.25, x, y + s * 0.25);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeartsPainter _) => false;
}

// ---------------------------------------------------------------------------
// Compact thumbnail (for layout selector)
// ---------------------------------------------------------------------------

class LayoutThumbnail extends StatelessWidget {
  const LayoutThumbnail({super.key, required this.layout, this.isSelected = false});
  final MemoryLayout layout;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white.withValues(alpha: 0.15),
          width: isSelected ? 2.5 : 1,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.40), blurRadius: 10)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          children: [
            // Thumbnail canvas (all placeholders, no interaction)
            MemoryCanvas(
              layout: layout,
              photos: const [],
              interactive: false,
              showPlaceholders: false,
            ),
            // Slot outlines for preview
            _ThumbnailOverlay(layout: layout),
            // Selected checkmark
            if (isSelected)
              Positioned(
                top: 4, right: 4,
                child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailOverlay extends StatelessWidget {
  const _ThumbnailOverlay({required this.layout});
  final MemoryLayout layout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return Stack(
        children: layout.slots.map((slot) {
          return Positioned(
            left: slot.xPct * w,
            top: slot.yPct * h,
            width: slot.wPct * w,
            height: slot.hPct * h,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.5),
              ),
            ),
          );
        }).toList(),
      );
    });
  }
}
