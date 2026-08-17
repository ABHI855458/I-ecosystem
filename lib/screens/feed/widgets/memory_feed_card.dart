import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../data/layouts.dart';
import '../../../services/feed_service.dart';
import '../../../widgets/memory_canvas.dart';

/// Pure content — the collage canvas only. Gestures, action row, and corner
/// clipping live in `SpotlightCard`, which wraps this uniformly with the
/// other card type so blur/dim/scale apply consistently.
class MemoryFeedCard extends StatelessWidget {
  const MemoryFeedCard({super.key, required this.item});
  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final layout = item.layoutId != null ? layoutById(item.layoutId!) : null;
    if (layout == null) return const SizedBox.shrink();

    final photoUrls = item.photos ?? [];
    final images = photoUrls
        .map<ImageProvider?>((url) => CachedNetworkImageProvider(url))
        .toList();

    return SizedBox.expand(child: MemoryCanvas(layout: layout, images: images));
  }
}
