import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/wall_service.dart';
import '../memory_wall_screen.dart';

const _wallHeroTag = 'wall-preview-strip';

/// Slim horizontal strip of tilted polaroid-style highlight peeks, pinned
/// onto a corkboard-style panel. Tapping the title expands (Hero) into
/// `MemoryWallScreen`; tapping an individual photo opens it directly.
/// Hidden entirely if there are no highlights yet.
class WallPreviewStrip extends StatelessWidget {
  const WallPreviewStrip({super.key, required this.highlights});
  final List<Highlight> highlights;

  void _openWall(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(_wallExpandRoute(highlights));
  }

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3E2E22), Color(0xFF241A12)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openWall(context),
              child: Hero(
                tag: _wallHeroTag,
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    'The Wall 📌',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: highlights.length.clamp(0, 6),
                itemBuilder: (context, i) => _Peek(
                  highlight: highlights[i],
                  index: i,
                  onTap: () => _openWall(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Peek extends StatelessWidget {
  const _Peek({required this.highlight, required this.index, required this.onTap});
  final Highlight highlight;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final angle = (index.isEven ? -1 : 1) * (4 + (index % 3) * 2) * 3.14159265 / 180;
    final photo = highlight.photos.first;

    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 6),
      child: Transform.rotate(
        angle: angle,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 60,
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(1, 3)),
                  ],
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
              memCacheWidth: 1080,
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(color: Colors.black12),
                  ),
                ),
              ),
              // Pin/tack — reinforces the "pinned to the board" feel.
              Positioned(
                top: -6,
                left: 26,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE1306C),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 3, offset: const Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Route<void> _wallExpandRoute(List<Highlight> highlights) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, anim, secAnim) => MemoryWallScreen(highlights: highlights),
    transitionsBuilder: (context, anim, secAnim, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: const Interval(0.3, 1.0)),
        child: child,
      );
    },
  );
}
