import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Design tokens for the Anon feed spec — §1 (typography), §2 (color),
// §13.2 (motion curves). Every literal value here is transcribed directly
// from the spec, not approximated — cross-reference by section/token name
// in comments so a future diff against a spec revision is mechanical.
// ---------------------------------------------------------------------------

/// §0 — design canvas is 660px wide; every spec dimension scales by this
/// factor against the real device width. Apply to EVERY numeric layout
/// value (padding, font size, radii, icon size) pulled from the spec.
const double kAnonDesignWidth = 660.0;
double anonScale(BuildContext context) => MediaQuery.of(context).size.width / kAnonDesignWidth;

// ---------------------------------------------------------------------------
// §2.1 Surfaces
// ---------------------------------------------------------------------------

class AnonFeedColors {
  AnonFeedColors._();

  static const screenBg = Color(0xFF0B0B0D);
  static const promptBarBg = Color(0xFF16161A);
  static const sheetBg = Color(0xFF131317);
  static const popoverBg = Color(0xFF17171B);
  static const peekBg = Color(0xFF141418);
  static const tabBarBg = Color(0xEB202024); // rgba(32,32,36,0.92)
  static const chipLight = Color(0xFFF5F4F1);
  static const trayBg = Color(0xE60E0E11); // rgba(14,14,17,0.90)
  static const countPillBg = Color(0x80101012); // rgba(16,16,18,0.50)
  static const mojiIdleDisc = Color(0xFF16161A);
  static const pingDisc = Color(0xFFFFFFFF);
  static const avatarSeat = Color(0xFFEFE9DC);

  // §2.2 Text
  static const inkOnLight = Color(0xFF0B0B0D);
  static const inkOnLightAlt = Color(0xFF17150F);
  static const textPrimary = Color(0xFFF5F4F1);
  static const textPeek = Color(0xFFDAD7D0);
  static const textCommentName = Color(0xFFE4E1DA);
  static const textBody = Color(0xFFC9C5BC);
  static const textOptionIdle = Color(0xFFB5B1A9);
  static const textTime = Color(0xFFA9A49A);
  static const textReplies = Color(0xFFA5A29A);
  static const textMuted = Color(0xFF8B8880);
  static const textDim = Color(0xFF7D7A74);
  static const textDimmer = Color(0xFF6F6C66);
  static const textFaint = Color(0xFF55524D);
  static const textFaintest = Color(0xFF4A4844);
  static const iconStroke = Color(0xFFB5B1A9);
  static const chevronStroke = Color(0xFF6B6862);
  static const strokeDark = Color(0xFF1C1C1E);

  // §2.3 Accents
  static const accentCyan = Color(0xFF29D3E8);
  static const accentCyanGlow = Color(0x8C29D3E8); // 0.55
  static const accentCyanWell = Color(0x1F29D3E8); // 0.12
  static const accentCyanWellBorder = Color(0x4D29D3E8); // 0.30
  static const accentCyanRowBg = Color(0x1A29D3E8); // 0.10
  static const accentCyanRowBorder = Color(0x6B29D3E8); // 0.42
  static const danger = Color(0xFFF0705E);

  // §2.4 Borders & hairlines
  static const hairlineStrong = Color(0x1AFFFFFF); // 0.10
  static const hairlinePromptBar = Color(0x14FFFFFF); // 0.08
  static const hairlineTabBar = Color(0x17FFFFFF); // 0.09
  static const hairlineTray = Color(0x24FFFFFF); // 0.14
  static const hairlineCountPill = Color(0x2EFFFFFF); // 0.18
  static const chipRingWhite = Color(0xE6FFFFFF); // 0.90
  static const mojiRingIdle = Color(0x29FFFFFF); // 0.16
  static const mojiRingActive = chipLight;
  static const radioIdle = Color(0x38FFFFFF); // 0.22
  static const avatarRing = screenBg;
  static const viewerDotRing = chipLight;

  // §2.5 Translucent fills
  static const fillRowIdle = Color(0x0CFFFFFF); // 0.045
  static const fillButtonGhost = Color(0x0FFFFFFF); // 0.06
  static const fillField = Color(0x12FFFFFF); // 0.07
  static const fillDisabled = Color(0x17FFFFFF); // 0.09
  static const fillTabActive = Color(0x21FFFFFF); // 0.13
  static const fillHandle = Color(0x2EFFFFFF); // 0.18
  static const scrimComments = Color(0x8C000000); // 0.55
  static const scrimSheet = Color(0x99000000); // 0.60

