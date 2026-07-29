import 'package:flutter/material.dart';
import 'photo_slot.dart';

enum BackgroundType { solid, linearGradient, radialGradient }

class CollageBackground {
  final BackgroundType type;
  final Color? color;
  final List<Color>? colors;
  final List<double>? stops;

  const CollageBackground.solid(this.color)
      : type = BackgroundType.solid,
        colors = null,
        stops = null;

  const CollageBackground.linearGradient(this.colors, {this.stops})
      : type = BackgroundType.linearGradient,
        color = null;

  const CollageBackground.radialGradient(this.colors, {this.stops})
      : type = BackgroundType.radialGradient,
        color = null;
}

enum DecorationKind {
  doodleCircle,
  doodleDashes,
  hearts,
  sparkle,
  daisy,
  brushLine,
  filmSprockets,
}

class CollageDecoration {
  /// Fractional position (0-1) relative to the canvas.
  final Offset position;
  final DecorationKind kind;

  /// For most kinds, an absolute pixel size. For [DecorationKind.brushLine]
  /// and [DecorationKind.filmSprockets] (which span the canvas), a fraction
  /// (0-1) of the canvas width instead.
  final double size;
  final double rotationDeg;
  final Color color;

  /// When true, painted before the photo slots (e.g. brush strokes that
  /// should sit behind the frames) instead of on top of them.
  final bool behindPhotos;

  const CollageDecoration({
    required this.position,
    required this.kind,
    required this.size,
    this.rotationDeg = 0,
    this.color = Colors.white,
    this.behindPhotos = false,
  });
}

class CollageLayout {
  final String id;
  final String name;
  final String category;
  final int photoCount;
  final List<PhotoSlot> slots;
  final CollageBackground background;
  final bool hasDecorations;
  final String decorationType;

  /// Positioned single-instance decorations (new Collage Studio styles).
  final List<CollageDecoration> decorations;

  /// Groups size variants of the same visual style (e.g. bigLeft_2/3/4)
  /// for the studio's chip carousel.
  final String? familyId;

  const CollageLayout({
    required this.id,
    required this.name,
    required this.category,
    required this.photoCount,
    required this.slots,
    required this.background,
    this.hasDecorations = false,
    this.decorationType = '',
    this.decorations = const [],
    this.familyId,
  });
}
