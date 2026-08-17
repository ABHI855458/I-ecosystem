import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../services/feed_service.dart';

/// Pure content — photo + a lightweight always-visible caption/music label
/// (real post content, not "chrome"). Gestures, the interactive action row,
/// and corner clipping live in `SpotlightCard`.
class SinglePostCard extends StatelessWidget {
  const SinglePostCard({super.key, required this.item, this.showFooter = true});
  final FeedItem item;

  /// EveryonePostCard (screens/feed/widgets/everyone_post_card.dart) draws
  /// its own caption block below the photo per the Feed Post Card v1 spec,
  /// so it passes false here — otherwise this widget's own on-photo caption
  /// scrim and that separate block show the same caption twice.
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _PhotoBackground(item: item),
        if (showFooter)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Footer(item: item),
          ),
      ],
    );
  }
}

class _PhotoBackground extends StatelessWidget {
  const _PhotoBackground({required this.item});
  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    if (item.photoPath != null) {
      return Image.file(File(item.photoPath!), fit: BoxFit.cover);
    }
    if (item.photoUrl != null) {
      return CachedNetworkImage(
        imageUrl: item.photoUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => _colorFill(item.postId),
      );
    }
    return _colorFill(item.postId);
  }

  Widget _colorFill(String id) {
    const palettes = [
      [Color(0xFF1C2A3C), Color(0xFF0D1520)],
      [Color(0xFF301A28), Color(0xFF1A0D15)],
      [Color(0xFF1E2C1E), Color(0xFF0D180D)],
      [Color(0xFF2A1A10), Color(0xFF150D08)],
      [Color(0xFF1A203C), Color(0xFF0D1020)],
    ];
    final idx = id.hashCode.abs() % palettes.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palettes[idx],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.item});
  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final hasCaption = item.caption != null && item.caption!.isNotEmpty;
    final hasMusic = item.musicTitle != null;

    if (!hasCaption && !hasMusic) return const SizedBox.shrink();

    return Container(
      // Extra right padding keeps the caption clear of the action pill
      // (react/comment/ping/share), which hugs the bottom-right edge.
      padding: const EdgeInsets.fromLTRB(12, 28, 96, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.80),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMusic) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.music_note_rounded,
                      color: Colors.white70, size: 14),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      item.musicArtist != null
                          ? '${item.musicTitle} · ${item.musicArtist}'
                          : item.musicTitle!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (hasCaption) const SizedBox(height: 8),
          ],
          if (hasCaption)
            Text(
              item.caption!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
