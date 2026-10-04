import 'dart:math' as math;

import 'package:flutter/rendering.dart';

// ---------------------------------------------------------------------------
// Anon feed post card frame — locked 4:5 shape with an avatar-seat dip on
// the top edge and a tray cutout on the bottom edge. Direct translation of
// the spec's §14.2 `framePath(H)` JS generator — see that section for the
// original source; this file mirrors its structure 1:1 (same constant
// names, same segment tables, same per-edge scale functions) so the two
// can be diffed against each other if the spec ever changes.
//
// §7.2's resolved path (for H = 468.809) is reproduced as a literal test
// fixture in anon_frame_clipper_test.dart-style comments below each
// section, not inline here — verify by rendering, not by re-deriving.
// ---------------------------------------------------------------------------

const double kCardDesignWidth = 375.047;
const double _h1 = 230.065; // reference height the DIP/TRAY tables were authored against

class _CornerRadii {
  const _CornerRadii({required this.tl, required this.tr, required this.br, required this.bl});
  final double tl, tr, br, bl;
}

const _baseRadii = _CornerRadii(tl: 12.68, tr: 25.92, br: 5.13, bl: 26.2);

/// Top-edge dip (avatar seat) — 18 cubic segments, each
/// [c1x, c1y, c2x, c2y, x, y] in the H1 = 230.065 reference space, x
/// measured from the card's left edge (origin).
const List<List<double>> _dip = [
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

/// Bottom-edge tray cutout — 19 cubic segments, right→left, each
/// [c1x, c1y, c2x, c2y, x, y] in H1 space, x/y measured from the CARD's
/// own origin (not yet offset to bottom-right — see `_trayX`/`_trayY`).
const List<List<double>> _tray = [
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

/// The same `s` scale factor the clipper uses internally for a given
/// rendered card [height] — exposed so callers positioning things AGAINST
/// the frame (persona avatar, tray icons) can derive their own geometry
/// from this one source of truth instead of hand-measuring pixel offsets
/// tuned to a single fixed height, which silently go stale the moment the
/// card's design height changes.
double anonCardScaleFor(double height) => math.sqrt(height / _h1);

/// The dip's own peak — segment index 8 of [_dip] (x=42.497, y=11.092 in
/// the h1 reference, the deepest point of the avatar's seat), scaled to
/// [height]. The persona avatar centres itself on this point: horizontally
/// on `.dx`, and its bottom edge sits at a fixed fraction of `.dy` (see
/// _PersonaAvatar's own doc in anon_feed_screen.dart for that ratio).
Offset anonCardDipPeak(double height) {
  final s = anonCardScaleFor(height);
  return const Offset(42.497, 11.092) * s;
}

/// The tray cutout's own endpoint-to-endpoint span, scaled to [height] — x
/// runs from [_tray]'s last row (268.604, left) to its first row (367.497,
/// right). `_TrayIcons` centres its ping/moji row on this span's midpoint
/// — see anon_feed_screen.dart's own derivation notes at that call site.
({double left, double right, double centerX}) anonCardTraySpan(double height) {
  final s = anonCardScaleFor(height);
  const w = kCardDesignWidth;
  double trayX(double x) => w - (w - x) * s;
  final left = trayX(268.604);
  final right = trayX(367.497);
  return (left: left, right: right, centerX: (left + right) / 2);
}

/// The tray cutout's flat inner-top edge Y, scaled to [height] — the
/// baseline `_TrayIcons` sits against (with a small intentional overlap
/// past the notch, same as before — see that widget's own doc).
double anonCardTrayInnerTopY(double height) {
  final s = anonCardScaleFor(height);
  const flatY = 212.29; // h1-space y of the tray's flat inner edge
  return height - (_h1 - flatY) * s;
}

/// Builds the post-card frame path for a given rendered card [height], per
/// §14.2's `framePath(H)`. Width is always [kCardDesignWidth] (locked 4:5
/// with the dip/tray applied only to height-dependent geometry — see the
/// scale factor S below, which scales corner radii and dip/tray offsets
/// but NOT the card width itself, matching the JS source exactly).
Path buildAnonCardFramePath(double height) {
  final s = math.sqrt(height / _h1);
  const w = kCardDesignWidth;

  final tl = _baseRadii.tl * s;
  final tr = _baseRadii.tr * s;
  final br = _baseRadii.br * s;
  final bl = _baseRadii.bl * s;

  // Dip: scaled from the card's own top-left origin.
  double dipX(double x) => x * s;
  double dipY(double y) => y * s;

  // Tray: scaled from the card's bottom-right corner inward, per the JS
  // source's `tX`/`tY` — NOT the same origin as the dip.
  double trayX(double x) => w - (w - x) * s;
  double trayY(double y) => height - (_h1 - y) * s;

  final path = Path()..moveTo(tl, 0);
  path.lineTo(dipX(15.983), 0);
  for (final seg in _dip) {
    path.cubicTo(
      dipX(seg[0]), dipY(seg[1]),
      dipX(seg[2]), dipY(seg[3]),
      dipX(seg[4]), dipY(seg[5]),
    );
  }
  path.lineTo(w - tr, 0);
  path.arcToPoint(Offset(w, tr), radius: Radius.circular(tr), clockwise: true);
  path.lineTo(w, height - br);
  path.arcToPoint(Offset(w - br, height), radius: Radius.circular(br), clockwise: true);
  for (final seg in _tray) {
    path.cubicTo(
      trayX(seg[0]), trayY(seg[1]),
      trayX(seg[2]), trayY(seg[3]),
      trayX(seg[4]), trayY(seg[5]),
    );
  }
  path.lineTo(bl, height);
  path.arcToPoint(Offset(0, height - bl), radius: Radius.circular(bl), clockwise: true);
  path.lineTo(0, tl);
  path.arcToPoint(Offset(tl, 0), radius: Radius.circular(tl), clockwise: true);
  path.close();
  return path;
}

class AnonCardFrameClipper extends CustomClipper<Path> {
  const AnonCardFrameClipper();

  @override
  Path getClip(Size size) => buildAnonCardFramePath(size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
