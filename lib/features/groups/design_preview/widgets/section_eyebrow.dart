import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Uppercase small-caps section label — "TODAY", the calendar month
/// header, "Recent together", etc. Defaults to the design spec's "Section
/// eyebrow" token (11px/600/1.4px letter-spacing); pass [fontSize] /
/// [letterSpacing] for the smaller "Card eyebrow" token (10px/1.6px) used
/// inside the streak hero card.
class SectionEyebrow extends StatelessWidget {
  const SectionEyebrow(
    this.label, {
    super.key,
    this.fontSize = 11,
    this.letterSpacing = 1.4,
    this.color,
  });

  final String label;
  final double fontSize;
  final double letterSpacing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.dmSans(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: letterSpacing,
        color: color ?? Colors.white.withValues(alpha: 0.35),
      ),
    );
  }
}
