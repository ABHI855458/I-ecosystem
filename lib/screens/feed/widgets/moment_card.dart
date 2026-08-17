import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// DemoMoment — a PLACEHOLDER stand-in for a real Bucket/Moment (see
// bucket_service.dart for the real backing model: id, title, expires_at,
// community_id). Buckets/Moments data is sparse right now, so these are
// hardcoded local entries — never touches Supabase, same pattern
// DemoContent.demoPosts uses — purely so the Everyone feed's Moment card UI
// is visually testable immediately. Swap for real BucketService data once
// enough buckets exist to make a live feed integration worth building.
// ---------------------------------------------------------------------------

class DemoMoment {
  const DemoMoment({
    required this.id,
    required this.title,
    required this.contributorCount,
    required this.timeLeft,
    required this.gradient,
    required this.icon,
  });

  final String id;
  final String title;
  final int contributorCount;

  /// Pre-formatted, e.g. "6h left" — a real integration would derive this
  /// from `buckets.expires_at`, same as this app's other "Xh"/"Xm" labels
  /// (see LocalPost.timeLabel).
  final String timeLeft;

  final List<Color> gradient;
  final IconData icon;
}

final List<DemoMoment> kDemoMoments = [
  DemoMoment(
    id: 'demo-moment-1',
    title: 'Quad Golden Hour',
    contributorCount: 14,
    timeLeft: '3h left',
    gradient: const [Color(0xFFFF9A6C), Color(0xFFE1306C)],
    icon: Icons.wb_twilight_rounded,
  ),
  DemoMoment(
    id: 'demo-moment-2',
    title: 'Gameday Watch Party',
    contributorCount: 41,
    timeLeft: '18h left',
    gradient: const [Color(0xFF405DE6), Color(0xFF833AB4)],
    icon: Icons.sports_football_rounded,
  ),
  DemoMoment(
    id: 'demo-moment-3',
    title: 'Finals Week Grind',
    contributorCount: 9,
    timeLeft: '2d left',
    gradient: const [Color(0xFF0F2027), Color(0xFF2C5364)],
    icon: Icons.local_cafe_rounded,
  ),
];

// ---------------------------------------------------------------------------
// MomentCard — glass-themed, weather-app-widget-style card: soft gradient
// background, frosted blur, a headline title, and a time-remaining pill —
// deliberately distinct from a post card (no photo, no reactions/comments)
// so it reads at a glance as "a Moment, not a post" while scrolling.
// ---------------------------------------------------------------------------

class MomentCard extends StatelessWidget {
  const MomentCard({super.key, required this.moment, this.onTap});

  final DemoMoment moment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 132,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: moment.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: moment.gradient.last.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Frosted glass sheen over the gradient — the "weather app
              // widget" look: soft blur + a faint white wash, not a flat
              // solid gradient block.
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(moment.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'MOMENT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const Spacer(),
                        _TimeLeftPill(label: moment.timeLeft),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      moment.title,
                      style: GoogleFonts.figtree(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.photo_camera_rounded, size: 13, color: Colors.white70),
                        const SizedBox(width: 5),
                        Text(
                          '${moment.contributorCount} contributed',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeLeftPill extends StatelessWidget {
  const _TimeLeftPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
