import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// PostPhotoCarousel — the photo area of a post card. Renders a single image
// when given one URL, and an Instagram-style horizontally-swipeable pager
// with dot indicators when given several.
//
// Deliberately ONLY the photo surface: the card's own overlays (live pill
// dropdown, Ping/RealMoji rail, reactions pill) stay where they are in the
// host card's Stack, layered above this. That's what keeps multi-photo a
// drop-in swap for the single CachedNetworkImage it replaces, with zero
// change to any surrounding widget's position or styling.
//
// The gradient scrim is applied ABOVE the pager rather than per-page, so it
// never scrolls with the photos — it's card chrome (it exists to keep the
// overlaid controls legible), not part of any one image.
// ---------------------------------------------------------------------------

class PostPhotoCarousel extends StatefulWidget {
  const PostPhotoCarousel({
    super.key,
    required this.photoUrls,
    this.aspectRatio = 4 / 5,
    this.borderRadius = 26,
    this.showScrim = true,
    this.roundTopOnly = false,
    this.blurFromIndex,
  });

  /// One entry renders as a plain image (no pager, no dots) — identical to
  /// the pre-carousel behavior. Empty renders nothing.
  final List<String> photoUrls;

  final double aspectRatio;
  final double borderRadius;

  /// The top/bottom darkening that keeps overlaid controls legible. Off for
  /// hosts that have no overlays (e.g. a profile grid tile).
  final bool showScrim;

  /// Square off the bottom corners, for a full-bleed card whose photo meets
  /// the footer rather than floating inside a padded frame.
  final bool roundTopOnly;

  /// Photos at this index and after are shown blurred and locked — a
  /// private group's post seen through a shared community (FeedItem.
  /// groupPostLocked passes 1: first photo clear, the rest blurred). Null =
  /// every photo clear.
  final int? blurFromIndex;

  @override
  State<PostPhotoCarousel> createState() => _PostPhotoCarouselState();
}

class _PostPhotoCarouselState extends State<PostPhotoCarousel> {
  late final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.photoUrls;
    if (urls.isEmpty) return const SizedBox.shrink();
    final isMulti = urls.length > 1;

    return ClipRRect(
      borderRadius: widget.roundTopOnly
          ? BorderRadius.vertical(top: Radius.circular(widget.borderRadius))
          : BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isMulti)
              PageView.builder(
                controller: _controller,
                itemCount: urls.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _photo(urls[i], i),
              )
            else
              _photo(urls.first, 0),

            if (widget.showScrim)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.22),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.42),
                      ],
                      stops: const [0.0, 0.18, 0.60, 1.0],
                    ),
                  ),
                ),
              ),

            // Counter pill (top-right) — only worth showing when there's
            // more than one photo. Sits opposite the live pill/menu the host
            // card puts top-left, so the two never collide.
            if (isMulti)
              Positioned(
                top: 12,
                right: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '${_page + 1}/${urls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

            // Dots — bottom-CENTER. The host card's own controls live in the
            // bottom-left and bottom-right corners, so centering keeps the
            // indicator clear of both without moving either of them.
            if (isMulti)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < urls.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 7 : 5.5,
                          height: i == _page ? 7 : 5.5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: i == _page ? 0.95 : 0.45),
                            boxShadow: const [
                              BoxShadow(color: Color(0x66000000), blurRadius: 3),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _photo(String url, int index) {
    final from = widget.blurFromIndex;
    if (from == null || index < from) {
      return CachedNetworkImage(
        memCacheWidth: 1080,
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Container(color: const Color(0xFF1A1A1E)),
      );
    }
    // Locked page: decoded tiny (no detail to recover from memory) and
    // blurred hard, with a lock so it reads as locked rather than broken.
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: CachedNetworkImage(
            memCacheWidth: 48,
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(color: const Color(0xFF1A1A1E)),
          ),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 15, color: Colors.white),
                SizedBox(width: 7),
                Text(
                  'Be a friend to see it',
                  style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Resolves a post's photo list from the additive schema: `photo_urls` when
/// present and non-empty, otherwise the legacy single column. Kept here so
/// every card resolves it identically instead of each re-implementing the
/// fallback. See migration 20260831000000_multi_photo_posts.sql.
List<String> resolvePostPhotos({List<String>? photoUrls, String? singleUrl}) {
  if (photoUrls != null && photoUrls.isNotEmpty) return photoUrls;
  if (singleUrl != null && singleUrl.isNotEmpty) return [singleUrl];
  return const [];
}
