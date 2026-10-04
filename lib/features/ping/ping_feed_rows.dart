import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import 'ping_feed_models.dart';
import 'ping_hold_reveal.dart';
import 'ping_visual_kit.dart';

// ---------------------------------------------------------------------------
// Row components for the merged Ping feed — see design-refs/no implemented/
// Ping Page.dc.html's "Component: To-Reply Row" / "Reply Row" / "Sent Row"
// sections. All three read [PingFeedEntry.origin] to render a small
// identity treatment distinguishing person/group/anonymous pings within the
// one merged list — this part isn't in the spec (which only covers
// person-to-person), kept minimal per the product decision to keep
// Group/Anonymous pings alive without redesigning the row shape for them.
// ---------------------------------------------------------------------------

// Anonymous identity is clay (THEME_CORRECTIONS.md Defect 7) — it is never
// the accent, so it never signals "alive" the way person/group pings do.
// Group keeps its own existing accent (electricPurple) — the design doc's
// corrections only call out CTA gradients, section labels, the hold ring,
// and anonymous identity, not this small origin-badge glyph, which exists
// outside the reference spec entirely per product's decision to keep
// Group/Anonymous functionality alive in the merged feed.
Color _originAccent(PingOrigin origin) => switch (origin) {
  PingOrigin.person => AppColors.neonCyan,
  PingOrigin.group => AppColors.electricPurple,
  PingOrigin.anonymous => pingClay,
};

IconData _originGlyph(PingOrigin origin) => switch (origin) {
  PingOrigin.person => Icons.person_rounded,
  PingOrigin.group => Icons.groups_rounded,
  PingOrigin.anonymous => Icons.visibility_off_rounded,
};

/// "{Group Name} · {n} people" for group pings (per spec's To-Reply group
/// row label), [PingFeedEntry.renderedName] ("Someone" for anonymous)
/// otherwise.
String _rowLabel(PingFeedEntry entry) {
  if (entry.origin == PingOrigin.group) {
    final count = entry.groupMembers?.length;
    return count != null
        ? '${entry.groupName ?? entry.displayName} · $count people'
        : entry.groupName ?? entry.displayName;
  }
  return entry.renderedName;
}

/// Small corner badge marking a row as Group/Anonymous — absent for plain
/// person pings so the common case matches the spec exactly with zero
/// extra chrome.
class _OriginBadge extends StatelessWidget {
  const _OriginBadge({required this.origin});
  final PingOrigin origin;

  @override
  Widget build(BuildContext context) {
    if (origin == PingOrigin.person) return const SizedBox.shrink();
    final accent = _originAccent(origin);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.18),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Icon(_originGlyph(origin), size: 9, color: accent),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry, this.photoPlaceholder = false});

  final PingFeedEntry entry;
  static const double _size = 36;

  /// True for surfaces standing in for an actual reply photo (spec §7a/§8a's
  /// "photo placeholder" leading element) — renders the hatch texture and
  /// drops the identity letter, matching the prototype exactly. False
  /// (default) for real identity avatars (To-Reply row, friend strip).
  final bool photoPlaceholder;

  @override
  Widget build(BuildContext context) {
    // Anonymous never resolves to a real name or initial anywhere, per
    // spec — dashed clay ring + "?" instead (THEME_CORRECTIONS.md Defect 7:
    // anonymous is never the accent or a kEarth pair).
    if (entry.origin == PingOrigin.anonymous) {
      return SizedBox(
        width: _size,
        height: _size,
        child: DottedBorderBox(
          color: pingClay.withValues(alpha: 0.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  pingClay.withValues(alpha: 0.20),
                  pingClay.withValues(alpha: 0.05),
                ],
              ),
            ),
            child: Center(
              child: Text(
                '?',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: _size * 0.42,
                  fontWeight: FontWeight.w700,
                  color: pingClay.withValues(alpha: 0.90),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: photoPlaceholder
              ? const HatchedPhoto(radius: _size / 2)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(_size / 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: pingAvatarGradient(entry.avatarColor),
                    ),
                    child: Center(
                      child: Text(
                        entry.renderedName.isNotEmpty
                            ? entry.renderedName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.inter(
                          fontSize: _size * 0.36,
                          fontWeight: FontWeight.w500,
                          color: const Color(
                            0xFF0B0B0D,
                          ).withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        if (entry.origin != PingOrigin.person)
          Positioned(
            right: -2,
            bottom: -2,
            child: _OriginBadge(origin: entry.origin),
          ),
      ],
    );
  }
}

/// Dashed border, used for the anonymous "?" avatar and the "hasn't
/// answered" group-wall tile. Painted directly (no dotted-border package
/// dependency) since this app has none installed.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    this.square = false,
  });
  final Widget child;
  final Color color;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, square: square),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.square});
  final Color color;
  final bool square;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = square
        ? (Path()..addRRect(
            RRect.fromRectAndRadius(
              Offset.zero & size,
              const Radius.circular(10),
            ),
          ))
        : (Path()..addOval(Offset.zero & size));
    for (final metric in path.computeMetrics()) {
      const dashLen = 4.0, gapLen = 3.0;
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.square != square;
}

