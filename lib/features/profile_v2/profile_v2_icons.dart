import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The two glyphs Profile v2 draws itself.
///
/// Everything else in the design maps cleanly onto Material icons, but the ping
/// mark and the anon mask are brand marks — substituting a stock icon changes
/// what the screen says, so they are transcribed from the canvas SVG paths.

// ---------------------------------------------------------------------------
// Ping
// ---------------------------------------------------------------------------

/// The ping mark: a standing figure inside a ring. Transcribed from the
/// canvas's 32×32 viewBox.
class PingGlyph extends StatelessWidget {
  const PingGlyph({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 2.1,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PingPainter(color, strokeWidth)),
    );
  }
}

class _PingPainter extends CustomPainter {
  const _PingPainter(this.color, this.strokeWidth);

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32; // canvas viewBox is 0 0 32 32
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Ring.
    canvas.drawCircle(Offset(16 * s, 16 * s), 13 * s, stroke);
    // Head.
    canvas.drawCircle(Offset(16 * s, 10.6 * s), 2 * s, fill);

    // Shoulders — a shallow curve across the figure.
    final shoulders = Path()
      ..moveTo(10 * s, 14.2 * s)
      ..relativeCubicTo(1.9 * s, 0.85 * s, 3.9 * s, 1.28 * s, 6 * s, 1.28 * s)
      ..relativeCubicTo(2.1 * s, 0, 4.1 * s, -0.43 * s, 6 * s, -1.28 * s);
    canvas.drawPath(shoulders, stroke);

    // Torso and legs.
    final body = Path()
      ..moveTo(16 * s, 15.48 * s)
      ..lineTo(16 * s, 19.18 * s)
      ..moveTo(16 * s, 19.18 * s)
      ..lineTo(13.4 * s, 23.58 * s)
      ..moveTo(16 * s, 19.18 * s)
      ..lineTo(18.6 * s, 23.58 * s);
    canvas.drawPath(body, stroke);
  }

  @override
  bool shouldRepaint(_PingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

// ---------------------------------------------------------------------------
// Anon mask
// ---------------------------------------------------------------------------

/// The anon mark: a domino mask — a rounded bar with two eye holes punched
/// through it. The holes are cut with [PathFillType.evenOdd] rather than
/// painted in the surface colour, so the glyph composites correctly over any
/// background (it sits on both [PV2.recessed] wells and darker avatar wells).
class AnonMaskGlyph extends StatelessWidget {
  const AnonMaskGlyph({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AnonMaskPainter(color)),
    );
  }
}

