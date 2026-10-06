import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'current_user_service.dart';
// Cyclic with feed_service.dart (which imports this file) — legal in Dart
// and safe here: the only thing used across the cycle is
// FeedService.anonCutoff(), a static method invoked at RUNTIME, not a
// top-level initializer, so there's no initialization-order hazard. Kept as
// an import rather than duplicating the 24h window constant, so the anon
// feed and the anon profile tab can never drift out of sync.
import 'feed_service.dart';
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
    this.postType,
    this.momentColor,
    this.prompt,
    this.communityId,
    this.promptId,
    this.branch,
    this.photoPath,
    this.videoPath,
    this.videoMs,
    this.photoUrls,
    this.photoUrl,
    this.aspectRatio = 4.0 / 5.0,
    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
    this.localOnly = false,
    this.showInFeed = true,
    this.audienceCommunityIds = const [],
    this.audienceCircleIds = const [],
    this.secondaryPhotoPath,
    this.insetOnRight = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String userId;
  final String username;

  /// 'everyone', 'anonymous', or 'friends' (C1 — the composer's audience
  /// picker: 'friends' plus zero-or-more communities in
  /// [audienceCommunityIds], enforced server-side by posts_select's
  /// can_view_post() gate — see 20260908010000_post_audiences.sql).
  final String visibility;
  final String caption;

  /// `posts.post_type` discriminator — 'moment', 'memory', or 'single'. Null
  /// means an ordinary post and is written as 'single': the column's DB
  /// DEFAULT is 'moment' (schema.sql), so leaving it out would silently mark
  /// every ordinary post a Moment and render it as a gradient MomentCard.
  final String? postType;

  /// Which preset gradient a Moment was posted with (palette id — see
  /// kMomentPalettes). Null for every non-moment post.
  final String? momentColor;

  bool get isMoment => postType == 'moment';

  /// `posts.prompt` — the one-line heading shown in the anon feed's peek bar
  /// (AnonFeedPost.prompt → _AnonBottomBlock) and its prompt pill. Either the
  /// daily prompt this post answers (when opened from the prompt bar) or the
  /// curiosity heading the poster typed in the composer. Nothing wrote this
  /// column before, so every anon post prior to this had a blank peek bar.
  final String? prompt;

  /// `posts.community_id` — which community an anonymous post was sent to.
  final String? communityId;

  /// `posts.prompt_id` — the `daily_prompts` row this post answers, when it
  /// was opened by tapping the anon feed's rotating prompt bar (see
  /// DailyPromptService). Null for a manually-typed heading or when the
  /// bar fell back to PromptService's hardcoded, DB-less list.
  final String? promptId;

  /// Poster's community/major tag (e.g. "CSE") shown next to their name.
  final String? branch;

  /// Absolute path to the local captured/picked image file.
  final String? photoPath;

  /// A VIDEO post (2026-10-06): the local clip, uploaded on save and written
  /// to posts.video_url. [photoPath] is null for these.
  final String? videoPath;
  final int? videoMs;

  /// Extra local photo paths BEYOND [photoPath], for a multi-photo post —
  /// [photoPath] stays the cover/first photo. Null or empty means a plain
  /// single-photo post, so every existing caller is unaffected. Uploaded
  /// into `posts.photo_urls` alongside the cover in `image_url` (see
  /// migration 20260831000000_multi_photo_posts.sql).
  final List<String>? photoUrls;

  /// Remote image URL (used by demo/seed content instead of a local file).
  final String? photoUrl;
  final double aspectRatio;
  final String? musicTitle;
  final String? musicArtist;
  final String? musicUrl;
  final DateTime createdAt;

  /// Demo/seed posts never round-trip to Supabase.
  final bool localOnly;

  /// C1 — "whether it appears in the feed". `posts.show_in_feed`.
  final bool showInFeed;

  /// C1 — communities also allowed to see a 'friends'-visibility post,
  /// combined with the friends audience (not exclusive). Written as
  /// `post_audiences` rows; ignored for any other [visibility].
  final List<String> audienceCommunityIds;

  /// C1 extension — circles also allowed to see a 'friends'-visibility post,
  /// combined with the friends + community audience (still not exclusive:
  /// your real friends see it regardless). Written as `post_audiences` rows
  /// with `audience_kind='circle'`; ignored for any other [visibility].
  /// Circle membership is silent — see CircleService's own doc — so this
  /// list only ever holds circles the poster themselves created.
  final List<String> audienceCircleIds;

  /// The un-flattened SECOND layer of a dual photo — local file path,
  /// pre-upload. Null for an ordinary single-photo post, or a dual post
  /// still going through the old compositeDualPhotos flattening (the
  /// camera's own dual capture, unchanged). When set, [photoPath] is the
  /// background and this is the inset — see FeedItem.secondaryPhotoUrl's
  /// own doc for how the feed renders the pair.
  final String? secondaryPhotoPath;

  /// Which corner the inset renders in. See FeedItem.insetOnRight.
  final bool insetOnRight;

  bool get isAnonymous => visibility == 'anonymous';
  bool get isEveryone => visibility == 'everyone';

  /// A personal post from the profile's own camera — 'friends' visibility,
  /// gated server-side by can_view_post (see 20260908010000_post_audiences.
  /// sql). It belongs in the same feed/profile lists as an 'everyone' post,
  /// so every list that filters on [isEveryone] must consider this too.
  bool get isFriends => visibility == 'friends';

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

  // Separate broadcast streams so EveryoneTab, Profile, and the Anonymous
  // feed can each subscribe independently.
  final _everyoneCtrl = StreamController<List<LocalPost>>.broadcast();
  final _myPostsCtrl = StreamController<List<LocalPost>>.broadcast();
  final _anonCtrl = StreamController<List<LocalPost>>.broadcast();

  Stream<List<LocalPost>> get everyoneFeedStream => _everyoneCtrl.stream;
  Stream<List<LocalPost>> get myPostsStream => _myPostsCtrl.stream;

  /// Feed-wide anonymous posts (not just the caller's own — see
  /// myPostsStream/myAnonymousPosts for that) — added so AnonymousTab
  /// (features/home/anonymous_tab.dart) can pick up a just-submitted post
  /// immediately, the same way EveryoneFeedScreen already does off
  /// everyoneFeedStream. It never subscribed to anything from this service
  /// before tonight — its feed was 100% static demo data (_kPosts),
  /// completely disconnected from addPost regardless of which screen
  /// called it (camera tab and the prompt bar's Respond button both
  /// already funneled into the same ComposerScreen -> addPost call, so
  /// this one subscription fixes both entry points at once).
  Stream<List<LocalPost>> get anonFeedStream => _anonCtrl.stream;

  // Synchronous snapshot reads (for initial state before first event)
  // 'friends'-visibility posts (the profile's personal-post camera) belong
  // here too — fetchEveryoneFeed already returns them from the server, so
  // excluding them here would make a just-posted personal post vanish until
  // the next refetch.
  List<LocalPost> get everyonePosts =>
      _posts.where((p) => p.isEveryone || p.isFriends).toList();
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
        // Second emit, AFTER the row actually exists in Postgres. The
        // optimistic emit above fires before the insert, so a subscriber
        // that reacts by REFETCHING (AnonFeedScreenV2 does) would query a
        // row that isn't there yet and conclude the post didn't land. This
        // is the event that tells such a listener the post is now real.
        _emit();
      } catch (_) {
        _posts.remove(post);
        _emit();
        rethrow;
      }
    }
  }

  /// The group-post twin of [fetchPostViewers] — group posts live in their
  /// own table, so they need their own views table and RPC (see
  /// 20260916130000_group_post_views_seen.sql). Same row shape, so the same
  /// PostViewer maps both.
  Future<List<PostViewer>> fetchGroupPostViewers(String groupPostId) async {
    try {
      final rows = await supabase
          .rpc('group_post_viewers', params: {'p_group_post_id': groupPostId})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          PostViewer.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (e, st) {
      debugPrint('[PostService.fetchGroupPostViewers] $groupPostId: $e\n$st');
      return const [];
    }
  }

  /// Records that the caller opened a group post. Fails soft — a missed
  /// view is a cosmetic loss, never worth interrupting the reader.
  Future<void> recordGroupPostView(String groupPostId) async {
    try {
      await supabase
          .rpc('record_group_post_view',
              params: {'p_group_post_id': groupPostId})
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[PostService.recordGroupPostView] $groupPostId: $e');
    }
  }

  /// [addPost], but resolving the author id itself so the caller can fire
  /// it and close immediately rather than awaiting a network round trip
  /// before it can even build the post.
  ///
  /// The returned future still completes (or fails) normally — callers
  /// attach their own error reporting, since by then their screen is gone.
  Future<void> addPostInBackground({
    required LocalPost Function(String userId) build,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await addPost(build(userId));
  }

  /// Soft-deletes one of the caller's own posts, the same `deleted_at`
  /// convention the rest of the schema uses (see GroupService.deletePost and
  /// posts_select, which reads `deleted_at IS NULL` — so the row stops
  /// coming back from every query the moment this lands, with no client-side
  /// filtering anywhere).
  ///
  /// Also drops it from the in-memory store, so a post deleted from the
  /// profile disappears from the Everyone feed too without anyone refetching
  /// — that list mirrors [myPostsStream].
  ///
  /// Throws if the write fails, same contract as [addPost]: the caller owns
  /// the optimistic removal and needs the throw to put the card back.
  ///
  /// `.select('id')` is not optional. BUG FIX — this call had none, and an
  /// RLS refusal on this project returns zero rows and NO error (the
  /// standing failure mode here), so a delete request that was silently
  /// rejected looked identical to one that worked: the local cache still
  /// dropped the post and the UI still reported success, while the row sat
  /// untouched on the server and reappeared on the next real fetch. This
  /// was live for every self-delete in the app — traced and fixed in
  /// migration 20260914010000_fix_soft_delete_visibility.sql, whose own
  /// doc has the full root cause.
  ///
  /// A Duo ("Us") post is NOT soft-deleted directly. Its `posts` row is a
  /// trigger-owned mirror of a mutual `us_album_photos` row
  /// (sync_us_album_post), and `posts.user_id` is only the uploader — so
  /// posts_update_own refused the partner outright (silent zero rows), and
  /// even the uploader's soft delete was undone by the trigger's
  /// `deleted_at = NULL` upsert on the photo's next edit. Instead the album
  /// photo itself is deleted — either member may
  /// (us_album_photos_delete_member) — and the post goes with it
  /// (posts_us_album_photo_id_fkey ON DELETE CASCADE). Deleting a Us post
  /// removes the photo from the album too.
  ///
  /// Returns the deleted album photo's id for a Us post (so a caller can
  /// drop it from any album grid it has cached), null otherwise.
  Future<String?> deletePost(String postId) async {
    final src = await supabase
        .from('posts')
        .select('us_album_photo_id')
        .eq('id', postId)
        .maybeSingle();
    final usPhotoId = src?['us_album_photo_id'] as String?;
    final rows = usPhotoId != null
        ? await supabase
            .from('us_album_photos')
            .delete()
            .eq('id', usPhotoId)
            .select('id')
        : await supabase
            .from('posts')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', postId)
            .select('id');
    if (rows.isEmpty) {
      throw StateError("Couldn't remove that post.");
    }
    _posts.removeWhere((p) => p.id == postId);
    _emit();
    return usPhotoId;
  }

  /// Records the caller viewing an anon post — feeds the Anon Score's
  /// "+5 whenever someone views that post" rule. Server-side
  /// (`record_post_view` RPC) is the only place this is deduped/gated: it
  /// no-ops for a non-anonymous post, the author's own view, or a repeat
  /// view from the same viewer, so this is safe to call on every scroll
  /// stop with no client-side tracking of what's already been recorded.
  Future<void> recordView(String postId) async {
    try {
      await supabase.rpc('record_post_view', params: {'p_post_id': postId});
    } catch (_) {
      // Best-effort — a dropped view ping is not worth surfacing to the
      // viewer, it just means one fewer +5 credited this session.
    }
  }

  /// Everyone who has opened [postId], pinned people first then most
  /// recent — the `post_viewers` RPC (20260906140000).
  ///
  /// An RPC rather than a table read because post_views' only SELECT policy
  /// is self-only; the function gates on post_engagement_visible(), so this
  /// can only ever return viewers of a post the caller can already see.
  /// Fails soft to an empty list — the popover then says nobody has opened
  /// it yet, which is also what an empty result legitimately means.
  Future<List<PostViewer>> fetchPostViewers(String postId) async {
    try {
      final rows = await supabase
          .rpc('post_viewers', params: {'p_post_id': postId})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          PostViewer.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (e, st) {
      debugPrint('[PostService.fetchPostViewers] $postId failed: $e\n$st');
      return const [];
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
  ///
  /// [within24h] applies the same 24-hour anon window the Anon FEED uses
  /// (FeedService.anonVisibleWindow / anonCutoff) — per the product rule
  /// that an anonymous post disappears from the Anon feed AND the author's
  /// own Anon profile tab after exactly 24h. Defaults true so the profile
  /// tab matches the feed by default; pass false for any caller that
  /// genuinely wants the author's full anon history (e.g. an export or
  /// moderation view), since the rows are still in the DB — this is a
  /// visibility filter, not a delete.
  Future<List<Map<String, dynamic>>> myAnonymousPosts({
    bool within24h = true,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    var query = supabase
        .from('posts_feed')
        .select()
        .eq('visibility', 'anonymous')
        .eq('user_id', userId);
    if (within24h) {
      query = query.gt('created_at', FeedService.anonCutoff());
    }
    final rows = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _emit() {
    _everyoneCtrl.add(everyonePosts);
    _myPostsCtrl.add(List.unmodifiable(_posts));
    _anonCtrl.add(anonPosts);
  }

  Future<void> _saveToSupabase(LocalPost post) async {
    String? imageUrl;
    String? secondaryUrl;
    // Every uploaded photo in display order, cover first. Stays empty for a
    // single-photo post so nothing is written to photo_urls in that case.
    final allUrls = <String>[];
    // The dual photo's un-flattened inset layer — uploaded alongside the
    // cover, under its own path so it can never collide with it. A failed
    // upload here degrades to an ordinary single-photo post rather than
    // losing the whole thing: the cover already succeeded by the time this
    // runs, and secondaryPhotoUrl staying null is exactly what a
    // single-photo post looks like anyway.
    String? videoUrl;
    if (post.videoPath != null) {
      videoUrl = await StorageService.uploadPostVideo(
        file: File(post.videoPath!),
        isAnon: post.isAnonymous,
        userId: post.userId,
      );
      if (videoUrl == null) throw StateError('Video upload failed');
    }
    if (post.photoPath != null && post.secondaryPhotoPath != null) {
      try {
        secondaryUrl = await StorageService.uploadPostImage(
          file: File(post.secondaryPhotoPath!),
          isAnon: post.isAnonymous,
          userId: post.userId,
          postId: '${post.id}-inset',
        );
      } catch (e, st) {
        debugPrint('[PostService] Inset photo upload FAILED for post ${post.id}: $e\n$st');
      }
    }
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

      // Extra photos only matter once the cover succeeded — uploaded
      // sequentially, since uploadPostImage derives its object path from
      // postId and concurrent calls would collide on it.
      final extras = post.photoUrls;
      if (extras != null && extras.isNotEmpty) {
        allUrls.add(imageUrl);
        for (var i = 0; i < extras.length; i++) {
          try {
            final extraUrl = await StorageService.uploadPostImage(
              file: File(extras[i]),
              isAnon: post.isAnonymous,
              userId: post.userId,
              // Distinct per photo, or each upload overwrites the last.
              postId: '${post.id}-$i',
            );
            allUrls.add(extraUrl);
          } catch (e, st) {
            // One failed extra shouldn't lose the whole post — the cover
            // already uploaded, so continue and save what we have.
            debugPrint('[PostService] Extra photo $i upload FAILED for post ${post.id}: $e\n$st');
          }
        }
      }
    }

    try {
      await supabase.from('posts').insert({
        'id': post.id,
        'user_id': post.userId,
        'visibility': post.visibility,
        // posts.content is the real column — NOT 'caption' (that name is
        // only real on the separate group_posts table). This mismatch was
        // silently rejecting every post insert with PGRST204 "Could not
        // find the 'caption' column of 'posts' in the schema cache."
        'content': post.caption,
        if (imageUrl != null) 'image_url': imageUrl,
        if (videoUrl != null) 'video_url': videoUrl,
        if (videoUrl != null && post.videoMs != null)
          'video_duration_ms': post.videoMs,
        // Only written for genuine multi-photo posts — a single-photo post
        // leaves this null and readers fall back to image_url.
        if (allUrls.length > 1) 'photo_urls': allUrls,
        // Dual photo's un-flattened inset layer — null for an ordinary
        // post, which is exactly the "no dual photo here" state the feed
        // already checks for (FeedItem.secondaryPhotoUrl).
        if (secondaryUrl != null) 'photo_url_secondary': secondaryUrl,
        if (secondaryUrl != null) 'inset_on_right': post.insetOnRight,
        // Always explicit — never let the DB default ('moment') decide, or
        // every ordinary post becomes a Moment card in the feed.
        'post_type': post.postType ?? 'single',
        'moment_color': ?post.momentColor,
        'prompt': ?post.prompt,
        'community_id': ?post.communityId,
        'prompt_id': ?post.promptId,
        'aspect_ratio': post.aspectRatio,
        if (post.musicTitle != null) 'music_title': post.musicTitle,
        if (post.musicArtist != null) 'music_artist': post.musicArtist,
        if (post.musicUrl != null) 'music_url': post.musicUrl,
        'show_in_feed': post.showInFeed,
        // BUG FIX — every post's expiry was wrong by the device's UTC
        // offset. `posts.created_at` is `timestamp` (no zone) in a UTC
        // database, but this sent `post.createdAt.toIso8601String()` on the
        // LOCAL DateTime — IST wall-clock digits with no zone marker — so
        // Postgres stored them as if they already were UTC. On this
        // project's IST devices that means every post's stored created_at
        // reads 5h30m in the FUTURE, which pushed every expiry window out
        // by the same 5h30m: a 24h Moment actually stayed visible ~29.5h,
        // a 48h anon post ~53.5h. Verified live — the newest post at
        // capture time compared 4h21m ahead of the database's own now().
        // `.toUtc()` makes the wall-clock digits sent match the zone the
        // column is actually interpreted in.
        'created_at': post.createdAt.toUtc().toIso8601String(),
      });
      debugPrint('[PostService] Insert OK for post ${post.id}');
    } catch (e, st) {
      debugPrint('[PostService] Insert FAILED for post ${post.id}: $e\n$st');
      rethrow;
    }

    // Combined audience (C1): only meaningful for a 'friends'-visibility
    // post — post_audiences_insert_own's RLS requires post.user_id to
    // already exist, so this always runs strictly after the insert above,
    // never inside the same statement.
    // Also for an ANONYMOUS post: a Dip sent to several communities keeps
    // its extra communities here (circles never apply to a Dip).
    if ((post.visibility == 'friends' || post.visibility == 'anonymous') &&
        (post.audienceCommunityIds.isNotEmpty || post.audienceCircleIds.isNotEmpty)) {
      try {
        await supabase.from('post_audiences').insert([
          for (final communityId in post.audienceCommunityIds)
            {
              'post_id': post.id,
              'audience_kind': 'community',
              'community_id': communityId,
            },
          for (final circleId in post.audienceCircleIds)
            {
              'post_id': post.id,
              'audience_kind': 'circle',
              'circle_id': circleId,
            },
        ]);
      } catch (e, st) {
        // The post itself already succeeded — losing an extra audience row
        // narrows who can see it (fails closed), never leaks it, so this is
        // logged rather than rethrown/rolled back.
        debugPrint('[PostService] post_audiences insert FAILED for post ${post.id}: $e\n$st');
        // EXCEPT a circles-only anon post (no community): without its
        // circle rows posts_feed treats it as a legacy public anon post,
        // so it would fail OPEN. Withdraw it and surface the failure.
        if (post.visibility == 'anonymous' &&
            post.communityId == null &&
            post.audienceCircleIds.isNotEmpty) {
          try {
            await supabase
                .from('posts')
                .update({
                  'deleted_at': DateTime.now().toUtc().toIso8601String(),
                })
                .eq('id', post.id);
          } catch (_) {}
          rethrow;
        }
      }
    }
  }
}


/// One person who has opened a post — a row of `post_viewers`.
///
/// These are real, named accounts on purpose. The POST is anonymous; the
/// people who opened it never were, and listing them says nothing about who
/// wrote it.
class PostViewer {
  const PostViewer({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.isPinned,
    required this.viewedAt,
  });

  factory PostViewer.fromRow(Map<String, dynamic> row) {
    final username = (row['username'] as String?)?.trim();
    final name = (row['name'] as String?)?.trim();
    // Unpinned viewers are masked server-side (no id, name or photo). All
    // that comes back is their BRANCH, derived from their college email
    // (20260928090000) — so the list reads "someone in CS" / "someone in
    // EC", or "someone from outside" for a non-RVCE address, instead of a
    // column of identical "someone"s.
    final branch = (row['branch'] as String?)?.trim();
    // Dip (anonymous) posts: their anon persona + branch instead
    // ("darth_vader · CS", 20260928120000). Null on every other post.
    final anonLabel = (row['anon_label'] as String?)?.trim();
    final masked = (anonLabel != null && anonLabel.isNotEmpty)
        ? anonLabel
        : (branch != null && branch.isNotEmpty)
            ? 'someone in ${branch.toUpperCase()}'
            : 'someone from outside';
    return PostViewer(
      // Unpinned viewers come back masked (user_id NULL, opaque viewer_key),
      // so their id here is a key that never resolves to a profile.
      userId: (row['user_id'] as String?) ?? 'k:${row['viewer_key']}',
      // Named whenever the server sent an identity: pinned people, and
      // everyone on an anon post (20261001010000).
      displayName: row['user_id'] == null
          ? masked
          : (username != null && username.isNotEmpty)
              ? username
              : (name != null && name.isNotEmpty ? name : 'someone'),
      avatarUrl:
          (row['avatar_url'] as String?) ?? row['anon_avatar_url'] as String?,
      isPinned: row['is_pinned'] as bool? ?? false,
      viewedAt: row['viewed_at'] != null
          ? DateTime.tryParse(row['viewed_at'] as String)
          : null,
    );
  }

  final String userId;
  final String displayName;
  final String? avatarUrl;

  /// Pinned by the VIEWER of this list, not by the post's author — these
  /// sort to the top.
  final bool isPinned;
  final DateTime? viewedAt;
}
