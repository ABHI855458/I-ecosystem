import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'current_user_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// CommunityFeedService — the member-authored `community_posts` noticeboard
// (text + up to 4 images + up to 2 PDFs, named or anonymous) and the
// dashboard-authored `community_feed_items` priority-notification channel,
// for one community at a time.
//
// This table is deliberately separate from `posts`/PostService — see the
// header comment on supabase/migrations/20260904000000_community_posts.sql
// for why. Posting HERE never advances a community's streak/XP; only an
// anonymous post through the existing composer's Anon destination does
// (see CommunityStreaksService and 20260904010000_community_streaks.sql).
//
// Image downscale mirrors GroupPostScreen's picker-level constraints
// (maxWidth 1440, quality 90 at PICK time — see
// profile_v2_create_flows.dart:1013), not ImagePrepService: that's the
// closest existing precedent for a multi-photo composer, and keeping one
// mechanism per flow avoids double-processing the same file.
// ---------------------------------------------------------------------------

const int kCommunityPostMaxImages = 4;
const int kCommunityPostMaxPdfs = 2;
const int kCommunityPostMaxPdfBytes = 10 * 1024 * 1024;
const int kCommunityPostMaxBodyChars = 1000;

/// Member feed posts (`community_posts`) drop out of [fetchPosts] 48h after
/// posting — confirmed with the user. Same convention as FeedService's
/// anon-feed 24h window: a query-time filter, not a delete or an
/// `expires_at` column, so the row (and any report/moderation trail on it)
/// still exists — it's just not shown in the normal feed view past the
/// window. Priority notices (`community_feed_items`, dashboard-authored)
/// run on their own, much longer window — see
/// [kPriorityItemVisibleWindow].
const kCommunityPostVisibleWindow = Duration(hours: 48);

/// How long a dashboard-authored priority notice stays in the community
/// feed. Explicit request: "the priority notifications shall go after 14
/// days" — these used to be permanent (the comment above still said so), so
/// a community feed only ever accumulated notices. Same query-filter rule
/// as every other window here: the row and its poll votes survive, they
/// just stop being listed. The dashboard applies the same cutoff
/// (PRIORITY_ITEM_VISIBLE_DAYS in src/lib/institutional.js).
const kPriorityItemVisibleWindow = Duration(days: 14);

String _priorityItemCutoff() =>
    DateTime.now().toUtc().subtract(kPriorityItemVisibleWindow).toIso8601String();

String _communityPostCutoff() =>
    DateTime.now().toUtc().subtract(kCommunityPostVisibleWindow).toIso8601String();

class CommunityPostDocument {
  const CommunityPostDocument({
    required this.id,
    required this.fileUrl,
    required this.fileName,
    this.fileSize,
  });

  final String id;
  final String fileUrl;
  final String fileName;
  final int? fileSize;

  factory CommunityPostDocument.fromRow(Map<String, dynamic> row) =>
      CommunityPostDocument(
        id: row['id'] as String,
        fileUrl: row['file_url'] as String,
        fileName: row['file_name'] as String,
        fileSize: row['file_size'] as int?,
      );
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.body,
    required this.photoUrls,
    required this.isAnonymous,
    required this.createdAt,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.documents,
    this.isMine = false,
  });

  final String id;
  final String communityId;

  /// Null for someone else's anonymous post: community_posts_feed never
  /// sends the author of an anonymous post to anyone but its author.
  final String? userId;

  /// The caller wrote this post (true even when it's anonymous).
  final bool isMine;
  final String? body;
  final List<String> photoUrls;
  final bool isAnonymous;
  final DateTime createdAt;
  /// Already masked by [fromRow] when [isAnonymous] — never the real name.
  final String authorName;
  final String? authorPhotoUrl;
  final List<CommunityPostDocument> documents;

  factory CommunityPost.fromRow(Map<String, dynamic> row) {
    final anon = row['is_anonymous'] as bool? ?? false;
    final user = row['users'] as Map<String, dynamic>?;
    final docs = (row['community_post_documents'] as List? ?? const [])
        .map((d) => CommunityPostDocument.fromRow(Map<String, dynamic>.from(d as Map)))
        .toList();
    return CommunityPost(
      id: row['id'] as String,
      communityId: row['community_id'] as String,
      userId: row['user_id'] as String?,
      body: row['body'] as String?,
      photoUrls: List<String>.from(row['photo_urls'] as List? ?? const []),
      isAnonymous: anon,
      createdAt: DateTime.parse(row['created_at'] as String),
      // Only used for the caller's OWN rows now (fetchMyPosts/createPost);
      // everyone else's posts come through community_posts_feed, masked
      // server-side (see [CommunityPost.fromFeedRow]).
      authorName: anon ? ((user?['anon_name'] as String?) ?? 'anonymous') : ((user?['name'] as String?) ?? 'someone'),
      authorPhotoUrl: anon ? null : user?['profile_photo_url'] as String?,
      documents: docs,
      isMine: true,
    );
  }

  /// A row from community_posts_feed(): author already masked server-side
  /// (anon name + anon avatar, no user_id) for anyone else's anonymous post.
  factory CommunityPost.fromFeedRow(Map<String, dynamic> row) => CommunityPost(
        id: row['id'] as String,
        communityId: row['community_id'] as String,
        userId: row['user_id'] as String?,
        body: row['body'] as String?,
        photoUrls: List<String>.from(row['photo_urls'] as List? ?? const []),
        isAnonymous: row['is_anonymous'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
        authorName: (row['author_name'] as String?) ?? 'someone',
        authorPhotoUrl: row['author_photo'] as String?,
        documents: [
          for (final d in (row['documents'] as List? ?? const []))
            CommunityPostDocument.fromRow(Map<String, dynamic>.from(d as Map)),
        ],
        isMine: row['is_mine'] as bool? ?? false,
      );
}

