import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

/// One person's photo contribution to a Moment.
///
/// Distinct from [MomentReply] (locked_replies_screen.dart), which is that
/// screen's own view model and also backs the hardcoded demo Moments — this
/// is the row as the server returns it.
class MomentReplyRow {
  const MomentReplyRow({
    required this.id,
    required this.userId,
    required this.name,
    required this.photoUrl,
    this.avatarUrl,
    this.createdAt,
    this.isMe = false,
    this.isAnonymous = false,
  });

  factory MomentReplyRow.fromRow(Map<String, dynamic> m) => MomentReplyRow(
    id: m['reply_id'] as String? ?? '',
    userId: m['user_id'] as String? ?? '',
    name: (m['name'] as String?)?.trim().isNotEmpty == true
        ? (m['name'] as String).trim()
        : 'someone',
    avatarUrl: m['avatar_url'] as String?,
    photoUrl: m['photo_url'] as String? ?? '',
    createdAt: m['created_at'] != null
        ? DateTime.tryParse(m['created_at'] as String)
        : null,
    isMe: m['is_me'] as bool? ?? false,
    isAnonymous: m['is_anonymous'] as bool? ?? false,
  );

  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String photoUrl;
  final DateTime? createdAt;
  final bool isMe;

  /// Contributed as their anon persona. When true [name] is already the
  /// anon name and [avatarUrl]/[userId] are already blanked — the server
  /// does the masking (see 20260907110000_moment_reply_anonymous.sql), so
  /// there is nothing for the UI to hide and nothing it can accidentally
  /// reveal.
  final bool isAnonymous;
}

/// Moments' photo-reply backend — the "Add yours" contribution model.
///
/// A Moment itself is a `posts` row with `post_type = 'moment'` (see
/// PostService and 20260829040000_moment_post_type.sql); this service owns
/// only the replies hanging off it (`moment_replies`, migration
/// 20260910000000). A reply is NEVER a `posts` row — it appears inside its
/// Moment and nowhere else, no feed, no profile grid.
///
/// The reveal rule is server-side, not a client blur: `get_moment_replies`
/// returns nothing until the caller has contributed (the Moment's author is
/// exempt), and `moment_replies_select` only ever exposes the caller's own
/// row, so a direct table query cannot bypass the lock. An EMPTY list from
/// [fetchReplies] therefore means "still locked" — which is exactly
/// LockedRepliesScreen's locked state, so there is no separate permission
/// call to make.
///
/// Singleton, matching DipService/GroupService.
class MomentService {
  MomentService._();
  static final instance = MomentService._();

