import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'memory_service.dart';
import 'post_service.dart';

// ---------------------------------------------------------------------------
// FeedItem — unified feed entry (memory collage or single post)
// ---------------------------------------------------------------------------

class FeedItem {
  const FeedItem({
    required this.postId,
    required this.type,
    required this.userId,
    this.username,
    this.branch,
    this.caption,
    this.photoPath,
    this.photoUrl,
    this.photoColor,
    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
    this.layoutId,
    this.photos,
    this.createdAt,
  });

  final String postId;
  final String type; // 'memory' | 'single'
  final String userId;
  final String? username;
  final String? branch;
  final String? caption;
  final String? photoPath;
  final String? photoUrl;
  final Color? photoColor;
  final String? musicTitle;
  final String? musicArtist;
  final String? musicUrl;
  final String? layoutId;
  final List<String>? photos;
  final DateTime? createdAt;

  factory FeedItem.fromLocalPost(LocalPost p) => FeedItem(
        postId: p.id,
        type: 'single',
        userId: p.userId,
        username: p.username,
        branch: p.branch,
        caption: p.caption,
        photoPath: p.photoPath,
        photoUrl: p.photoUrl,
        musicTitle: p.musicTitle,
        musicArtist: p.musicArtist,
        musicUrl: p.musicUrl,
        createdAt: p.createdAt,
      );
}

// ---------------------------------------------------------------------------
// FeedService
// ---------------------------------------------------------------------------

class FeedService {
  FeedService._();
  static final instance = FeedService._();

  final _sb = Supabase.instance.client;

  Future<List<FeedItem>> fetchEveryoneFeed({int limit = 60}) async {
    try {
      final rows = await _sb
          .from('posts')
          .select('*, memories(*)')
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));

      return (rows as List).map<FeedItem>((r) {
        final m = Map<String, dynamic>.from(r as Map);
        final memory = m['memories'] as Map<String, dynamic>?;

        if (memory != null) {
          final photos = (memory['photos'] as List?)?.cast<String>();
          final photoUrls = photos
              ?.map((p) => MemoryService.instance.publicUrl(p))
              .toList();
          return FeedItem(
            postId: m['id'] as String? ?? '',
            type: 'memory',
            userId: m['user_id'] as String? ?? '',
            layoutId: memory['layout_id'] as String?,
            photos: photoUrls,
            createdAt: m['created_at'] != null
                ? DateTime.tryParse(m['created_at'] as String)
                : null,
          );
        }

        return FeedItem(
          postId: m['id'] as String? ?? '',
          type: 'single',
          userId: m['user_id'] as String? ?? '',
          caption: m['content'] as String?,
          photoUrl: m['image_url'] as String?,
          musicTitle: m['music_title'] as String?,
          musicArtist: m['music_artist'] as String?,
          musicUrl: m['music_url'] as String?,
          createdAt: m['created_at'] != null
              ? DateTime.tryParse(m['created_at'] as String)
              : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
