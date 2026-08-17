import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/wall_service.dart';
import 'widgets/photo_lightbox.dart';

const _wallHeroTag = 'wall-preview-strip';

/// Full-screen highlights view reached by expanding the feed's Wall
/// preview strip. Real data (the existing `highlights` table), simple
/// grid presentation — the full curated "wall" experience described in
/// the brief is a separate, larger build.
class MemoryWallScreen extends StatelessWidget {
  const MemoryWallScreen({super.key, required this.highlights});
  final List<Highlight> highlights;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3E2E22), Color(0xFF16110C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Hero(
                      tag: _wallHeroTag,
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          'The Wall 📌',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 22,
                    childAspectRatio: 0.76,
                  ),
                  itemCount: highlights.length,
                  itemBuilder: (context, i) => _HighlightTile(highlight: highlights[i], index: i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({required this.highlight, required this.index});
  final Highlight highlight;
  final int index;

  @override
  Widget build(BuildContext context) {
    final angle = (index.isEven ? -1 : 1) * (3 + (index % 3) * 2) * 3.14159265 / 180;

    return Transform.rotate(
      angle: angle,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          openPhotoLightbox(context, photos: highlight.photos);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(2, 5)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: CachedNetworkImage(
                      imageUrl: highlight.photos.first,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    highlight.title,
                    style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Positioned(
              top: -7,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE1306C),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
