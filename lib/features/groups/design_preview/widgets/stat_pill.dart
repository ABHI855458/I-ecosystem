import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pill-shaped stat chip — 1c's "41-day streak" / "Since Mar 2025". Not
/// reused by 1a's stats bar, which the spec defines as a divided
/// three-column grid (numeral + label, hairline dividers) rather than
/// pills — a genuinely different shape, so that one stays inline in the
/// Cover screen instead of being forced through this widget.
class StatPill extends StatelessWidget {
  const StatPill(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.6)),
      ),
    );
  }
}
