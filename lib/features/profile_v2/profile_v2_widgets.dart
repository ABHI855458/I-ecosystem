import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import 'profile_v2_icons.dart';
import 'profile_v2_tokens.dart';

// ---------------------------------------------------------------------------
// Inner shadow
// ---------------------------------------------------------------------------

/// Paints CSS `inset` box-shadows, which Flutter's [BoxDecoration] cannot.
///
/// The technique per shadow: clip to the shape, flood the clip with the shadow
/// colour, then punch out a blurred copy of the shape offset by the shadow's
/// offset using [BlendMode.dstOut]. What survives is a soft band hugging the
/// edge *opposite* the offset — which is exactly an inset shadow.
///
/// This is the load-bearing piece of the neumorphic look: the recessed wells,
/// active tabs and poll rows are only distinguishable from raised cards by
/// these, so approximating them with a flat darker fill loses the design.
class InnerShadow extends StatelessWidget {
  const InnerShadow({
    super.key,
    required this.shadows,
    required this.borderRadius,
    this.child,
  });

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _InnerShadowPainter(shadows, borderRadius),
      child: child,
    );
  }
}

class _InnerShadowPainter extends CustomPainter {
  const _InnerShadowPainter(this.shadows, this.borderRadius);

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final bounds = Offset.zero & size;
    final rrect = borderRadius.toRRect(bounds);

    canvas.save();
    canvas.clipRRect(rrect);
    for (final shadow in shadows) {
      canvas.saveLayer(bounds, Paint());
      canvas.drawPaint(Paint()..color = shadow.color);

      final cut = Paint()..blendMode = BlendMode.dstOut;
      if (shadow.blurRadius > 0) {
        // CSS blur-radius is ~2σ; Flutter's MaskFilter takes σ directly.
        cut.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          shadow.blurRadius / 2,
        );
      }
      canvas.drawRRect(rrect.shift(shadow.offset), cut);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter old) =>
      old.shadows != shadows || old.borderRadius != borderRadius;
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// A raised neumorphic card: flat fill, hairline border, drop-shadow pair.
class NeuCard extends StatelessWidget {
  const NeuCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding,
    this.color = PV2.raised,
    this.border = PV2.hairline,
    this.shadows = PV2.raisedLg,
    this.innerGlow,
    this.width,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color color;
  final Color? border;
  final List<BoxShadow> shadows;

  /// CSS `inset 0 0 Npx rgba(...)` — an even interior glow with no offset,
  /// used on the streak hero and the self-profile rank card. Rendered as a
  /// radial gradient rather than via [InnerShadow] because it has no direction.
  final Color? innerGlow;

  final double? width;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);

    Widget content = Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: br,
        border: border == null ? null : Border.all(color: border!, width: 1),
        boxShadow: shadows,
        gradient: innerGlow == null
            ? null
            : RadialGradient(
                radius: 0.85,
                colors: [color, Color.alphaBlend(innerGlow!, color)],
                stops: const [0.35, 1.0],
              ),
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: child,
    );

    if (onTap != null) {
      content = _Tappable(onTap: onTap!, borderRadius: br, child: content);
    }
    return content;
  }
}

/// A recessed well — the inverse of [NeuCard]. Used for icon wells, active
/// tabs, poll rows and the streak ring's centre.
class NeuWell extends StatelessWidget {
  const NeuWell({
    super.key,
    required this.child,
    this.radius = 12,
    this.padding,
    this.shadows = PV2.insetWell,
    this.color = PV2.recessed,
    this.border,
    this.width,
    this.height,
    this.circle = false,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow> shadows;
  final Color color;
  final Color? border;
  final double? width;
  final double? height;
  final bool circle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = circle ? (width ?? height ?? radius * 2) / 2 : radius;
    final br = BorderRadius.circular(r);

    Widget content = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: br,
        border: border == null ? null : Border.all(color: border!, width: 1),
      ),
      child: InnerShadow(
        shadows: shadows,
        borderRadius: br,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Center(child: child),
        ),
      ),
    );

    if (onTap != null) {
      content = _Tappable(onTap: onTap!, borderRadius: br, child: content);
    }
    return content;
  }
}

