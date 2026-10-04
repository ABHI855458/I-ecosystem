import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ping_feed_models.dart';
import 'ping_feed_rows.dart' show DottedBorderBox;
import 'ping_visual_kit.dart' show pingAvatarGradient, pingClay, pingCtaGradient, pingCyan;

// ---------------------------------------------------------------------------
// OPEN LOOPS — replaces the single page-level Ping Back banner. Symmetric
// rule (see design doc's "Additional Features" → "Open Loops"): a loop
// appears when EITHER you replied to an inbound ping, or they replied to
// yours. Rendered below the "Ping Someone" strip/groups row, headingless —
// the rows read fine as a continuation of that section on their own.
// ---------------------------------------------------------------------------

class OpenLoopsSection extends StatelessWidget {
  const OpenLoopsSection({super.key, required this.loops, required this.onPingBack});

  final List<OpenLoop> loops;
  final void Function(OpenLoop loop) onPingBack;

  @override
  Widget build(BuildContext context) {
    if (loops.isEmpty) return const SizedBox.shrink();
    final sorted = [...loops]..sort((a, b) => a.remaining.compareTo(b.remaining));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final loop in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OpenLoopRow(loop: loop, onTap: () => onPingBack(loop)),
          ),
      ],
    );
  }
}

class _OpenLoopRow extends StatelessWidget {
  const _OpenLoopRow({required this.loop, required this.onTap});
  final OpenLoop loop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = loop.remaining.inHours;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            pingCyan.withValues(alpha: 0.16),
            pingCyan.withValues(alpha: 0.08),
          ],
        ),
        boxShadow: [BoxShadow(color: pingCyan.withValues(alpha: 0.10), blurRadius: 26)],
      ),
      child: Row(
        children: [
          _LoopAvatar(loop: loop),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ping ${loop.renderedName} back?',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loop.reasonLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${h}h left',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(99)),
                gradient: pingCtaGradient,
                boxShadow: [BoxShadow(color: Color(0x4D29D3E8), blurRadius: 22)],
              ),
              child: Text(
                'Ping back',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0A0A0D),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoopAvatar extends StatelessWidget {
  const _LoopAvatar({required this.loop});
  final OpenLoop loop;

  @override
  Widget build(BuildContext context) {
    if (loop.isAnonymous) {
      return SizedBox(
        width: 36,
        height: 36,
        child: DottedBorderBox(
          color: pingClay.withValues(alpha: 0.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [pingClay.withValues(alpha: 0.20), pingClay.withValues(alpha: 0.05)]),
            ),
            child: Center(
              child: Text(
                '?',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: pingClay.withValues(alpha: 0.90),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: pingAvatarGradient(loop.avatarColor),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Center(
        child: Text(
          loop.name.isNotEmpty ? loop.name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0B0B0D).withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
