import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

// ---------------------------------------------------------------------------
// Anonymous-feed post card frame — ported directly from the Post Card
// Implementation Spec's framePath(H)/scaleFor(H) generator (section 2.5),
// not re-derived by hand. The spec measured a landscape 13:8 reference
// (375.047×230.065, S=1) sub-pixel and gives a single generator that
// reproduces every ratio (including this app's actual 4:5 portrait frame)
// by feeding it the target height — see [scaleFor]'s doc comment for why
// the scale is a SQUARE ROOT of the height ratio, not a linear one.
//
// The dip (top edge, under the avatar) scales from the top-left; the tray
// cut (bottom edge, under the ping/reaction icons) scales from the
// bottom-right — see [AnonPostCardClipper._framePathData]. Scaling both
// from the same origin detaches the tray from its own bottom-right corner
// radius (spec section 2.4).
//
// Anon-feed-exclusive: PhotoPostCard (this app's only caller of this file)
// is only ever instantiated from the Anonymous feed. Deliberately NOT the
// same class as PixelExactCardGeometry/PixelExactPostCardClipper
// (pixel_exact_post_card_clipper.dart) even though the shape is closely
// related — that pair is also reused by EveryonePostCard (Friends/Everyone
// feed) purely as a decorative frame, so changing its numbers in place
// would have changed that feed's card too. This file exists so the new
// spec's exact measurements land on the Anonymous feed only.
// ---------------------------------------------------------------------------

class AnonPostCardGeometry {
  const AnonPostCardGeometry._(this.scale, this._h, this._s);

  /// Render pixels per reference pixel: actualWidth / [refWidth].
  final double scale;

  /// The reference height this instance's S was derived from — refHeight
  /// for [AnonPostCardGeometry.of] (the IDEAL, uncompressed case), or the
  /// real rendered height for [AnonPostCardGeometry.fromSize]. Everything
  /// below (avatar/tray positions) is computed relative to THIS, not the
  /// compile-time refHeight constant directly — see fromSize's own doc
  /// comment for why that distinction is load-bearing.
  final double _h;
  final double _s;

  static const double refWidth = 375.047;

  /// This card's own frame ratio — locked to portrait 4:5, the app's actual
  /// capture ratio (never landscape/square framing — see photo_post_card.
  /// dart). [AnonPostCardClipper._framePathData] is written generically
  /// against H per spec, but this is the only H the app ever feeds it.
  static const double refHeight = 468.809;

  /// Landscape 13:8 reference height — S=1 baseline every other ratio's
  /// feature scale is measured against (spec section 1).
  static const double _h1 = 230.065;

  static const double _rTl = 12.68;
  static const double _rTr = 25.92;
  static const double _rBr = 5.13;
  static const double _rBl = 26.2;

  /// S = sqrt(H / H1) — the non-uniform feature scale. Width never changes
  /// (always [refWidth]) so height alone drives this; a square root (not
  /// the raw H/H1 ratio) is what keeps radii/dip/tray proportioned instead
  /// of either swelling past the frame or reading undersized — spec
  /// section 1, "why the square root".
  static double scaleFor(double height) => math.sqrt(height / _h1);

  /// Ideal/uncompressed geometry — assumes height is exactly refHeight at
  /// this scale. Fine as long as the card actually renders at that height
  /// (the common case); use [AnonPostCardGeometry.fromSize] once the real
  /// rendered size is known instead — see that factory's doc comment.
  factory AnonPostCardGeometry.of(double width) {
    final scale = width / refWidth;
    return AnonPostCardGeometry._(scale, refHeight, scaleFor(refHeight));
  }

  /// Derives S from the ACTUAL rendered size, exactly the way the
  /// clipper's own getClip(size) already does (refH = size.height *
  /// refWidth / size.width) — self-adjusting.
  ///
  /// Needed because PhotoPostCard's image box is a Flexible(loose)
  /// SizedBox: when a page doesn't have enough vertical room (e.g.
  /// HomeScreen's composer plus the tab-bar-clearance reserve leave less
  /// than idealImageHeight), its REAL height ends up smaller than
  /// AnonPostCardGeometry.of(width) ever assumed — but that factory has
  /// no way to know that, it only ever sees width. Avatar/tray positions
  /// computed from the ideal (uncompressed) S then land past the actual
  /// (compressed) frame's own edge — visibly below the photo, near
  /// whatever renders next (the comments row) — since the clip path
  /// itself DOES already self-adjust to the real size and shrinks with
  /// it, just these Positioned offsets didn't. This is that fix: call it
  /// with the real, post-layout Size once known (see photo_post_card.dart)
  /// instead of the width-only factory above.
  factory AnonPostCardGeometry.fromSize(Size size) {
    final scale = size.width / refWidth;
    final refH = size.height * refWidth / size.width;
    return AnonPostCardGeometry._(scale, refH, scaleFor(refH));
  }