/// A blurred translucent chrome surface — back button, score chip, backdrop
/// picker. [BackdropFilter] is what makes these read as glass over the
/// gradient rather than as flat dark pills.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.fill = const Color(0x8008080A),
    this.border = const Color(0x1AFFFFFF),
    this.blur = 14,
    this.width,
    this.height,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final Color fill;
  final Color border;
  final double blur;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget content = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: br,
            border: Border.all(color: border, width: 1),
          ),
          child: child,
        ),
      ),
    );
    if (onTap != null) {
      content = _Tappable(onTap: onTap!, borderRadius: br, child: content);
    }
    return content;
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.onTap,
    required this.borderRadius,
    required this.child,
  });

  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: PV2.accent.withValues(alpha: 0.06),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conic ring
// ---------------------------------------------------------------------------

/// A CSS `conic-gradient` progress ring.
///
/// CSS measures conic angles clockwise from 12 o'clock; Flutter's
/// [SweepGradient] measures from 3 o'clock, hence the `- pi/2`. The hard stop
/// is produced by repeating each colour at the same offset — no interpolation
/// band, matching the design's crisp edge.
class ConicRing extends StatelessWidget {
  const ConicRing({
    super.key,
    required this.size,
    required this.fromTurn,
    required this.fillTurns,
    this.fill = PV2.accent,
    this.track = const Color(0x12FFFFFF),
    this.child,
  });

  final double size;
  final double fromTurn;
  final double fillTurns;
  final Color fill;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final start = fromTurn * 2 * math.pi - math.pi / 2;
    final t = fillTurns.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            startAngle: start,
            endAngle: start + 2 * math.pi,
            colors: [fill, fill, track, track],
            stops: [0.0, t, t, 1.0],
          ),
        ),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashed border
// ---------------------------------------------------------------------------

/// A dashed rounded-rect outline for the "add" affordances. Flutter's
/// [Border] has no dash support, so the path is dashed explicitly.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    required this.radius,
    this.color = const Color(0x47FFFFFF),
    this.strokeWidth = 1.5,
    this.dash = const [5, 4],
  });

  final Widget child;
  final double radius;
  final Color color;
  final double strokeWidth;
  final List<double> dash;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedPainter(radius, color, strokeWidth, dash),
      child: child,
    );
  }
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(this.radius, this.color, this.strokeWidth, this.dash);

  final double radius;
  final Color color;
  final double strokeWidth;
  final List<double> dash;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final path = dashPath(
      Path()..addRRect(rrect),
      dashArray: CircularIntervalList<double>(dash),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius;
}

// ---------------------------------------------------------------------------
// Mosaic
// ---------------------------------------------------------------------------

/// One cell of a [Mosaic]: how many columns it spans and its aspect ratio.
class MosaicTile {
  const MosaicTile({required this.span, required this.ratio, required this.child});

  final int span;
  final double ratio;
  final Widget child;
}

/// A 3-column aspect-ratio grid where tiles may span 2 columns.
///
/// This reproduces `grid-template-columns: repeat(3, minmax(0, 1fr))`. The
/// `minmax(0, …)` in the canvas is load-bearing and the reason this widget
/// computes the cell size from the available width rather than letting the
/// children negotiate it: with plain `1fr`, a spanning tile's aspect-derived
/// height feeds back into the track minimum and fattens the first column. Here
/// the cell is derived once — `(width - 2·gap) / 3` — so at the 430px reference
/// every square tile is exactly 128×128 and the wide tile 263×131.5.
class Mosaic extends StatelessWidget {
  const Mosaic({super.key, required this.tiles, this.gap = 7});

  final List<MosaicTile> tiles;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              _sized(tile, cell),
          ],
        );
      },
    );
  }

  Widget _sized(MosaicTile tile, double cell) {
    final width = cell * tile.span + gap * (tile.span - 1);
    return SizedBox(width: width, height: width / tile.ratio, child: tile.child);
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

/// Section title with the accent-tinted count chip beside it ("Us · 7").
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.count, this.subtitle});

  final String title;
  final String? count;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: PV2.display(size: 18, letterSpacing: -0.2),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              CountChip(label: count!),
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: PV2.body(size: 11, color: PV2.inkSub)),
        ],
      ],
    );
  }
}

class CountChip extends StatelessWidget {
  const CountChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PV2.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PV2.accent.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: PV2.body(size: 10, weight: FontWeight.w800, color: PV2.accentSoft),
      ),
    );
  }
}

