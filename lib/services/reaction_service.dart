import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/image_compress.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum ReactionType { emoji, face }

extension on ReactionType {
  String get wire => this == ReactionType.emoji ? 'emoji' : 'face';
}

ReactionType _typeFromWire(String wire) =>
    wire == 'face' ? ReactionType.face : ReactionType.emoji;

class FaceReaction {
  const FaceReaction({
    required this.userId,
    required this.photoUrl,
    required this.emoji,
  });

  final String userId;
  final String photoUrl;
  final String emoji;

  factory FaceReaction.fromRow(Map<String, dynamic> row) => FaceReaction(
        userId: row['user_id'] as String,
        photoUrl: row['photo_url'] as String,
        emoji: row['emoji'] as String,
      );
}

/// One recent reactor, for EveryonePostCard's floating reactor cluster
/// (screens/feed/widgets/reactor_cluster.dart) — who reacted, with what,
/// and when, resolved against `users` (schema: reactions.user_id
/// REFERENCES users(id), a single unambiguous FK, so the embed below is
/// safe — unlike posts→users, which the codebase's own FeedService notes
/// left unwired to avoid guessing an ambiguous relationship name).
class LikeReactor {
  const LikeReactor({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.emoji,
    required this.at,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String emoji;
  final DateTime at;
}

/// Aggregated reaction state for one post. Two independent slots per
/// (post, user) — see the coexistence-model note on ReactionService.
class ReactionSummary {
  const ReactionSummary({
    required this.emojiCounts,
    required this.myEmoji,
    required this.faceReactions,
    required this.myFaceReaction,
  });

  const ReactionSummary.empty()
      : emojiCounts = const {},
        myEmoji = null,
        faceReactions = const [],
        myFaceReaction = null;

  final Map<String, int> emojiCounts;
  final String? myEmoji;
  final List<FaceReaction> faceReactions;
  final FaceReaction? myFaceReaction;

  int get totalEmojiCount => emojiCounts.values.fold(0, (a, b) => a + b);

  String? get topEmoji {
    if (emojiCounts.isEmpty) return null;
    return emojiCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

// ---------------------------------------------------------------------------
// ReactionEvent — realtime insert/update payload, for callers that want a
// live "someone just reacted" nudge (e.g. a floating-emoji animation).
// ---------------------------------------------------------------------------

class ReactionEvent {
  const ReactionEvent({
    required this.postId,
    required this.userId,
    required this.type,
    required this.emoji,
  });
  final String postId;
  final String userId;
  final ReactionType type;
  final String emoji;
}

// ---------------------------------------------------------------------------
// ReactionService
// ---------------------------------------------------------------------------
//
// Coexistence model: a user can hold at most ONE emoji reaction AND, on
// feeds where face reactions are allowed, at most ONE face reaction on a
// given post — simultaneously, independently. This is enforced by the
// database itself: reactions.UNIQUE(post_id, user_id, type). Reacting again
// with the same type replaces (upserts) that slot; the other type's slot,
// if any, is untouched. This was the shape DATA/STORAGE specified, not a
// free choice — flagging it here so it's explicit rather than implicit in
// the upsert calls below.
class ReactionService {
  ReactionService._();
  static final instance = ReactionService._();

  final _sb = Supabase.instance.client;

  // ── Reads ──────────────────────────────────────────────────────────────

  Future<ReactionSummary> fetchSummary(String postId) async {
    final rows = await _sb
        .from('reactions')
        .select()
        .eq('post_id', postId)
        .timeout(const Duration(seconds: 8));

    String? myUserId;
    try {
      myUserId = await CurrentUserService.instance.resolveId();
    } catch (_) {
      // Not signed in — still show everyone else's reactions, just no
      // "mine" highlighting.
    }

    final emojiCounts = <String, int>{};
    String? myEmoji;
    final faceReactions = <FaceReaction>[];
    FaceReaction? myFaceReaction;

    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final type = _typeFromWire(row['type'] as String);
      final userId = row['user_id'] as String;

      if (type == ReactionType.emoji) {
        final emoji = row['emoji'] as String;
        emojiCounts[emoji] = (emojiCounts[emoji] ?? 0) + 1;
        if (userId == myUserId) myEmoji = emoji;
      } else {
        final face = FaceReaction.fromRow(row);
        faceReactions.add(face);
        if (userId == myUserId) myFaceReaction = face;
      }
    }

    return ReactionSummary(
      emojiCounts: emojiCounts,
      myEmoji: myEmoji,
      faceReactions: faceReactions,
      myFaceReaction: myFaceReaction,
    );
  }

  /// Most recent emoji reactors on a post, newest first — for
  /// EveryonePostCard's floating reactor cluster
  /// (screens/feed/widgets/reactor_cluster.dart). Embeds `users(name,
  /// profile_photo_url)` via the reactions.user_id FK for real name/avatar;
  /// fails closed to an empty list on any error (bad/missing embed, network,
  /// etc.) rather than surfacing a broken cluster or breaking the whole
  /// card — the cluster is decorative, not load-bearing.
  Future<List<LikeReactor>> fetchRecentReactors(String postId, {int limit = 3}) async {
    try {
      final rows = await _sb
          .from('reactions')
          .select('user_id, emoji, created_at, users(name, profile_photo_url)')
          .eq('post_id', postId)
          .eq('type', ReactionType.emoji.wire)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 8));

      return (rows as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final user = row['users'] as Map<String, dynamic>?;
        return LikeReactor(
          id: row['user_id'] as String,
          name: (user?['name'] as String?) ?? 'someone',
          avatarUrl: user?['profile_photo_url'] as String?,
          emoji: row['emoji'] as String,
          at: DateTime.parse(row['created_at'] as String),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Live inserts/updates for one post's reactions — for a floating-reaction
  /// nudge or similar; not required to render the static summary above.
  RealtimeChannel subscribeToPost(
    String postId,
    void Function(ReactionEvent) onReaction,
  ) {
    void handle(PostgresChangePayload payload) {
      final row = payload.newRecord;
      onReaction(ReactionEvent(
        postId: row['post_id'] as String,
        userId: row['user_id'] as String,
        type: _typeFromWire(row['type'] as String),
        emoji: row['emoji'] as String,
      ));
    }

    return _sb
        .channel('reactions_$postId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'reactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: postId,
          ),
          callback: handle,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'reactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: postId,
          ),
          callback: handle,
        )
        .subscribe();
  }

  // ── Legacy call-site compatibility ────────────────────────────────────
  // SpotlightCard (Everyone feed) and SpotlightPrivilegesController still
  // call these two under their pre-redesign names/shapes. This rewrite was
  // scoped to the new PostCard + its own service/widgets, not to migrating
  // every existing caller onto PostCard yet (see this session's summary) —
  // these keep that feed compiling and working unchanged in the meantime.
  // Remove once SpotlightCard is migrated to PostCard.

  Future<void> react(String postId, String emoji) =>
      setEmojiReaction(postId: postId, emoji: emoji);

  Future<int> countRecentReactions(
    String postId, {
    Duration window = const Duration(minutes: 10),
  }) async {
    try {
      final since = DateTime.now().subtract(window).toIso8601String();
      final rows = await _sb
          .from('reactions')
          .select('id')
          .eq('post_id', postId)
          .eq('type', ReactionType.emoji.wire)
          .gte('created_at', since)
          .timeout(const Duration(seconds: 8));
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  // ── Emoji reactions ───────────────────────────────────────────────────

  Future<void> setEmojiReaction({
    required String postId,
    required String emoji,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb.from('reactions').upsert(
      {
        'post_id': postId,
        'user_id': userId,
        'type': ReactionType.emoji.wire,
        'emoji': emoji,
        'photo_url': null,
      },
      onConflict: 'post_id,user_id,type',
    );
  }

  Future<void> removeEmojiReaction(String postId) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb
        .from('reactions')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId)
        .eq('type', ReactionType.emoji.wire);
  }

  // ── Face reactions ────────────────────────────────────────────────────

  /// Compresses [selfie] aggressively (these render as small circular
  /// thumbnails, not full photos — no reason to upload/cache anything
  /// larger than that) then uploads and upserts the face reaction.
  Future<void> setFaceReaction({
    required String postId,
    required File selfie,
    required String emoji,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    final compressed = await compressForThumbnail(selfie);

    final url = await StorageService.uploadReactionPhoto(
      file: compressed,
      postId: postId,
      userId: userId,
    );
    if (url == null) {
      throw StateError('Face reaction photo upload failed');
    }

    await _sb.from('reactions').upsert(
      {
        'post_id': postId,
        'user_id': userId,
        'type': ReactionType.face.wire,
        'emoji': emoji,
        'photo_url': url,
      },
      onConflict: 'post_id,user_id,type',
    );
  }

  /// Same upsert as [setFaceReaction], but for applying a saved reaction
  /// preset (reaction_preset_service.dart): [photoUrl] already exists in
  /// storage (the preset's own object under reaction-photos/presets/...),
  /// so this skips the compress+upload round-trip entirely and just points
  /// the reaction row at it — the whole point of a preset being a faster
  /// SOURCE for a reaction, not a separate storage path.
  Future<void> setFaceReactionFromPreset({
    required String postId,
    required String photoUrl,
    required String emoji,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb.from('reactions').upsert(
      {
        'post_id': postId,
        'user_id': userId,
        'type': ReactionType.face.wire,
        'emoji': emoji,
        'photo_url': photoUrl,
      },
      onConflict: 'post_id,user_id,type',
    );
  }

  Future<void> removeFaceReaction(String postId) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb
        .from('reactions')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId)
        .eq('type', ReactionType.face.wire);
    // Storage cleanup is best-effort — a stray orphaned object under
    // reaction-photos/$postId/$userId.jpg costs nothing to leave behind and
    // gets overwritten if this slot is ever reused.
  }
}
