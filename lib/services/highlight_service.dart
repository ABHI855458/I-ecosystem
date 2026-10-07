import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase_config.dart';
import '../features/highlights/highlight_models.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// HighlightService — personal highlights (the polaroids).
//
// Reads go straight to `highlights` with items and their posts embedded;
// RLS decides what comes back (see 20261007010000_personal_highlights.sql:
// an item is readable exactly when its post is, so a highlight is visible
// to its owner and to the people in the owner's Friends circle — nothing
// here widens that).
//
// Writes go through save_highlight / delete_highlight only. A new photo is
// uploaded with the ordinary post-image upload and inserted as a QUIET
// post (post_type 'highlight', show_in_feed false): no notification, no
// feed card — the polaroid is the only place it shows.
//
// A ChangeNotifier so every surface that draws polaroids (profile row,
// feed pile, the Wall) refreshes after a save, a delete or a "seen".
// ---------------------------------------------------------------------------

class HighlightService extends ChangeNotifier {
  HighlightService._();
  static final instance = HighlightService._();

  static const maxPhotos = 20;
  static const maxTitle = 24;
  static const maxHighlights = 12;

  /// A highlight video: short. The database refuses anything over 65 s
  /// (posts_video_duration_ck); the size cap keeps one clip inside a single
  /// upload request.
  static const maxVideoSeconds = 60;
  static const maxVideoBytes = 45 * 1024 * 1024;

  static const _select =
      'id, user_id, title, updated_at, '
      'users(name, username, profile_photo_url), '
      'highlight_items(position, post_id, '
      'posts(id, image_url, photo_urls, aspect_ratio, deleted_at, '
      'video_url, video_duration_ms))';

  // ── reads ───────────────────────────────────────────────────────────────

  /// [userId]'s highlights this viewer may see, most recently updated
  /// first. Empty for someone who hasn't put the viewer in their Friends
  /// circle — the rows simply aren't returned.
  Future<List<Highlight>> fetchForUser(String userId) async {
    final rows = await supabase
        .from('highlights')
        .select(_select)
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .timeout(const Duration(seconds: 12));
    return _parse(rows);
  }

  /// Every highlight this viewer may see — their own and their friends' —
  /// most recently updated first. The Wall and the feed pile.
  Future<List<Highlight>> fetchWall({int limit = 90}) async {
    final rows = await supabase
        .from('highlights')
        .select(_select)
        .order('updated_at', ascending: false)
        .limit(limit)
        .timeout(const Duration(seconds: 12));
    return _parse(rows);
  }

  List<Highlight> _parse(List<dynamic> rows) => [
    for (final r in rows)
      ?Highlight.fromRow(Map<String, dynamic>.from(r as Map)),
  ];

  // ── "seen" (this device only) ───────────────────────────────────────────
  //
  // highlight id -> the updated_at it had when last opened. A friend adding
  // photos moves updated_at, so the stamp no longer matches and the
  // polaroid is "new" again. Kept on the device: it is a nudge, not data
  // anyone else needs (the owner's "seen by" comes from post_views).

  Map<String, String> _seen = {};
  String? _myId;
  Future<void>? _ready;

  /// Bumped when a highlight is saved or deleted (not on a "seen"), so a
  /// listening screen can tell "refetch" from "just redraw".
  int get version => _version;
  int _version = 0;

  String? get myId => _myId;

  /// Loads who I am and what I've already opened. Cheap to await often,
  /// and re-loads by itself when a different account has signed in (the
  /// "seen" stamps are kept per account).
  Future<void> ready() async {
    final me = await CurrentUserService.instance.resolveId();
    if (_ready == null || me != _myId) _ready = _load(me);
    return _ready;
  }

