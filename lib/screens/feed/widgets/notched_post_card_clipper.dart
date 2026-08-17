import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Ported 1:1 from the design handoff's CSS clip-path geometry:
// design-refs/design_handoff_notched_post_card/ (README.md has the math,
// "Notched Post Card.dc.html" has the reference implementation). That
// handoff is the authoritative source of truth for this shape — see the
// README's "Fidelity" note: small deviations in the dip are immediately
// visible, so this is a direct translation, not a re-derivation.
//
// The reference box is 380 (w) wide; every plain px constant below (corner
// radius, dip depth, notch width, etc.) is scaled by `scale = actual width
// / 380` so the same proportions hold at any rendered card size. TWO
// values are deliberately NOT derived from that scale:
//   - `avatarRadius` — the real radius of our persona icon widget, not the
//     reference's 17px placeholder avatar.
//   - `notchCenterX` — the real horizontal position of our ping+reaction
//     icon cluster, not the reference's fixed 300/380 fraction.
//
// `NotchedDipGeometry.compute` is the single source of truth for the TOP
// dip's numbers (cx, x0, x1, ...). `NotchedPostCardClipper` (the image's
// clip-path) and PhotoPostCard's header row (which needs `inset` to line
// the avatar up exactly above the dip it sinks into) both call this same
// function — that's what stops the two from drifting apart, which is what
// broke across recent edits before this handoff.
// ---------------------------------------------------------------------------

class NotchedDipGeometry {
  const NotchedDipGeometry({
    required this.scale,
    required this.d,
    required this.inset,
    required this.cx,
    required this.x0,
    required this.x1,
    required this.rtl,
    required this.hwL,
    required this.hwR,
  });

  /// actualWidth / [refWidth] — every reference px constant is multiplied
  /// by this to scale proportionally to the real rendered card.
  final double scale;

  final double d; // dip depth
  final double inset; // dip centre offset from the box's left edge
  final double cx; // dip centre x
  final double x0; // left foot of the dip
  final double x1; // right foot of the dip (mirrors x0 about cx)
  final double rtl; // shrunk top-left corner radius, meeting the dip smoothly
  final double hwL;
  final double hwR;

  /// Width of the reference design's box (design-refs handoff). Not a
  /// hardcoded card size — just the denominator the handoff's constants
  /// were authored against, used to derive [scale].
  static const double refWidth = 380;

  factory NotchedDipGeometry.compute({
    required double width,
    required double avatarRadius,
    required double cardRadius,
    required double avatarOverlap,
    required double avatarHaloGap,
  }) {
    final scale = width / refWidth;
    final r = cardRadius * scale;
    final overlap = avatarOverlap * scale;
    final gap = avatarHaloGap * scale;
    final av = avatarRadius; // real value — not scaled again

    final d = overlap + gap + 2 * scale;
    final halfR = av + gap + _max(16 * scale, d * 1.35);
    final inset = _max3(24 * scale, r + 16 * scale, r + 2 * scale + halfR - av) - 18 * scale;
    final cx = inset + av;
    final x0 = _max(7 * scale, cx - (av + gap + 10 * scale));
    final x1 = cx + (cx - x0); // mirrors x0 about cx — symmetric dip
    final rtl = _max(6 * scale, _min(r, x0 - 2 * scale));
    final hwL = (cx - x0) * 0.9;
    final hwR = (x1 - cx) * 0.82;

    return NotchedDipGeometry(
      scale: scale,
      d: d,
      inset: inset,
      cx: cx,
      x0: x0,
      x1: x1,
      rtl: rtl,
      hwL: hwL,
      hwR: hwR,
    );
  }

  static double _max(double a, double b) => a > b ? a : b;
  static double _min(double a, double b) => a < b ? a : b;
  static double _max3(double a, double b, double c) => _max(a, _max(b, c));
}

/// The image container's clip-path: a smooth concave dip in the top edge
/// (the avatar sinks into it) and a scallop notch in the bottom edge (the
/// ping + reaction icons sit in it), cut by one continuous path — exactly
/// as specced in design-refs/design_handoff_notched_post_card/README.md.
class NotchedPostCardClipper extends CustomClipper<Path> {
  const NotchedPostCardClipper({
    required this.avatarRadius,
    required this.notchCenterX,
    this.cardRadius = 22,
    this.avatarOverlap = 9,
    this.avatarHaloGap = 7,
    this.iconOverhang = 20,
    this.dipSmoothness = 22,
    this.bottomNotch = true,
  });

  /// Real radius of our persona icon (not the reference's 17px placeholder).
  final double avatarRadius;

  /// Real x position (local to this clip box) the bottom notch is centred
  /// on — the actual position of our ping+reaction icon cluster. Unused
  /// when [bottomNotch] is false.
  final double notchCenterX;

  /// Whether to cut the bottom scallop notch at all — false gives a plain
  /// rounded bottom edge (no notch, no icon overhang), for cards whose
  /// action icons have moved off the image entirely. The top dip is
  /// unaffected either way.
  final bool bottomNotch;

  /// R — outer corner radius (reference default 22).
  final double cardRadius;

  /// overlap — px the avatar sinks into the image (reference default 9).
  final double avatarOverlap;

  /// gap — clear halo ring around the avatar (reference default 7).
  final double avatarHaloGap;

  /// over — how far the icon cluster hangs below the bottom edge
  /// (reference default 20).
  final double iconOverhang;

