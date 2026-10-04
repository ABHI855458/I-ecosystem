import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Visual language shared across the Ping feature — pulled directly from the
// live prototype (design-refs/design_handoff_ping_page 2/Ping Page.dc.html),
// which is more visually complete than SPEC.md's prose in a few places:
// a muted/earthy avatar tint palette (not saturated app-generic darks), and
// a diagonal-hatch "photo placeholder" texture used everywhere a real photo
// would sit (Group Wall tiles — SPEC.md §9 calls this out explicitly as
// "striped overlay" — plus Reply photos and the Reply Detail hero, which
// the prototype treats the same way even though SPEC.md's prose omits it).
// ---------------------------------------------------------------------------

/// Base tone per demo identity, matching the prototype's palette family
/// (terracotta / tan / sage / mustard / taupe / dusty-teal / dusty-rose).
/// [pingAvatarGradient] derives the darker second stop from this alone, so
/// call sites only ever need to know one color per person.
const Map<String, Color> pingIdentityTints = {
  'alex_xyz': Color(0xFFC97B5A),
  'jordan_23': Color(0xFFD2A05C),
  'study_bug': Color(0xFF7A8B6F),
  'sunset_chaser': Color(0xFF6E8B8A),
  'coffee_talk': Color(0xFFB08968),
  'library_mode': Color(0xFF8A7A6D),
  'fest_vibes': Color(0xFFB58A94),
  'priya': Color(0xFF7A8B6F),
  'rahul': Color(0xFFB08968),
  'meera': Color(0xFF6E8B8A),
  'kabir': Color(0xFFD2A05C),
};

Color pingTintFor(
  String identityKey, {
  Color fallback = const Color(0xFF8A7A6D),
}) => pingIdentityTints[identityKey] ?? fallback;

/// Exact light→dark pairs from THEME_CORRECTIONS.md's `kEarth` table, keyed
/// by the light stop so [pingAvatarGradient] can look up the correct dark
/// stop instead of deriving an approximate one.
const Map<int, Color> _kEarthDarkFor = {
  0xFFC97B5A: Color(0xFFA85D3E), // terracotta
  0xFFB08968: Color(0xFF8B6A4F), // tan
  0xFF7A8B6F: Color(0xFF5F7355), // sage
  0xFFD2A05C: Color(0xFFB8843F), // ochre
  0xFF8A7A6D: Color(0xFF6B5D52), // taupe
  0xFF6E8B8A: Color(0xFF516B6A), // slate-teal
};

/// Page/screen background — the design's exact `kGround`. Distinct from
/// the app-wide `AppColors.background` (#0A0A0F), which is one hex off;
/// use this, not that, for anything meant to match the design pixel-exact
/// (Scaffold backgroundColor for Ping's own full-screen surfaces).
const Color pingGround = Color(0xFF0B0B0D);

/// The ONE accent — cyan. Never violet/magenta/pink anywhere in Ping.
const Color pingCyan = Color(0xFF29D3E8);
const Color pingCyanLite = Color(0xFF7FE8F2);
const Color pingCyanDeep = Color(0xFF1BAFC4);

/// Anonymous identity — clay, never the accent, never a kEarth pair.
const Color pingClay = Color(0xFFA9A49A);

/// G1 — Ping-back CTAs (loops row + reply banner). Single-hue cyan ramp.
const Gradient pingCtaGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [pingCyanLite, pingCyan],
);

/// G2 — Send buttons, empty-state CTA, comment-send.
const Gradient pingSendGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [pingCyan, pingCyanDeep],
);

/// Irregular 4-corner radius — the app's shape fingerprint (COLORS_AND_
/// SHAPES.md §2.1). Uniform `BorderRadius.circular` is reserved for pills/
/// chips/tiles/inputs only (§2.2).
BorderRadius pingR4(double tl, double tr, double br, double bl) =>
    BorderRadius.only(
      topLeft: Radius.circular(tl),
      topRight: Radius.circular(tr),
      bottomRight: Radius.circular(br),
      bottomLeft: Radius.circular(bl),
    );

/// The prototype's avatar fills are `linear-gradient(160deg, base, darker)`.
/// Looks up the exact kEarth dark stop when [base] is a known light tone,
/// else falls back to a derived darken (used only for the app's own extra
/// demo tones outside the 6-color kEarth table, e.g. fest_vibes's rose).
Gradient pingAvatarGradient(Color base) {
  final dark =
      _kEarthDarkFor[base.toARGB32()] ?? Color.lerp(base, Colors.black, 0.24)!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [base, dark],
  );
}

