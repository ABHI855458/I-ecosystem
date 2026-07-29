import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// LocalPost — a post created this session (local + Supabase-backed)
// ---------------------------------------------------------------------------

class LocalPost {
  LocalPost({
    required this.id,
    required this.userId,
    this.username = 'you',
    required this.visibility,
    this.caption = '',
    this.branch,
    this.photoPath,
    this.photoUrl,
    this.aspectRatio = 4.0 / 5.0,
    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
    this.localOnly = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String userId;
  final String username;

  /// 'everyone' or 'anonymous'
  final String visibility;
  final String caption;

  /// Poster's community/major tag (e.g. "CSE") shown next to their name.
  final String? branch;

  /// Absolute path to the local captured/picked image file.
  final String? photoPath;

  /// Remote image URL (used by demo/seed content instead of a local file).
  final String? photoUrl;
  final double aspectRatio;
  final String? musicTitle;
  final String? musicArtist;
  final String? musicUrl;
  final DateTime createdAt;

  /// Demo/seed posts never round-trip to Supabase.
  final bool localOnly;

  bool get isAnonymous => visibility == 'anonymous';
  bool get isEveryone => visibility == 'everyone';

  String get timeLabel {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}

// ---------------------------------------------------------------------------
// PostService — singleton
// ---------------------------------------------------------------------------

class PostService {
  PostService._();
  static final PostService instance = PostService._();

  final List<LocalPost> _posts = [];

  // Separate broadcast streams so EveryoneTab and Profile can each subscribe
  final _everyoneCtrl = StreamController<List<LocalPost>>.broadcast();
  final _myPostsCtrl = StreamController<List<LocalPost>>.broadcast();

  Stream<List<LocalPost>> get everyoneFeedStream => _everyoneCtrl.stream;
  Stream<List<LocalPost>> get myPostsStream => _myPostsCtrl.stream;

  // Synchronous snapshot reads (for initial state before first event)
  List<LocalPost> get everyonePosts =>
      _posts.where((p) => p.isEveryone).toList();
  List<LocalPost> get anonPosts =>
      _posts.where((p) => p.isAnonymous).toList();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Throws if the Supabase write fails — callers must not swallow this.
  /// The optimistic local insert is rolled back on failure so the UI never
  /// shows a post that isn't actually saved.
  Future<void> addPost(LocalPost post) async {
    _posts.insert(0, post);
    _emit();
    if (!post.localOnly) {
      try {
        await _saveToSupabase(post);
      } catch (_) {
        _posts.remove(post);
        _emit();
        rethrow;
      }
    }
  }

  /// The signed-in user's own anonymous posts, WITH identity attached —
  /// backs the profile's "Private" tab. Reads through `posts_feed`, not the
  /// raw `posts` table: that view is what un-masks `user_id` for a row's
  /// own author while keeping it null for everyone else, so filtering by
  /// `.eq('user_id', myId)` here only ever matches rows this caller
  /// actually owns — someone else's anonymous posts come back with
  /// user_id == null from the view and can never match the filter, even if
  /// this method were called for the wrong reasons.
  Future<List<Map<String, dynamic>>> myAnonymousPosts() async {
    final userId = await CurrentUserService.instance.resolveId();
    final rows = await supabase
        .from('posts_feed')
        .select()
        .eq('visibility', 'anonymous')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _emit() {
    _everyoneCtrl.add(everyonePosts);
    _myPostsCtrl.add(List.unmodifiable(_posts));
  }

  Future<void> _saveToSupabase(LocalPost post) async {
    String? imageUrl;
    if (post.photoPath != null) {
      try {
        imageUrl = await StorageService.uploadPostImage(
          file: File(post.photoPath!),
          isAnon: post.isAnonymous,
          userId: post.userId,
          postId: post.id,
        );
        debugPrint('[PostService] Image upload OK for post ${post.id}: $imageUrl');
      } catch (e, st) {
        debugPrint('[PostService] Image upload FAILED for post ${post.id}: $e\n$st');
        rethrow;
      }
    }

    try {
      await supabase.from('posts').insert({
        'id': post.id,
        'user_id': post.userId,
        'visibility': post.visibility,
        'caption': post.caption,
        'image_url': ?imageUrl,
        'aspect_ratio': post.aspectRatio,
        if (post.musicTitle != null) 'music_title': post.musicTitle,
        if (post.musicArtist != null) 'music_artist': post.musicArtist,
        if (post.musicUrl != null) 'music_url': post.musicUrl,
        'created_at': post.createdAt.toIso8601String(),
      });
      debugPrint('[PostService] Insert OK for post ${post.id}');
    } catch (e, st) {
      debugPrint('[PostService] Insert FAILED for post ${post.id}: $e\n$st');
      rethrow;
    }
  }
}
