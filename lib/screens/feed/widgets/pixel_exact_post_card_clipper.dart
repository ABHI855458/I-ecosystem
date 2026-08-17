import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

// ---------------------------------------------------------------------------
// Sub-pixel measured (50%-brightness edge crossing) off a 384×288 reference
// screenshot, then RE-DERIVED for 4:5 portrait — the app's actual capture
// ratio (4:5 or 1:1 square only, never landscape). Card width and every
// horizontal/top-edge measurement (avatar notch, top corners) carried over
// unchanged; height stretched to width×5/4 and the bottom-edge features
// (tray cut, tray icons, bottom corners) shifted down by the resulting
// delta (238.744px at the reference width) to preserve their distance from
// the bottom edge. Four independently-fitted corner radii (NOT a uniform
// border-radius) plus two non-elliptical cuts: the avatar notch in the top
// edge and the reaction-tray cut in the bottom edge.
//
// The raw SVG path below is parsed via path_drawing's parseSvgPathData
// rather than hand-transcribed into Path.cubicTo/lineTo calls — the avatar
// notch alone is ~50 traced cubic segments forming a smooth valley (not an
// arc), and porting that by eye is exactly the kind of thing that silently
// drifts, per notched_post_card_clipper.dart's own warning about this same
// failure mode on the older, formula-driven dip. Parsed once (static final)
// and scaled uniformly per getClip call — scale = actual width / refWidth,
// same factor applied to every reference number, aspect ratio locked at
// 4:5 (refWidth / refHeight).
//
// Frame geometry only: this clipper and PixelExactCardGeometry below
// replace the card's outer shape and the avatar/tray-icon POSITIONS only.
// What actually renders in the avatar circle (anon persona vs. real photo)
// and what icons sit in the tray (ping+heart vs. like+comment) is each
// card's own concern, unchanged by this file.
// ---------------------------------------------------------------------------

class PixelExactCardGeometry {
  const PixelExactCardGeometry._(this.scale);

  final double scale;

  static const double refWidth = 375.047;
  static const double refHeight = 468.809;

  factory PixelExactCardGeometry.of(double width) =>
      PixelExactCardGeometry._(width / refWidth);

  /// Height to render the card at for this width, keeping the reference's
  /// 1.6302:1 aspect ratio locked.
  double get height => refHeight * scale;

  /// Avatar center, local to the card's own box — floats mostly ABOVE the
  /// top edge (only 22.2% of its diameter overlaps down into the card).
  /// Do not clamp this inside the card's bounds.
  Offset get avatarCenter => Offset(42.600, -9.255) * scale;
  double get avatarRadius => 16.616 * scale;

  /// White ring around the avatar — outer radius; ring thickness is
  /// (avatarRingOuterRadius - avatarRadius).
  double get avatarRingOuterRadius => 20.503 * scale;
  double get avatarRingThickness => avatarRingOuterRadius - avatarRadius;

  /// The reaction-tray cut in the bottom-right — flat top, measured from
  /// the card's own top edge (so content above this y is on the card
  /// proper; below it is the cut-out apron the tray icons sit in).
  double get trayTopY => 451.034 * scale;

  /// Icon top inset below [trayTopY] — matches the reference's send/heart
  /// icons, reusable as an anchor for whatever icons actually render here.
  double get trayIconTopInset => 7.95 * scale;
  double get trayRightInset => 25.05 * scale;
  double get trayIconGap => 18.0 * scale;
}

class PixelExactPostCardClipper extends CustomClipper<Path> {
  const PixelExactPostCardClipper();

  static final Path _refPath = parseSvgPathData(_svgPathData);

  static const String _svgPathData =
      'M 12.68 0 H 15.983 C 16.402,0.125 17.578,0.469 18.497,0.748 C 19.416,1.027 20.497,1.282 21.497,1.673 C 22.497,2.064 23.497,2.585 24.497,3.096 C 25.497,3.606 26.497,4.114 27.497,4.735 C 28.497,5.355 29.497,6.155 30.497,6.818 C 31.497,7.481 32.497,8.154 33.497,8.71 C 34.497,9.267 35.497,9.783 36.497,10.155 C 37.497,10.526 38.497,10.784 39.497,10.941 C 40.497,11.097 41.497,11.079 42.497,11.092 C 43.497,11.105 44.497,11.178 45.497,11.018 C 46.497,10.858 47.497,10.592 48.497,10.134 C 49.497,9.676 50.497,8.942 51.497,8.27 C 52.497,7.599 53.497,6.809 54.497,6.107 C 55.497,5.404 56.497,4.682 57.497,4.055 C 58.497,3.429 59.497,2.833 60.497,2.348 C 61.497,1.863 62.497,1.439 63.497,1.145 C 64.497,0.852 65.566,0.779 66.497,0.588 C 67.428,0.397 68.651,0.098 69.082,0 H 349.127 A 25.92 25.92 0 0 1 375.047 25.92 V 463.679 A 5.13 5.13 0 0 1 369.917 468.809 C 369.197,468.682 368.397,468.472 367.497,467.732 C 366.383,466.674 365.497,464.363 364.497,462.463 C 363.497,460.563 362.497,457.832 361.497,456.333 C 360.497,454.834 359.497,454.214 358.497,453.471 C 357.497,452.728 356.497,452.268 355.497,451.873 C 354.497,451.478 353.58,451.242 352.497,451.102 C 351.414,450.962 350.914,451.045 348.997,451.034 C 347.08,451.023 344.83,451.034 340.997,451.034 C 337.164,451.034 330.997,451.034 325.997,451.034 C 320.997,451.034 315.997,451.034 310.997,451.034 C 305.997,451.034 299.58,451.033 295.997,451.034 C 292.414,451.035 291.08,450.923 289.497,451.038 C 287.914,451.153 287.497,451.385 286.497,451.722 C 285.497,452.06 284.497,452.439 283.497,453.063 C 282.497,453.687 281.497,454.215 280.497,455.469 C 279.497,456.723 278.497,459.04 277.497,460.589 C 276.497,462.138 275.497,463.69 274.497,464.763 C 273.497,465.836 272.479,466.352 271.497,467.026 C 270.515,467.7 269.086,468.512 268.604,468.809 H 26.2 A 26.2 26.2 0 0 1 0 442.609 V 12.68 A 12.68 12.68 0 0 1 12.68 0 Z';

  @override
  Path getClip(Size size) {
    final scale = size.width / PixelExactCardGeometry.refWidth;
    return _refPath.transform(
      Matrix4.diagonal3Values(scale, scale, 1.0).storage,
    );
  }

  @override
  bool shouldReclip(covariant PixelExactPostCardClipper old) => false;
}
