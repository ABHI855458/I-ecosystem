import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
  static const _usAlbumPhotosBucket = 'us-album-photos';
  static const _communityPhotosBucket = 'community-photos';
  static const _communityDocsBucket = 'community-docs';
  static const _pingPhotosBucket = 'ping-photos';

  /// The real image format of [bytes], read from its magic number rather
  /// than trusting a filename.
  ///
  /// BUG FIX (reproduced on a release build, ping reply camera): the ping
  /// upload paths hardcoded a `.jpg` name and `contentType: 'image/jpeg'`
  /// no matter what was actually captured. `camera`'s takePicture() does
  /// NOT always produce JPEG — on the device under test it wrote a PNG —
  /// and an album pick can obviously be a PNG too. The object then went up
  /// with PNG bytes labelled as JPEG, which `curl` confirmed against the
  /// live bucket:
  ///
  ///   HTTP 200  Content-Type: image/jpeg
  ///   /tmp/dl.bin: PNG image data, 1344 x 2992
  ///
  /// A decoder that trusts the declared MIME then refuses the bytes, so the
  /// reply photo never rendered and its box stayed on the hatched
  /// "uploading" placeholder forever (ping_page.dart's
  /// _uploadingPlaceholder, which is also the failure state).
  ///
  /// Returns a `(extension, mimeType)` pair. Defaults to jpeg — the old
  /// behaviour — only when nothing matches, so this can never be worse than
  /// what it replaces.
  static (String, String) _sniffImageType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4E && bytes[3] == 0x47) {
      return ('png', 'image/png');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return ('jpg', 'image/jpeg');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 &&
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 &&
        bytes[10] == 0x42 && bytes[11] == 0x50) {
      return ('webp', 'image/webp');
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return ('gif', 'image/gif');
    }
    return ('jpg', 'image/jpeg');
  }

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
      await supabase.storage
          .from(_postsBucket)
          .uploadBinary(
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
        'message=${e.message} error=${e.error}\n$st',
      );
      rethrow;
    } catch (e, st) {
      debugPrint(
        '[StorageService.uploadPostImage] Unexpected error uploading to '
        '"$path" (bucket: $_postsBucket): $e\n$st',
      );
      rethrow;
    }
  }

  /// Uploads one Moment reply photo. Shares the `posts` bucket rather than
  /// getting its own — a `moment-replies/` path prefix keeps the object
  /// namespace separate, exactly the pattern [uploadDipPhoto] uses inside
  /// `group-photos`. Upsert on a fixed per-(moment, user) path, matching the
  /// `moment_replies_one_per_user` unique index: re-contributing replaces
  /// your photo instead of orphaning the old object.
  ///
  /// Throws on failure, same contract as [uploadPostImage] — a reply row
  /// must never be written without its photo.
  static Future<String> uploadMomentReplyPhoto({
    required File file,
    required String momentPostId,
    required String userId,
  }) async {
    final path = 'moment-replies/$momentPostId/$userId.jpg';

    try {
      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_postsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_postsBucket).getPublicUrl(path);
    } catch (e, st) {
      debugPrint(
        '[StorageService.uploadMomentReplyPhoto] Failed uploading to '
        '"$path" (bucket: $_postsBucket): $e\n$st',
      );
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Profile avatar upload
  // ---------------------------------------------------------------------------

  /// Uploads a profile avatar and returns its public URL.
  ///
  /// THROWS on failure — it does not return null. Reported as "I am unable
  /// to upload the banner and DP": both of these used to swallow every
  /// StorageException and hand back null, so a refused or failed upload
  /// looked identical to a successful one that simply hadn't rendered yet.
  /// The picker opened, the spinner ran, nothing changed, and no message
  /// ever said why. The caller shows the thrown message instead.
  ///
  /// The path must stay `avatars/{users.id}.jpg`: the `profiles` bucket's
  /// INSERT/UPDATE policies (migration 20260908150000) check
  /// `split_part(filename, '.', 1) = my_users_id_text()`, so the filename
  /// IS the authorisation. Passing an `auth.uid()` here instead of a
  /// `users.id` is the keyspace trap and gets a 403.
  static Future<String> uploadAvatar({
    required File file,
    required String userId,
  }) async {
    return _uploadProfileImage(
      file: file,
      path: 'avatars/$userId.jpg',
      what: 'profile photo',
    );
  }

  /// Uploads a profile banner/cover photo. Same bucket and deterministic-
  /// path-per-user pattern as [uploadAvatar] — a separate `banners/`
  /// prefix so the two don't collide. `upsert: true` means the returned
  /// URL is cache-busted with a `?v=` query param, since the object path
  /// itself never changes on re-upload.
  static Future<String> uploadUserBanner({
    required File file,
    required String userId,
  }) async {
    final url = await _uploadProfileImage(
      file: file,
      path: 'banners/$userId.jpg',
      what: 'banner',
    );
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// The shared body of the two above. Kept together so the error handling
  /// can only be right or wrong once.
  static Future<String> _uploadProfileImage({
    required File file,
    required String path,
    required String what,
  }) async {
    final bytes = await file.readAsBytes();
    try {
      await supabase.storage
          .from(_profilesBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
    } on StorageException catch (e) {
      // A 403 here means the path didn't match the policy — worth saying
      // plainly rather than as a raw storage error, because it is the one
      // failure a user can do nothing about and support has to recognise.
      if (e.statusCode == '403' || e.statusCode == '401') {
        throw StateError(
          "You're not allowed to upload that $what. Try signing out and "
          'back in.',
        );
      }
      throw StateError("Couldn't upload your $what: ${e.message}");
    }
    return supabase.storage.from(_profilesBucket).getPublicUrl(path);
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
      // BUG FIX: was 'personas/$userId.jpg' — `.from(_personasBucket)`
      // already scopes every call to the "personas" bucket, so that
      // prefix nested every object one folder deeper than intended
      // (storage path `personas/personas/$userId.jpg`). Not a broken
      // link (the object exists wherever it's actually uploaded, and the
      // public URL always matches), just needless nesting — fixed for
      // new uploads; the one already-live URL still resolves under its
      // old path, so nothing needs migrating.
      final bytes = await file.readAsBytes();
      // Same MIME lie that broke ping reply photos: this hardcoded
      // 'image/jpeg' regardless of what the picker actually returned.
      // The picker here is ImageSource.gallery (my_profile_screen.dart's
      // _pickAnonPhoto) — a PNG or HEIC-converted pick would upload with a
      // Content-Type that doesn't match its bytes, which is exactly the
      // class of bug _sniffImageType exists to close. Extension now comes
      // from the bytes too, so a non-.jpg file no longer sits at a `.jpg`
      // path with a mismatched header.
      final (ext, mime) = _sniffImageType(bytes);
      final path = '$userId.$ext';
      await supabase.storage
          .from(_personasBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mime,
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
      await supabase.storage
          .from(_bucketPhotosBucket)
          .uploadBinary(
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
      await supabase.storage
          .from(_reactionPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage.from(_reactionPhotosBucket).getPublicUrl(path);
    } on StorageException catch (e, st) {
      // BUG FIX: this log tag said [uploadRealmojiSelfie] — copy-pasted
      // from that function without updating the name — so every face-
      // reaction storage failure was misattributed in the logs to a
      // completely different upload path. Harmless for THIS function's own
      // symptoms, but actively misleading while chasing "the real emoji
      // isn't getting saved": grepping logs for uploadRealmojiSelfie turned
      // up entries that were actually this function's failures.
      debugPrint('[StorageService.uploadReactionPhoto] storage error: ${e.statusCode} ${e.message}\n$st');
      return null;
    } catch (e, st) {
      debugPrint('[StorageService.uploadRealmojiSelfie] failed: $e\n$st');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Reaction preset selfie upload
  // ---------------------------------------------------------------------------

  /// Uploads a saved reaction preset's selfie (reaction_preset_service.dart)
  /// — same bucket as live face-reaction selfies, but under its own
  /// `presets/$userId/` prefix so a preset's object can never collide with
  /// (or be overwritten by) a live per-post reaction, which lives at
  /// `$postId/$userId.jpg`. Path is keyed on the preset's own id, not
  /// deterministic per-user, since a user can hold multiple presets at
  /// once. Returns the public URL, or null on failure.
  static Future<String?> uploadReactionPresetPhoto({
    required File file,
    required String userId,
    required String presetId,
  }) async {
    try {
      final path = 'presets/$userId/$presetId.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_reactionPhotosBucket)
          .uploadBinary(
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
  // RealMoji selfie upload
  // ---------------------------------------------------------------------------

  /// Uploads a saved RealMoji selfie (realmoji_service.dart) — same bucket
  /// as live face-reaction selfies, under its own `realmoji/` prefix so it
  /// can never collide with a live per-post reaction (`$postId/$userId.jpg`)
  /// or a reaction preset (`presets/$userId/$presetId.jpg`). Deterministic
  /// path per (user, feedScope, emojiType) — matches
  /// user_realmojis' own UNIQUE(user_id, feed_scope, emoji_type), so a
  /// re-capture overwrites the same object instead of orphaning the one.
  /// Returns the public URL, or null on failure.
  ///
  /// BUG FIX ("the real emoji isn't getting saved"): this used to swallow
  /// BOTH catch clauses with a bare `_`, with no logging at all — the ONE
  /// function in this whole file with zero diagnostics on failure (every
  /// sibling upload function at least debugPrints the storage error).
  /// Confirmed live against the database: no realmoji storage object had
  /// been created OR overwritten in days, meaning uploads were genuinely
  /// failing, silently, with nothing anywhere to say why. Now logged like
  /// every other upload here.
  ///
  /// Cache-busted with a `?v=` timestamp — same fix applied to
  /// uploadGroupIcon for the identical symptom: `upsert: true` overwrites
  /// the SAME path, so a retake returns the exact same url string, and a
  /// device that already cached that url (CachedNetworkImage, keyed on the
  /// url) never refetches and keeps showing the OLD photo even after a
  /// successful retake.
  static Future<String?> uploadRealmojiSelfie({
    required File file,
    required String userId,
    required String feedScope,
    required String emojiType,
  }) async {
    try {
      final path = 'realmoji/$userId/$feedScope/$emojiType.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_reactionPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final url = supabase.storage.from(_reactionPhotosBucket).getPublicUrl(path);
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    } on StorageException catch (e, st) {
      debugPrint('[StorageService.uploadRealmojiSelfie] storage error: ${e.statusCode} ${e.message}\n$st');
      return null;
    } catch (e, st) {
      debugPrint('[StorageService.uploadRealmojiSelfie] failed: $e\n$st');
      return null;
    }
  }

  /// Deletes a saved RealMoji selfie's storage object — called on retake,
  /// ahead of re-capture, per the explicit "delete then re-run capture"
  /// requirement (rather than relying on uploadRealmojiSelfie's own
  /// upsert:true to silently overwrite it). Best-effort: a failed delete
  /// here just leaves an orphaned object that the next upload to the same
  /// deterministic path will overwrite anyway.
  static Future<void> deleteRealmojiSelfie({
    required String userId,
    required String feedScope,
    required String emojiType,
  }) async {
    try {
      await supabase.storage.from(_reactionPhotosBucket).remove([
        'realmoji/$userId/$feedScope/$emojiType.jpg',
      ]);
    } catch (_) {
      // Best-effort, see doc above.
    }
  }

  // ---------------------------------------------------------------------------
  // Group icon upload
  // ---------------------------------------------------------------------------

  /// Uploads a group's icon. Deterministic path (one icon per group,
  /// overwritten on change) — same reasoning as uploadAvatar. Returns the
  /// public URL, or null on failure.
  ///
  /// Cache-busted with a `?v=` timestamp — same fix [uploadGroupBanner]
  /// already has and this was missing. Without it, re-uploading a group's
  /// icon returns the EXACT SAME url string every time (`upsert: true`
  /// overwrites the file at the same path), so a device that already
  /// cached that url (CachedNetworkImage, keyed on the url) never refetches
  /// and keeps showing the old photo — verified live: the storage object's
  /// `updated_at` had moved (the re-upload genuinely happened, the file
  /// itself was fine and publicly fetchable), but `groups.icon_url` was an
  /// unchanged string, so nothing downstream had any signal to invalidate
  /// its cache. Reported as "unable to upload the group dp... it still
  /// appears as [the initial]".
  static Future<String?> uploadGroupIcon({
    required File file,
    required String groupId,
  }) async {
    try {
      final path = 'icons/$groupId.jpg';
      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_groupIconsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final url = supabase.storage.from(_groupIconsBucket).getPublicUrl(path);
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Uploads a group's banner/cover photo. Same bucket as [uploadGroupIcon]
  /// (a distinct `banners/` prefix keeps it from colliding with the icon
  /// path) — there's no dedicated cover-photo bucket, and group-icons is
  /// already public and group-scoped. Cache-busted the same way as
  /// [uploadUserBanner], for the same upsert-keeps-the-path reason.
  /// A Duo's shared banner — public, like group banners, under duo-banners/.
  static Future<String?> uploadDuoBanner({
    required File file,
    required String albumId,
  }) async {
    try {
      final path = 'duo-banners/$albumId.jpg';
      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_groupIconsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      final url = supabase.storage.from(_groupIconsBucket).getPublicUrl(path);
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadGroupBanner({
    required File file,
    required String groupId,
  }) async {
    try {
      final path = 'banners/$groupId.jpg';
      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_groupIconsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final url = supabase.storage.from(_groupIconsBucket).getPublicUrl(path);
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
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
      await supabase.storage
          .from(_groupPhotosBucket)
          .uploadBinary(
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

  /// Uploads one photo for a group CHAT message (group_chat_service.dart).
  /// Same bucket and mechanics as [uploadGroupPhoto], under a `chat/`
  /// segment so chat files stay apart from the group's album. Returns the
  /// public URL, or null on failure.
  static Future<String?> uploadGroupChatPhoto({
    required File file,
    required String groupId,
    required String userId,
    int index = 0,
  }) async {
    try {
      final path =
          '$groupId/chat/$userId/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_groupPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      return supabase.storage.from(_groupPhotosBucket).getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  /// Uploads a Dip photo. Same bucket/upload mechanics as [uploadGroupPhoto]
  /// (this app has no separate "ephemeral content" bucket, and `dips` rows
  /// are already RLS-gated to group members same as `group_posts`) — a
  /// `dips/` path prefix keeps the object namespace separate from regular
  /// group posts rather than sharing their exact path shape.
  static Future<String?> uploadDipPhoto({
    required File file,
    required String groupId,
    required String userId,
  }) async {
    try {
      final path =
          'dips/$groupId/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_groupPhotosBucket)
          .uploadBinary(
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

  /// Uploads a photo to a Duo. Returns the bare object path (not a
  /// public URL — see TICKET 5 in TODO_TICKETS.md: `us-album-photos` is a
  /// private bucket, so the only way to read it back is [signedUrlFor]/
  /// [signedDuoPhotoUrl], which expect exactly this shape). Path is
  /// `albumId/uuid.jpg` — a random, non-guessable object name (NOT
  /// `albumId/userId/timestamp.jpg`, this bucket's own convention otherwise),
  /// kept as defense in depth even though the bucket's own RLS is what
  /// actually enforces `us_album_photos.visibility`.
  static Future<String?> uploadDuoPhoto({
    required File file,
    required String albumId,
  }) async {
    try {
      final path = '$albumId/${const Uuid().v4()}.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_usAlbumPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      return path;
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Uploads one image for a community_posts row. Path is
  /// `communityId/postId/uuid.jpg` — deliberately NO userId anywhere in it,
  /// unlike [uploadPostImage]'s `{anonymous|everyone}/$userId/...` — a
  /// community post can be anonymous (`community_posts.is_anonymous`), and
  /// this bucket is public like every other one in this app, so a path
  /// segment naming the author would leak identity by URL alone even though
  /// the row itself is membership/block-gated. `postId` is generated
  /// client-side before the row is inserted (see CommunityFeedService) so
  /// every photo for a post shares one prefix.
  static Future<String?> uploadCommunityPhoto({
    required File file,
    required String communityId,
    required String postId,
  }) async {
    try {
      final path = '$communityId/$postId/${const Uuid().v4()}.jpg';

      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_communityPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      return supabase.storage.from(_communityPhotosBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Uploads one PDF for a community_posts row. Same identity-free path
  /// convention as [uploadCommunityPhoto]. Callers must reject files over
  /// the 10 MB product limit BEFORE calling this — it does not re-check
  /// size, since by the time bytes are in memory here the expensive part
  /// (reading a possibly-huge file) has already happened.
  static Future<String?> uploadCommunityDoc({
    required File file,
    required String communityId,
    required String postId,
    required String fileName,
  }) async {
    try {
      final safeName = fileName.replaceAll(RegExp(r'[^\w\-. ]'), '_');
      final path = '$communityId/$postId/${const Uuid().v4()}_$safeName';

      final bytes = await file.readAsBytes();
      await supabase.storage
          .from(_communityDocsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );

      return supabase.storage.from(_communityDocsBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Ping reply photo upload
  // ---------------------------------------------------------------------------

  /// Uploads a photo reply to a ping. Path is `pingId/uuid.jpg` — random,
  /// not deterministic-per-user, since PingService.reply() has no cap on
  /// replies-per-ping the way a face reaction has one-per-(post,user).
  /// Returns the public URL, or null on failure.
  static Future<String?> uploadPingPhoto({
    required File file,
    required String pingId,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      // Extension AND content type both come from the actual bytes — see
      // _sniffImageType. Hardcoding jpeg here is what broke ping reply
      // photos on a PNG capture.
      final (ext, mime) = _sniffImageType(bytes);
      final path = '$pingId/${const Uuid().v4()}.$ext';

      await supabase.storage
          .from(_pingPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mime,
              upsert: false,
            ),
          );

      return supabase.storage.from(_pingPhotosBucket).getPublicUrl(path);
    } on StorageException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Uploads the front-camera half of a dual ping-reply capture — the
  /// selfie shown in the small top-left inset on the reply photo. Same
  /// bucket and path shape as [uploadPingPhoto], suffixed `-selfie` so the
  /// two objects for one capture don't collide. Only ever called for a
  /// CAMERA reply (PingCameraScreen's automatic back-then-front sequence,
  /// see ping_reveal_screen.dart) — an album pick has no second frame, so
  /// callers simply don't call this for one, and `ping_replies.selfie_url`
  /// stays null.
  static Future<String?> uploadPingSelfie({
    required File file,
    required String pingId,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      // Same sniff as uploadPingPhoto — the selfie half comes off the same
      // camera and had the same hardcoded-jpeg bug.
      final (ext, mime) = _sniffImageType(bytes);
      final path = '$pingId/${const Uuid().v4()}-selfie.$ext';

      await supabase.storage
          .from(_pingPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mime,
              upsert: false,
            ),
          );

      return supabase.storage.from(_pingPhotosBucket).getPublicUrl(path);
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

  // ---------------------------------------------------------------------
  // TICKET 5 — signed reads for the private buckets
  // ---------------------------------------------------------------------

  /// Buckets that are (or are being made) private, and therefore cannot be
  /// read through getPublicUrl. See
  /// supabase/migrations/20260921000000_ticket5_private_buckets_phase_ab.sql.
  ///
  /// `profiles` and `group-icons` are deliberately NOT here: avatars are
  /// shown broadly by design, so making them private buys nothing and
  /// costs a signing round-trip on every render.
  static const privateBuckets = <String>{
    _usAlbumPhotosBucket,
    _pingPhotosBucket,
  };

  /// How long a signed image URL stays valid. Long enough to survive a
  /// scroll-back or a slow connection, short enough that a leaked URL
  /// stops working quickly — the whole point of the ticket.
  static const _signedUrlTtl = Duration(hours: 1);

  static final Map<String, ({String url, DateTime expires})> _signedCache = {};

  /// Resolves a stored value into something an <img> can actually load.
  ///
  /// SAFE TO SHIP BEFORE THE MIGRATION RUNS. [stored] may be either:
  ///   * a bare object path (`<uuid>.jpg`) — post-migration; gets signed, or
  ///   * a full absolute URL (`https://…/object/public/…`) — pre-migration;
  ///     returned unchanged.
  /// That dual handling is what lets the client deploy first and the SQL
  /// land second without a window where images are broken (see the
  /// migration's own ORDER OF OPERATIONS note).
  ///
  /// Returns null only when signing genuinely fails — which, thanks to the
  /// storage SELECT policies, is also what a caller who is not allowed to
  /// see the photo gets. Callers should render their existing placeholder
  /// rather than an error: "you can't see this" and "the network hiccuped"
  /// are intentionally indistinguishable here.
  static Future<String?> signedUrlFor(String bucket, String? stored) async {
    if (stored == null || stored.isEmpty) return null;
    // Pre-migration rows, and any bucket we left public, pass straight
    // through — nothing to sign.
    if (stored.startsWith('http://') || stored.startsWith('https://')) {
      return stored;
    }
    if (!privateBuckets.contains(bucket)) {
      return supabase.storage.from(bucket).getPublicUrl(stored);
    }

    final key = '$bucket/$stored';
    final hit = _signedCache[key];
    // Re-sign a minute early so a URL can't expire mid-render.
    if (hit != null &&
        hit.expires.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return hit.url;
    }

    try {
      final url = await supabase.storage
          .from(bucket)
          .createSignedUrl(stored, _signedUrlTtl.inSeconds);
      _signedCache[key] = (
        url: url,
        expires: DateTime.now().add(_signedUrlTtl),
      );
      return url;
    } catch (_) {
      // Refused (not allowed to see it) or offline. Caller shows its
      // placeholder; see this method's own doc on why these are one case.
      return null;
    }
  }

  static Future<String?> signedDuoPhotoUrl(String? stored) =>
      signedUrlFor(_usAlbumPhotosBucket, stored);

  static Future<String?> signedPingPhotoUrl(String? stored) =>
      signedUrlFor(_pingPhotosBucket, stored);

  /// Drops every cached signed URL. Must be called on sign-out — a signed
  /// URL outlives the session that minted it, so leaving these in memory
  /// would let the next account on the device keep loading the previous
  /// account's private photos until the TTL ran out.
  static void clearSignedUrlCache() => _signedCache.clear();
}
