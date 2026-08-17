import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/collage_layout.dart';
import '../models/photo_slot.dart';
import 'collage_decorations.dart';
import 'decoration_painter.dart';
import 'shape_clippers.dart';

class MemoryCanvas extends StatelessWidget {
  final CollageLayout layout;
  final List<ImageProvider?> images;
  final bool blurred;

  const MemoryCanvas({
    super.key,
    required this.layout,
    required this.images,
    this.blurred = false,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final ordered = [...layout.slots]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(child: _background()),
                if (layout.hasDecorations &&
                    layout.decorationType != 'daisies' &&
                    layout.decorationType != 'scrapbook')
                  Positioned.fill(
                    child: CustomPaint(
                      painter: DecorationPainter(layout.decorationType),
                    ),
                  ),
                for (final deco in layout.decorations.where((d) => d.behindPhotos))
                  _buildDecoration(deco, w, h),
                for (int i = 0; i < ordered.length; i++)
                  _buildSlot(ordered[i], _imageForSlot(ordered[i]), w, h,
                      layout.slots.indexOf(ordered[i])),
                if (layout.decorationType == 'daisies' ||
                    layout.decorationType == 'scrapbook')
                  Positioned.fill(
                    child: CustomPaint(
                      painter: DecorationPainter(layout.decorationType),
                    ),
                  ),
                for (final deco in layout.decorations.where((d) => !d.behindPhotos))
                  _buildDecoration(deco, w, h),
                if (blurred)
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                          color: Colors.black.withValues(alpha: 0.05)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  ImageProvider? _imageForSlot(PhotoSlot slot) {
    final idx = layout.slots.indexOf(slot);
    if (idx < 0 || idx >= images.length) return null;
    return images[idx];
  }

  Widget _background() {
    final bg = layout.background;
    switch (bg.type) {
      case BackgroundType.linearGradient:
        if (bg.colors != null && bg.colors!.isNotEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bg.colors!,
                stops: bg.stops,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
        }
        return const ColoredBox(color: Colors.black);
      case BackgroundType.radialGradient:
        if (bg.colors != null && bg.colors!.isNotEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: bg.colors!,
                stops: bg.stops,
                radius: 1.1,
              ),
            ),
          );
        }
        return const ColoredBox(color: Colors.black);
      case BackgroundType.solid:
        return ColoredBox(color: bg.color ?? Colors.black);
    }
  }

  Widget _buildDecoration(CollageDecoration deco, double cw, double ch) {
    final isLine = deco.kind == DecorationKind.brushLine ||
        deco.kind == DecorationKind.filmSprockets;
    final boxW = isLine ? deco.size * cw : deco.size;
    final boxH = isLine ? 10.0 : deco.size;
    final left = deco.position.dx * cw - boxW / 2;
    final top = deco.position.dy * ch - boxH / 2;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: deco.rotationDeg * 3.14159265 / 180,
          child: SizedBox(
            width: boxW,
            height: boxH,
            child: CustomPaint(
              painter: SingleDecorationPainter(kind: deco.kind, color: deco.color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlot(PhotoSlot slot, ImageProvider? img, double cw, double ch, int slotIndex) {
    final width = slot.w * cw;
    final height = slot.h * ch;
    final seed = slot.tornSeed ?? slotIndex;
    final glitterShadow = layout.decorationType == 'glitter';

    return Positioned(
      left: slot.x * cw,
      top: slot.y * ch,
      child: Transform.rotate(
        angle: slot.rotation * 3.14159265 / 180,
        child: buildCollageFrame(
          slot: slot,
          img: img,
          width: width,
          height: height,
          seed: seed,
          glitterShadow: glitterShadow,
        ),
      ),
    );
  }
}

/// Builds the framed (clipped/bordered/shadowed) photo widget for a slot at
/// a fixed [width]x[height], with no position/rotation applied — callers
/// (static [MemoryCanvas] and the animated Collage Studio canvas) wrap this
/// themselves so the studio can tween position/rotation independently of the
/// frame's own visual identity.
Widget buildCollageFrame({
  required PhotoSlot slot,
  required ImageProvider? img,
  required double width,
  required double height,
  required int seed,
  bool glitterShadow = false,
}) {
  Widget rawContent(double w, double h) => img == null
      ? Container(
          color: Colors.white10,
          child: const Center(
            child: Icon(Icons.add_photo_alternate_outlined,
                color: Colors.white38, size: 22),
          ),
        )
      : Image(image: img, fit: BoxFit.cover, width: w, height: h);

  // Polaroid-style instant-film frame (borderWidth/bottomBorderExtra fall
  // back to the classic 6px/22px chin when a style doesn't set them).
  if (slot.shape == MaskShape.polaroid) {
    final frameColor = slot.borderColor ?? Colors.white;
    final borderW = slot.borderWidth > 0 ? slot.borderWidth : 6.0;
    final chin = slot.bottomBorderExtra > 0 ? slot.bottomBorderExtra : 22.0;

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.fromLTRB(borderW, borderW, borderW, borderW + chin),
      decoration: BoxDecoration(
        color: frameColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: slot.shadow ? 0.5 : 0.4),
            blurRadius: slot.shadow ? 14 : 6,
            offset: Offset(2, slot.shadow ? 6 : 3),
          ),
        ],
      ),
      child: rawContent(width - borderW * 2, height - borderW - chin),
    );
  }

  final isRounded = slot.shape == MaskShape.roundedRect;
  final radius = isRounded ? BorderRadius.circular(16) : BorderRadius.zero;
  final frameShadow = <BoxShadow>[
    if (glitterShadow)
      BoxShadow(
        color: const Color(0xFFFFD700).withValues(alpha: 0.4),
        blurRadius: 12,
      ),
    if (slot.shadow)
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.45),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
  ];

  Widget photo;
  if (slot.shape == MaskShape.tornPaper && slot.borderWidth > 0) {
    // Torn white paper wrapped around an inset, similarly-torn photo.
    final pad = slot.borderWidth;
    photo = ClipPath(
      clipper: ShapeClipper(slot.shape, seed: seed),
      child: Container(
        width: width,
        height: height,
        color: slot.borderColor ?? Colors.white,
        padding: EdgeInsets.all(pad),
        child: ClipPath(
          clipper: ShapeClipper(slot.shape, seed: seed + 1000),
          child: rawContent(width - pad * 2, height - pad * 2),
        ),
      ),
    );
    if (frameShadow.isNotEmpty) {
      photo = DecoratedBox(decoration: BoxDecoration(boxShadow: frameShadow), child: photo);
    }
  } else if (slot.borderWidth > 0 &&
      !isRounded &&
      slot.shape != MaskShape.rect &&
      (slot.borderGradient != null || slot.borderColor != null)) {
    // Border.all only draws a rectangle, which looks wrong against a
    // non-rectangular clip (circle/blob/pill/wave/arch/squircle) — instead,
    // fill the full shape with the border color/gradient and clip a smaller,
    // inset copy of the same shape for the photo so the border hugs the
    // silhouette.
    final bw = slot.borderWidth;
    photo = ClipPath(
      clipper: ShapeClipper(slot.shape, seed: seed),
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all(bw),
        decoration: BoxDecoration(
          color: slot.borderGradient == null ? slot.borderColor : null,
          gradient: slot.borderGradient != null
              ? LinearGradient(
                  colors: slot.borderGradient!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          boxShadow: frameShadow,
        ),
        child: ClipPath(
          clipper: ShapeClipper(slot.shape, seed: seed),
          child: rawContent(width - bw * 2, height - bw * 2),
        ),
      ),
    );
  } else if (slot.borderWidth > 0 && slot.borderColor != null) {
    photo = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: slot.borderColor!, width: slot.borderWidth),
        borderRadius: radius,
        boxShadow: frameShadow,
      ),
      child: ClipRRect(
        borderRadius: isRounded ? BorderRadius.circular(12) : BorderRadius.zero,
        child: ClipPath(
          clipper: ShapeClipper(slot.shape, seed: seed),
          child: SizedBox(width: width, height: height, child: rawContent(width, height)),
        ),
      ),
    );
  } else {
    photo = ClipPath(
      clipper: ShapeClipper(slot.shape, seed: seed),
      child: SizedBox(width: width, height: height, child: rawContent(width, height)),
    );
    if (slot.shadow) {
      photo = DecoratedBox(decoration: BoxDecoration(boxShadow: frameShadow), child: photo);
    }
  }

  return SizedBox(width: width, height: height, child: photo);
}
