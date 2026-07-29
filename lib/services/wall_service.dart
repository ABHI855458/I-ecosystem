import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo_content.dart';

class Highlight {
  const Highlight({
    required this.id,
    required this.userId,
    required this.title,
    required this.photos,
    this.iconUrl,
  });

  final String id;
  final String userId;
  final String title;
  final List<String> photos;
  final String? iconUrl;

  factory Highlight.fromMap(Map<String, dynamic> m) => Highlight(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        title: m['title'] as String? ?? '',
        photos: (m['photos'] as List?)?.cast<String>() ?? const [],
        iconUrl: m['icon_url'] as String?,
      );
}

/// Backs the feed's "Wall" preview strip from the existing (currently
/// unused) `highlights` table.
class WallService {
  WallService._();
  static final instance = WallService._();

  final _sb = Supabase.instance.client;

  /// Falls back to local demo highlights when the (currently unpopulated)
  /// `highlights` table has nothing yet, so the Wall always has content.
  Future<List<Highlight>> fetchTopHighlights({int limit = 8}) async {
    try {
      final rows = await _sb
          .from('highlights')
          .select()
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 8));
      final remote = (rows as List)
          .map((r) => Highlight.fromMap(Map<String, dynamic>.from(r as Map)))
          .where((h) => h.photos.isNotEmpty)
          .toList();
      return remote.isEmpty ? DemoContent.demoHighlights : remote;
    } catch (_) {
      return DemoContent.demoHighlights;
    }
  }
}
