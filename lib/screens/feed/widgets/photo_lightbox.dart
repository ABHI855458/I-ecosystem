import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen swipeable photo viewer. Tapping a pinned photo (in the Wall
/// strip or the Wall grid) opens straight to that photo instead of just
/// dropping the user into the grid screen.
void openPhotoLightbox(
  BuildContext context, {
  required List<String> photos,
  int initialIndex = 0,
  String? heroTag,
}) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, anim, secAnim) => FadeTransition(
      opacity: anim,
      child: _PhotoLightbox(
        photos: photos,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
    ),
  ));
}

class _PhotoLightbox extends StatefulWidget {
  const _PhotoLightbox({
    required this.photos,
    required this.initialIndex,
    this.heroTag,
  });

  final List<String> photos;
  final int initialIndex;
  final String? heroTag;

  @override
  State<_PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<_PhotoLightbox> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final image = PageView.builder(
      controller: _controller,
      itemCount: widget.photos.length,
      itemBuilder: (context, i) => Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: CachedNetworkImage(
              memCacheWidth: 1080,
            imageUrl: widget.photos[i],
            fit: BoxFit.contain,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: widget.heroTag != null && widget.photos.length == 1
                  ? Hero(tag: widget.heroTag!, child: image)
                  : image,
            ),
          ),
          Positioned(
            top: topPad + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