class CommunityPriorityItem {
  const CommunityPriorityItem({
    required this.id,
    required this.itemType,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.authorName,
    required this.documents,
    required this.pollOptions,
    required this.myVoteOptionId,
  });

  final String id;
  final String itemType; // 'news' | 'poll' | 'daily_prompt'
  final String title;
  final String? body;
  final DateTime createdAt;
  final String authorName;
  final List<CommunityPostDocument> documents;
  final List<CommunityPollOption> pollOptions;
  final String? myVoteOptionId;

  factory CommunityPriorityItem.fromRow(Map<String, dynamic> row, {String? myAuthId}) {
    final moderator = row['moderators'] as Map<String, dynamic>?;
    final docs = (row['community_feed_documents'] as List? ?? const [])
        .map((d) => CommunityPostDocument.fromRow(Map<String, dynamic>.from(d as Map)))
        .toList();
    final options = (row['community_feed_poll_options'] as List? ?? const [])
        .map((o) => CommunityPollOption.fromRow(Map<String, dynamic>.from(o as Map)))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    String? myVote;
    for (final o in (row['community_feed_poll_votes'] as List? ?? const [])) {
      final v = Map<String, dynamic>.from(o as Map);
      if (v['profile_id'] == myAuthId) myVote = v['option_id'] as String?;
    }
    return CommunityPriorityItem(
      id: row['id'] as String,
      itemType: row['item_type'] as String,
      title: row['title'] as String,
      body: row['body'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      authorName: (moderator?['email'] as String?)?.split('@').first ?? 'moderator',
      documents: docs,
      pollOptions: options,
      myVoteOptionId: myVote,
    );
  }
}

class CommunityPollOption {
  const CommunityPollOption({
    required this.id,
    required this.label,
    required this.position,
    required this.voteCount,
  });

  final String id;
  final String label;
  final int position;
  final int voteCount;

  factory CommunityPollOption.fromRow(Map<String, dynamic> row) => CommunityPollOption(
        id: row['id'] as String,
        label: row['label'] as String,
        position: row['position'] as int,
        voteCount: (row['community_feed_poll_votes'] as List? ?? const []).length,
      );
}

class CommunityFeedService {
  CommunityFeedService._();
  static final instance = CommunityFeedService._();

  final _sb = Supabase.instance.client;

  // ── Priority notices (dashboard-authored) ──────────────────────────────

  /// `community_feed_items` for one community, newest first, with nested
  /// poll options/votes and documents in a single round trip. Filters
  /// `deleted_at IS NULL` explicitly rather than trusting RLS alone — see
  /// the standing project note about permissive-policy OR-ing on `posts`;
  /// applying the same caution here even though no such second policy is
  /// known to exist on this table.
  Future<List<CommunityPriorityItem>> fetchPriorityItems(String communityId) async {
    try {
      final myAuthId = _sb.auth.currentUser?.id;
      final rows = await _sb
          .from('community_feed_items')
          .select('*, moderators(email), '
              // community_feed_documents has NO file_size column (confirmed
              // live — it's file_url/file_name/created_at only; file_size
              // exists on community_post_documents, the NEW member-post
              // table, not this pre-existing dashboard-side one). Selecting
              // it threw 42703 on every call. CommunityPostDocument.fromRow
              // already treats file_size as nullable, so simply omitting it
              // here is enough — no other change needed.
              'community_feed_documents(id, file_url, file_name), '
              'community_feed_poll_options(id, label, position, community_feed_poll_votes(profile_id)), '
              'community_feed_poll_votes(profile_id, option_id)')
          .eq('community_id', communityId)
          .isFilter('deleted_at', null)
          .gte('created_at', _priorityItemCutoff())
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .map((r) => CommunityPriorityItem.fromRow(Map<String, dynamic>.from(r as Map), myAuthId: myAuthId))
          .toList();
    } catch (e, st) {
      debugPrint('[CommunityFeedService.fetchPriorityItems] failed: $e\n$st');
      return const [];
    }
  }

