// ---------------------------------------------------------------------------
// Personal highlights — the polaroids on a profile and on the Wall.
//
// A highlight is a named, hand-picked set of photos. Each photo is a quiet
// `posts` row (post_type 'highlight', visibility 'friends', show_in_feed
// false) — see supabase/migrations/20261007010000_personal_highlights.sql
// for why, and for who can see one (the owner's Friends circle, the same
// rule as a friends-only post).
// ---------------------------------------------------------------------------

class HighlightPhoto {
  const HighlightPhoto({
    required this.postId,
    required this.url,
    this.aspect = 0.8,
    this.videoUrl,
    this.videoMs,
  });

  /// The quiet post behind this photo — what reactions, comments and
  /// "seen by" are recorded against.
  final String postId;

  /// The photo — or, for a video, its poster still (posts require one).
  final String url;

  /// Width / height.
  final double aspect;

  /// Set when this item is a short video (2026-10-07: "uploading a short
  /// video as well into the highlights"). [url] is then its poster.
  final String? videoUrl;
  final int? videoMs;

  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;
}

class Highlight {
  const Highlight({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.updatedAt,
    required this.photos,
    this.ownerName = '',
    this.ownerAvatarUrl,
  });

  final String id;
  final String ownerId;
  final String title;

  /// `highlights.updated_at` exactly as the server sent it. Only ever
  /// compared for equality (the local "seen" stamp), never parsed: the
  /// column is a zoneless timestamp, and it moves only when photos are
  /// ADDED — which is what makes a polaroid "new" again.
  final String updatedAt;

  /// In display order; the first one is the cover. Never empty for a
  /// highlight returned by HighlightService (ones with nothing visible to
  /// this viewer are dropped).
  final List<HighlightPhoto> photos;

  final String ownerName;
  final String? ownerAvatarUrl;

  String? get coverUrl => photos.isEmpty ? null : photos.first.url;

  /// The cover's own shape, so its polaroid can show it whole.
  double get coverAspect => photos.isEmpty ? 1 : photos.first.aspect;

  bool get coverIsVideo => photos.isNotEmpty && photos.first.isVideo;

  /// From a `highlights` row with its items and their posts embedded (see
  /// HighlightService._select). Null when no photo in it is visible.
  static Highlight? fromRow(Map<String, dynamic> row) {
    final items = [
      for (final i in (row['highlight_items'] as List? ?? const []))
        Map<String, dynamic>.from(i as Map),
    ]..sort(
        (a, b) => ((a['position'] as num?) ?? 0).compareTo(
          (b['position'] as num?) ?? 0,
        ),
      );
    final photos = <HighlightPhoto>[];
    for (final i in items) {
      final post = i['posts'];
      if (post is! Map) continue;
      if (post['deleted_at'] != null) continue;
      final url = _photoUrlOf(post);
      if (url == null) continue;
      photos.add(
        HighlightPhoto(
          postId: post['id'] as String,
          url: url,
          aspect: _aspectOf(post['aspect_ratio']),
          videoUrl: post['video_url'] as String?,
          videoMs: (post['video_duration_ms'] as num?)?.toInt(),
        ),
      );
    }
    if (photos.isEmpty) return null;
    final owner = row['users'];
    return Highlight(
      id: row['id'] as String,
      ownerId: row['user_id'] as String,
      title: (row['title'] as String?)?.trim() ?? '',
      updatedAt: (row['updated_at'] ?? '').toString(),
      photos: photos,
      ownerName: owner is Map
          ? ((owner['name'] as String?)?.trim().isNotEmpty == true
                ? (owner['name'] as String).trim()
                : (owner['username'] as String?) ?? '')
          : '',
      ownerAvatarUrl: owner is Map
          ? owner['profile_photo_url'] as String?
          : null,
    );
  }

  static String? _photoUrlOf(Map<dynamic, dynamic> post) {
    final single = post['image_url'] as String?;
    if (single != null && single.isNotEmpty) return single;
    final many = post['photo_urls'];
    if (many is List && many.isNotEmpty) return many.first as String?;
    return null;
  }

  /// posts.aspect_ratio is text: a plain number ("0.8") or "w:h".
  static double _aspectOf(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return 0.8;
    final direct = double.tryParse(s);
    if (direct != null && direct > 0) return direct;
    final parts = s.split(':');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0]);
      final h = double.tryParse(parts[1]);
      if (w != null && h != null && w > 0 && h > 0) return w / h;
    }
    return 0.8;
  }
}

/// One item in the editor: either already saved ([postId]) or freshly
/// picked from the phone ([localPath]) and not uploaded yet. A local VIDEO
/// carries the video file in [localVideoPath] and its poster still in
/// [localPath], so everything that draws "the photo" keeps working.
class HighlightDraftPhoto {
  const HighlightDraftPhoto.saved({
    required String this.postId,
    this.url,
    this.isVideo = false,
  }) : localPath = null,
       localVideoPath = null,
       videoMs = null;
  const HighlightDraftPhoto.local(String this.localPath)
    : postId = null,
      url = null,
      localVideoPath = null,
      videoMs = null,
      isVideo = false;
  const HighlightDraftPhoto.localVideo({
    required String videoPath,
    required String posterPath,
    required int this.videoMs,
  }) : postId = null,
       url = null,
       localPath = posterPath,
       localVideoPath = videoPath,
       isVideo = true;

  final String? postId;
  final String? url;
  final String? localPath;
  final String? localVideoPath;
  final int? videoMs;
  final bool isVideo;

  bool get isLocal => localPath != null;
}

/// Why a save was refused, in words for the person.
class HighlightException implements Exception {
  const HighlightException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Newest-unseen first, then the rest by most recently updated — the order
/// the Wall and the feed pile both use. [isNew] is injected so this stays
/// a pure function (tests don't need the seen store).
List<Highlight> sortForWall(
  List<Highlight> all, {
  required bool Function(Highlight) isNew,
}) {
  final fresh = <Highlight>[];
  final seen = <Highlight>[];
  for (final h in all) {
    (isNew(h) ? fresh : seen).add(h);
  }
  int byUpdated(Highlight a, Highlight b) =>
      b.updatedAt.compareTo(a.updatedAt);
  fresh.sort(byUpdated);
  seen.sort(byUpdated);
  return [...fresh, ...seen];
}
