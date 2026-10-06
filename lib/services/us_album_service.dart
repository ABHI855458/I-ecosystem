import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'current_user_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// DuoService — thin wrapper over `us_albums`/`us_album_photos` (see
// supabase/migrations/20260828000000_us_albums.sql for the schema/RLS this
// relies on: pending/accepted lifecycle, mutual-consent delete handshake,
// per-photo private/mutual visibility). See that migration's own doc for
// the full reasoning behind each rule enforced here.
// ---------------------------------------------------------------------------

enum DuoStatus { pending, accepted }

class DuoPhotoRow {
  const DuoPhotoRow({
    required this.id,
    required this.uploadedBy,
    required this.photoUrl,
    required this.isMutual,
    required this.createdAt,
    this.videoUrl,
    this.videoMs,
  });

  final String id;
  final String uploadedBy;

  /// Empty for a VIDEO row (2026-10-06) — [videoUrl] is what plays then.
  final String photoUrl;
  final String? videoUrl;
  final int? videoMs;
  final bool isMutual;
  final DateTime createdAt;

  factory DuoPhotoRow.fromRow(Map<String, dynamic> row) => DuoPhotoRow(
        id: row['id'] as String,
        uploadedBy: row['uploaded_by'] as String,
        photoUrl: (row['photo_url'] as String?) ?? '',
        videoUrl: row['video_url'] as String?,
        videoMs: (row['video_duration_ms'] as num?)?.toInt(),
        isMutual: row['visibility'] == 'mutual',
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

class DuoRow {
  const DuoRow({
    required this.id,
    required this.userA,
    required this.userB,
    required this.createdBy,
    required this.status,
    required this.deleteRequestedBy,
  });

  final String id;
  final String userA;
  final String userB;
  final String createdBy;
  final DuoStatus status;
  final String? deleteRequestedBy;

  String otherParty(String myId) => userA == myId ? userB : userA;

  factory DuoRow.fromRow(Map<String, dynamic> row) => DuoRow(
        id: row['id'] as String,
        userA: row['user_a'] as String,
        userB: row['user_b'] as String,
        createdBy: row['created_by'] as String,
        status: row['status'] == 'accepted' ? DuoStatus.accepted : DuoStatus.pending,
        deleteRequestedBy: row['delete_requested_by'] as String?,
      );
}

/// One row in "My Duos" — the album plus the other party's identity
/// and this album's own private/mutual photo tallies (per-album counts,
/// per the original spec — not a running total across every album).
class MyDuoSummary {
  const MyDuoSummary({
    required this.album,
    required this.otherUserId,
    required this.otherName,
    required this.otherAvatarUrl,
    required this.privateCount,
    required this.mutualCount,
  });

  final DuoRow album;
  final String otherUserId;
  final String otherName;
  final String? otherAvatarUrl;
  final int privateCount;
  final int mutualCount;
}

/// One of [personId]'s Duos, as far as the CURRENT viewer may see it —
/// [partnerId] is whichever side of the pairing isn't [personId] (the
/// viewer themselves, or a third person). [visiblePhotoCount] already
/// reflects RLS: a non-member only ever sees photos published to an
/// audience that admits them.
class PersonDuoRow {
  const PersonDuoRow({
    required this.album,
    required this.partnerId,
    required this.partnerName,
    required this.partnerAvatarUrl,
    required this.visiblePhotoCount,
  });

  final DuoRow album;
  final String partnerId;
  final String partnerName;
  final String? partnerAvatarUrl;
  final int visiblePhotoCount;
}

class DuoService {
  DuoService._();
  static final instance = DuoService._();

  final _client = Supabase.instance.client;

  /// The album between the current user and [otherUserId], if any (any
  /// status — see the migration's own doc on why both parties always see
  /// their own row regardless of pending/accepted).
  Future<DuoRow?> fetchAlbumWith(String otherUserId) async {
    final myId = await CurrentUserService.instance.resolveId();
    final row = await _client
        .from('us_albums')
        .select('id, user_a, user_b, created_by, status, delete_requested_by')
        .or(
          'and(user_a.eq.$myId,user_b.eq.$otherUserId),'
          'and(user_a.eq.$otherUserId,user_b.eq.$myId)',
        )
        .maybeSingle();
    return row == null ? null : DuoRow.fromRow(row);
  }

  /// Every album the current user is a party to (any status), for "My Us
  /// albums" on MyProfileScreen. Two follow-up queries (users, photo
  /// counts) rather than PostgREST embeds, to avoid an ambiguous multi-FK
  /// embed (`us_albums` has TWO FKs to `users`, plus
  /// created_by/delete_requested_by).
  Future<List<MyDuoSummary>> fetchMyAlbums() async {
    final myId = await CurrentUserService.instance.resolveId();
    final albumRows = await _client
        .from('us_albums')
        .select('id, user_a, user_b, created_by, status, delete_requested_by')
        .or('user_a.eq.$myId,user_b.eq.$myId')
        .order('created_at', ascending: false);
    final albums = albumRows.map((r) => DuoRow.fromRow(r)).toList();
    if (albums.isEmpty) return const [];

    final otherIds = albums.map((a) => a.otherParty(myId)).toSet().toList();
    final userRows = await _client
        .from('users')
        .select('id, name, profile_photo_url')
        .inFilter('id', otherIds);
    final userMap = {for (final u in userRows) u['id'] as String: u};

    final photoRows = await _client
        .from('us_album_photos')
        .select('album_id, visibility')
        .inFilter('album_id', albums.map((a) => a.id).toList());
    final counts = <String, (int, int)>{}; // albumId -> (private, mutual)
    for (final r in photoRows) {
      final id = r['album_id'] as String;
      final cur = counts[id] ?? (0, 0);
      counts[id] = r['visibility'] == 'mutual' ? (cur.$1, cur.$2 + 1) : (cur.$1 + 1, cur.$2);
    }

    return albums.map((a) {
      final otherId = a.otherParty(myId);
      final u = userMap[otherId];
      final c = counts[a.id] ?? (0, 0);
      return MyDuoSummary(
        album: a,
        otherUserId: otherId,
        otherName: (u?['name'] as String?) ?? 'someone',
        otherAvatarUrl: u?['profile_photo_url'] as String?,
        privateCount: c.$1,
        mutualCount: c.$2,
      );
    }).toList();
  }

  /// People I have a Duo with that counts toward onboarding's "send Duo
  /// requests to 3 people" step: albums I CREATED (pending or accepted)
  /// plus any accepted album. A pending invite someone else sent me doesn't
  /// count until I accept it.
  Future<Set<String>> fetchDuoPartnerIds() async {
    final myId = await CurrentUserService.instance.resolveId();
    final rows = await _client
        .from('us_albums')
        .select('id, user_a, user_b, created_by, status, delete_requested_by')
        .or('user_a.eq.$myId,user_b.eq.$myId');
    return {
      for (final r in rows)
        if (DuoRow.fromRow(r) case final a
            when a.createdBy == myId || a.status == DuoStatus.accepted)
          a.otherParty(myId),
    };
  }

  /// Onboarding's "Send Duo" button: sends a request to [otherUserId], or
  /// accepts theirs if they already sent me one — either way the pair then
  /// counts toward [fetchDuoPartnerIds].
  Future<void> sendOrAccept(String otherUserId) async {
    final myId = await CurrentUserService.instance.resolveId();
    final album = await ensureAlbum(otherUserId);
    if (album.status == DuoStatus.pending && album.createdBy != myId) {
      await accept(album.id);
    }
  }

  /// Creates a pending album and uploads its first photo in one step — per
  /// the migration's own resolved reading of the spec: the creator can add
  /// a photo before the other side accepts.
  Future<DuoRow> createWithFirstPhoto({
    required String otherUserId,
    required File photo,
  }) async {
    final myId = await CurrentUserService.instance.resolveId();
    final inserted = await _client
        .from('us_albums')
        .insert({
          'user_a': myId,
          'user_b': otherUserId,
          'created_by': myId,
          'status': 'pending',
        })
        .select('id, user_a, user_b, created_by, status, delete_requested_by')
        .single();
    final album = DuoRow.fromRow(inserted);

    final url = await StorageService.uploadDuoPhoto(file: photo, albumId: album.id);
    if (url != null) {
      await _client.from('us_album_photos').insert({
        'album_id': album.id,
        'uploaded_by': myId,
        'photo_url': url,
      });
    }
    return album;
  }

  /// The album with [otherUserId], creating a pending one with no photo yet
  /// if none exists — used by [DuoPostScreen]'s entry point on someone
  /// else's profile, which always needs an albumId before it can open,
  /// whether or not an album already exists.
  Future<DuoRow> ensureAlbum(String otherUserId) async {
    final existing = await fetchAlbumWith(otherUserId);
    if (existing != null) return existing;
    final myId = await CurrentUserService.instance.resolveId();
    final inserted = await _client
        .from('us_albums')
        .insert({
          'user_a': myId,
          'user_b': otherUserId,
          'created_by': myId,
          'status': 'pending',
        })
        .select('id, user_a, user_b, created_by, status, delete_requested_by')
        .single();
    return DuoRow.fromRow(inserted);
  }

  Future<void> accept(String albumId) async {
    await _client.from('us_albums').update({
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', albumId);
  }

  /// Ends a Duo completely, either partner, no second confirmation: the
  /// album, its photos and the feed posts made from them are deleted
  /// (end_duo). The other partner is notified.
  Future<void> endDuo(String albumId) async {
    await _client.rpc('end_duo', params: {'p_album': albumId});
  }

  /// MY side of a Duo post's audience (the partner's side is separate).
  /// Empty circleIds = "my Friends circle".
  Future<({Set<String> circleIds, Set<String> communityIds})> myPostAudience(
    String postId,
  ) async {
    final rows = await _client.rpc(
      'my_duo_post_audience',
      params: {'p_post': postId},
    ) as List;
    final row = rows.isEmpty ? const <String, dynamic>{} : rows.first as Map;
    return (
      circleIds: {for (final c in (row['circle_ids'] as List?) ?? const []) c as String},
      communityIds: {for (final c in (row['community_ids'] as List?) ?? const []) c as String},
    );
  }

  /// Rewrites only MY side of a Duo post's audience; the partner's choice
  /// is untouched (set_my_duo_post_audience).
  Future<void> setMyPostAudience(
    String postId, {
    required Set<String> circleIds,
    required Set<String> communityIds,
  }) async {
    await _client.rpc('set_my_duo_post_audience', params: {
      'p_post': postId,
      'p_circle_ids': circleIds.toList(),
      'p_community_ids': communityIds.toList(),
    });
  }

  /// Declining a still-pending invite — simple delete, no mutual-consent
  /// handshake at this stage (see the migration's own note on why).
  Future<void> declinePending(String albumId) async {
    await _client.from('us_albums').delete().eq('id', albumId);
  }

  /// Step 1 of the mutual-consent delete handshake for an ACCEPTED album —
  /// marks the current user as requesting deletion. Does not delete
  /// anything by itself; see confirmDelete.
  Future<void> requestDelete(String albumId) async {
    final myId = await CurrentUserService.instance.resolveId();
    await _client.from('us_albums').update({
      'delete_requested_by': myId,
      'delete_requested_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', albumId);
  }

  /// Cancels a pending delete request (either party — the requester
  /// changing their mind, or the other party declining it).
  Future<void> cancelDeleteRequest(String albumId) async {
    await _client.from('us_albums').update({
      'delete_requested_by': null,
      'delete_requested_at': null,
    }).eq('id', albumId);
  }

  /// Step 2 — only succeeds if the OTHER party already called
  /// requestDelete (enforced by us_albums_delete_confirmed's RLS, not
  /// re-checked client-side here).
  Future<void> confirmDelete(String albumId) async {
    await _client.from('us_albums').delete().eq('id', albumId);
  }

  /// The accepted Duo between two people, as anyone allowed to see it (RLS:
  /// a member, or a friend of either once it has a shared photo).
  Future<DuoRow?> fetchAlbumBetween(String userA, String userB) async {
    final row = await _client
        .from('us_albums')
        .select('id, user_a, user_b, created_by, status, delete_requested_by')
        .or(
          'and(user_a.eq.$userA,user_b.eq.$userB),'
          'and(user_a.eq.$userB,user_b.eq.$userA)',
        )
        .maybeSingle();
    return row == null ? null : DuoRow.fromRow(row);
  }

  Future<String?> fetchBannerUrl(String albumId) async {
    final row = await _client
        .from('us_albums')
        .select('banner_url')
        .eq('id', albumId)
        .maybeSingle();
    return row?['banner_url'] as String?;
  }

  /// Uploads [file] as the Duo's banner (either member).
  Future<String?> setBanner(String albumId, File file) async {
    final url = await StorageService.uploadDuoBanner(file: file, albumId: albumId);
    if (url == null) return null;
    await _client.rpc('set_duo_banner', params: {'p_album': albumId, 'p_url': url});
    return url;
  }

  /// Either member flips a photo public/private. Returns 'live',
  /// 'awaiting' (my own photo, partner hasn't approved) or 'private'.
  Future<String> toggleVisibility(String photoId, {required bool mutual}) async {
    final res = await _client.rpc(
      'set_duo_photo_visibility',
      params: {'p_photo': photoId, 'p_mutual': mutual},
    );
    return res as String;
  }

  /// photo id -> how many people opened its post.
  Future<Map<String, int>> seenCounts(String albumId) async {
    final rows = await _client.rpc(
      'duo_photo_seen_counts',
      params: {'p_album': albumId},
    ) as List;
    return {
      for (final r in rows)
        (r as Map)['photo_id'] as String: (r['seen'] as num).toInt(),
    };
  }

  /// Every Duo [personId] is a party to, filtered by RLS (us_albums_select)
  /// to what the CURRENT viewer may see at all: their own pairing with
  /// [personId] at any status, or an accepted album with a mutual photo
  /// where the viewer is a friend of either party. [PersonDuoRow.
  /// visiblePhotoCount] additionally tells the caller exactly how many of
  /// that album's photos the viewer can see — a profile screen uses this to
  /// drop a card down to nothing rather than show an album with nothing in
  /// it for this particular viewer (explicit request, 2026-10-01).
  Future<List<PersonDuoRow>> fetchAlbumsInvolving(String personId) async {
    final albumRows = await _client
        .from('us_albums')
        .select('id, user_a, user_b, created_by, status, delete_requested_by')
        .or('user_a.eq.$personId,user_b.eq.$personId')
        .order('created_at', ascending: false);
    final albums = albumRows.map((r) => DuoRow.fromRow(r)).toList();
    if (albums.isEmpty) return const [];

    final partnerIds = albums.map((a) => a.otherParty(personId)).toSet().toList();
    final userRows = await _client
        .from('users')
        .select('id, name, username, profile_photo_url')
        .inFilter('id', partnerIds);
    final userMap = {for (final u in userRows) u['id'] as String: u};

    // RLS on us_album_photos already returns only what THIS viewer may see
    // (every row for a member, only admitted 'mutual' ones otherwise) — a
    // plain count query, no signed URLs needed just to size each card.
    final photoRows = await _client
        .from('us_album_photos')
        .select('album_id')
        .inFilter('album_id', albums.map((a) => a.id).toList());
    final countByAlbum = <String, int>{};
    for (final r in photoRows) {
      final id = r['album_id'] as String;
      countByAlbum[id] = (countByAlbum[id] ?? 0) + 1;
    }

    return [
      for (final a in albums)
        PersonDuoRow(
          album: a,
          partnerId: a.otherParty(personId),
          partnerName: (userMap[a.otherParty(personId)]?['username'] as String?) ??
              (userMap[a.otherParty(personId)]?['name'] as String?) ??
              'someone',
          partnerAvatarUrl:
              userMap[a.otherParty(personId)]?['profile_photo_url'] as String?,
          visiblePhotoCount: countByAlbum[a.id] ?? 0,
        ),
    ];
  }

  /// Newest photo's stored path per album, for highlight covers. One query
  /// for every album; albums with no photos are simply absent.
  Future<Map<String, String>> fetchLatestPhotoPaths(List<String> albumIds) async {
    if (albumIds.isEmpty) return const {};
    final rows = await _client
        .from('us_album_photos')
        .select('album_id, photo_url, created_at')
        .inFilter('album_id', albumIds)
        .order('created_at', ascending: false);
    final out = <String, String>{};
    for (final r in rows) {
      out.putIfAbsent(r['album_id'] as String, () => r['photo_url'] as String);
    }
    return out;
  }

  Future<List<DuoPhotoRow>> fetchPhotos(String albumId) async {
    final rows = await _client
        .from('us_album_photos')
        .select('id, uploaded_by, photo_url, visibility, created_at')
        .eq('album_id', albumId)
        .order('created_at');
    return rows.map((r) => DuoPhotoRow.fromRow(r)).toList();
  }

  Future<String?> addPhoto({required String albumId, required File photo}) async {
    final myId = await CurrentUserService.instance.resolveId();
    final url = await StorageService.uploadDuoPhoto(file: photo, albumId: albumId);
    if (url == null) return null;
    // 'mutual' on upload, not the column's 'private' default.
    //
    // Every photo added to an accepted album stayed private, so it reached
    // neither the friends feed nor the third-party mutual view — reported as
    // "I uploaded in adithi's us album, it's not showing up in the feed".
    // A shared album whose photos default to invisible to everyone but the
    // two of you makes the sharing features unreachable without knowing to
    // hunt for the per-tile badge first.
    //
    // Still per-photo reversible: the privacy badge on each tile flips it
    // back to private, which takes the feed post down again (see
    // sync_us_album_post).
    await _client.from('us_album_photos').insert({
      'album_id': albumId,
      'uploaded_by': myId,
      'photo_url': url,
      'visibility': 'mutual',
    });
    return url;
  }

  /// Posts a photo with a caption and a real audience — the "add photo" flow
  /// backed by [DuoPostScreen], replacing the bare [addPhoto]'s hardcoded
  /// 'mutual'-no-caption-no-audience insert.
  ///
  /// [mutual] false ('Lock') stores the photo as private to the album — no
  /// post. [mutual] true stores MY audience ([circleIds]/[communityIds]) on
  /// the photo and notifies my partner, who approves with theirs
  /// ([approvePhoto]); only then does it go live, to both audiences.
  Future<void> addPhotoWithAudience({
    required String albumId,
    required File photo,
    required String caption,
    required bool mutual,
    required List<String> communityIds,
    required List<String> circleIds,
    bool isVideo = false,
    int? videoMs,
  }) async {
    final myId = await CurrentUserService.instance.resolveId();
    // A Duo VIDEO (2026-10-06) goes to the same bucket and row; photo_url
    // stays null and video_url is what every render site plays.
    final url = isVideo
        ? await StorageService.uploadDuoVideo(
            file: photo,
            albumId: albumId,
            userId: myId,
          )
        : await StorageService.uploadDuoPhoto(file: photo, albumId: albumId);
    if (url == null) return;

    // A mutual photo carries MY side of the audience and waits for my
    // partner to approve with theirs; the server publishes it to the union
    // of both only then (sync_us_album_post, 20260926020000_shared_album_
    // audiences.sql). Empty circles = my Friends circle.
    await _client.from('us_album_photos').insert({
      'album_id': albumId,
      'uploaded_by': myId,
      if (isVideo) 'video_url': url else 'photo_url': url,
      if (isVideo && videoMs != null) 'video_duration_ms': videoMs,
      'visibility': mutual ? 'mutual' : 'private',
      'caption': caption.isEmpty ? null : caption,
      'uploader_circle_ids': circleIds,
      'uploader_community_ids': communityIds,
    });
  }

  /// My partner added a shared photo: pick MY side of its audience and
  /// approve it — that's what puts it live, to both our audiences.
  Future<void> approvePhoto(
    String photoId, {
    required List<String> circleIds,
    required List<String> communityIds,
  }) async {
    await _client.rpc('approve_duo_photo', params: {
      'p_photo': photoId,
      'p_circle_ids': circleIds,
      'p_community_ids': communityIds,
    });
  }

  /// Shared photos in [albumId] my partner added that are still waiting on
  /// my approval.
  Future<List<String>> photosAwaitingMyApproval(String albumId) async {
    final myId = await CurrentUserService.instance.resolveId();
    final rows = await _client
        .from('us_album_photos')
        .select('id')
        .eq('album_id', albumId)
        .eq('visibility', 'mutual')
        .neq('uploaded_by', myId)
        .isFilter('partner_approved_at', null);
    return [for (final r in rows) r['id'] as String];
  }

  /// Toggles one photo's visibility. Flipping to mutual (publishing it to
  /// both people's friends) is RLS-enforced (us_album_photos_update_own) to
  /// the uploader only. Flipping back to private — locking a currently-live
  /// photo down, which takes its post off the feed (see
  /// 20260907160000_us_album_feed_posts.sql / 20260926020000_shared_album_
  /// audiences.sql) — is allowed for EITHER member of the Duo
  /// (us_album_photos_lock_partner, 20260926110000_duo_either_member_lock.
  /// sql): "if either one of the 2 people locks the post, the live post is
  /// deleted and it goes private." Only the narrowing direction is granted
  /// to the non-uploader; a caller passing `mutual: true` for someone
  /// else's photo still 403s.
  Future<void> setPhotoVisibility(String photoId, {required bool mutual}) async {
    await _client
        .from('us_album_photos')
        .update({'visibility': mutual ? 'mutual' : 'private'}).eq('id', photoId);
  }


  /// The `posts` row a mutual album photo was published as, or null when
  /// the photo is private (no post exists) or the caller can't see it.
  ///
  /// A mutual photo is mirrored into `posts` by a trigger (see
  /// 20260907160000_us_album_feed_posts.sql), and THAT is what carries its
  /// reactions, comments and reports — they are all keyed on posts.id. This
  /// is the lookup that lets the album's own photo viewer show them instead
  /// of making people find the same photo in the feed.
  Future<String?> feedPostIdForPhoto(String photoId) async {
    try {
      final row = await _client
          .from('posts')
          .select('id')
          .eq('us_album_photo_id', photoId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Removes a photo. EITHER album member may do this, not just whoever
  /// uploaded it — see 20260907190000_us_album_either_member_delete.sql.
  ///
  /// `.select('id')` so an RLS refusal (zero rows, no error on this
  /// project) throws instead of the UI reporting "Photo removed."
  Future<void> deletePhoto(String photoId) async {
    final rows = await _client
        .from('us_album_photos')
        .delete()
        .eq('id', photoId)
        .select('id');
    if (rows.isEmpty) throw StateError("Couldn't remove that photo.");
  }

  /// The pair's ping streak (days) behind a published Us post — the number
  /// under the blue flame (PV2Icons.blueFlameStreak).
  ///
  /// Takes the POST id, not two user ids, on purpose: `us_post_streak`
  /// gates on can_view_post() server-side, so this can only ever return a
  /// number for a post the caller can already see. The underlying
  /// ping_streak_between(a, b) is not callable from a client at all — it
  /// would let anyone probe the streak between two arbitrary strangers.
  ///
  /// Null when the photo isn't published as a post, the caller can't see
  /// it, or the pair has no live streak.
  Future<int?> pairStreakForPost(String postId) async {
    try {
      final v = await _client
          .rpc('us_post_streak', params: {'p_post_id': postId})
          .timeout(const Duration(seconds: 8));
      final n = (v as num?)?.toInt();
      return (n == null || n <= 0) ? null : n;
    } catch (_) {
      // Badge just doesn't render — never worth failing the viewer over.
      return null;
    }
  }
}
