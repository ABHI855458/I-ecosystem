import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/image_compress.dart';
import 'current_user_service.dart';
import 'reaction_preset_service.dart' show ReactionPresetCategory, ReactionPresetCategoryWire;
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// RealmojiService — BeReal-style RealMoji capture-and-react, per the
// user_realmojis / post_realmoji_reactions schema (already live in
// Supabase, not owned by this service — see supabase/schema.sql for the
// documented shape). Two concerns, cleanly split:
//   - user_realmojis: a user's own saved selfie per (feed_scope, emoji_type)
//     — captured once, reused on every subsequent react. Mirrors
//     reaction_presets' own "capture once, reuse forever" model
//     (reaction_preset_service.dart), just scoped by emoji_type instead of
//     freeform emoji text.
//   - post_realmoji_reactions: the actual per-post reaction events. No
//     feed_scope column here by design (the schema derives it from
//     posts.visibility) — this service takes feedScope as a parameter
//     purely to route user_realmojis lookups/writes correctly, never
//     writes it anywhere.
//
// feed_scope reuses ReactionPresetCategory's wire strings
// ('anonymous'/'everyone') rather than a parallel enum — same two values,
// no reason to duplicate the mapping.
// ---------------------------------------------------------------------------

/// Every reaction a RealMoji can be. Declaration order IS display order in
/// the tray and the library grid.
///
/// Mirrors `emoji_type_enum` in Postgres exactly — the wire value is the
/// enum NAME, so adding one here without the matching
/// `alter type ... add value` (see 20260906180000_more_emoji_types.sql)
/// makes every reaction with it fail the insert.
enum RealmojiType {
  like,
  love,
  joy,
  laughter,
  surprise,
  fire,
  heartEyes,
  cool,
  cry,
  clap,
  wink,
  party,
  mindBlown,
  shy,
  angry,
  skull,
  hundred,
  instant,
}

extension RealmojiTypeWire on RealmojiType {
  /// The Postgres enum label. Dart's lowerCamelCase names and the DB's
  /// snake_case labels only diverge for the two-word ones, so those are
  /// mapped explicitly rather than left to `name`.
  String get wire => switch (this) {
        RealmojiType.heartEyes => 'heart_eyes',
        RealmojiType.mindBlown => 'mind_blown',
        _ => name,
      };

  /// Short human label, shown under the photo in the RealMoji library.
  String get label => switch (this) {
        RealmojiType.heartEyes => 'heart eyes',
        RealmojiType.mindBlown => 'mind blown',
        _ => name,
      };

  /// Display glyph — the schema stores the enum name, not an emoji
  /// character, so every UI surface needs this mapping in exactly one
  /// place.
  String get glyph => switch (this) {
        RealmojiType.like => '👍',
        RealmojiType.love => '❤️',
        RealmojiType.joy => '😂',
        RealmojiType.laughter => '🤣',
        RealmojiType.surprise => '😮',
        RealmojiType.fire => '🔥',
        RealmojiType.heartEyes => '😍',
        RealmojiType.cool => '😎',
        RealmojiType.cry => '😭',
        RealmojiType.clap => '👏',
        RealmojiType.wink => '😉',
        RealmojiType.party => '🥳',
        RealmojiType.mindBlown => '🤯',
        RealmojiType.shy => '🥹',
        RealmojiType.angry => '😡',
        RealmojiType.skull => '💀',
        RealmojiType.hundred => '💯',
        RealmojiType.instant => '⚡',
      };
}

RealmojiType realmojiTypeFromWire(String wire) =>
    RealmojiType.values.firstWhere((t) => t.wire == wire, orElse: () => RealmojiType.like);

/// Reverse of [RealmojiTypeWire.glyph] — the reaction-preset tray/library
/// pipe (post_card_shared.dart, reaction_preset_service.dart's ReactionPreset
/// DTO) carries emoji as a display glyph, not the wire enum name, so
/// anything repointing that pipe at RealMoji needs to convert back.
RealmojiType realmojiTypeFromGlyph(String glyph) =>
    RealmojiType.values.firstWhere((t) => t.glyph == glyph, orElse: () => RealmojiType.like);

