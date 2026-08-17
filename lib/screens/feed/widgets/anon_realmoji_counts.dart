import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/realmoji_service.dart';

// ---------------------------------------------------------------------------
// AnonRealmojiCounts — Anonymous feed only. Emoji + count chips, sourced
// from RealmojiService.fetchAnonCounts (the anon_reaction_counts view) —
// NEVER post_realmoji_reactions or user_realmojis directly, which both
// carry a user_id. No faces, no names, no tap-to-see-who, ever, per spec
// item 5. Visually mirrors PhotoPostCard's existing EmojiReactionRow
// (chip-per-emoji, count inside) so it reads as the same family of UI as
// the rest of that card, just fed by the new schema.
// ---------------------------------------------------------------------------

class AnonRealmojiCounts extends StatelessWidget {
  const AnonRealmojiCounts({super.key, required this.counts});

  final List<AnonRealmojiCount> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in counts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.emojiType.glyph, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Text(
                  '${c.count}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