  Future<void> _load(String me) async {
    _myId = me;
    _seen = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seenKey);
      if (raw != null) {
        _seen = {
          for (final e in (jsonDecode(raw) as Map).entries)
            e.key as String: e.value.toString(),
        };
      }
    } catch (_) {
      // Unreadable store = nothing seen yet; never worth failing a screen.
      _seen = {};
    }
  }

  String get _seenKey => 'highlights_seen_v1_${_myId ?? 'anon'}';

  /// True for a friend's highlight I haven't opened since it last gained
  /// photos. My own are never "new" to me.
  bool isNew(Highlight h) => h.ownerId != _myId && _seen[h.id] != h.updatedAt;

  bool isMine(Highlight h) => h.ownerId == _myId;

  Future<void> markSeen(Highlight h) async {
    await ready();
    if (h.ownerId == _myId || _seen[h.id] == h.updatedAt) return;
    _seen[h.id] = h.updatedAt;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenKey, jsonEncode(_seen));
    } catch (_) {}
  }

  // ── writes ──────────────────────────────────────────────────────────────

  /// Creates ([id] null) or edits a highlight so it holds exactly [photos]
  /// in that order, uploading the ones that are still on the phone.
  /// Returns the highlight's id. Throws [HighlightException] with a
  /// sentence the person can read.
  Future<String> save({
    String? id,
    required String title,
    required List<HighlightDraftPhoto> photos,
    void Function(int done, int total)? onProgress,
  }) async {
    final clean = title.trim();
    if (clean.isEmpty) {
      throw const HighlightException('Give it a name first.');
    }
    if (photos.isEmpty) {
      throw const HighlightException('Add at least one photo.');
    }
    if (photos.length > maxPhotos) {
      throw const HighlightException(
        'A highlight holds up to $maxPhotos photos.',
      );
    }

    final me = await CurrentUserService.instance.resolveId();
    final total = photos.where((p) => p.isLocal).length;
    final created = <String>[];
    final ids = <String>[];
    var done = 0;
    try {
      for (final p in photos) {
        if (!p.isLocal) {
          ids.add(p.postId!);
          continue;
        }
        final postId = const Uuid().v4();
        final file = File(p.localPath!);
        final aspect = await _aspectOf(file);
        final url = await StorageService.uploadPostImage(
          file: file,
          isAnon: false,
          userId: me,
          postId: postId,
        );
        // A video: [file] above was its poster still (posts need one next
        // to a video); the clip itself goes up beside it.
        String? videoUrl;
        if (p.localVideoPath != null) {
          videoUrl = await StorageService.uploadPostVideo(
            file: File(p.localVideoPath!),
            isAnon: false,
            userId: me,
          );
          if (videoUrl == null) {
            throw const HighlightException(
              "Couldn't upload the video. Check your connection and try "
              'again.',
            );
          }
        }
        await supabase.from('posts').insert({
          'id': postId,
          'user_id': me,
          'visibility': 'friends',
          'content': '',
          'image_url': url,
          'video_url': ?videoUrl,
          if (videoUrl != null && p.videoMs != null)
            'video_duration_ms': p.videoMs,
          // The three fields that make this a QUIET post — save_highlight
          // refuses a photo that doesn't carry all of them.
          'post_type': 'highlight',
          'show_in_feed': false,
          'aspect_ratio': aspect.toString(),
          // posts.created_at is a zoneless timestamp read as UTC.
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        created.add(postId);
        ids.add(postId);
        onProgress?.call(++done, total);
      }
      final result = await supabase.rpc(
        'save_highlight',
        params: {'p_id': id, 'p_title': clean, 'p_post_ids': ids},
      );
      _version++;
      notifyListeners();
      return result as String;
    } catch (e, st) {
      debugPrint('[HighlightService.save] failed: $e\n$st');
      // Nothing was attached, so the photos uploaded in THIS attempt have
      // no highlight to live in. Take them back out rather than leave
      // invisible rows behind.
      if (created.isNotEmpty) {
        try {
          await supabase
              .from('posts')
              .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
              .inFilter('id', created);
        } catch (_) {}
      }
      throw _friendly(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await supabase.rpc('delete_highlight', params: {'p_id': id});
      _version++;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[HighlightService.delete] failed: $e\n$st');
      throw _friendly(e);
    }
  }

  static HighlightException _friendly(Object e) {
    if (e is HighlightException) return e;
    final msg = e is PostgrestException ? e.message : e.toString();
    if (msg.contains('HIGHLIGHT_LIMIT')) {
      return const HighlightException(
        'You already have $maxHighlights highlights. Delete one to add '
        'another.',
      );
    }
    if (msg.contains('HIGHLIGHT_BAD_TITLE')) {
      return const HighlightException(
        'The name needs 1 to $maxTitle letters.',
      );
    }
    if (msg.contains('HIGHLIGHT_BAD_PHOTO_COUNT')) {
      return const HighlightException(
        'A highlight needs 1 to $maxPhotos photos.',
      );
    }
    if (msg.contains('HIGHLIGHT_NOT_FOUND')) {
      return const HighlightException('That highlight is gone.');
    }
    return const HighlightException(
      "Couldn't save the highlight. Check your connection and try again.",
    );
  }

  /// Width / height of a photo on disk; 4:5 when it can't be read.
  static Future<double> _aspectOf(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final aspect = image.width / image.height;
      image.dispose();
      return aspect;
    } catch (_) {
      return 0.8;
    }
  }
}
