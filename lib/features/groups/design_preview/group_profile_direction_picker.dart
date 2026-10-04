import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'group_profile_cover_screen.dart';
import 'group_profile_roster_screen.dart';
import 'group_profile_streak_screen.dart';

/// Debug-only comparison picker for the three Group Profile design
/// directions from design-refs/design_handoff_group_profile — reachable via
/// lib/main.dart's `_screenshotMode` debug switch (mode 40). All three push
/// screens built against the same MockGroupData instance so they're
/// directly comparable; none of this touches the real, live-data
/// group_profile_screen.dart.
class GroupProfileDirectionPicker extends StatelessWidget {
  const GroupProfileDirectionPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Group Profile — directions',
                style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'Mock-data comparison, not the shipped screen.',
                style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 28),
              _DirectionButton(
                id: '1a',
                title: 'Cover',
                subtitle: 'Collage banner, stats bar, tabbed posts grid.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GroupProfileCoverScreen()),
                ),
              ),
              const SizedBox(height: 12),
              _DirectionButton(
                id: '1b',
                title: 'Streak',
                subtitle: "Today's slots, streak number, calendar.",
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GroupProfileStreakScreen()),
                ),
              ),
              const SizedBox(height: 12),
              _DirectionButton(
                id: '1c',
                title: 'Roster',
                subtitle: 'People-first cards, one per member.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GroupProfileRosterScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({required this.id, required this.title, required this.subtitle, required this.onTap});
  final String id;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              child: Text(id, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