  double get height => _h * scale;

  /// Avatar center, local to the card's own box — floats mostly ABOVE the
  /// top edge (only 22.2% of its diameter overlaps down into the card, per
  /// spec section 3). Do not clamp this inside the card's bounds.
  Offset get avatarCenter =>
      Offset((25.984 + 33.232 / 2) * _s, (-25.871 + 33.232 / 2) * _s) * scale;
  double get avatarRadius => (33.232 / 2) * _s * scale;

  /// White ring around the avatar — outer radius (spec section 3).
  double get avatarRingOuterRadius => (41.006 / 2) * _s * scale;
  double get avatarRingThickness => avatarRingOuterRadius - avatarRadius;

  /// The reaction-tray cut — flat top, measured from the card's own top
  /// edge (spec section 2.2/2.3: "tray cut flat top y = H − 17.775·S").
  double get trayTopY => (_h - 17.775 * _s) * scale;

  /// Icon top inset below [trayTopY] (spec section 4).
  double get trayIconTopInset => 7.948 * _s * scale;
  double get trayRightInset => 25.05 * _s * scale;
  double get trayIconGap => 18.0 * _s * scale;

  /// Stick-figure (ping) icon box — 19×20 at S=1 (spec section 4.1).
  Size get stickFigureSize => const Size(19, 20) * _s * scale;

  /// Reaction (smiley+plus) icon box — 22×19 at S=1 (spec section 4.2).
  Size get reactionIconSize => const Size(22, 19) * _s * scale;
}

class AnonPostCardClipper extends CustomClipper<Path> {
  const AnonPostCardClipper();

  // Traced cubic segments at S=1, each [c1x,c1y,c2x,c2y,x,y] — spec section
  // 2.5, copied verbatim. Do not hand-edit these numbers.
  static const List<List<double>> _dip = [
    [16.402, 0.125, 17.578, 0.469, 18.497, 0.748],
    [19.416, 1.027, 20.497, 1.282, 21.497, 1.673],
    [22.497, 2.064, 23.497, 2.585, 24.497, 3.096],
    [25.497, 3.606, 26.497, 4.114, 27.497, 4.735],
    [28.497, 5.355, 29.497, 6.155, 30.497, 6.818],
    [31.497, 7.481, 32.497, 8.154, 33.497, 8.71],
    [34.497, 9.267, 35.497, 9.783, 36.497, 10.155],
    [37.497, 10.526, 38.497, 10.784, 39.497, 10.941],
    [40.497, 11.097, 41.497, 11.079, 42.497, 11.092],
    [43.497, 11.105, 44.497, 11.178, 45.497, 11.018],
    [46.497, 10.858, 47.497, 10.592, 48.497, 10.134],
    [49.497, 9.676, 50.497, 8.942, 51.497, 8.27],
    [52.497, 7.599, 53.497, 6.809, 54.497, 6.107],
    [55.497, 5.404, 56.497, 4.682, 57.497, 4.055],
    [58.497, 3.429, 59.497, 2.833, 60.497, 2.348],
    [61.497, 1.863, 62.497, 1.439, 63.497, 1.145],
    [64.497, 0.852, 65.566, 0.779, 66.497, 0.588],
    [67.428, 0.397, 68.651, 0.098, 69.082, 0],
  ];

