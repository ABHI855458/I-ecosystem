import 'package:flutter/material.dart';

import '../../models/collage_layout.dart';
import '../../models/photo_slot.dart';
import '../../widgets/collage_decorations.dart';
import '../../widgets/memory_canvas.dart' show buildCollageFrame;

/// Animated Collage Studio canvas — unlike the static [MemoryCanvas], every
/// photo keeps a stable identity (its index) across a style switch, so
/// switching styles moves/resizes/rotates each photo into its new frame
/// instead of hard-cutting to a new tree.
class StudioCanvas extends StatelessWidget {
  final CollageLayout layout;
  final List<ImageProvider?> images;

  const StudioCanvas({super.key, required this.layout, required this.images});

  static const _switchDuration = Duration(milliseconds: 550);
  static const _switchCurve = Curves.easeOutBack;
  static const _fadeDuration = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final ordered = List<int>.generate(layout.slots.length, (i) => i)
            ..sort((a, b) => layout.slots[a].zIndex.compareTo(layout.slots[b].zIndex));

          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: _fadeDuration,
                    child: KeyedSubtree(
                      key: ValueKey(layout.id),
                      child: _background(layout.background),
                    ),
                  ),
                ),
                for (final deco in layout.decorations.where((d) => d.behindPhotos))
                  _decoration(deco, w, h),
                for (final i in ordered)
                  if (i < images.length) _animatedSlot(layout.slots[i], images[i], w, h, i),
                for (final deco in layout.decorations.where((d) => !d.behindPhotos))
                  _decoration(deco, w, h),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _background(CollageBackground bg) {
    // AnimatedSwitcher gives its current child loose (not tight) constraints,
    // so a childless ColoredBox/DecoratedBox would collapse to zero size —
    // SizedBox.expand forces it to fill the canvas regardless.
    switch (bg.type) {
      case BackgroundType.linearGradient:
        return SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bg.colors ?? const [Colors.black, Colors.black],
                stops: bg.stops,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        );
      case BackgroundType.radialGradient:
        return SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: bg.colors ?? const [Colors.black, Colors.black],
                stops: bg.stops,
                radius: 1.1,
              ),
            ),
          ),
        );
      case BackgroundType.solid:
        return SizedBox.expand(child: ColoredBox(color: bg.color ?? Colors.black));
    }
  }

  Widget _decoration(CollageDecoration deco, double cw, double ch) {
    final isLine = deco.kind == DecorationKind.brushLine ||
        deco.kind == DecorationKind.filmSprockets;
    final boxW = isLine ? deco.size * cw : deco.size;
    final boxH = isLine ? 10.0 : deco.size;

    return AnimatedPositioned(
      duration: _switchDuration,
      curve: _switchCurve,
      left: deco.position.dx * cw - boxW / 2,
      top: deco.position.dy * ch - boxH / 2,
      child: IgnorePointer(
        child: AnimatedRotation(
          duration: _switchDuration,
          curve: _switchCurve,
          turns: deco.rotationDeg / 360,
          child: AnimatedOpacity(
            duration: _fadeDuration,
            opacity: 1,
            child: SizedBox(
              width: boxW,
              height: boxH,
              child: CustomPaint(
                painter: SingleDecorationPainter(kind: deco.kind, color: deco.color),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _animatedSlot(PhotoSlot slot, ImageProvider? img, double cw, double ch, int photoIndex) {
    final width = slot.w * cw;
    final height = slot.h * ch;

    return AnimatedPositioned(
      key: ValueKey('studio_photo_$photoIndex'),
      duration: _switchDuration,
      curve: _switchCurve,
      left: slot.x * cw,
      top: slot.y * ch,
      width: width,
      height: height,
      child: AnimatedRotation(
        duration: _switchDuration,
        curve: _switchCurve,
        turns: slot.rotation / 360,
        child: RepaintBoundary(
          child: AnimatedSwitcher(
            duration: _fadeDuration,
            child: KeyedSubtree(
              key: ValueKey(_frameSignature(slot)),
              child: buildCollageFrame(
                slot: slot,
                img: img,
                width: width,
                height: height,
                seed: slot.tornSeed ?? photoIndex,
                glitterShadow: layout.decorationType == 'glitter',
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Identity for the parts of a frame that can't be smoothly tweened (clip
  /// shape, border style) — the AnimatedSwitcher cross-fades on change
  /// instead of trying to interpolate them.
  String _frameSignature(PhotoSlot slot) =>
      '${slot.shape}_${slot.borderColor?.toARGB32()}_${slot.borderWidth}_${slot.borderGradient}_${slot.bottomBorderExtra}_${slot.shadow}';
}
