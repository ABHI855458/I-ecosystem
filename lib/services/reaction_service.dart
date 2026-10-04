import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/image_compress.dart';
import 'current_user_service.dart';
import 'realmoji_service.dart' show RealmojiTypeWire, realmojiTypeFromWire;
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
    this.selfieUrl,
  });

  final String id;
  final String name;

  /// The reactor's PROFILE photo (`users.profile_photo_url`) — who they
  /// are, not what they reacted with.
  final String? avatarUrl;
  final String emoji;
  final DateTime at;

  /// The RealMoji SELFIE this reaction was made with
  /// (`user_realmojis.image_url`, or `reactions.photo_url` for a face-type
  /// row). Null for a plain glyph-emoji reaction, which has no selfie.
  ///
  /// BUG FIX: the reactor tiles rendered [avatarUrl], so a RealMoji row
  /// showed the reactor's DP with a small glyph badge instead of the face
  /// they actually pulled. Reported against the comment sheet's REALMOJIS
  /// strip: "the real emoji shall be seen here, not their dps".
  final String? selfieUrl;

  /// What a "who reacted" tile should actually show: the RealMoji selfie
  /// when there is one, falling back to the profile photo for a plain
  /// emoji reaction.
  String? get displayPhotoUrl =>
      (selfieUrl != null && selfieUrl!.isNotEmpty) ? selfieUrl : avatarUrl;
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

  /// Every reaction on the post, glyph emoji AND RealMoji faces combined.
  ///
  /// [totalEmojiCount] alone undercounts: a RealMoji reaction with a
  /// resolved selfie lands ONLY in [faceReactions], never in
  /// [emojiCounts] — the two are kept deliberately disjoint (see this
  /// class's own fetchSummary, "must stay DISJOINT... a row counted in
  /// both would be counted twice"). ReactionPreviewChip's badge already
  /// adds them by hand at every call site; this is that same sum, named,
  /// so a NEW call site can't independently make the same mistake.
  ///
  /// BUG FIX: every `showPostCommentsSheet`/`PostCommentCard` call site in
  /// the app was passing `totalEmojiCount` alone as `reactionCount`, which
  /// gates the sheet's whole "REALMOJIS · N" reactor row
  /// (`if (reactionCount > 0)`). A post whose only reactions were RealMoji
  /// faces — the app's primary reaction mechanism — had that row hidden
  /// entirely, even though the on-card badge showed a nonzero count and
  /// `fetchRecentReactors` had already fetched the reactors to show.
  /// Reported as "the real emoji viewing in the comment section its not
  /// visible when opened in profile".
  int get totalReactionCount => totalEmojiCount + faceReactions.length;

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

  /// Reactor selfie URLs, keyed `'<userId>|<emoji_type wire>'`.
  ///
  /// [fetchSummary] resolves a RealMoji reaction's photo from a SEPARATE
  /// table (user_realmojis) — the reaction row itself carries no image. Done
  /// naively that is one extra round trip PER POST CARD, and a profile that
  /// renders ten posts pays it ten times over: reported as "the reactions in
  /// my profile are loading very slowly".
  ///
  /// The same handful of people react across many of a profile's posts, so
  /// this caches by reactor+emoji rather than by post: the first card that
  /// needs a given face pays for it, every later card reads it back for
  /// free. Session-lifetime and never invalidated, which is correct for what
  /// it holds — a saved selfie for a given emoji slot is replaced by
  /// captureAndReact writing a NEW row, and that flow refreshes its own
  /// summary anyway.
  final Map<String, String> _selfieCache = {};

  /// Drops the selfie cache — call on sign-out so the next account doesn't
  /// render the previous one's faces.
  void resetSelfieCache() => _selfieCache.clear();

  // ── Reads ──────────────────────────────────────────────────────────────

  /// [groupPostId] routes the same query at a group_posts row instead of a
  /// posts row (mutually exclusive with [postId] — see the group_post_id
  /// migration on reactions/comments/post_realmoji_reactions). Exactly one
  /// of the two must be non-null.
  ///
  /// Reads BOTH `reactions` (this table's own emoji/face rows) AND
  /// `post_realmoji_reactions` (the RealmojiService flow every reaction
  /// tray in the app — RealmojiTray, PostReactionCorner's popup — actually
  /// writes to, see realmoji_service.dart). Before this, the count returned
  /// here only reflected `reactions`, so the visible reaction number on a
  /// post undercounted (sometimes to zero) the moment anyone reacted via a
  /// saved RealMoji — the same merge fetchRecentReactors below already
  /// does for the "who reacted" cluster, just missing here for the total.
  Future<ReactionSummary> fetchSummary(String? postId, {String? groupPostId}) async {
    var reactionsQuery = _sb.from('reactions').select();
    reactionsQuery = groupPostId != null
        ? reactionsQuery.eq('group_post_id', groupPostId)
        : reactionsQuery.eq('post_id', postId!);

    var realmojiQuery = _sb.from('post_realmoji_reactions').select('user_id, emoji_type, created_at');
    realmojiQuery = groupPostId != null
        ? realmojiQuery.eq('group_post_id', groupPostId)
        : realmojiQuery.eq('post_id', postId!);

    // Newest-first on both: every preview (ReactionPreviewChip etc.) shows
    // the first 3 faces/glyphs, which must be the LATEST 3 reactions —
    // unordered, it was whichever 3 Postgres happened to return.
    final results = await Future.wait([
      reactionsQuery
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8)),
      realmojiQuery
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8)),
    ]);
    final rows = results[0] as List;
    final realmojiRows = results[1] as List;
    // Faces come from two tables; timestamps let the merged list be
    // re-sorted newest-first below.
    final faceAt = <FaceReaction, DateTime>{};
    DateTime at(Map<String, dynamic> r) =>
        DateTime.tryParse(r['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

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

    for (final raw in rows) {
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
        faceAt[face] = at(row);
        if (userId == myUserId) myFaceReaction = face;
      }
    }

    // post_realmoji_reactions has no "face vs emoji" split — every row is
    // one reaction event, glyph resolved from its emoji_type. Counted into
    // the same emojiCounts map (by glyph) so totalEmojiCount reflects
    // every reaction regardless of which table it landed in; myEmoji only
    // gets set here if the `reactions` loop above didn't already find one,
    // matching a viewer having at most one active reaction either way.
    // The reaction row itself carries no photo — post_realmoji_reactions is
    // (post_id, user_id, emoji_type) only. The SELFIE lives in the
    // reactor's own library, user_realmojis(user_id, emoji_type,
    // image_url, feed_scope). Without this join the preview chip fell back
    // to a plain glyph circle, which is what "the preview shall be real
    // emoji not just the reactions" reported.
    //
    // Scoped to feed_scope='everyone' deliberately, and that is also the
    // only scope RLS will return for someone else: user_realmojis_select is
    // `own rows OR feed_scope='everyone'`. An ANON-scope selfie stays
    // private to its owner, so this can never surface a face against an
    // anonymous reaction — the anon feed's own stack reads
    // anon_reaction_counts (emoji+count, no user_id) and is untouched.
    // Only the (user, emoji) pairs this post actually needs, minus whatever
    // an earlier card already resolved — see [_selfieCache]. On a profile
    // where the same people react to post after post, this drops to zero
    // extra round trips after the first card. Shared with
    // fetchRecentReactors so both resolve selfies identically.
    await _resolveSelfies([
      for (final raw in realmojiRows) Map<String, dynamic>.from(raw as Map),
    ]);
    final selfieByUserAndType = _selfieCache;

    for (final raw in realmojiRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final wire = row['emoji_type'] as String;
      final glyph = realmojiTypeFromWire(wire).glyph;
      final userId = row['user_id'] as String;
      if (userId == myUserId) myEmoji ??= glyph;

      // emojiCounts and faceReactions must stay DISJOINT: every consumer
      // totals them as `totalEmojiCount + faceReactions.length` (see
      // ReactionPreviewChip's callers), so a row counted in both would be
      // counted twice. A realmoji reaction with a resolved selfie is a
      // FACE; only one without a photo falls back to being a glyph count.
      final photo = selfieByUserAndType['$userId|$wire'];
      if (photo != null && photo.isNotEmpty) {
        final face = FaceReaction(userId: userId, photoUrl: photo, emoji: glyph);
        faceReactions.add(face);
        faceAt[face] = at(row);
        if (userId == myUserId) myFaceReaction ??= face;
      } else {
        emojiCounts[glyph] = (emojiCounts[glyph] ?? 0) + 1;
      }
    }
    faceReactions.sort((a, b) => faceAt[b]!.compareTo(faceAt[a]!));

    return ReactionSummary(
      emojiCounts: emojiCounts,
      myEmoji: myEmoji,
      faceReactions: faceReactions,
      myFaceReaction: myFaceReaction,
    );
  }

  /// Fills [_selfieCache] with the RealMoji selfie for every
  /// (user_id, emoji_type) pair in [realmojiRows] that isn't cached yet.
  ///
  /// Scoped to feed_scope='everyone' deliberately, and that is also the
  /// only scope RLS will return for someone else: user_realmojis_select is
  /// `own rows OR feed_scope='everyone'`. An ANON-scope selfie stays
  /// private to its owner, so this can never surface a face against an
  /// anonymous reaction.
  ///
  /// Fails soft — a missing photo must never take the caller down with it;
  /// the tile falls back to the reactor's profile photo.
  Future<void> _resolveSelfies(List<Map<String, dynamic>> realmojiRows) async {
    final needed = <String>{
      for (final row in realmojiRows) '${row['user_id']}|${row['emoji_type']}',
    }..removeWhere(_selfieCache.containsKey);
    if (needed.isEmpty) return;

    final missingUserIds = <String>{for (final k in needed) k.split('|').first};
    try {
      final selfieRows = await _sb
          .from('user_realmojis')
          .select('user_id, emoji_type, image_url')
          .inFilter('user_id', missingUserIds.toList())
          .eq('feed_scope', 'everyone')
          .timeout(const Duration(seconds: 8));
      for (final raw in (selfieRows as List)) {
        final row = raw as Map;
        _selfieCache['${row['user_id']}|${row['emoji_type']}'] =
            row['image_url'] as String;
      }
    } catch (_) {
      // Glyph/DP fallback — see doc above.
    }
  }

  /// Most recent emoji reactors on a post, newest first — for
  /// EveryonePostCard's floating reactor cluster
  /// (screens/feed/widgets/reactor_cluster.dart). Embeds `users(name,
  /// profile_photo_url)` via the reactions.user_id FK for real name/avatar;
  /// fails closed to an empty list on any error (bad/missing embed, network,
  /// etc.) rather than surfacing a broken cluster or breaking the whole
  /// card — the cluster is decorative, not load-bearing.
  Future<List<LikeReactor>> fetchRecentReactors(String? postId, {String? groupPostId, int limit = 3}) async {
    try {
      // Two independent reaction event tables feed the poster's "who
      // reacted" view: `reactions` (emoji AND face types — dropping the
      // old `type=emoji`-only filter, which hid every face reaction) and
      // `post_realmoji_reactions` (the separate RealmojiService flow the
      // app's actual RealMoji button writes to — live data showed most
      // real reaction events landing there, not in `reactions`). Fetched
      // and merged client-side since they're different tables with no FK
      // between them.
      // photo_url comes along now: a face-type `reactions` row carries the
      // RealMoji selfie on the row itself (same column FaceReaction.fromRow
      // reads), and that selfie — not the reactor's DP — is what a "who
      // reacted" tile is supposed to show.
      var reactionsQuery = _sb
          .from('reactions')
          .select(
            'user_id, emoji, photo_url, created_at, '
            'users(name, profile_photo_url)',
          );
      reactionsQuery = groupPostId != null
          ? reactionsQuery.eq('group_post_id', groupPostId)
          : reactionsQuery.eq('post_id', postId!);

      var realmojiQuery = _sb
          .from('post_realmoji_reactions')
          .select('user_id, emoji_type, created_at, users(name, profile_photo_url)');
      realmojiQuery = groupPostId != null
          ? realmojiQuery.eq('group_post_id', groupPostId)
          : realmojiQuery.eq('post_id', postId!);

      final results = await Future.wait([
        reactionsQuery
            .order('created_at', ascending: false)
            .limit(limit)
            .timeout(const Duration(seconds: 8)),
        realmojiQuery
            .order('created_at', ascending: false)
            .limit(limit)
            .timeout(const Duration(seconds: 8)),
      ]);

      final realmojiRows = [
        for (final raw in results[1] as List)
          Map<String, dynamic>.from(raw as Map),
      ];

      // A post_realmoji_reactions row is (post_id, user_id, emoji_type)
      // only — it carries no photo. The SELFIE lives in the reactor's own
      // library, user_realmojis(user_id, emoji_type, image_url), so it has
      // to be resolved with a second query, exactly as fetchSummary does.
      // Shares fetchSummary's [_selfieCache], so on a profile where the
      // same people react post after post this costs nothing after the
      // first card.
      await _resolveSelfies(realmojiRows);

      LikeReactor fromReactionsRow(Map<String, dynamic> row) {
        final user = row['users'] as Map<String, dynamic>?;
        return LikeReactor(
          id: row['user_id'] as String,
          name: (user?['name'] as String?) ?? 'someone',
          avatarUrl: user?['profile_photo_url'] as String?,
          // A face-type row carries its selfie on the row itself.
          selfieUrl: row['photo_url'] as String?,
          emoji: row['emoji'] as String,
          at: DateTime.parse(row['created_at'] as String),
        );
      }

      LikeReactor fromRealmojiRow(Map<String, dynamic> row) {
        final user = row['users'] as Map<String, dynamic>?;
        final userId = row['user_id'] as String;
        final wire = row['emoji_type'] as String;
        return LikeReactor(
          id: userId,
          name: (user?['name'] as String?) ?? 'someone',
          avatarUrl: user?['profile_photo_url'] as String?,
          selfieUrl: _selfieCache['$userId|$wire'],
          emoji: realmojiTypeFromWire(wire).glyph,
          at: DateTime.parse(row['created_at'] as String),
        );
      }

      final merged = [
        for (final raw in results[0] as List)
          fromReactionsRow(Map<String, dynamic>.from(raw as Map)),
        for (final row in realmojiRows) fromRealmojiRow(row),
      ]..sort((a, b) => b.at.compareTo(a.at));

      return merged.take(limit).toList();
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
      // .toUtc() — reactions.created_at is `timestamp` (no zone) in a UTC
      // database; without it this sent IST wall-clock digits with no zone
      // marker, which Postgres reads as UTC. On an IST device `since` was
      // computed 5h30m into the future, so the `gte` below matched almost
      // nothing — this silently undercounted every "is this post hot"
      // check. Same root cause as post_service.dart's created_at bug (see
      // migration 20260914010000_fix_soft_delete_visibility.sql's sibling
      // fix), independently discovered here.
      final since = DateTime.now().toUtc().subtract(window).toIso8601String();
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
    String? postId,
    String? groupPostId,
    required String emoji,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb.from('reactions').upsert(
      {
        'post_id': postId,
        'group_post_id': groupPostId,
        'user_id': userId,
        'type': ReactionType.emoji.wire,
        'emoji': emoji,
        'photo_url': null,
      },
      onConflict: groupPostId != null ? 'group_post_id,user_id,type' : 'post_id,user_id,type',
    );
  }

  Future<void> removeEmojiReaction(String? postId, {String? groupPostId}) async {
    final userId = await CurrentUserService.instance.resolveId();
    var query = _sb.from('reactions').delete();
    query = groupPostId != null ? query.eq('group_post_id', groupPostId) : query.eq('post_id', postId!);
    await query.eq('user_id', userId).eq('type', ReactionType.emoji.wire);
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