  // §2.6 Persona palette — assign deterministically by persona hash.
  static const personaPalette = <Color>[
    Color(0xFFC3B9A6), // quietmoon
    Color(0xFFA8BFA4), // paper.crane
    Color(0xFFC6C0D2), // ringer_02
    Color(0xFFB4BEC6), // no.name.7
    Color(0xFFCFC0B4), // slow.tide
    Color(0xFFC9BFB2), // extra
    Color(0xFFBCC7B6), // extra
  ];

  static Color personaColorFor(String seed) =>
      personaPalette[seed.hashCode.abs() % personaPalette.length];

  /// The persona glyph's ink — drawn on top of a [personaPalette] fill.
  /// The palette is all light, close-toned pastels (greige/sage/lavender,
  /// all ~75-85% luminance), and the glyph used to draw at 0xFFA39C8F — a
  /// mid-tone taupe close enough to EVERY one of those fills that a 2.4px
  /// stroke nearly vanished into the circle behind it. Reported as "the
  /// poster dp isn't visible": the circle was there, the identifying mark
  /// inside it wasn't. A near-black ink guarantees strong contrast against
  /// all seven palette colors at once, rather than picking a per-color
  /// value — every fill here is light, so one dark ink always works.
  static const personaGlyphInk = Color(0xFF2B2822);

  static const liveChipDots = [Color(0xFFC3B9A6), Color(0xFFC6C0D2), Color(0xFFA8BFA4)];
  static const reactionChipFills = [Color(0xFFF0E7D5), Color(0xFFF2DED4)];
}

// ---------------------------------------------------------------------------
// §1.4 Type scale — every text node, T1–T36. Font family always 'Manrope'.
// ---------------------------------------------------------------------------

class AnonFeedType {
  AnonFeedType._();

  static TextStyle _m({
    required double size,
    required FontWeight weight,
    double height = 1.2,
    double letterSpacing = 0,
    required Color color,
  }) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  // Bumped 15 -> 17 alongside the Anon/Friends toggle pill's own
  // enlargement (see AnonFriendsTogglePill in anon_feed_screen.dart) — the
  // only call site, so safe to size directly for that pill.
  static TextStyle t1(Color color) => _m(size: 17, weight: FontWeight.w600, color: color);
  // 23 -> 18: the only call site is the anon prompt bar's headline, which
  // allows a 2-line wrap (see that Text's own doc — a 1-line cap used to
  // cut prompts off mid-sentence). At 23px/w700 a wrapped 2-line prompt
  // ("What's keeping you up. One photo.") made the whole pill balloon in
  // height ("why is the prompt bar so big"). 18px keeps it clearly the
  // bar's headline (still bigger/bolder than every other label in it) while
  // a 2-line wrap now costs noticeably less vertical space.
  static TextStyle t2 = _m(size: 18, weight: FontWeight.w700, height: 1.2, letterSpacing: -0.36, color: AnonFeedColors.textPrimary);
  static TextStyle t3 = _m(size: 14, weight: FontWeight.w600, letterSpacing: -0.07, color: AnonFeedColors.textDim);
  static TextStyle t4 = _m(size: 15, weight: FontWeight.w700, letterSpacing: -0.15, color: AnonFeedColors.inkOnLightAlt);
  // Bumped (explicit request: "live here" dropdown wasn't clearly
  // visible) — same class of fix as the comment-section font sizes: this
  // design-px value gets further multiplied by the real device's own
  // scale (~0.6), so the old 9/13 rendered at only ~5-8px on screen.
  static TextStyle t5 = _m(size: 13, weight: FontWeight.w700, letterSpacing: 1.62, color: AnonFeedColors.textDimmer);
  static TextStyle t6 = _m(size: 18, weight: FontWeight.w500, color: AnonFeedColors.textPeek);
  static TextStyle t7 = _m(size: 10, weight: FontWeight.w700, color: Colors.white);
  static TextStyle t8 = _m(size: 24, weight: FontWeight.w600, height: 1.36, letterSpacing: -0.36, color: AnonFeedColors.textPrimary);
  static TextStyle t9 = _m(size: 13, weight: FontWeight.w700, letterSpacing: 1.56, color: AnonFeedColors.textMuted);
  static TextStyle t10 = _m(size: 14, weight: FontWeight.w400, color: AnonFeedColors.textTime);
  static TextStyle t11 = _m(size: 15, weight: FontWeight.w500, color: AnonFeedColors.textReplies);
  static TextStyle t12 = _m(size: 17, weight: FontWeight.w800, letterSpacing: -0.17, color: AnonFeedColors.textPeek);
  static TextStyle t13 = _m(size: 14, weight: FontWeight.w700, letterSpacing: 1.6, color: AnonFeedColors.textDim);
  static TextStyle t14 = _m(size: 14, weight: FontWeight.w700, letterSpacing: 1.6, color: AnonFeedColors.textMuted);
  static TextStyle t15 = _m(size: 24, weight: FontWeight.w700, height: 1.3, letterSpacing: -0.36, color: AnonFeedColors.textPeek);
  // Comment-section sizes bumped ~15-20% (explicit request: "words aren't
  // clearly visible" in the comments sheet) — this whole file's sizes are
  // DESIGN-px, further multiplied by the ambient `scale` TextScaler
  // (screenWidth/660, ~0.6 on a typical phone — see AnonFeedScreenV2.build's
  // own MediaQuery override), so the original values rendered noticeably
  // smaller in absolute px than their design-px numbers suggest (e.g. t23's
  // old 17 rendered at ≈10px on a ~390pt-wide phone).
  static TextStyle t16 = _m(size: 13, weight: FontWeight.w700, letterSpacing: 1.98, color: AnonFeedColors.textDimmer);
  static TextStyle t17 = _m(size: 15, weight: FontWeight.w600, color: AnonFeedColors.textFaintest);
  static TextStyle t18 = _m(size: 12.5, weight: FontWeight.w600, color: AnonFeedColors.textMuted);
  static TextStyle t19 = _m(size: 22, weight: FontWeight.w700, letterSpacing: -0.38, color: AnonFeedColors.textPrimary);
  static TextStyle t20 = _m(size: 17, weight: FontWeight.w600, color: AnonFeedColors.textDimmer);
  static TextStyle t21 = _m(size: 18, weight: FontWeight.w700, letterSpacing: -0.15, color: AnonFeedColors.textCommentName);
  static TextStyle t22 = _m(size: 15, weight: FontWeight.w400, color: AnonFeedColors.textDimmer);
  static TextStyle t23 = _m(size: 20, weight: FontWeight.w500, height: 1.42, color: AnonFeedColors.textBody);
  static TextStyle t24 = _m(size: 18, weight: FontWeight.w400, color: AnonFeedColors.textDimmer);
  static TextStyle t25 = _m(size: 20, weight: FontWeight.w700, letterSpacing: -0.40, color: AnonFeedColors.textPrimary);
  static TextStyle t26 = _m(size: 14, weight: FontWeight.w500, color: AnonFeedColors.textDimmer);
  static TextStyle t27 = _m(size: 11, weight: FontWeight.w700, letterSpacing: 1.98, color: AnonFeedColors.textFaint);
  static TextStyle t28(Color color) => _m(size: 16.5, weight: FontWeight.w600, height: 1.32, letterSpacing: -0.2475, color: color);
  static TextStyle t29 = _m(size: 16, weight: FontWeight.w700, color: AnonFeedColors.textReplies);
  static TextStyle t30(Color color) => _m(size: 16, weight: FontWeight.w700, letterSpacing: -0.16, color: color);
  static TextStyle t31 = _m(size: 11, weight: FontWeight.w700, letterSpacing: 1.98, color: AnonFeedColors.textFaint);
  static TextStyle t32(Color color) => _m(size: 16.5, weight: FontWeight.w700, letterSpacing: -0.2475, color: color);
  static TextStyle t33 = _m(size: 13, weight: FontWeight.w500, color: AnonFeedColors.textDimmer);
}