/// One RealMoji reaction on an ANONYMOUS post, stripped of identity — the
/// reaction's photo and which emoji it was, and deliberately nothing else.
class AnonReactionFace {
  const AnonReactionFace({required this.type, required this.imageUrl});

  final RealmojiType type;
  final String? imageUrl;
}

/// One reaction on a post, for the Everyone feed's reactor-selfie stack.
/// [selfieUrl] is null if the reactor's saved user_realmojis row is somehow
/// missing (deleted after reacting) — callers fall back to a plain glyph
/// badge rather than crashing.
class RealmojiReaction {
  const RealmojiReaction({
    required this.id,
    required this.userId,
    required this.userName,
    required this.emojiType,
    required this.selfieUrl,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final RealmojiType emojiType;
  final String? selfieUrl;
  final DateTime createdAt;
}

/// One row of the Anonymous feed's emoji+count display — sourced from
/// anon_reaction_counts (the public-safe aggregate view), never from raw
/// post_realmoji_reactions, so no user_id ever reaches this feed's UI.
class AnonRealmojiCount {
  const AnonRealmojiCount({required this.emojiType, required this.count});
  final RealmojiType emojiType;
  final int count;
}

class RealmojiService {
  RealmojiService._();
  static final instance = RealmojiService._();

  final _sb = Supabase.instance.client;

  // In-memory cache of the caller's own saved selfie URLs, keyed
  // "$feedScope:$emojiType" — same instant-render reasoning as
  // ReactionPresetService's own cache: the picker row needs to know
  // instantly (no async gap) whether tapping an emoji skips straight to
  // reacting or opens the camera first.
  final Map<String, String?> _savedCache = {};

  /// One RealMoji set for both feeds (explicit request, 2026-10-01): every
  /// read and write uses this scope, whichever feed asked.
  static const kOneScope = 'everyone';

  String _cacheKey(String feedScope, RealmojiType emojiType) => '$kOneScope:${emojiType.wire}';

  /// All of the caller's saved selfies for [feedScope] in one query — the
  /// picker row prefetches this once on open so all 6 options can render
  /// their "already captured" state (a cyan ring) instantly, instead of 6
  /// separate round trips. Populates the same cache savedSelfieUrl reads,
  /// so a subsequent per-emoji lookup is free.
  Future<Map<RealmojiType, String>> savedSelfies({required String feedScope}) async {
    feedScope = kOneScope;
    final userId = await CurrentUserService.instance.resolveId();
    final rows = await _sb
        .from('user_realmojis')
        .select('emoji_type, image_url')
        .eq('user_id', userId)
        .eq('feed_scope', feedScope)
        .timeout(const Duration(seconds: 8));

    final result = <RealmojiType, String>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final type = realmojiTypeFromWire(row['emoji_type'] as String);
      final url = row['image_url'] as String;
      result[type] = url;
      _savedCache[_cacheKey(feedScope, type)] = url;
    }
    // Types with no saved row must also be cached as "known absent" (null),
    // or savedSelfieUrl would re-query them one at a time right after this
    // batch fetch already established they don't exist.
    for (final type in RealmojiType.values) {
      _savedCache.putIfAbsent(_cacheKey(feedScope, type), () => result[type]);
    }
    return result;
  }

  /// The caller's own saved selfie for (feedScope, emojiType), or null if
  /// they've never captured one for this combination yet. Cached after the
  /// first lookup; pass [forceRefresh] to bypass (e.g. right after a
  /// retake).
  Future<String?> savedSelfieUrl({
    required String feedScope,
    required RealmojiType emojiType,
    bool forceRefresh = false,
  }) async {
    feedScope = kOneScope;
    final key = _cacheKey(feedScope, emojiType);
    if (!forceRefresh && _savedCache.containsKey(key)) return _savedCache[key];

    final userId = await CurrentUserService.instance.resolveId();
    final row = await _sb
        .from('user_realmojis')
        .select('image_url')
        .eq('user_id', userId)
        .eq('feed_scope', feedScope)
        .eq('emoji_type', emojiType.wire)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));

