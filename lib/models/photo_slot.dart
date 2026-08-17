import 'package:flutter/material.dart';

enum MaskShape {
  rect,
  roundedRect,
  circle,
  polaroid,
  blob1,
  blob2,
  blob3,
  pill,
  wave,
  arch,
  tornPaper,
  squircle,
}

class PhotoSlot {
  final double x;
  final double y;
  final double w;
  final double h;
  final MaskShape shape;
  final double rotation;
  final int zIndex;
  final Color? borderColor;
  final double borderWidth;

  /// Deterministic seed for [MaskShape.tornPaper] so the jagged edge doesn't
  /// flicker on rebuild. Defaults to the slot's index in its layout when null.
  final int? tornSeed;

  /// When set, overrides [borderColor] with a gradient border.
  final List<Color>? borderGradient;

  /// Extra bottom border height for a polaroid-style "chin".
  final double bottomBorderExtra;

  /// Opt-in drop shadow behind the frame.
  final bool shadow;

  const PhotoSlot({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.shape = MaskShape.rect,
    this.rotation = 0,
    this.zIndex = 0,
    this.borderColor,
    this.borderWidth = 0,
    this.tornSeed,
    this.borderGradient,
    this.bottomBorderExtra = 0,
    this.shadow = false,
  });
}
