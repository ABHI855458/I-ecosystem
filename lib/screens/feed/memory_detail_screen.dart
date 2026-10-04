import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/layouts.dart';
import '../../services/feed_service.dart';
import '../../widgets/memory_canvas.dart';

class MemoryDetailScreen extends StatelessWidget {
  const MemoryDetailScreen({super.key, required this.item});
  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final layout = item.layoutId != null ? layoutById(item.layoutId!) : null;
    final photoUrls = item.photos ?? [];
    final images = photoUrls
        .map<ImageProvider?>((url) => CachedNetworkImageProvider(url))
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: layout != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: MemoryCanvas(layout: layout, images: images),
                    )
                  : const Center(
                      child: Text(
                        'Layout unavailable',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