class _AnonMaskPainter extends CustomPainter {
  const _AnonMaskPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // canvas viewBox is 0 0 24 24
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * s, 9 * s, 18 * s, 6.5 * s),
        Radius.circular(3.25 * s),
      ),
    );
    path.addOval(
      Rect.fromCircle(center: Offset(8.5 * s, 12.2 * s), radius: 1.5 * s),
    );
    path.addOval(
      Rect.fromCircle(center: Offset(15.5 * s, 12.2 * s), radius: 1.5 * s),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AnonMaskPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Stock glyph shorthands
// ---------------------------------------------------------------------------

/// Thin wrappers so screens read as the design does, and so the stroke weight
/// stays consistent wherever a given mark appears.
class PV2Icons {
  PV2Icons._();

  static Widget lock(double size, Color color) =>
      Icon(Icons.lock_outline_rounded, size: size, color: color);

  static Widget streak(double size, Color color) =>
      Icon(Icons.local_fire_department_rounded, size: size, color: color);

  /// The ICE FLAME — the glyph every RELATIONSHIP (blue) streak uses.
  ///
  /// Built from the actual approved design (Claude Design project
  /// "Emoji color change request" / Blue Flame.dc.html), read via
  /// DesignSync once design-system access was authorised. Its technique is
  /// literal: take the real 🔥 emoji and apply a CSS
  /// `hue-rotate() saturate() brightness()` filter chain — the design's own
  /// note is explicit that "the blue lives in the styling", not in a
  /// different glyph.
  ///
  /// The file ships a hero plus four labelled swatches. This uses the HERO
  /// — `hue-rotate(185deg) saturate(1.4) brightness(1.05)`, its prop
  /// defaults — reproduced exactly via [_hueRotateSaturateBrightness].
  /// The swatches (ice 170/1.1/1.25, cyan 185/1.6/1.05, cobalt
  /// 215/1.8/0.95, indigo 240/1.7/0.85) are alternatives, not the approved
  /// mark; the name `iceFlame` predates reading the file and is kept only
  /// so call sites don't churn.
  ///
  /// An earlier version of this glyph redrew the flame as a vector icon
  /// with a manual blue gradient — a reasonable guess made before the
  /// design file was reachable, but not what was actually approved, and
  /// visibly a different shape from the 🔥 everyone already recognises.
  /// This replaces it.
  ///
  /// The warm [streak] glyph above is still used for the RED personal anon
  /// streak — two streak families, two glyphs, no ambiguity about which
  /// number you're reading.
  static Widget iceFlame(double size) => ColorFiltered(
        colorFilter: ColorFilter.matrix(
          // Blue Flame.dc.html's HERO filter — its `hue`/`saturation`/
          // `brightness` prop defaults (185 / 1.4 / 1.05), which is what the
          // file renders as the thing actually labelled "blue flame".
          //
          // This used to be 170 / 1.1 / 1.25, which is that file's separate
          // "ice" SWATCH, not its hero — so every blue flame in the app was
          // rendering the wrong one of the four swatches. Corrected against
          // the design rather than eyeballed.
          _hueRotateSaturateBrightness(
            hueDeg: 185,
            saturation: 1.4,
            brightness: 1.05,
          ),
        ),
        child: Text('🔥', style: TextStyle(fontSize: size, height: 1)),
      );

  /// The Us-album streak mark: the count printed ON TOP of the ice flame
  /// itself, Snapchat-style — not beside it in a pill like [StreakFlamePill]
  /// (profile_v2_widgets.dart). This is Blue Flame.dc.html's own primary
  /// layout, not a variant of it: the file's hero shows exactly this —
  /// `{{ streak }}` absolutely positioned at top:58%/left:50% over a 220px
  /// flame at font-size 60, font-weight 900, in BLACK (#000000) with no
  /// shadow or stroke — the file sets `text-shadow: none` and
  /// `-webkit-text-stroke: 0`, so the number reads as a cutout in the
  /// flame's bright middle rather than a label over it. Every ratio below
  /// (number size = flame size × 0.2727, centre at 58%/50%, weight 900) is
  /// taken directly from that file rather than eyeballed.
  ///
  /// [flameSize] is the emoji's font-size — the design's own 220px hero.
  /// Sizes down cleanly for feed-card use (see design_solo_card.dart).
  /// [showZero] draws the flame with a "0" instead of nothing — for a slot
  /// that must not change size or appear late (the Duo post avatar).
  static Widget blueFlameStreak(
    int count, {
    double flameSize = 44,
    bool showZero = false,
  }) {
    if (count <= 0 && !showZero) return const SizedBox.shrink();
    if (count < 0) count = 0;
    // The design's own 220px hero has plenty of room for a number at 25.5%
    // of the flame's size, but a small on-corner badge (e.g. the 20-28px
    // size used on an avatar in design_solo_card.dart) does not — the same
    // ratio there rounds to a 5-7px digit, which renders but is not
    // actually legible on a phone screen. Floored at 11px so the count
    // stays readable at every size this app uses it at, matching every
    // other small count label (StreakFlamePill, SeenPill) in this file's
    // own size range.
    return _flameStreak(count, iceFlame(flameSize), flameSize, numberColor: Colors.black);
  }

  /// Shared overlay layout for [blueFlameStreak] — the personal anon streak
  /// this used to pair with (redFlameStreak) was removed with that feature.
  static Widget _flameStreak(
    int count,
    Widget flame,
    double flameSize, {
    required Color numberColor,
  }) {
    // Ratios taken literally from Blue Flame.dc.html's hero:
    //   font-size 60 on a 220px flame          -> 0.2727
    //   top: 58% with translate(-50%, -50%)    -> centre at 0.58, so the
    //                                             box top is 0.58 - half
    //   font-weight 900
    // Previously 0.255 / 0.56 / w800, which were close but not the file's
    // own numbers. The 11px floor below is NOT from the design and stays
    // deliberately — see blueFlameStreak's doc.
    // The 11px floor made the digit 42% of a 26px feed badge (vs the
    // design's 27%), so it overflowed the flame's pale core and sat over
    // the dark tip instead — reported as the number not being "in the
    // flames white region". 9.5 keeps it legible at feed size while
    // bringing the ratio back near the design's, so the digit lands inside
    // the core rather than below it.
    //
    // BUG FIX: the SAME overflow, again, at ping_page.dart's 22px badge —
    // 9.5/22 = 43%, worse than the 26px case this floor was tuned for
    // (9.5/26 = 36.5%), so the digit spilled past the flame's visible
    // edge. Reported as "shall come exactly inside the white part of the
    // flame not outside". 8.0 holds every existing call site at or below
    // that already-accepted 36.5% ceiling — 22px -> 36.4%, 26px -> 30.8%
    // (tighter, still fine), 34px -> 27.3% (the ratio itself takes over,
    // exactly the design's own number).
    final numberSize = math.max(flameSize * 0.2727, 8.0);
    return SizedBox(
      width: flameSize,
      height: flameSize,
      child: Stack(
        // The flame glyph itself must stay centred in the box exactly as
        // before — only the digit gets an explicit left/top override
        // below. Dropping this (as an earlier pass here did) re-anchors
        // the flame to Stack's default topStart instead, which silently
        // moves the WHOLE glyph and invalidates every measurement taken
        // against its rendered position.
        alignment: Alignment.center,
        children: [
          flame,
          Positioned(
            // BOTH axes measured directly off a live screenshot of this
            // exact badge (ping_page.dart's 22px avatar flame, physically
            // 72.25px on the 3x/448-logical-width test device — computed
            // from the SAME Scale formula this call site uses, not
            // guessed), by pixel-scanning the rendered PNG for the
            // near-white core (all channels > 220) and taking its mass
            // CENTROID — the true visual centre of the bright region,
            // which a teardrop shape's bounding-box midpoint is not.
            //
            // Two rounds were needed. Round 1 (0.637/0.86) fixed the
            // vertical miss but undershot horizontally — re-verified on
            // device against a fresh screenshot, the digit's own rendered
            // centre still sat left of the core's true centroid by ~11% of
            // flameSize (measured, not eyeballed: 116.9px vs 109.0px in
            // the same screenshot's pixel-coordinate frame). That 11%
            // shift is the correction applied on TOP of round 1, not a
            // fresh guess — see the arithmetic this comment describes:
            // new_fraction = old_fraction + (target_px - measured_px) /
            // flameSize_px, which is exact because this Positioned's
            // left/top already reduce to `flameSize * fraction` once the
            // `- numberSize * 0.5` centering term cancels out.
            left: flameSize * 0.746 - numberSize * 0.5,
            top: flameSize * 0.715 - numberSize * 0.5,
            child: Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: numberSize,
                color: numberColor,
                height: 1,
                shadows: numberColor == Colors.black
                    ? null
                    : const [
                        Shadow(color: Color(0x80000000), blurRadius: 3, offset: Offset(0, 1)),
                      ],
                // Text has no native stroke property; foreground+shadow
                // above approximates the design's -webkit-text-stroke well
                // enough at these small on-card sizes — a literal stroke
                // would need a second Text painted behind this one. Not
                // used for the black number: a dark shadow reads as a
                // smudge rather than a stroke against the black itself.
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// CSS `filter: hue-rotate(hueDeg) saturate(saturation)
  /// brightness(brightness)`, composed in that same left-to-right order (a
  /// applies first, feeding b, feeding c) and returned as a Skia colour
  /// matrix. The hue-rotate term is the W3C Filter Effects spec's
  /// `feColorMatrix type="hueRotate"` formula — the exact matrix a browser
  /// evaluates for the CSS function of the same name, which is what makes
  /// this reproduce the design file's swatch precisely rather than
  /// approximately.
  static List<double> _hueRotateSaturateBrightness({
    required double hueDeg,
    required double saturation,
    required double brightness,
  }) {
    final a = hueDeg * math.pi / 180;
    final cosA = math.cos(a);
    final sinA = math.sin(a);
    // hue-rotate
    var m = [
      0.213 + cosA * 0.787 - sinA * 0.213,
      0.715 - cosA * 0.715 - sinA * 0.715,
      0.072 - cosA * 0.072 + sinA * 0.928,
      0.213 - cosA * 0.213 + sinA * 0.143,
      0.715 + cosA * 0.285 + sinA * 0.140,
      0.072 - cosA * 0.072 - sinA * 0.283,
      0.213 - cosA * 0.213 - sinA * 0.787,
      0.715 - cosA * 0.715 + sinA * 0.715,
      0.072 + cosA * 0.928 + sinA * 0.072,
    ];
    // saturate — scales the same 3x3 the hue-rotate matrix already is.
    const lumR = 0.213, lumG = 0.715, lumB = 0.072;
    final sat = [
      lumR + (1 - lumR) * saturation,
      lumG * (1 - saturation),
      lumB * (1 - saturation),
      lumR * (1 - saturation),
      lumG + (1 - lumG) * saturation,
      lumB * (1 - saturation),
      lumR * (1 - saturation),
      lumG * (1 - saturation),
      lumB + (1 - lumB) * saturation,
    ];
    // Compose saturate ∘ hueRotate (apply hue-rotate first, its output
    // feeds saturate), matching CSS's left-to-right filter order.
    final c = List<double>.filled(9, 0);
    for (var r = 0; r < 3; r++) {
      for (var col = 0; col < 3; col++) {
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          sum += sat[r * 3 + k] * m[k * 3 + col];
        }
        c[r * 3 + col] = sum;
      }
    }
    m = c;
    // brightness — a flat post-multiply, last in the CSS chain.
    return [
      m[0] * brightness, m[1] * brightness, m[2] * brightness, 0, 0,
      m[3] * brightness, m[4] * brightness, m[5] * brightness, 0, 0,
      m[6] * brightness, m[7] * brightness, m[8] * brightness, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  static Widget globe(double size, Color color) =>
      Icon(Icons.public_rounded, size: size, color: color);

  static Widget camera(double size, Color color) =>
      Icon(Icons.photo_camera_outlined, size: size, color: color);

  static Widget image(double size, Color color) =>
      Icon(Icons.image_outlined, size: size, color: color);

  static Widget plus(double size, Color color) =>
      Icon(Icons.add_rounded, size: size, color: color);

  static Widget back(double size, Color color) =>
      Icon(Icons.chevron_left_rounded, size: size, color: color);

  static Widget more(double size, Color color) =>
      Icon(Icons.more_horiz_rounded, size: size, color: color);

  static Widget send(double size, Color color) =>
      Icon(Icons.send_rounded, size: size, color: color);

  static Widget message(double size, Color color) =>
      Icon(Icons.chat_bubble_outline_rounded, size: size, color: color);

  static Widget settings(double size, Color color) =>
      Icon(Icons.settings_outlined, size: size, color: color);

  static Widget edit(double size, Color color) =>
      Icon(Icons.edit_outlined, size: size, color: color);

  static Widget addPeople(double size, Color color) =>
      Icon(Icons.person_add_alt_1_outlined, size: size, color: color);

  static Widget place(double size, Color color) =>
      Icon(Icons.place_outlined, size: size, color: color);

  static Widget verified(double size, Color color) =>
      Icon(Icons.verified_rounded, size: size, color: color);

  static Widget block(double size, Color color) =>
      Icon(Icons.block_rounded, size: size, color: color);

  static Widget report(double size, Color color) =>
      Icon(Icons.flag_outlined, size: size, color: color);

  static Widget close(double size, Color color) =>
      Icon(Icons.close_rounded, size: size, color: color);
}
