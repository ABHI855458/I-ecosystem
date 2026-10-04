import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// BlockService — thin wrapper over the `blocks` table (see
// supabase/migrations/20260903000000_blocks_formalize_and_account_soft_delete.sql
// for the schema/RLS/enforcement this relies on).
//
// KEY-SPACE: unlike every other table in this app, `blocks` is keyed by raw
// auth UIDs (blocker_id/blocked_id -> profiles(id), i.e. auth.uid()), NOT
// `users.id`. Every method here takes/returns a `users.id` at its public
// boundary (matching the rest of the app — TheirProfileScreen, search
// results, etc. all carry users.id) and does the auth-UID translation
// internally. Never write a users.id straight into `blocks` — that's the
// exact bug the previous, unreachable settings_screen.dart implementation
// had (confirmed empty/never-worked via the live blocks row count).
// ---------------------------------------------------------------------------

class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.authId,
    required this.name,
    required this.photoUrl,
  });

  final String userId;
  final String authId;
  final String name;
  final String? photoUrl;
}

class BlockService {
  BlockService._();
  static final instance = BlockService._();

  final _client = Supabase.instance.client;

  String get _myAuthId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('BlockService called with no signed-in user');
    }
    return id;
  }

  Future<String> _authIdFor(String userId) async {
    final row = await _client
        .from('users')
        .select('auth_id')
        .eq('id', userId)
        .single();
    return row['auth_id'] as String;
  }

  /// Blocks the given `users.id`. Mutual per `is_blocked_user()` — the
  /// content-filtering RLS hides both people's named content from each
  /// other regardless of who blocked whom.
  Future<void> block(String userId) async {
    _invalidateBlocked();
    try {
      final targetAuthId = await _authIdFor(userId);
      await _client.from('blocks').insert({
        'blocker_id': _myAuthId,
        'blocked_id': targetAuthId,
      });
    } catch (e, st) {
      debugPrint('[BlockService.block] failed: $e\n$st');
      rethrow;
    }
  }

  /// Blocks whoever wrote community post [communityPostId], named or
  /// anonymous (block_community_post_author). For an anonymous post the
  /// block is stored where the app can't read the author back.
  Future<void> blockCommunityPostAuthor(String communityPostId) async {
    _invalidateBlocked();
    await _client.rpc('block_community_post_author', params: {'p_post': communityPostId});
  }

  /// Blocks made from anonymous posts — ids and dates only, never who.
  Future<List<({String id, DateTime createdAt})>> fetchAnonBlocks() async {
    final rows = await _client.rpc('my_anon_blocks') as List;
    return [
      for (final r in rows)
        (
          id: (r as Map)['id'] as String,
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }

  Future<void> unblockAnon(String anonBlockId) async {
    _invalidateBlocked();
    await _client.rpc('unblock_anon', params: {'p_id': anonBlockId});
  }

  /// Unblocks by the target's `auth_id` (as returned in [BlockedUser] —
  /// avoids a second users lookup on unblock).
  Future<void> unblock(String targetAuthId) async {
    _invalidateBlocked();
    try {
      await _client
          .from('blocks')
          .delete()
          .eq('blocker_id', _myAuthId)
          .eq('blocked_id', targetAuthId);
    } catch (e, st) {
      debugPrint('[BlockService.unblock] failed: $e\n$st');
      rethrow;
    }
  }

  /// Everyone the current user has blocked, with display info.
  Future<List<BlockedUser>> fetchBlocked() async {
    final blockRows = await _client
        .from('blocks')
        .select('blocked_id, created_at')
        .eq('blocker_id', _myAuthId)
        .order('created_at', ascending: false) as List;
    if (blockRows.isEmpty) return const [];

    final authIds = blockRows.map((r) => r['blocked_id'] as String).toList();
    final users = await _client
        .from('users')
        .select('id, auth_id, name, profile_photo_url')
        .inFilter('auth_id', authIds) as List;

    return users
        .map((u) => BlockedUser(
              userId: u['id'] as String,
              authId: u['auth_id'] as String,
              name: (u['name'] as String?) ?? 'Unknown user',
              photoUrl: u['profile_photo_url'] as String?,
            ))
        .toList();
  }

  /// Whether the current user and [otherUserId] have any block between them,
  /// in EITHER direction — via the same `is_blocked_user()` the server's own
  /// RLS relies on everywhere else, not a plain client select on `blocks`.
  /// `blk_read`'s RLS only exposes rows where the CALLER is the blocker
  /// (`blocker_id = auth.uid()`) — a row where someone else blocked YOU is
  /// invisible to a plain `.from('blocks').select()` no matter how the
  /// query is filtered, since RLS narrows the result regardless of the
  /// client's own WHERE. `is_blocked_user` is SECURITY DEFINER precisely to
  /// see both directions; this is the one correct way to ask "would sending
  /// to this person be blocked" from the client.
  ///
  /// Fails OPEN (returns false on error) — this is a fast-fail UX nicety
  /// only. The server's own RESTRICTIVE policies (pings/ping_replies/
  /// posts/etc.) are the real enforcement regardless of what this returns.
  Future<bool> isBlockedWith(String otherUserId) async {
    try {
      final result = await _client.rpc<dynamic>(
        'is_blocked_user',
        params: {'viewer_auth': _myAuthId, 'target_user_id': otherUserId},
      );
      return result == true;
    } catch (e) {
      debugPrint('[BlockService.isBlockedWith] failed: $e');
      return false;
    }
  }

  /// The `users.id` set of everyone the current user has blocked (either
  /// direction — is_blocked_user()/is_blocked() are both mutual, so search
  /// results hide symmetrically too) — for client-side filtering of search
  /// results (friend search, group member search), where a RESTRICTIVE
  /// policy on `users` isn't an option (it would also hide blocked users
  /// from the Blocked Users list itself).
  /// Short-lived cache: nearly every people list asks for this first, and
  /// each uncached call is two round trips. Cleared on block/unblock.
  Future<Set<String>>? _blockedCache;
  DateTime? _blockedAt;

  void _invalidateBlocked() {
    _blockedCache = null;
    _blockedAt = null;
  }

  Future<Set<String>> blockedUserIds() {
    final at = _blockedAt;
    if (_blockedCache != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 60)) {
      return _blockedCache!;
    }
    _blockedAt = DateTime.now();
    return _blockedCache = _fetchBlockedUserIds().catchError((Object e) {
      _invalidateBlocked();
      throw e;
    });
  }

  Future<Set<String>> _fetchBlockedUserIds() async {
    final myAuth = _myAuthId;
    final rows = await _client
        .from('blocks')
        .select('blocker_id, blocked_id')
        .or('blocker_id.eq.$myAuth,blocked_id.eq.$myAuth') as List;
    if (rows.isEmpty) return const {};

    final otherAuthIds = rows
        .map((r) => r['blocker_id'] == myAuth
            ? r['blocked_id'] as String
            : r['blocker_id'] as String)
        .toSet();
    final users = await _client
        .from('users')
        .select('id, auth_id')
        .inFilter('auth_id', otherAuthIds.toList()) as List;
    return users.map((u) => u['id'] as String).toSet();
  }
}
