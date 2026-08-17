import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'group_service.dart';
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
    this.avatarUrl,
    this.commentCount = 0,
    this.groupId,
    this.groupName,
    this.communityTag,
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

  /// The poster's real profile photo, for EveryonePostCard's header row.
  /// Not yet wired to a real query (fetchEveryoneFeed doesn't join `users`
  /// below — the FK relationship name PostgREST would need wasn't
  /// confirmed, and guessing it risks breaking the whole feed fetch, which
  /// already fails closed to an empty list on any query error) — always
  /// null for now, so the header falls back to its plain person glyph.
  final String? avatarUrl;

  /// Also not wired yet — this feed has no comments-count query in place,
  /// so EveryonePostCard's comment icon/row always reads 0 until one exists.
  final int commentCount;

  /// The group this post belongs to — set only for GROUP posts, alongside
  /// [groupName]. Drives GroupPostCard's own member/post lookups (see
  /// screens/feed/widgets/group_post_cards/group_post_card.dart).
  final String? groupId;

  /// Set only for GROUP posts (group_posts, not the regular per-user
  /// `posts` table) — the group's display name, e.g. "CS Study Group".
  /// Null for a regular individual post. Drives EveryonePostCard's
  /// "Posted by {groupName} · {username}" attribution line and its small
  /// community tag — individual posts show neither (see item #4: the
  /// on-photo community tag was removed from individual anonymous posts;
  /// group posts are the one place a community indicator still belongs,
  /// since it's structurally relevant to a group in a way it isn't to an
  /// anonymous individual).
  final String? groupName;

  /// The community the group belongs to (e.g. "CSE") — shown as a small
  /// tag/pill beside the group attribution line. Ignored when [groupName]
  /// is null.
  final String? communityTag;

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

  Future<List<FeedItem>> fetchEveryoneFeed({int limit = 60, int offset = 0}) async {
    try {
      final rows = await _sb
          .from('posts')
          .select('*, memories(*)')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
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

  /// Real GROUP posts for the Everyone/Friends feed — every group_posts row
  /// from a group the caller belongs to, mapped to the same FeedItem shape
  /// individual posts use so EveryonePostCard's existing groupName support
  /// (see FeedItem.groupName's own doc) renders them with zero widget
  /// changes. communityTag is always null: groups have no community concept
  /// in this schema (no community_id column on `groups`), unlike the demo
  /// placeholders this replaces which had a fabricated one.
  Future<List<FeedItem>> fetchGroupFeed({int limit = 30, int offset = 0}) async {
    try {
      final rows = await GroupService.instance
          .fetchFeedPosts(limit: limit, offset: offset);
      return rows.map((r) {
        final group = r['groups'] as Map?;
        final user = r['users'] as Map?;
        return FeedItem(
          postId: r['id'] as String? ?? '',
          type: 'single',
          userId: r['user_id'] as String? ?? '',
          username: user?['name'] as String?,
          avatarUrl: user?['profile_photo_url'] as String?,
          caption: r['caption'] as String?,
          photoUrl: r['photo_url'] as String?,
          createdAt: r['created_at'] != null
              ? DateTime.tryParse(r['created_at'] as String)
              : null,
          groupId: r['group_id'] as String?,
          groupName: group?['name'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Paginated anonymous-feed posts, via `posts_feed` (masks user_id for
  /// anon rows the same way [PostService.myAnonymousPosts] relies on) —
  /// AnonymousTab had zero backend query before this; it rendered only the
  /// hardcoded `_kPosts` demo list.
  Future<List<Map<String, dynamic>>> fetchAnonFeed({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final rows = await _sb
          .from('posts_feed')
          .select()
          .eq('visibility', 'anonymous')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 10));
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }
}