  /// Uploads [photo] and writes one `moment_replies` row. Upserts on
  /// (moment_post_id, user_id) — re-contributing replaces your photo rather
  /// than stacking a second card, matching the table's own unique index.
  ///
  /// Throws on failure (upload or insert), same contract as
  /// PostService.addPost — the composer's send button catches it and shows
  /// the real error rather than pretending the reply landed.
  /// [asAnon] contributes under the person's anon persona instead of their
  /// name — the same post-as choice the composer offers on a Moment itself.
  /// It is stored on the row and applied server-side when the replies are
  /// read back, never by the client.
  Future<void> addReply({
    required String momentPostId,
    required File photo,
    bool asAnon = false,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    final url = await StorageService.uploadMomentReplyPhoto(
      file: photo,
      momentPostId: momentPostId,
      userId: userId,
    );

    // .select() is mandatory on this project: an RLS refusal comes back as
    // zero rows and NO error, so a bare upsert would let the composer run
    // its reward animation and close for a contribution that was never
    // stored — and the person would find out only when the Moment stayed
    // locked to them.
    final rows = await supabase
        .from('moment_replies')
        .upsert({
          'moment_post_id': momentPostId,
          'user_id': userId,
          'photo_url': url,
          'is_anonymous': asAnon,
        }, onConflict: 'moment_post_id,user_id')
        .select('id');
    if (rows.isEmpty) {
      throw StateError("Couldn't add your photo to this moment.");
    }
  }

  /// Every contribution to [momentPostId], oldest first — or an empty list
  /// when the caller hasn't contributed yet (see the class doc: empty means
  /// locked, not "no replies").
  ///
  /// Fails closed to an empty list, the same contract the feeds use.
  Future<List<MomentReplyRow>> fetchReplies(String momentPostId) async {
    try {
      final rows = await supabase.rpc<dynamic>(
        'get_moment_replies',
        params: {'p_post_id': momentPostId},
      );
      return (rows as List)
          .map((r) => MomentReplyRow.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e, st) {
      debugPrint('[MomentService] fetchReplies failed for $momentPostId: $e\n$st');
      return [];
    }
  }

  /// Whether the caller has contributed to [momentPostId] — the durable
  /// replacement for MomentPrefsService's local flag. Derived from the same
  /// RPC, since a non-empty result IS the unlock.
  Future<bool> hasReplied(String momentPostId) async {
    final replies = await fetchReplies(momentPostId);
    return replies.any((r) => r.isMe);
  }

  /// Contributor counts for several Moments in one round trip — for the feed
  /// cards' "N contributors" label. Batch, so a screenful of Moment cards is
  /// one query rather than one per card. Unlike [fetchReplies] this is NOT
  /// gated on having contributed: a count reveals no photos.
  Future<Map<String, int>> replyCounts(List<String> momentPostIds) async {
    if (momentPostIds.isEmpty) return const {};
    try {
      final rows = await supabase.rpc<dynamic>(
        'get_moment_reply_counts',
        params: {'p_post_ids': momentPostIds},
      );
      return {
        for (final r in rows as List)
          (r as Map)['moment_post_id'] as String: (r['n'] as num).toInt(),
      };
    } catch (e, st) {
      debugPrint('[MomentService] replyCounts failed: $e\n$st');
      return const {};
    }
  }

  /// Post ids of Moments the caller has contributed to, newest contribution
  /// first — backs the profile's "Contributed" Moments tab.
  ///
  /// [anonymous] follows the identity the contribution was made UNDER:
  /// false = contributed as yourself (belongs in the Moments tab), true =
  /// contributed anonymously (belongs in the Anon tab, and must never be
  /// listed under your own name), null = both.
  /// Whether the caller may see [momentPostId]'s photo and replies.
  ///
  /// ONE definition, server-side (moment_is_revealed): the poster always
  /// can, anyone who has replied always can, and once the moment expires
  /// everyone can. The gate therefore only bites for a live moment shown
  /// to someone who is neither — which in practice is the friends feed.
  ///
  /// Fails CLOSED: a network error returns false, so a blip shows the
  /// gate rather than leaking a photo.
  Future<bool> isRevealed(String momentPostId) async {
    try {
      final v = await supabase.rpc<dynamic>(
        'moment_is_revealed',
        params: {'p_post_id': momentPostId},
      );
      return v == true;
    } catch (e) {
      debugPrint('[MomentService] isRevealed failed for $momentPostId: $e');
      return false;
    }
  }

  /// The caller's own replies still listed on their profile, newest first —
  /// straight from moment_replies (moment_replies_select_own), so a reply
  /// stays listed even after its parent Moment is removed. [anonymous]
  /// null = both; true/false = only anon / only named contributions.
  Future<List<Map<String, dynamic>>> myProfileReplies({bool? anonymous}) async {
    final me = await CurrentUserService.instance.resolveId();
    var q = supabase
        .from('moment_replies')
        .select('id, moment_post_id, photo_url, created_at, is_anonymous')
        .eq('user_id', me)
        .eq('hidden_from_profile', false);
    if (anonymous != null) q = q.eq('is_anonymous', anonymous);
    final rows = await q
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 10));
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  }

  /// "Remove from my profile" for one of the caller's own replies. Only
  /// flags THEIR row: the photo still shows inside the Moment, and nothing
  /// about any other Moment or contribution changes. `.select` so an RLS
  /// refusal (zero rows, no error on this project) throws instead of the
  /// UI claiming it worked.
  Future<void> hideFromProfile(String replyId) async {
    final rows = await supabase
        .from('moment_replies')
        .update({'hidden_from_profile': true})
        .eq('id', replyId)
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError("Couldn't remove that from your profile.");
    }
  }

  Future<List<String>> myContributedMomentIds({bool? anonymous}) async {
    try {
      final rows = await supabase.rpc<dynamic>(
        'my_contributed_moment_ids',
        params: {'p_anonymous': anonymous},
      );
      return [
        for (final r in rows as List)
          (r as Map)['moment_post_id'] as String,
      ];
    } catch (e, st) {
      debugPrint('[MomentService] myContributedMomentIds failed: $e\n$st');
      return [];
    }
  }
}
