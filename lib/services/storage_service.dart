import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

class StorageService {
  StorageService._();

  static const _postsBucket = 'posts';
  static const _profilesBucket = 'profiles';
  // Separate from _profilesBucket: the anon persona photo is a distinct
  // image the user picks to represent their anonymous identity, never the
  // real profile photo — keeping it in its own bucket/path means the two
  // can never accidentally resolve to the same object.
  static const _personasBucket = 'personas';
  // Named distinctly from the app's "Bucket" feature (buckets/
  // bucket_contributions tables) to avoid confusing a Supabase Storage
  // bucket with the product concept that happens to share the word.
  static const _bucketPhotosBucket = 'bucket-photos';
  static const _reactionPhotosBucket = 'reaction-photos';
  static const _groupIconsBucket = 'group-icons';
  static const _groupPhotosBucket = 'group-photos';

  // ---------------------------------------------------------------------------
  // Post image upload
  // ---------------------------------------------------------------------------

  /// Uploads a post image and returns the public URL. Throws on failure —
  /// callers must not swallow this, since a failed upload means the post
  /// would otherwise silently save without its photo.
  static Future<String> uploadPostImage({
    required File file,
    required bool isAnon,
    String userId = 'user_local',
    String? postId,
  }) async {
    final pid = postId ?? 'post_${DateTime.now().millisecondsSinceEpoch}';
    final folder = isAnon ? 'anonymous' : 'everyone';
    final path = '$folder/$userId/$pid.jpg';

    try {
      final bytes = await file.readAsBytes();
      await supabase.storage.from(_postsBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_postsBucket).getPublicUrl(path);
    } on StorageException catch (e, st) {
      debugPrint(
          '[StorageService.uploadPostImage] StorageException uploading to '
          '"$path" (bucket: $_postsBucket): statusCode=${e.statusCode} '
          'message=${e.message} error=${e.error}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint(
          '[StorageService.uploadPostImage] Unexpected error uploading to '
          '"$path" (bucket: $_postsBucket): $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Profile avatar upload
  // ---------------------------------------------------------------------------

  /// Uploads a profile avatar. Returns the public URL, or null on failure.
  static Future<String?> uploadAvatar({
    required File file,
    required String userId,
  }) async {
    try {
      final path = 'avatars/$userId.jpg';
      final bytes = await file.readAsBytes();
      await supabase.storage.from(_profilesBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_profilesBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Anon persona photo upload
  // ---------------------------------------------------------------------------

  /// Uploads the photo a user picks to represent their anonymous identity
  /// (shown on anon posts instead of their real profile photo/name). Returns
  /// the public URL, or null on failure.
  static Future<String?> uploadPersonaPhoto({
    required File file,
    required String userId,
  }) async {
    try {
      final path = 'personas/$userId.jpg';
      final bytes = await file.readAsBytes();
      await supabase.storage.from(_personasBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_personasBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Bucket contribution photo upload
  // ---------------------------------------------------------------------------

  /// Uploads a photo dropped into a Bucket. Returns the public URL, or null
  /// on failure.
  static Future<String?> uploadBucketPhoto({
    required File file,
    required String bucketId,
    required String userId,
  }) async {
    try {
      final path =
          '$bucketId/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage.from(_bucketPhotosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_bucketPhotosBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Face reaction selfie upload
  // ---------------------------------------------------------------------------

  /// Uploads a face-reaction selfie. Path is deterministic per (post, user)
  /// rather than timestamp-suffixed — a user only ever has one active face
  /// reaction per post (reactions.UNIQUE(post_id,user_id,type)), so
  /// re-reacting overwrites the same storage object instead of leaving the
  /// old one orphaned. Returns the public URL, or null on failure.
  static Future<String?> uploadReactionPhoto({
    required File file,
    required String postId,
    required String userId,
  }) async {
    try {
      final path = '$postId/$userId.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage.from(_reactionPhotosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_reactionPhotosBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Group icon upload
  // ---------------------------------------------------------------------------

  /// Uploads a group's icon. Deterministic path (one icon per group,
  /// overwritten on change) — same reasoning as uploadAvatar. Returns the
  /// public URL, or null on failure.
  static Future<String?> uploadGroupIcon({
    required File file,
    required String groupId,
  }) async {
    try {
      final path = 'icons/$groupId.jpg';
      final bytes = await file.readAsBytes();
      await supabase.storage.from(_groupIconsBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_groupIconsBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Group post photo upload
  // ---------------------------------------------------------------------------

  /// Uploads a photo posted to a group's shared album. Returns the public
  /// URL, or null on failure.
  static Future<String?> uploadGroupPhoto({
    required File file,
    required String groupId,
    required String userId,
  }) async {
    try {
      final path =
          '$groupId/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage.from(_groupPhotosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_groupPhotosBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the public URL for a given path in the posts bucket.
  static String postPublicUrl(String path) =>
      supabase.storage.from(_postsBucket).getPublicUrl(path);

  /// Returns the public URL for a given path in the profiles bucket.
  static String profilePublicUrl(String path) =>
      supabase.storage.from(_profilesBucket).getPublicUrl(path);
}