  static const List<List<double>> _tray = [
    [369.197, 229.938, 368.397, 229.728, 367.497, 228.988],
    [366.383, 227.93, 365.497, 225.619, 364.497, 223.719],
    [363.497, 221.819, 362.497, 219.088, 361.497, 217.589],
    [360.497, 216.09, 359.497, 215.47, 358.497, 214.727],
    [357.497, 213.984, 356.497, 213.524, 355.497, 213.129],
    [354.497, 212.734, 353.58, 212.498, 352.497, 212.358],
    [351.414, 212.218, 350.914, 212.301, 348.997, 212.29],
    [347.08, 212.279, 344.83, 212.29, 340.997, 212.29],
    [337.164, 212.29, 330.997, 212.29, 325.997, 212.29],
    [320.997, 212.29, 315.997, 212.29, 310.997, 212.29],
    [305.997, 212.29, 299.58, 212.289, 295.997, 212.29],
    [292.414, 212.291, 291.08, 212.179, 289.497, 212.294],
    [287.914, 212.409, 287.497, 212.641, 286.497, 212.978],
    [285.497, 213.316, 284.497, 213.695, 283.497, 214.319],
    [282.497, 214.943, 281.497, 215.471, 280.497, 216.725],
    [279.497, 217.979, 278.497, 220.296, 277.497, 221.845],
    [276.497, 223.394, 275.497, 224.946, 274.497, 226.019],
    [273.497, 227.092, 272.479, 227.608, 271.497, 228.282],
    [270.515, 228.956, 269.086, 229.768, 268.604, 230.065],
  ];

  /// Spec section 2.5's framePath(H), ported 1:1. Builds the path in the
  /// fixed 375.047-wide reference space at the given height — the dip
  /// scales from the top-left (nX/nY), the tray cut from the bottom-right
  /// (tX/tY); see spec section 2.4 for why those must NOT share an origin.
  static String _framePathData(double h) {
    final s = AnonPostCardGeometry.scaleFor(h);
    const w = AnonPostCardGeometry.refWidth;
    const h1 = AnonPostCardGeometry._h1;

    double nX(double x) => x * s;
    double nY(double y) => y * s;
    double tX(double x) => w - (w - x) * s;
    double tY(double y) => h - (h1 - y) * s;
    String f(double v) => v.toStringAsFixed(3);

    final tl = AnonPostCardGeometry._rTl * s;
    final tr = AnonPostCardGeometry._rTr * s;
    final br = AnonPostCardGeometry._rBr * s;
    final bl = AnonPostCardGeometry._rBl * s;

    final b = StringBuffer('M ${f(tl)} 0 H ${f(nX(15.983))}');
    for (final a in _dip) {
      b.write(
        ' C ${f(nX(a[0]))},${f(nY(a[1]))} ${f(nX(a[2]))},${f(nY(a[3]))} ${f(nX(a[4]))},${f(nY(a[5]))}',
      );
    }
    b.write(' H ${f(w - tr)} A ${f(tr)} ${f(tr)} 0 0 1 ${f(w)} ${f(tr)}');
    b.write(' V ${f(h - br)} A ${f(br)} ${f(br)} 0 0 1 ${f(w - br)} ${f(h)}');
    for (final a in _tray) {
      b.write(
        ' C ${f(tX(a[0]))},${f(tY(a[1]))} ${f(tX(a[2]))},${f(tY(a[3]))} ${f(tX(a[4]))},${f(tY(a[5]))}',
      );
    }
    b.write(' H ${f(bl)} A ${f(bl)} ${f(bl)} 0 0 1 0 ${f(h - bl)}');
    b.write(' V ${f(tl)} A ${f(tl)} ${f(tl)} 0 0 1 ${f(tl)} 0 Z');
    return b.toString();
  }

  @override
  Path getClip(Size size) {
    // The widget's own render size may not be exactly 375.047 wide — map
    // its height into that fixed reference width (preserving the real
    // aspect ratio being rendered) before generating the path, then scale
    // the whole result uniformly back up to actual pixels. In practice
    // this app only ever renders the portrait 4:5 ratio (refH ≈ 468.809),
    // but the generator itself stays correct for any ratio, per spec.
    final refH = size.height * AnonPostCardGeometry.refWidth / size.width;
    final path = parseSvgPathData(_framePathData(refH));
    final pixelScale = size.width / AnonPostCardGeometry.refWidth;
    return path.transform(
      Matrix4.diagonal3Values(pixelScale, pixelScale, 1.0).storage,
    );
  }

  @override
  bool shouldReclip(covariant AnonPostCardClipper old) => false;
}