// ---------------------------------------------------------------------------
// HatchTexture — diagonal-stripe placeholder, matching the prototype's
// repeating-linear-gradient(135deg, rgba(255,255,255,a1) 0 w, rgba(255,255,
// 255,a2) w 2w). Used as an overlay on top of a tint gradient wherever the
// design stands in for a photo that hasn't rendered (Group Wall tiles,
// Reply photos, Reply Detail hero) — never on live camera output.
// ---------------------------------------------------------------------------

class HatchTexture extends StatelessWidget {
  const HatchTexture({
    super.key,
    this.stripeWidth = 9,
    this.lightAlpha = 0.09,
    this.darkAlpha = 0.03,
  });

  final double stripeWidth;
  final double lightAlpha;
  final double darkAlpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _HatchPainter(
          stripeWidth: stripeWidth,
          lightAlpha: lightAlpha,
          darkAlpha: darkAlpha,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter({
    required this.stripeWidth,
    required this.lightAlpha,
    required this.darkAlpha,
  });

  final double stripeWidth;
  final double lightAlpha;
  final double darkAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final diag = size.width + size.height;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(0.75 * 3.14159265 / 2); // 135deg
    canvas.translate(-diag / 2, -diag / 2);

    final light = Paint()..color = Colors.white.withValues(alpha: lightAlpha);
    final dark = Paint()..color = Colors.white.withValues(alpha: darkAlpha);
    final band = stripeWidth * 2;
    for (double x = -diag; x < diag * 2; x += band) {
      canvas.drawRect(Rect.fromLTWH(x, -diag, stripeWidth, diag * 2), light);
      canvas.drawRect(
        Rect.fromLTWH(x + stripeWidth, -diag, stripeWidth, diag * 2),
        dark,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.stripeWidth != stripeWidth ||
      old.lightAlpha != lightAlpha ||
      old.darkAlpha != darkAlpha;
}

/// Fixed tan→cyan wash used behind every unrevealed "photo" (not a real
/// person's identity tint) — matches the prototype's reply-row/viewed-card
/// placeholders, which are the same two-tone gradient regardless of who
/// sent the photo.
const Gradient pingPhotoGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0x4DB08968), Color(0x3D29D3E8)],
);

/// Tint gradient + hatch, rounded to [radius] — the standard "photo" stand-in
/// used across Group Wall tiles, Reply photos, and the Reply Detail hero.
class HatchedPhoto extends StatelessWidget {
  const HatchedPhoto({
    super.key,
    this.tint,
    this.gradient,
    this.radius = 10,
    this.child,
  });

  /// Identity tint (derives a gradient via [pingAvatarGradient]). Ignored if
  /// [gradient] is set. Neither set → falls back to [pingPhotoGradient].
  final Color? tint;
  final Gradient? gradient;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final resolved =
        gradient ??
        (tint != null ? pingAvatarGradient(tint!) : pingPhotoGradient);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(gradient: resolved),
        child: Stack(
          fit: StackFit.expand,
          children: [const HatchTexture(), ?child],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PingScoreTag — the page's own 3-tier badge (Deeply Present / Showing Up /
// Getting Started), lifted verbatim from the prototype's `scoreTag` logic.
// Deliberately separate from the app-wide TierBadge/tierInfoForScore system
// (lib/shared/score_tier.dart, its own Instagram-style 4-tier ladder used
// for post glow rings elsewhere) — the Ping header needs the design's exact
// thresholds/labels/treatment, not the shared component.
// ---------------------------------------------------------------------------

class PingScoreTagInfo {
  const PingScoreTagInfo({
    required this.label,
    required this.color,
    required this.bg,
    required this.border,
  });
  final String label;
  final Color color;
  final Color bg;
  final Color border;
}

PingScoreTagInfo pingScoreTagFor(int score) {
  if (score >= 700) {
    return const PingScoreTagInfo(
      label: 'Deeply Present',
      color: Color(0xFF0B0B0D),
      bg: Color(0xFF29D3E8),
      border: Color(0xFF29D3E8),
    );
  }
  if (score >= 400) {
    return PingScoreTagInfo(
      label: 'Showing Up',
      color: Colors.white.withValues(alpha: 0.85),
      bg: Colors.white.withValues(alpha: 0.08),
      border: Colors.white.withValues(alpha: 0.18),
    );
  }
  return PingScoreTagInfo(
    label: 'Getting Started',
    color: Colors.white.withValues(alpha: 0.5),
    bg: Colors.transparent,
    border: Colors.white.withValues(alpha: 0.14),
  );
}

class PingScoreTag extends StatelessWidget {
  const PingScoreTag({super.key, required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final info = pingScoreTagFor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: info.bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: info.border),
      ),
      child: Text(
        info.label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.04 * 10,
          color: info.color,
        ),
      ),
    );
  }
}
