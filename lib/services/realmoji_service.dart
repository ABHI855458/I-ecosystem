import 'dart:io';

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

enum RealmojiType { like, joy, surprise, love, laughter, instant }

extension RealmojiTypeWire on RealmojiType {
  String get wire => name;

  /// Display glyph — the schema stores the enum name, not an emoji
  /// character, so every UI surface needs this mapping in exactly one
  /// place.
  String get glyph => switch (this) {
        RealmojiType.like => '👍',
        RealmojiType.joy => '😂',
        RealmojiType.surprise => '😮',
        RealmojiType.love => '❤️',
        RealmojiType.laughter => '🤣',
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

  String _cacheKey(String feedScope, RealmojiType emojiType) => '$feedScope:${emojiType.wire}';

  /// All of the caller's saved selfies for [feedScope] in one query — the
  /// picker row prefetches this once on open so all 6 options can render
  /// their "already captured" state (a cyan ring) instantly, instead of 6
  /// separate round trips. Populates the same cache savedSelfieUrl reads,
  /// so a subsequent per-emoji lookup is free.
  Future<Map<RealmojiType, String>> savedSelfies({required String feedScope}) async {
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
  /// reaction event using it. No upload, no camera.
  Future<void> reactWithSaved({
    required String postId,
    required RealmojiType emojiType,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb.from('post_realmoji_reactions').insert({
      'post_id': postId,
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

    await _sb.from('user_realmojis').upsert(
      {
        'user_id': userId,
        'feed_scope': feedScope,
        'emoji_type': emojiType.wire,
        'image_url': url,
      },
      onConflict: 'user_id,feed_scope,emoji_type',
    );
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
    required String postId,
    required String feedScope,
    required RealmojiType emojiType,
    required File selfie,
  }) async {
    await captureSelfieOnly(feedScope: feedScope, emojiType: emojiType, selfie: selfie);

    await reactWithSaved(postId: postId, emojiType: emojiType);
  }

  /// Retake: deletes the old storage object + user_realmojis row (per the
  /// explicit requirement, rather than relying on upsert to silently
  /// overwrite) and clears the cache entry so the next picker tap re-opens
  /// the camera instead of instant-reacting with the stale URL.
  Future<void> retake({
    required String feedScope,
    required RealmojiType emojiType,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await StorageService.deleteRealmojiSelfie(
      userId: userId,
      feedScope: feedScope,
      emojiType: emojiType.wire,
    );
    await _sb
        .from('user_realmojis')
        .delete()
        .eq('user_id', userId)
        .eq('feed_scope', feedScope)
        .eq('emoji_type', emojiType.wire);
    _savedCache.remove(_cacheKey(feedScope, emojiType));
  }

  /// Everyone feed only — reactor selfies for the bottom stack. Two queries
  /// rather than one PostgREST embed: user_realmojis has no FK tying it to
  /// a specific post_realmoji_reactions row (it's keyed on
  /// user+scope+emoji, not per-reaction), so a single embedded select can't
  /// express "this reactor's selfie for THIS emoji_type" — fetch the
  /// reaction rows, then batch-fetch the matching selfies and zip them
  /// client-side.
  Future<List<RealmojiReaction>> fetchReactors(String postId) async {
    final reactionRows = await _sb
        .from('post_realmoji_reactions')
        .select('id, user_id, emoji_type, created_at, users(name)')
        .eq('post_id', postId)
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
  Future<RealmojiType?> myReaction(String postId) async {
    final userId = await CurrentUserService.instance.resolveId();
    final row = await _sb
        .from('post_realmoji_reactions')
        .select('emoji_type')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    if (row == null) return null;
    return realmojiTypeFromWire(row['emoji_type'] as String);
  }

  /// Clears the saved-selfie cache — call on sign-out, same convention as
  /// ReactionPresetService.reset().
  void reset() => _savedCache.clear();
}