    final url = row == null ? null : row['image_url'] as String?;
    _savedCache[key] = url;
    return url;
  }

  /// Fast path — a saved selfie already exists, so this just writes the
  /// reaction event using it. No upload, no camera. [groupPostId] routes
  /// this at a group_posts row instead of a posts row (mutually exclusive
  /// with [postId] — see the group_post_id migration on
  /// post_realmoji_reactions).
  Future<void> reactWithSaved({
    String? postId,
    String? groupPostId,
    required RealmojiType emojiType,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb.from('post_realmoji_reactions').insert({
      'post_id': postId,
      'group_post_id': groupPostId,
      'user_id': userId,
      'emoji_type': emojiType.wire,
    });
  }

  /// Uploads + saves a selfie for (feedScope, emojiType) WITHOUT reacting
  /// to any post — used by RealmojiLibraryScreen, which manages saved
  /// selfies ahead of time and has no postId of its own. captureAndReact
  /// below is this plus an immediate reaction, for the in-post capture
  /// flow. Returns the public URL.
  Future<String> captureSelfieOnly({
    required String feedScope,
    required RealmojiType emojiType,
    required File selfie,
  }) async {
    feedScope = kOneScope;
    final userId = await CurrentUserService.instance.resolveId();
    final compressed = await compressForThumbnail(selfie);

    final url = await StorageService.uploadRealmojiSelfie(
      file: compressed,
      userId: userId,
      feedScope: feedScope,
      emojiType: emojiType.wire,
    );
    if (url == null) {
      throw StateError('RealMoji selfie upload failed');
    }

    // .select() is mandatory on this project: an RLS refusal comes back as
    // ZERO ROWS AND NO ERROR, so a save that was rejected looked exactly
    // like one that worked — the screen would reload, find nothing new, and
    // silently show the old RealMoji. Reported as "the retaken photo isn't
    // getting saved". The upload above already threw on ITS failure; this
    // makes the row write equally honest.
    //
    // A retake is the case that matters most here: it conflicts on
    // (user_id, feed_scope, emoji_type), so the upsert takes its UPDATE
    // path — a different policy from the INSERT that the first-ever save
    // uses, and therefore able to fail on its own.
    final rows = await _sb
        .from('user_realmojis')
        .upsert(
          {
            'user_id': userId,
            'feed_scope': feedScope,
            'emoji_type': emojiType.wire,
            'image_url': url,
          },
          onConflict: 'user_id,feed_scope,emoji_type',
        )
        .select('id');
    if (rows.isEmpty) {
      throw StateError("Couldn't save that RealMoji.");
    }
    _savedCache[_cacheKey(feedScope, emojiType)] = url;
    return url;
  }

  /// Slow path — no saved selfie yet for this (feedScope, emojiType).
  /// Compresses + uploads [selfie] to storage, upserts the user_realmojis
  /// row, then immediately writes the post_realmoji_reactions event. Order
  /// matters: the saved-selfie row must exist before the reaction row, so
  /// any reader joining the two (the reactor stack) never sees a dangling
  /// reaction with no selfie to show.
  Future<void> captureAndReact({
    String? postId,
    String? groupPostId,
    required String feedScope,
    required RealmojiType emojiType,
    required File selfie,
  }) async {
    await captureSelfieOnly(feedScope: feedScope, emojiType: emojiType, selfie: selfie);

    await reactWithSaved(postId: postId, groupPostId: groupPostId, emojiType: emojiType);
  }

  /// Retake: deletes the old storage object + user_realmojis row (per the
  /// explicit requirement, rather than relying on upsert to silently
  /// overwrite) and clears the cache entry so the next picker tap re-opens
  /// the camera instead of instant-reacting with the stale URL.
  /// BUG FIX: this used to delete the old storage object + user_realmojis
  /// row UP FRONT, before the camera even opened. RealmojiLibraryScreen's
  /// own _capture returns immediately, without calling captureSelfieOnly at
  /// all, the moment the camera result comes back null — which is exactly
  /// what happens when the user cancels. So cancelling a retake destroyed
  /// the existing RealMoji with nothing to replace it: total loss from
  /// backing out of the camera, one further symptom of the same underlying
  /// report as the mislabeled/silent upload logging fixed alongside this.
  ///
  /// Now purely a client-side cache clear: [captureSelfieOnly]'s own upsert
  /// (`onConflict: user_id,feed_scope,emoji_type`) already overwrites the
  /// same storage path and row on a SUCCESSFUL new capture — nothing here
  /// needs to pre-delete anything for that to work. Clearing the cache
  /// entry is still necessary so the picker re-opens the camera on the next
  /// tap instead of instant-reacting with the (still valid, still saved)
  /// old photo.
  void retake({
    required String feedScope,
    required RealmojiType emojiType,
  }) {
    _savedCache.remove(_cacheKey(feedScope, emojiType));
  }

  /// Everyone feed only — reactor selfies for the bottom stack. Two queries
  /// rather than one PostgREST embed: user_realmojis has no FK tying it to
  /// a specific post_realmoji_reactions row (it's keyed on
  /// user+scope+emoji, not per-reaction), so a single embedded select can't
  /// express "this reactor's selfie for THIS emoji_type" — fetch the
  /// reaction rows, then batch-fetch the matching selfies and zip them
  /// client-side.
  Future<List<RealmojiReaction>> fetchReactors(String? postId, {String? groupPostId}) async {
    var query = _sb
        .from('post_realmoji_reactions')
        .select('id, user_id, emoji_type, created_at, users(name)');
    query = groupPostId != null ? query.eq('group_post_id', groupPostId) : query.eq('post_id', postId!);
    final reactionRows = await query
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 8));

    final reactions = (reactionRows as List).cast<Map<String, dynamic>>();
    if (reactions.isEmpty) return const [];

    final userIds = reactions.map((r) => r['user_id'] as String).toSet().toList();
    final selfieRows = await _sb
        .from('user_realmojis')
        .select('user_id, emoji_type, image_url')
        .eq('feed_scope', ReactionPresetCategory.everyone.wire)
        .inFilter('user_id', userIds)
        .timeout(const Duration(seconds: 8));

    String? selfieFor(String userId, String emojiType) {
      for (final row in (selfieRows as List).cast<Map<String, dynamic>>()) {
        if (row['user_id'] == userId && row['emoji_type'] == emojiType) {
          return row['image_url'] as String?;
        }
      }
      return null;
    }

    return reactions.map((r) {
      final emojiType = r['emoji_type'] as String;
      final userId = r['user_id'] as String;
      final user = r['users'] as Map?;
      return RealmojiReaction(
        id: r['id'] as String,
        userId: userId,
        userName: (user?['name'] as String?) ?? 'someone',
        emojiType: realmojiTypeFromWire(emojiType),
        selfieUrl: selfieFor(userId, emojiType),
        createdAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  /// Anonymous feed only — emoji+count, no identity. Reads the
  /// anon_reaction_counts view directly rather than post_realmoji_reactions
  /// itself, so there is no code path in this feed that can even see a
  /// user_id, let alone render one.
  /// The RealMoji FACES on an anonymous post — photo + emoji, no identity.
  ///
  /// Backed by the anon_post_reaction_faces RPC (20260906190000), which is
  /// what makes this possible at all: post_realmoji_reactions stays closed
  /// for anonymous posts so raw rows can never hand out a reactor -> user
  /// map, and the RPC returns only the emoji and the selfie url.
  ///
  /// [AnonReactionFace.imageUrl] is null when the reactor has since retaken
  /// that RealMoji away — render the glyph alone rather than dropping the
  /// reaction, or the strip would disagree with the count beside it.
  Future<List<AnonReactionFace>> fetchAnonReactionFaces(String postId) async {
    try {
      final rows = await _sb
          .rpc('anon_post_reaction_faces', params: {'p_post_id': postId})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          AnonReactionFace(
            type: realmojiTypeFromWire(
              (r as Map)['emoji_type'] as String? ?? 'like',
            ),
            imageUrl: r['image_url'] as String?,
          ),
      ];
    } catch (e, st) {
      debugPrint('[RealmojiService.fetchAnonReactionFaces] $postId failed: $e\n$st');
      return const [];
    }
  }

  /// The top viewers' faces on an anonymous post — for the seen-count chip.
  /// Explicit request, with a screenshot circling three plain decorative
  /// dots: "attach real dp of the people there, top 3 if not 2".
  ///
  /// NOT the same trust boundary as [fetchAnonReactionFaces] above. A
  /// reaction is a voluntary act; viewing is passive (recordView fires on
  /// scroll, no consent gesture) — returning a viewer's REAL profile photo
  /// here would let an anon post's author see the actual faces of everyone
  /// who merely scrolled past it. The RPC (anon_post_seen_faces) mirrors
  /// the reaction-face precedent instead: a viewer contributes a face only
  /// if they've saved a feed_scope='anonymous' RealMoji selfie (their own
  /// affirmative choice to have an anon-feed face at all) — never their
  /// user id, real name, or real profile_photo_url. A viewer with no anon
  /// selfie contributes nothing; the chip's own decorative-dot fallback
  /// covers that, same as it always has.
  Future<List<String>> fetchAnonPostSeenFaces(String postId, {int limit = 3}) async {
    try {
      final rows = await _sb
          .rpc('anon_post_seen_faces', params: {'p_post_id': postId, 'p_limit': limit})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          if (((r as Map)['photo_url'] as String?) != null) r['photo_url'] as String,
      ];
    } catch (e, st) {
      debugPrint('[RealmojiService.fetchAnonPostSeenFaces] $postId failed: $e\n$st');
      return const [];
    }
  }

  /// Batched twin of [fetchAnonPostSeenFaces] — one round trip for a whole
  /// page of posts instead of one RPC per post.
  ///
  /// BUG FIX: _hydrateCounts (anon_feed_screen.dart) used to fan out
  /// fetchAnonPostSeenFaces per-post via Future.wait, all fired at once.
  /// Each has an 8s timeout; past ~4 concurrent calls on a real network the
  /// rest started timing out and failing soft to [], so the seen pill fell
  /// back to decorative dots on any post beyond the first few. Reported as
  /// "if more than 4 it's not showing the dp in the pill". The engagement
  /// fetch got the same batching treatment already
  /// (20260907120000_anon_feed_engagement_batch) — this closes the gap.
  ///
  /// Fails soft to an empty map: a missing entry just means that post keeps
  /// the decorative-dot fallback, never a broken feed.
  Future<Map<String, List<String>>> fetchAnonPostSeenFacesBatch(
    List<String> postIds, {
    int limit = 3,
  }) async {
    if (postIds.isEmpty) return {};
    try {
      final rows = await _sb
          .rpc('anon_post_seen_faces_batch', params: {
            'p_post_ids': postIds,
            'p_limit': limit,
          })
          .timeout(const Duration(seconds: 10));
      final out = <String, List<String>>{};
      for (final raw in (rows as List)) {
        final row = raw as Map;
        final pid = row['post_id'] as String?;
        final url = row['photo_url'] as String?;
        if (pid == null || url == null) continue;
        (out[pid] ??= []).add(url);
      }
      return out;
    } catch (e, st) {
      debugPrint('[RealmojiService.fetchAnonPostSeenFacesBatch] failed: $e\n$st');
      return {};
    }
  }

  Future<List<AnonRealmojiCount>> fetchAnonCounts(String postId) async {
    final rows = await _sb
        .from('anon_reaction_counts')
        .select('emoji_type, count')
        .eq('post_id', postId)
        .timeout(const Duration(seconds: 8));

    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      return AnonRealmojiCount(
        emojiType: realmojiTypeFromWire(r['emoji_type'] as String),
        count: r['count'] as int,
      );
    }).toList();
  }

  /// The CALLER's own reaction on this post, if any — drives the reaction-
  /// entry badge's "already reacted" glow (PostReactionButton's `myEmoji`,
  /// post_card_shared.dart), same role reactions.myEmoji played for the old
  /// system. Safe to read even on an anon post: this is the viewer checking
  /// their OWN row (RLS-scoped to auth.uid()), not exposing anyone's
  /// identity to anyone else — see AnonRealmojiCounts' doc for the rule
  /// this does NOT violate.
  Future<RealmojiType?> myReaction(String? postId, {String? groupPostId}) async {
    final userId = await CurrentUserService.instance.resolveId();
    var query = _sb.from('post_realmoji_reactions').select('emoji_type');
    query = groupPostId != null ? query.eq('group_post_id', groupPostId) : query.eq('post_id', postId!);
    final row = await query
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    if (row == null) return null;
    return realmojiTypeFromWire(row['emoji_type'] as String);
  }

  /// Reaction + comment data for a WHOLE PAGE of anon posts in one call.
  ///
  /// Replaces the per-post fan-out of fetchAnonCounts + myReaction +
  /// CommentService.fetchCount + fetchAnonReactionFaces, which cost 3-4
  /// requests per post — 60-80 for a 20-post page, throttled to 4 at a time
  /// so it didn't time out, and therefore ~15-20 sequential waves before the
  /// last card lost its skeleton.
  ///
  /// Same visibility rule as before: the RPC applies post_engagement_visible
  /// per post, so a post whose engagement the caller can't see comes back
  /// empty exactly as the individual queries returned empty.
  ///
  /// Fails soft to an empty map — callers keep their nulls, so the cards go
  /// on showing skeletons rather than fabricating zeros.
  Future<Map<String, AnonPostEngagement>> fetchAnonEngagement(
    List<String> postIds,
  ) async {
    if (postIds.isEmpty) return const {};
    try {
      final rows = await _sb
          .rpc('anon_feed_engagement', params: {'p_post_ids': postIds})
          .timeout(const Duration(seconds: 10));
      final out = <String, AnonPostEngagement>{};
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final id = m['post_id'] as String?;
        if (id == null) continue;
        out[id] = AnonPostEngagement(
          commentCount: (m['comment_count'] as num?)?.toInt() ?? 0,
          myReaction: m['my_reaction'] == null
              ? null
              : realmojiTypeFromWire(m['my_reaction'] as String),
          counts: [
            for (final c in (m['counts'] as List? ?? const []))
              AnonRealmojiCount(
                emojiType: realmojiTypeFromWire(
                  (c as Map)['emoji_type'] as String? ?? 'like',
                ),
                count: (c['count'] as num?)?.toInt() ?? 0,
              ),
          ],
          faces: [
            for (final f in (m['faces'] as List? ?? const []))
              AnonReactionFace(
                type: realmojiTypeFromWire(
                  (f as Map)['emoji_type'] as String? ?? 'like',
                ),
                imageUrl: f['image_url'] as String?,
              ),
          ],
        );
      }
      return out;
    } catch (e, st) {
      debugPrint('[RealmojiService.fetchAnonEngagement] failed: $e\n$st');
      return const {};
    }
  }

  /// Clears the saved-selfie cache — call on sign-out, same convention as
  /// ReactionPresetService.reset().
  void reset() => _savedCache.clear();
}

/// One post's worth of [RealmojiService.fetchAnonEngagement].
class AnonPostEngagement {
  const AnonPostEngagement({
    required this.commentCount,
    required this.myReaction,
    required this.counts,
    required this.faces,
  });

  final int commentCount;

  /// The CALLER's own reaction, or null. Same field myReaction() returned.
  final RealmojiType? myReaction;
  final List<AnonRealmojiCount> counts;
  final List<AnonReactionFace> faces;

  /// Total reactions across every emoji — what the card shows as the count.
  int get totalReactions => counts.fold<int>(0, (a, c) => a + c.count);
}