/// The pill-shaped raised "Add" / "New" button used by section headers.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      radius: 16,
      shadows: PV2.raisedSm,
      border: PV2.hairlinePanel,
      onTap: onTap,
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 6),
              Text(
                label,
                style: PV2.body(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontally-scrolling rail with the scrollbar suppressed, matching the
/// canvas's `.hs` class.
class Rail extends StatelessWidget {
  const Rail({
    super.key,
    required this.children,
    this.gap = 9,
    this.padding = const EdgeInsets.fromLTRB(PV2.pad, 2, PV2.pad, 4),
    this.height,
    this.stretch = false,
  });

  final List<Widget> children;
  final double gap;
  final EdgeInsets padding;
  final double? height;

  /// Sizes every card to the tallest one. Needed where a rail mixes a fixed
  /// "add" affordance with content cards whose height comes from their text.
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    Widget row = Row(
      crossAxisAlignment:
          stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          children[i],
        ],
      ],
    );
    if (stretch) row = IntrinsicHeight(child: row);

    return SizedBox(
      height: height,
      child: ScrollConfiguration(
        behavior: const _NoScrollbar(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding,
          child: row,
        ),
      ),
    );
  }
}

class _NoScrollbar extends ScrollBehavior {
  const _NoScrollbar();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails d) =>
      child;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}

/// A row of overlapping circular face swatches ("who was there").
/// A streak, as a flame + number in a compact pill.
///
/// THE shared streak display — every surface that shows a streak uses this,
/// so a streak looks like a streak wherever you meet it (profile, ping page,
/// group profile, group posts, Duo, leaderboard).
///
/// Shape follows the reaction pill this app already uses for RealMoji
/// counts (glyph, then count, in a tinted rounded pill) — explicit request
/// to reuse that treatment for "the flame with number" rather than invent a
/// second one.
///
/// Always a relationship streak (ping, group, pair) — blue, with the ice
/// flame glyph. See PV2.streakBlue.
class StreakFlamePill extends StatelessWidget {
  const StreakFlamePill({
    super.key,
    required this.count,
    this.size = 11,
    this.label,
  });

  final int count;
  final double size;

  /// Optional trailing word ("days together"), for the roomier surfaces.
  final String? label;

  @override
  Widget build(BuildContext context) {
    // Never a bare 0 — the same rule every other count in this app follows.
    if (count <= 0) return const SizedBox.shrink();
    const tint = PV2.streakBlue;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.62, vertical: size * 0.3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PV2Icons.iceFlame(size),
          SizedBox(width: size * 0.42),
          Text(
            '$count',
            style: PV2.body(
              size: size * 1.06,
              weight: FontWeight.w800,
              color: tint,
            ),
          ),
          if (label != null) ...[
            SizedBox(width: size * 0.5),
            Text(
              label!,
              style: PV2.body(size: size * 0.95, color: PV2.inkBio),
            ),
          ],
        ],
      ),
    );
  }
}

class FaceStack extends StatelessWidget {
  const FaceStack({
    super.key,
    required this.colors,
    this.size = 22,
    this.overlap = 8,
    this.ringColor = PV2.raised,
    this.ringWidth = 2,
  });

  final List<Color> colors;
  final double size;
  final double overlap;
  final Color ringColor;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) return const SizedBox.shrink();

    // Overlapping faces need negative offsets, which Flutter's margin rejects,
    // so the row is laid out explicitly: each face advances by `size - overlap`
    // and the box is sized to the last face's right edge.
    final step = size - overlap;
    return SizedBox(
      width: size + step * (colors.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: ringWidth),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A neumorphic segmented tab row (Posts / Moments / Anon).
///
/// The selected tab is *recessed* while the others are raised — the design's
/// only selection cue besides colour, so the inset shadow has to be real.
class NeuTabs extends StatelessWidget {
  const NeuTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.icons,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Optional leading glyph per tab; `null` entries render label-only.
  final List<Widget?>? icons;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(child: _tab(i)),
        ],
      ],
    );
  }

  Widget _tab(int i) {
    final on = i == selected;
    final fg = on ? Colors.white : PV2.inkTabOff;
    final br = BorderRadius.circular(19);

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icons != null && icons![i] != null) ...[
          icons![i]!,
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            labels[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PV2.body(size: 12.5, weight: FontWeight.w700, color: fg),
          ),
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(i),
        borderRadius: br,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: on ? PV2.recessed : PV2.raised,
            borderRadius: br,
            border: Border.all(
              color: on ? PV2.hairlineActive : PV2.hairline,
            ),
            boxShadow: on ? null : PV2.tabOff,
          ),
          child: on
              ? InnerShadow(
                  shadows: PV2.insetStd,
                  borderRadius: br,
                  child: Center(child: label),
                )
              : Center(child: label),
        ),
      ),
    );
  }
}