// ---------------------------------------------------------------------------
// ToReplyRow
// ---------------------------------------------------------------------------

class ToReplyRow extends StatelessWidget {
  const ToReplyRow({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onRevealed,
  });

  final PingFeedEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRevealed;

  @override
  Widget build(BuildContext context) {
    // Unrevealed rows reserve a 90-wide gutter on the right for the hold
    // zone (spec §7a); revealed rows drop the hold zone for a slim trailing
    // dot+time cluster instead (§7b), so they don't need the wide gutter.
    final content = Container(
      padding: EdgeInsets.fromLTRB(18, 17, entry.isRevealed ? 16 : 90, 17),
      decoration: BoxDecoration(
        borderRadius: pingR4(26, 14, 30, 10),
        border: Border.all(
          color: entry.isRevealed
              ? AppColors.neonCyan.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.11),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: entry.isRevealed
              ? [
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.02),
                ]
              : [
                  Colors.white.withValues(alpha: 0.085),
                  Colors.white.withValues(alpha: 0.04),
                ],
        ),
      ),
      child: Row(
        children: [
          _Avatar(entry: entry),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _rowLabel(entry),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.prompt,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: entry.isRevealed ? onTap : null,
      child: Container(
        // Shadow lives outside the ClipRRect (a clipped Container can't
        // paint its own shadow) — idle vs holding per COLORS_AND_SHAPES.md
        // §2.6. Holding state's glow is approximated at rest here; the
        // live hold-progress version is driven by HoldToRevealBlur itself.
        decoration: BoxDecoration(
          borderRadius: pingR4(26, 14, 30, 10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: pingR4(26, 14, 30, 10),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 11, sigmaY: 11),
            child: entry.isRevealed
                ? content
                : HoldToRevealBlur(
                    revealed: false,
                    onRevealed: onRevealed,
                    rightAnchoredWidth: 90,
                    child: content,
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ReplyRow — identical sizing to ToReplyRow per spec, square photo
// placeholder instead of a circular avatar. Unrevealed state uses the same
// hold gesture; viewed state is a distinct flatter card (not just unblurred).
// ---------------------------------------------------------------------------

class ReplyRow extends StatelessWidget {
  const ReplyRow({super.key, required this.entry, required this.onTap});

  /// Always an unviewed entry — the caller (ping_screen.dart's REPLIES
  /// section) filters `isViewed` entries out of the list entirely. Once a
  /// reply is opened full-screen, it disappears from REPLIES for good; any
  /// still-open ping-back window for that person surfaces in OPEN LOOPS
  /// instead, not as a lingering row here.
  final PingFeedEntry entry;

  /// Tap opens the reply full-screen directly (no intermediate inline
  /// "viewed" card) and marks it viewed. Unlike To-Reply rows, Replies are
  /// never blurred/held — a reply someone already sent you is yours to
  /// read immediately, one tap.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Shadow outside the clip (§2.6 "row idle"), glass blur inside it
        // (§2.7 sigma 11) — same treatment as ToReplyRow's card shell, just
        // without the hold gesture (unblurred by design, per product).
        decoration: BoxDecoration(
          borderRadius: pingR4(26, 14, 30, 10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: pingR4(26, 14, 30, 10),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 11, sigmaY: 11),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.085),
                    Colors.white.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Row(
                children: [
                  _Avatar(entry: entry, photoPlaceholder: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_rowLabel(entry)} replied',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.prompt,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Unread signal replacing the old blur — a plain cyan
                  // dot, no hint copy needed since the row is tappable.
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pingCyan.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SentRow — flatter, no blur/glow. Seen/Delivered indicator.
// ---------------------------------------------------------------------------

class SentRow extends StatelessWidget {
  const SentRow({super.key, required this.entry});
  final PingFeedEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: pingR4(20, 10, 22, 12),
        color: const Color(0xFF17171B), // surface2
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.4,
                style: BorderStyle.solid,
              ),
            ),
            child: Icon(
              _originGlyph(entry.origin),
              size: 15,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'to ${_rowLabel(entry)}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.38),
                  ),
                ),
              ],
            ),
          ),
          if (entry.seen)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonCyan,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Seen',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: AppColors.neonCyan.withValues(alpha: 0.8),
                  ),
                ),
              ],
            )
          else
            Text(
              'Delivered',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.24),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SectionLabel — shared section header (To Reply / Replies / Sent).
// ---------------------------------------------------------------------------

class PingSectionLabel extends StatelessWidget {
  const PingSectionLabel({
    super.key,
    required this.label,
    this.count,
    this.opacity = 0.72,
  });
  final String label;
  final int? count;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.18 * 11,
            color: Colors.white.withValues(alpha: opacity),
          ),
        ),
        if (count != null) ...[
          const Spacer(),
          Text(
            '$count',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ],
    );
  }
}
