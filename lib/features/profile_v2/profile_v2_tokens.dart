import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for Profile v2.
///
/// Values are transcribed 1:1 from the Claude Design canvas
/// (`Profile v2.dc.html`, project "Postcard feed design layout"). The canvas is
/// authored at a 430px reference column; every literal here is a device-
/// independent pixel at that width, and [PV2.columnWidth] is how the screens
/// clamp themselves back to it on wider devices.
///
/// The canvas supersedes the older `PROFILE_V2_SPEC.md` handoff — most notably
/// the accent moved from pure cyan `#00FFFF` to the softer [PV2.accent]
/// `#37C9E6`, and several accent-tinted glyphs were flattened to plain white.
class PV2 {
  PV2._();

  // --- surfaces -----------------------------------------------------------
  static const Color page = Color(0xFF08080A);
  static const Color raised = Color(0xFF101013);
  static const Color recessed = Color(0xFF0C0C0F);
  static const Color anonWell = Color(0xFF1A1A1E);

  // --- accents ------------------------------------------------------------
  static const Color accent = Color(0xFF37C9E6);
  static const Color accentDeep = Color(0xFF1FB5D0);
  static const Color accentSoft = Color(0xFF7DE8F8);

  /// Ink on an accent-filled surface. The identity-panel Ping button is the
  /// exception that uses white; the newer create-flow buttons and Ping All all
  /// use this near-black.
  static const Color onAccent = Color(0xFF04070A);

  /// Dips are the one place the design leaves the cyan family: an amber that
  /// reads as "expiring".
  // ── STREAK colours ───────────────────────────────────────────────────
  // Explicit rule: "everywhere the flame related to ping streaks shall be
  // blue." streakBlue covers all three relationship streaks: the one-to-one
  // ping streak, the group's shared all-or-nothing streak, and each member's
  // own group-reply streak. (The personal anon streak this used to pair
  // with — streakRed — was removed from the app entirely.)
  //
  // Deliberately NOT `accent`: accent is this app's cyan and is already
  // spent on a dozen unrelated affordances, so a streak painted with it
  // reads as "highlighted", not as "this is a streak."
  static const Color streakBlue = Color(0xFF4DA6FF);

  static const Color amber = Color(0xFFFFC94D);
  static const Color amberInk = Color(0xFF3A2C05);
  static const Color danger = Color(0xFFFF5C5C);