  /// s — dipSmoothness in the reference handoff. Kept for parity with the
  /// design's exposed prop; the upstream geometry itself never actually
  /// reads it (dead in the source handoff too), so it's unused here as
  /// well — not an omission.
  final double dipSmoothness;

  /// halfTop + rampW (both scaled) — how far the notch's shoulders reach
  /// out from [notchCenterX] on EITHER side, regardless of how wide the
  /// actual icon cluster sitting in it is (the ramps are a fixed
  /// decorative width from the reference handoff, not derived from
  /// cluster size). `notchCenterX` must stay at least this far from BOTH
  /// edges of the clip box, or `footL`/`footR` run past the box and the
  /// path self-intersects — which renders as an empty/garbled clip, not
  /// an error, so this is easy to silently break. Exposed so callers can
  /// clamp their own notchCenterX against it instead of guessing.
  static double notchHalfReach(double width) =>
      (44 + 24) * (width / NotchedDipGeometry.refWidth);

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;

    final geo = NotchedDipGeometry.compute(
      width: w,
      avatarRadius: avatarRadius,
      cardRadius: cardRadius,
      avatarOverlap: avatarOverlap,
      avatarHaloGap: avatarHaloGap,
    );
    final scale = geo.scale;
    final d = geo.d, cx = geo.cx, x0 = geo.x0, x1 = geo.x1;
    final rtl = geo.rtl, hwL = geo.hwL, hwR = geo.hwR;

    final r = cardRadius * scale;

    // --- bottom notch (only when bottomNotch is true) ---
    double rbr = r;
    double nh = 0, tL = 0, tR = 0, footL = 0, footR = 0, rc = 0;
    if (bottomNotch) {
      final over = iconOverhang * scale;
      nh = NotchedDipGeometry._max(14 * scale, 39 * scale - over);
      final halfTop = 44 * scale;
      final rampW = 24 * scale;
      final reach = halfTop + rampW;
      // Clamped defensively even though callers are expected to clamp too —
      // an un-clamped notchCenterX near either edge produces a
      // self-intersecting path (negative Rbr, or footL < 0) that silently
      // renders as an empty clip rather than throwing. `hi` can't be let
      // dip below `reach` itself (an image narrower than 2*reach), which
      // would otherwise make clamp's bounds invalid and throw for real.
      final hi = w - reach < reach ? reach : w - reach;
      final cxN = notchCenterX.clamp(reach, hi);
      tL = cxN - halfTop;
      tR = cxN + halfTop;
      footL = tL - rampW;
      footR = tR + rampW;
      rc = rampW * 0.5;
      rbr = w - footR;
    }

    // M x0,2
    final path = Path()
      ..moveTo(x0, 2 * scale)
      // C (x0+hwL*0.55),(D*0.3) (cx-10),D cx,D  — left wall into the trough
      ..cubicTo(x0 + hwL * 0.55, d * 0.3, cx - 10 * scale, d, cx, d)
      // C (cx+10),D (x1-hwR*0.55),(D*0.3) x1,2  — right wall, mirrors the left
      ..cubicTo(cx + 10 * scale, d, x1 - hwR * 0.55, d * 0.3, x1, 2 * scale)
      // C (x1+8),1.8 (x1+22),0 (x1+38),0  — tiny convex crest after the dip
      ..cubicTo(x1 + 8 * scale, 1.8 * scale, x1 + 22 * scale, 0, x1 + 38 * scale, 0)
      // H (W-R)
      ..lineTo(w - r, 0)
      // Q W,0 W,R
      ..quadraticBezierTo(w, 0, w, r)
      // V (H-Rbr)
      ..lineTo(w, h - rbr)
      // Q W,H (W-Rbr),H
      ..quadraticBezierTo(w, h, w - rbr, h);

    if (bottomNotch) {
      path
        // H footR
        ..lineTo(footR, h)
        // C footR-rc,H tR+rc,H-NH tR,H-NH — right S ramp up into the notch
        ..cubicTo(footR - rc, h, tR + rc, h - nh, tR, h - nh)
        // H tL — flat notch top
        ..lineTo(tL, h - nh)
        // C tL-rc,H-NH footL+rc,H footL,H — left S ramp down, mirror
        ..cubicTo(tL - rc, h - nh, footL + rc, h, footL, h)
        // H R
        ..lineTo(r, h);
    } else {
      // Plain straight bottom edge — no notch.
      path.lineTo(r, h);
    }

    path
      // Q 0,H 0,H-R
      ..quadraticBezierTo(0, h, 0, h - r)
      // V (Rtl*1.9)
      ..lineTo(0, rtl * 1.9)
      // C 0,(Rtl*0.75) (x0-hwL*0.5),2 x0,2 — shoulder levels out exactly at the dip start
      ..cubicTo(0, rtl * 0.75, x0 - hwL * 0.5, 2 * scale, x0, 2 * scale)
      ..close();

    return path;
  }

  @override
  bool shouldReclip(covariant NotchedPostCardClipper old) =>
      old.avatarRadius != avatarRadius ||
      old.notchCenterX != notchCenterX ||
      old.cardRadius != cardRadius ||
      old.avatarOverlap != avatarOverlap ||
      old.avatarHaloGap != avatarHaloGap ||
      old.iconOverhang != iconOverhang ||
      old.bottomNotch != bottomNotch;
}
