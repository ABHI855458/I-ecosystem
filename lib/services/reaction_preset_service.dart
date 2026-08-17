import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/image_compress.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// ReactionPresetService — the personal "reaction library". A user records a
// face+emoji (Everyone) or emoji-only (Anonymous) reaction ONCE here, then
// reuses it instantly on any post (reaction_preset_tray.dart) instead of
// capturing a fresh selfie every time. Presets are just a faster SOURCE for
// a `reactions` row — applying one still writes to that table exactly like
// today (see ReactionService.setEmojiReaction /
// setFaceReactionFromPreset), so this service owns ONLY the
// `reaction_presets` table + its own storage prefix, nothing about live
// per-post reactions.
// ---------------------------------------------------------------------------

enum ReactionPresetCategory { anonymous, everyone }

extension ReactionPresetCategoryWire on ReactionPresetCategory {
  String get wire => this == ReactionPresetCategory.anonymous ? 'anonymous' : 'everyone';
}

ReactionPresetCategory categoryFromWire(String wire) =>
    wire == 'everyone' ? ReactionPresetCategory.everyone : ReactionPresetCategory.anonymous;

class ReactionPreset {
  const ReactionPreset({
    required this.id,
    required this.category,
    required this.emoji,
    required this.photoUrl,
    required this.createdAt,
  });

  final String id;
  final ReactionPresetCategory category;
  final String emoji;

  /// Null for 'anonymous' presets — a real face breaks anonymity on that
  /// feed, so the add flow skips the camera entirely for that category and
  /// this is never set. Always set for 'everyone' presets. Also enforced
  /// at the DB layer — see the CHECK constraint in supabase/schema.sql.
  final String? photoUrl;
  final DateTime createdAt;

  factory ReactionPreset.fromRow(Map<String, dynamic> row) => ReactionPreset(
        id: row['id'] as String,
        category: categoryFromWire(row['category'] as String),
        emoji: row['emoji'] as String,
        photoUrl: row['photo_url'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

class ReactionPresetService {
  ReactionPresetService._();
  static final instance = ReactionPresetService._();

  final _sb = Supabase.instance.client;
  final _uuid = const Uuid();

  // In-memory cache, per category — the whole point of the quick-pick tray
  // (reaction_preset_tray.dart) is that it renders instantly on every post;
  // re-querying Supabase on every single tap of the reaction badge would
  // defeat that. Populated on first fetch, kept in sync by add/delete
  // below, cleared on sign-out.
  final Map<ReactionPresetCategory, List<ReactionPreset>> _cache = {};

  /// Presets already loaded for [category] this session, or null if never
  /// fetched — lets a caller (the tray) render instantly with no async gap
  /// once the library's been opened, or a post reacted to, at least once.
  List<ReactionPreset>? cached(ReactionPresetCategory category) => _cache[category];

  /// Returns the cached list instantly if present, else fetches from
  /// Supabase and populates the cache. Pass [forceRefresh] to bypass the
  /// cache (e.g. after the library screen's own pull-to-refresh).
  Future<List<ReactionPreset>> fetchPresets(
    ReactionPresetCategory category, {
    bool forceRefresh = false,
  }) async {
    final existing = _cache[category];
    if (existing != null && !forceRefresh) return existing;

    final userId = await CurrentUserService.instance.resolveId();
    final rows = await _sb
        .from('reaction_presets')
        .select()
        .eq('user_id', userId)
        .eq('category', category.wire)
        .order('created_at')
        .timeout(const Duration(seconds: 8));

    final presets = (rows as List)
        .map((raw) => ReactionPreset.fromRow(Map<String, dynamic>.from(raw as Map)))
        .toList();
    _cache[category] = presets;
    return presets;
  }

  /// Anonymous-category preset — emoji only, never a photo. Skips the
  /// camera step entirely (enforced here in the client, and again by a DB
  /// CHECK constraint — see supabase/schema.sql).
  Future<ReactionPreset> addAnonymousPreset({required String emoji}) async {
    final userId = await CurrentUserService.instance.resolveId();
    final row = await _sb
        .from('reaction_presets')
        .insert({
          'user_id': userId,
          'category': ReactionPresetCategory.anonymous.wire,
          'emoji': emoji,
          'photo_url': null,
        })
        .select()
        .single();

    final preset = ReactionPreset.fromRow(row);
    _addToCache(preset);
    return preset;
  }

  /// Everyone-category preset — compresses [selfie] to thumbnail size (it
  /// only ever renders as a small circular thumbnail, same reasoning as
  /// ReactionService.setFaceReaction), uploads it to
  /// reaction-photos/presets/$userId/$presetId.jpg, then saves the row.
  Future<ReactionPreset> addEveryonePreset({
    required String emoji,
    required File selfie,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    final presetId = _uuid.v4();
    final compressed = await compressForThumbnail(selfie);

    final url = await StorageService.uploadReactionPresetPhoto(
      file: compressed,
      userId: userId,
      presetId: presetId,
    );
    if (url == null) {
      throw StateError('Reaction preset photo upload failed');
    }

    final row = await _sb
        .from('reaction_presets')
        .insert({
          'id': presetId,
          'user_id': userId,
          'category': ReactionPresetCategory.everyone.wire,
          'emoji': emoji,
          'photo_url': url,
        })
        .select()
        .single();

    final preset = ReactionPreset.fromRow(row);
    _addToCache(preset);
    return preset;
  }

  Future<void> deletePreset(ReactionPreset preset) async {
    await _sb.from('reaction_presets').delete().eq('id', preset.id);
    _cache[preset.category] =
        (_cache[preset.category] ?? const []).where((p) => p.id != preset.id).toList();
    // Storage cleanup is best-effort, same convention as
    // ReactionService.removeFaceReaction — a stray orphaned object under
    // reaction-photos/presets/ costs nothing to leave behind.
  }

  void _addToCache(ReactionPreset preset) {
    final list = _cache[preset.category];
    _cache[preset.category] = list == null ? [preset] : [...list, preset];
  }

  /// Clears the cache — call on sign-out so a subsequent sign-in (as a
  /// different user) doesn't show the previous user's presets.
  void reset() => _cache.clear();
}
