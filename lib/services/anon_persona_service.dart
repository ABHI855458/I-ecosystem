import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

/// The current user's anon persona photo — the image they set specifically
/// to represent their anonymous identity, distinct from (and never derived
/// from) their real profile photo.
///
/// Backed by `users.anon_photo_url` (migration 20260912000000). It used to
/// be an in-memory field with no column behind it, so the photo was lost on
/// every restart and no one else could ever see it — the anon feed drew a
/// generated glyph for every post instead.
///
/// Anonymity is preserved on the read side: `posts_feed` exposes
/// anon_photo_url alongside a NULL user_id, so a viewer sees the persona
/// without ever learning whose it is.
class AnonPersonaService extends ChangeNotifier {
  AnonPersonaService._();
  static final instance = AnonPersonaService._();

  String? _photoUrl;
  String? get photoUrl => _photoUrl;

  /// In-memory only — for callers that already have the URL (e.g. straight
  /// after their own upload). Use [uploadAndSave] to actually persist.
  void setPhoto(String? url) {
    _photoUrl = url;
    notifyListeners();
  }

  /// Reads the persisted persona photo into memory. Safe to call more than
  /// once; fails soft, leaving whatever is already cached.
  Future<void> load() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      final row = await supabase
          .from('users')
          .select('anon_photo_url')
          .eq('id', id)
          .maybeSingle();
      final url = row?['anon_photo_url'] as String?;
      if (url != _photoUrl) {
        _photoUrl = url;
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('[AnonPersonaService.load] failed: $e\n$st');
    }
  }

  /// Uploads [photo] to the `personas` bucket and writes the URL to
  /// `users.anon_photo_url`, so it survives a restart and other people see
  /// it on this user's anonymous posts. Throws on failure — the caller
  /// shows the error rather than pretending it saved.
  Future<void> uploadAndSave(File photo) async {
    final id = await CurrentUserService.instance.resolveId();
    final url = await StorageService.uploadPersonaPhoto(
      file: photo,
      userId: id,
    );
    if (url == null) {
      throw StateError('Persona photo upload failed');
    }
    await supabase.from('users').update({'anon_photo_url': url}).eq('id', id);
    setPhoto(url);
  }

  /// Clears the persona photo everywhere — posts fall back to the generated
  /// glyph avatar.
  Future<void> clear() async {
    final id = await CurrentUserService.instance.resolveId();
    await supabase.from('users').update({'anon_photo_url': null}).eq('id', id);
    setPhoto(null);
  }
}