// ---------------------------------------------------------------------------
// §13.2 Motion curves — the two custom cubic-beziers plus the two mapped
// standard curves, named to match the spec's own keyframe names.
// ---------------------------------------------------------------------------

class AnonFeedCurves {
  AnonFeedCurves._();

  static const trayCurve = Cubic(0.2, 1.1, 0.3, 1.0); // trayExpand
  static const sheetCurve = Cubic(0.2, 1.0, 0.3, 1.0); // sheetUp
  static const chipCurve = Cubic(0.4, 1.1, 0.4, 1.0); // toggle chip
  static const mojiCurve = Cubic(0.2, 1.3, 0.3, 1.0); // real-moji button / saved-moji select

  static const livePulseCurve = Curves.easeInOut; // livePulse
  static const popInCurve = Curves.easeOut; // popIn
  static const fadeInCurve = Curves.easeOut; // fadeIn

  static const livePulseDuration = Duration(milliseconds: 2200);
  static const popInDuration = Duration(milliseconds: 180);
  static const trayExpandDuration = Duration(milliseconds: 300);
  static const sheetUpDuration = Duration(milliseconds: 320);
  static const fadeInDuration = Duration(milliseconds: 220);
  static const mojiButtonDuration = Duration(milliseconds: 300);
  static const savedMojiDuration = Duration(milliseconds: 180);
  static const chipDuration = Duration(milliseconds: 300);
  static const rowSelectDuration = Duration(milliseconds: 180);
  static const sendButtonDuration = Duration(milliseconds: 200);
  static const stackOpacityDuration = Duration(milliseconds: 220);
  static const peekOpacityDuration = Duration(milliseconds: 300);
}