  static const LinearGradient accentButton = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDeep],
  );

  /// A primary action that cannot yet be taken — the create flows gate their
  /// commit button on required input. The design states the requirement in
  /// text beneath rather than hiding the button, so the disabled state has to
  /// read as "not yet", not as decoration.
  static const Color disabledFill = Color(0x14FFFFFF); // .08
  static const Color disabledInk = Color(0x40FFFFFF); // .25

  // --- menu surfaces ------------------------------------------------------
  /// Dropdown panels float above everything and are the one surface that is
  /// near-opaque rather than neumorphic — they must stay legible over photos.
  static const Color menuFill = Color(0xF70E0E10); // .97
  static const Color menuFillLight = Color(0xF20E0E10); // .95
  static const Color menuBorder = Color(0x14FFFFFF); // .08
  static const Color menuBorderStrong = Color(0x17FFFFFF); // .09
  static const Color menuDivider = Color(0x12FFFFFF); // .07

  // --- text tiers ---------------------------------------------------------
  static const Color ink = Colors.white;
  static const Color inkBio = Color(0xB3FFFFFF); // .70
  static const Color inkMember = Color(0x94FFFFFF); // .58
  static const Color inkTabOff = Color(0x80FFFFFF); // .50
  static const Color inkByline = Color(0x66FFFFFF); // .40
  static const Color inkHandle = Color(0x5CFFFFFF); // .36
  static const Color inkLabel = Color(0x57FFFFFF); // .34
  static const Color inkSub = Color(0x52FFFFFF); // .32
  static const Color inkCount = Color(0x4DFFFFFF); // .30
  static const Color inkStamp = Color(0x47FFFFFF); // .28

  // --- borders ------------------------------------------------------------
  static const Color hairline = Color(0x0DFFFFFF); // .05
  static const Color hairlinePanel = Color(0x0FFFFFFF); // .06
  static const Color hairlineBright = Color(0x21FFFFFF); // .13
  static const Color hairlineActive = Color(0x47FFFFFF); // .28

  // --- shadow stacks ------------------------------------------------------
  /// Raised, large — bento cards, streak hero, memory collages.
  static const List<BoxShadow> raisedLg = [
    BoxShadow(color: Color(0xB8000000), offset: Offset(6, 6), blurRadius: 16),
    BoxShadow(color: Color(0x07FFFFFF), offset: Offset(-3, -3), blurRadius: 12),
  ];

  /// Raised, medium — group cards, moment cards, community cards.
  static const List<BoxShadow> raisedMd = [
    BoxShadow(color: Color(0xB3000000), offset: Offset(6, 6), blurRadius: 15),
    BoxShadow(color: Color(0x07FFFFFF), offset: Offset(-3, -3), blurRadius: 11),
  ];

  /// Raised, small — the pill-shaped Add / New buttons.
  static const List<BoxShadow> raisedSm = [
    BoxShadow(color: Color(0xA8000000), offset: Offset(4, 4), blurRadius: 10),
    BoxShadow(color: Color(0x08FFFFFF), offset: Offset(-2, -2), blurRadius: 7),
  ];

  /// Inactive tab — slightly flatter than [raisedMd] so the active inset tab
  /// beside it reads as pressed rather than merely darker.
  static const List<BoxShadow> tabOff = [
    BoxShadow(color: Color(0xA8000000), offset: Offset(5, 5), blurRadius: 13),
    BoxShadow(color: Color(0x06FFFFFF), offset: Offset(-3, -3), blurRadius: 10),
  ];

  /// The floating identity panel, which also casts upward over the backdrop.
  static const List<BoxShadow> panel = [
    BoxShadow(color: Color(0xB3000000), offset: Offset(0, -8), blurRadius: 34),
    BoxShadow(color: Color(0x99000000), offset: Offset(8, 8), blurRadius: 20),
    BoxShadow(color: Color(0x07FFFFFF), offset: Offset(-3, -3), blurRadius: 14),
  ];

  static const List<BoxShadow> photo = [
    BoxShadow(color: Color(0x99000000), offset: Offset(5, 5), blurRadius: 13),
  ];

  // --- inner (inset) shadow stacks ---------------------------------------
  // Flutter has no inset box-shadow; these feed [InnerShadow], which paints
  // them with a clip + dstOut pass. See profile_v2_widgets.dart.

  /// Active tab, circular icon buttons on the identity panel.
  static const List<BoxShadow> insetStd = [
    BoxShadow(color: Color(0xC7000000), offset: Offset(3, 3), blurRadius: 9),
    BoxShadow(color: Color(0x08FFFFFF), offset: Offset(-2, -2), blurRadius: 7),
  ];

  /// Small square wells — the 34px icon wells, poll rows, rank tile.
  static const List<BoxShadow> insetWell = [
    BoxShadow(color: Color(0xCC000000), offset: Offset(3, 3), blurRadius: 8),
    BoxShadow(color: Color(0x08FFFFFF), offset: Offset(-2, -2), blurRadius: 6),
  ];

  /// Dashed "add" tiles, which sit deeper than a normal well.
  static const List<BoxShadow> insetDeep = [
    BoxShadow(color: Color(0xB3000000), offset: Offset(3, 3), blurRadius: 10),
    BoxShadow(color: Color(0x06FFFFFF), offset: Offset(-2, -2), blurRadius: 7),
  ];

  // --- backdrops ----------------------------------------------------------
  static const List<String> backdropNames = ['indigo', 'teal', 'plum', 'slate'];

  /// The four selectable page backdrops, in canvas order. A person profile
  /// shows `backdrops[i]`; the group profile it navigates to shows `i + 1`, so
  /// the two screens never read as the same surface.
  static final List<LinearGradient> backdrops = [
    cssLinear(168, const [
      Color(0xFF1B2B5E),
      Color(0xFF3B2A6B),
      Color(0xFF6D2A63),
    ], const [0.0, 0.44, 1.0]),
    cssLinear(168, const [
      Color(0xFF062C33),
      Color(0xFF0A4D55),
      Color(0xFF127A7F),
    ], const [0.0, 0.46, 1.0]),
    cssLinear(168, const [
      Color(0xFF2A1F3D),
      Color(0xFF4A2340),
      Color(0xFF7D3A4A),
    ], const [0.0, 0.48, 1.0]),
    cssLinear(168, const [
      Color(0xFF111827),
      Color(0xFF1F3A47),
      Color(0xFF2F5D5F),
    ], const [0.0, 0.50, 1.0]),
  ];

  /// The white highlight wash laid over a backdrop. [x]/[y] are the CSS
  /// radial-gradient focus, which differs between person (78%/8%) and group
  /// (22%/10%) so the light appears to come from opposite sides.
  static RadialGradient wash({required double x, required double y}) {
    return RadialGradient(
      center: Alignment(x * 2 - 1, y * 2 - 1),
      radius: 1.0,
      colors: const [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
      stops: const [0.0, 0.58],
    );
  }

  /// The fade that dissolves the backdrop into the page so the identity panel
  /// can overlap it without a visible seam.
  static const LinearGradient bottomFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0008080A), Color(0x8008080A), page],
    stops: [0.0, 0.62, 1.0],
  );

  /// Scrim over an album/dip tile: darkens the top edge (so a white privacy
  /// badge stays legible) and the bottom (for the uploader stamp).
  static const LinearGradient tileScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x4D000000), Color(0x00000000), Color(0x00000000), Color(0x9E000000)],
    stops: [0.0, 0.32, 0.58, 1.0],
  );

  /// Scrim over a post-grid tile — bottom only, since posts carry no top badge.
  static const LinearGradient postScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0x99000000)],
    stops: [0.55, 1.0],
  );

  // --- geometry -----------------------------------------------------------
  static const double columnWidth = 430;
  static const double gutter = 12; // panel + bento inset
  static const double pad = 16; // section content inset

  // --- type ---------------------------------------------------------------
  /// Display face — names, numerals, section titles.
  static TextStyle display({
    required double size,
    FontWeight weight = FontWeight.w800,
    Color color = ink,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.nunito(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Body face — bios, labels, captions.
  static TextStyle body({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color color = ink,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Monospace face — handles, counts, meta lines. The canvas asks for the
  /// system UI mono stack; Menlo is its closest match on iOS/macOS and Android
  /// falls through to its own monospace.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = inkHandle,
  }) {
    return TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['SFMono-Regular', 'monospace'],
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  /// An all-caps micro-label (`ANON SCORE`, `MEMBERS`, `DAYS`). The tracking is
  /// what makes 8–9px type readable at this size, so it is not optional.
  static TextStyle caps({
    required double size,
    required double tracking,
    Color color = inkLabel,
    FontWeight weight = FontWeight.w700,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: size * tracking,
    );
  }

  // --- helpers ------------------------------------------------------------
  /// Converts a CSS `linear-gradient(Ndeg, …)` to Flutter's alignment-based
  /// form. CSS measures clockwise from "to top"; Flutter wants begin/end
  /// points, so the angle becomes a unit vector and its negation.
  static LinearGradient cssLinear(
    double degrees,
    List<Color> colors, [
    List<double>? stops,
  ]) {
    final rad = degrees * math.pi / 180;
    final dx = math.sin(rad);
    final dy = -math.cos(rad);
    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: colors,
      stops: stops,
    );
  }
}

/// Group-post card surfaces (feed + group profile): the card body is black,
/// and the header panel + location strip sit on it as a lighter black
/// (explicit request).
const Color kGroupCardBody = Color(0xFF0A0A0D);
const Color kGroupCardPanel = Color(0xFF141417);