  /// Upserts the caller's vote on `(feed_item_id, profile_id)`. Throws on
  /// failure — the poll card's optimistic fill must roll back if this does.
  Future<void> votePoll({required String feedItemId, required String optionId}) async {
    final authId = _sb.auth.currentUser?.id;
    if (authId == null) {
      throw StateError('CommunityFeedService.votePoll called with no signed-in user');
    }
    await _sb.from('community_feed_poll_votes').upsert({
      'feed_item_id': feedItemId,
      'option_id': optionId,
      'profile_id': authId,
    }, onConflict: 'feed_item_id,profile_id');
  }

  // ── Member posts (the noticeboard) ─────────────────────────────────────

  /// `community_posts` for one community, newest first, with the author
  /// join and nested documents. Fails closed to `[]` — an empty feed and a
  /// broken feed must look the same to a member with no posts, per this
  /// app's standing convention (see FeedService's own comment on the same
  /// choice).
  Future<List<CommunityPost>> fetchPosts(
    String communityId, {
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      // Through community_posts_feed, not the table: it masks the author of
      // every anonymous post server-side, so the real name never reaches
      // anyone else's phone.
      final rows = await _sb
          .rpc('community_posts_feed', params: {
            'p_community': communityId,
            'p_since': _communityPostCutoff(),
            'p_limit': limit,
            'p_offset': offset,
          })
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .map((r) => CommunityPost.fromFeedRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e, st) {
      debugPrint('[CommunityFeedService.fetchPosts] failed: $e\n$st');
      return const [];
    }
  }

  /// The caller's own posts in [communityId] — named or anonymous, and
  /// deliberately WITHOUT the 48h [_communityPostCutoff] filter [fetchPosts]
  /// applies: a post that's aged out of the general feed should still be
  /// visible here so its author can find and delete it. Backs the "My
  /// Posts" view reached from the composer's own header toggle — the only
  /// place a delete action is offered now that the feed's "..." menu is
  /// report/block-only (see community_post_menu.dart).
  ///
  /// `.eq('user_id', usersId)` naturally returns only rows the caller
  /// authored regardless of `is_anonymous` — RLS doesn't mask `user_id` in
  /// the row a caller queries by their own id, only in how the UI displays
  /// someone ELSE's anonymous post (see the FOLLOW-UP note on
  /// community_posts_block_filter in the migration for the broader caveat).
  Future<List<CommunityPost>> fetchMyPosts(String communityId) async {
    try {
      final usersId = await CurrentUserService.instance.resolveId();
      final rows = await _sb
          .from('community_posts')
          .select('*, users(name, anon_name, profile_photo_url), '
              'community_post_documents(id, file_url, file_name, file_size, position)')
          .eq('community_id', communityId)
          .eq('user_id', usersId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .map((r) => CommunityPost.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e, st) {
      debugPrint('[CommunityFeedService.fetchMyPosts] failed: $e\n$st');
      return const [];
    }
  }

  /// Uploads [imageFiles] (already downscaled by the caller — see the
  /// composer, which picks at maxWidth 1440/quality 90) and [pdfFiles],
  /// then inserts the post row. The post id is generated client-side
  /// BEFORE any upload so every file's storage path can share one prefix
  /// without depending on the not-yet-created row (see
  /// StorageService.uploadCommunityPhoto/uploadCommunityDoc).
  ///
  /// Uploads run sequentially, not in parallel — same reasoning as
  /// GroupService.addPost: predictable ordering matters more than upload
  /// speed here, and it keeps failure handling (which file, exactly, failed)
  /// legible. Throws on any failure; callers own the optimistic UI and its
  /// rollback (see PostService.addPost for the pattern).
  Future<CommunityPost> createPost({
    required String communityId,
    String? body,
    List<File> imageFiles = const [],
    List<File> pdfFiles = const [],
    required bool isAnonymous,
  }) async {
    if (imageFiles.length > kCommunityPostMaxImages) {
      throw ArgumentError('At most $kCommunityPostMaxImages images per post');
    }
    if (pdfFiles.length > kCommunityPostMaxPdfs) {
      throw ArgumentError('At most $kCommunityPostMaxPdfs PDFs per post');
    }
    final trimmedBody = body?.trim();
    // A message needs something: text, a photo, or a PDF (a PDF-only
    // message is fine, like sending a document on WhatsApp).
    if ((trimmedBody == null || trimmedBody.isEmpty) &&
        imageFiles.isEmpty &&
        pdfFiles.isEmpty) {
      throw ArgumentError('A post needs text or an attachment');
    }
    if (trimmedBody != null && trimmedBody.length > kCommunityPostMaxBodyChars) {
      throw ArgumentError('Body exceeds $kCommunityPostMaxBodyChars characters');
    }
    for (final f in pdfFiles) {
      final size = await f.length();
      if (size > kCommunityPostMaxPdfBytes) {
        throw ArgumentError('${f.path.split('/').last} is over the 10 MB PDF limit');
      }
    }

    final userId = await CurrentUserService.instance.resolveId();
    final postId = const Uuid().v4();

    final photoUrls = <String>[];
    for (final f in imageFiles) {
      final url = await StorageService.uploadCommunityPhoto(
        file: f,
        communityId: communityId,
        postId: postId,
      );
      if (url == null) throw StateError('Photo upload failed');
      photoUrls.add(url);
    }

    final docs = <Map<String, dynamic>>[];
    for (var i = 0; i < pdfFiles.length; i++) {
      final f = pdfFiles[i];
      final name = f.path.split('/').last;
      final url = await StorageService.uploadCommunityDoc(
        file: f,
        communityId: communityId,
        postId: postId,
        fileName: name,
      );
      if (url == null) throw StateError('PDF upload failed');
      docs.add({
        'file_url': url,
        'file_name': name,
        'file_size': await f.length(),
        'position': i,
      });
    }

    await _sb.from('community_posts').insert({
      'id': postId,
      'community_id': communityId,
      'user_id': userId,
      if (trimmedBody != null && trimmedBody.isNotEmpty) 'body': trimmedBody,
      if (photoUrls.isNotEmpty) 'photo_urls': photoUrls,
      'is_anonymous': isAnonymous,
    });

    if (docs.isNotEmpty) {
      await _sb.from('community_post_documents').insert(
        docs.map((d) => {...d, 'community_post_id': postId}).toList(),
      );
    }

    final rows = await _sb
        .from('community_posts')
        .select('*, users(name, anon_name, profile_photo_url), '
            'community_post_documents(id, file_url, file_name, file_size, position)')
        .eq('id', postId)
        .single();
    return CommunityPost.fromRow(Map<String, dynamic>.from(rows));
  }

  /// Soft-deletes one of the caller's own posts (or a moderator's, via
  /// community_posts_update_moderator) — same deleted_at convention as
  /// posts/community_feed_items.
  ///
  /// `.select('id')` verifies the write actually landed — see
  /// PostService.deletePost's own doc and migration
  /// 20260914010000_fix_soft_delete_visibility.sql for why a bare
  /// `.update()` here was a silent no-op on this project rather than a
  /// visible failure.
  Future<void> deletePost(String postId) async {
    final rows = await _sb
        .from('community_posts')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', postId)
        .select('id');
    if (rows.isEmpty) {
      throw StateError("Couldn't remove that post.");
    }
  }

  // ── Realtime ────────────────────────────────────────────────────────────

  /// New/changed posts in [communityId], filtered server-side. Listens to
  /// BOTH insert and update — delete is a soft-delete (`UPDATE ... SET
  /// deleted_at`, see [deletePost]), so an update listener is required for
  /// a post deleted from "My Posts" to actually disappear from the live
  /// feed of anyone else currently viewing it; insert-only was tried first
  /// and missed this. Caller owns the channel's lifecycle (subscribe in
  /// initState, unsubscribe in dispose) — see ReactionService
  /// .subscribeToPost / SpotlightPrivilegesController for the exact
  /// pattern this mirrors.
  RealtimeChannel subscribePosts(
    String communityId,
    void Function(PostgresChangePayload) onChange,
  ) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'community_id',
      value: communityId,
    );
    return _sb
        .channel('community_posts_$communityId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'community_posts',
          filter: filter,
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'community_posts',
          filter: filter,
          callback: onChange,
        )
        .subscribe();
  }
}
