import 'dart:io';

import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

/// v1 Bucket system — community buckets only (bucket_type stays at its
/// 'community' default; 'feed' and 'ping' types are schema-ready but
/// deliberately not built here).
///
/// Unlike MemoryService/WallService, which swallow every failure and return
/// an empty list (collapsing "empty" and "error" into the same UI state),
/// these methods let failures propagate. Buckets/profile screens need to
/// tell "no photos yet" apart from "couldn't load" per the loading/empty/
/// error requirement, and a silently-empty list can't express that.
class BucketService {
  BucketService._();
  static final instance = BucketService._();

  /// Creates a bucket and returns its new id.
  Future<String> createBucket({
    required String title,
    required Duration expiryDuration,
    String? communityId,
  }) async {
    final creatorId = await CurrentUserService.instance.resolveId();
    final expiresAt = DateTime.now().toUtc().add(expiryDuration);

    final row = await supabase
        .from('buckets')
        .insert({
          'creator_id': creatorId,
          'title': title,
          'community_id': communityId,
          'expires_at': expiresAt.toIso8601String(),
        })
        .select('id')
        .single();

    return row['id'] as String;
  }

  /// Fetches a single bucket's metadata. Returns null if it doesn't exist
  /// or isn't visible under RLS (e.g. expired and you never contributed).
  Future<Map<String, dynamic>?> fetchBucket(String bucketId) async {
    final row = await supabase
        .from('buckets')
        .select()
        .eq('id', bucketId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// All photo contributions currently in a bucket, newest first.
  Future<List<Map<String, dynamic>>> fetchContributions(
      String bucketId) async {
    final rows = await supabase
        .from('bucket_contributions')
        .select()
        .eq('bucket_id', bucketId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Uploads [photoFile] and drops it into the bucket as a contribution.
  Future<void> addContribution({
    required String bucketId,
    required File photoFile,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();

    final url = await StorageService.uploadBucketPhoto(
      file: photoFile,
      bucketId: bucketId,
      userId: userId,
    );
    if (url == null) {
      throw StateError('Photo upload failed');
    }

    await supabase.from('bucket_contributions').insert({
      'bucket_id': bucketId,
      'user_id': userId,
      'photo_url': url,
    });
  }

  /// Distinct buckets the current user has contributed to, most-recently-
  /// contributed first — backs the profile's Buckets tab grid.
  Future<List<Map<String, dynamic>>> fetchMyContributedBuckets() async {
    final userId = await CurrentUserService.instance.resolveId();

    final rows = await supabase
        .from('bucket_contributions')
        .select('created_at, buckets(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final seen = <String>{};
    final buckets = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final bucket = (r as Map)['buckets'] as Map?;
      if (bucket == null) continue; // bucket deleted out from under this row
      final id = bucket['id'] as String;
      if (seen.add(id)) buckets.add(Map<String, dynamic>.from(bucket));
    }
    return buckets;
  }
}
