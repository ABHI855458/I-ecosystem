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
            _ActionRow(item: item),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({required this.item});
  final FeedItem item;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _liked = false;
  int _likes = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _liked = !_liked;
                _likes += _liked ? 1 : -1;
              });
            },
            child: Row(
              children: [
                Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? const Color(0xFFE1306C) : Colors.white54,
                  size: 22,
                ),
                if (_likes > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$_likes',
                    style: TextStyle(
                      color: _liked ? const Color(0xFFE1306C) : Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.chat_bubble_outline,
                color: Colors.white54, size: 22),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.share_outlined,
                color: Colors.white54, size: 22),
          ),
        ],
      ),
    );
  }
}
