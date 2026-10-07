import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/postgrest_search.dart';
import 'block_service.dart';
import 'current_user_service.dart';

// ---------------------------------------------------------------------------
// PeopleService — finding people. There is no relationship state here any
// more: friend requests were removed (20260926000000_circles_replace_
// friendships.sql). Who someone is TO YOU is now which of your circles
// you've put them in — see CircleService.
//
// Every list returns the same user-row shape (id, name, anon_name, username,
// profile_photo_url) so pickers can take any of them interchangeably.
//
// community_members.user_id is an `auth.uid()` (= profiles.id), NOT a
// `users.id` — the keyspace trap documented in community_service.dart — so
// every join back to `users` here is on auth_id.
// ---------------------------------------------------------------------------

class PeopleService {
  PeopleService._();
  static final instance = PeopleService._();

  final _client = Supabase.instance.client;

  static const _cols = 'id, name, anon_name, anon_name_2, active_anon_slot, '
      'username, profile_photo_url, deleted_at';

  /// ilike over name/anon_name/username, excluding the caller, deleted
  /// accounts and anyone blocked. No RESTRICTIVE policy filters blocks out
  /// of `users` itself (see 20260903000000_blocks_formalize_and_account_
  /// soft_delete.sql), so that filter is client-side.
  Future<List<Map<String, dynamic>>> searchPeople(String query) async {
    final q = sanitizeSearchTerm(query);
    if (q == null) return [];
    final myId = await CurrentUserService.instance.resolveId();
    final blockedIds = await BlockService.instance.blockedUserIds();

    // .limit runs before the self/blocked filter below, so fetch a bit
    // wider than the eventual result cap to keep it from starving.
    final rows = await _client
        .from('users')
        .select(_cols)
        .or('name.ilike.%$q%,anon_name.ilike.%$q%,username.ilike.%$q%')
        .limit(50);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where((u) => u['id'] != myId && u['deleted_at'] == null && !blockedIds.contains(u['id']))
        .toList();
  }

  /// Everyone in the communities you've joined (or in [communityIds] when
  /// given — onboarding passes the ones just picked). This is also exactly
  /// the pool circle_member_is_eligible() lets you add to a circle, so it's
  /// the natural list for every circle picker. Alphabetical: browsed, not
  /// ranked.
  Future<List<Map<String, dynamic>>> communityMembers({
    List<String>? communityIds,
    int limit = 200,
  }) async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final myAuthId = _client.auth.currentUser?.id;
      if (myAuthId == null) return const [];

      var ids = communityIds;
      if (ids == null) {
        final mine = await _client
            .from('community_members')
            .select('community_id')
            .eq('user_id', myAuthId);
        ids = (mine as List)
            .map((r) => (r as Map)['community_id'] as String)
            .toSet()
            .toList();
      }
      if (ids.isEmpty) return const [];

      final memberRows = await _client
          .from('community_members')
          .select('user_id')
          .inFilter('community_id', ids)
          .limit(400);
      final authIds = (memberRows as List)
          .map((r) => (r as Map)['user_id'] as String)
          .where((id) => id != myAuthId)
          .toSet()
          .toList();
      if (authIds.isEmpty) return const [];

      final rows = await _client
          .from('users')
          .select(_cols)
          .inFilter('auth_id', authIds)
          .limit(limit);

      final blockedIds = await BlockService.instance.blockedUserIds();
      final out = (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .where((u) =>
              u['id'] != myId &&
              u['deleted_at'] == null &&
              !blockedIds.contains(u['id']))
          .toList();
      out.sort((a, b) => ((a['name'] as String?) ?? '')
          .toLowerCase()
          .compareTo(((b['name'] as String?) ?? '').toLowerCase()));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// People to suggest in the Friends feed (suggested_people RPC): share a
  /// community with me, not in ANY of my circles yet, not blocked either
  /// way — most mutual friends first (2026-10-07), then newest accounts, so
  /// people you probably know lead and the rest reads as people arriving.
  /// Rows: user_id, name, username, profile_photo_url, joined_at,
  /// community_name, mutual_count. Empty on failure; suggestions are never
  /// critical.
  Future<List<Map<String, dynamic>>> suggestedPeople({int limit = 60}) async {
    try {
      final rows = await _client.rpc(
        'suggested_people',
        params: {'p_limit': limit},
      );
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Mutual friends ──────────────────────────────────────────────────────
  //
  // "Mutual" = in MY Friends circle and also in THEIR Friends circle.
  // Circles are private (creator-only under RLS), so both of these are
  // SECURITY DEFINER RPCs that only ever return people already in the
  // caller's own Friends circle — see 20261007020000_mutual_friends.sql.
  // Blocks and deleted accounts are dropped server-side.

  /// The friends I share with [otherUserId]. Rows: user_id, name, username,
  /// profile_photo_url. Empty on failure — never worth failing a profile.
  Future<List<Map<String, dynamic>>> mutualFriends(String otherUserId) async {
    try {
      final rows = await _client
          .rpc('mutual_friends', params: {'p_other': otherUserId})
          .timeout(const Duration(seconds: 10));
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// How many friends I share with each of [userIds] — one call for a whole
  /// list (search rows, suggestions). Ids with none are simply absent.
  Future<Map<String, int>> mutualCounts(Iterable<String> userIds) async {
    final ids = userIds.toSet().take(200).toList();
    if (ids.isEmpty) return const {};
    try {
      final rows = await _client
          .rpc('mutual_friend_counts', params: {'p_ids': ids})
          .timeout(const Duration(seconds: 10));
      return {
        for (final r in rows as List)
          (r as Map)['user_id'] as String: (r['mutual_count'] as num).toInt(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// User rows for [ids], same shape as the lists above, order not kept.
  ///
  /// BUG FIX (explicit report, 2026-09-29: "blocking the person he goes
  /// everywhere out... no [ping] name in ping page... no information about
  /// him"): unlike [searchPeople]/[communityMembers] above, this never
  /// filtered blocks — so someone already sitting in a Friends circle (a
  /// manual membership, which blocking doesn't touch) kept showing up by
  /// name, photo and streak in the Ping page's "Ping Someone" strip
  /// ([CircleService.fetchFriendsCircleUsers] calls this) even after being
  /// blocked. Same fix as the other two: drop a blocked id from the result,
  /// on either side of the block.
  Future<List<Map<String, dynamic>>> usersByIds(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const [];
    final blockedIds = await BlockService.instance.blockedUserIds();
    final rows = await _client.from('users').select(_cols).inFilter('id', list);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where((u) => u['deleted_at'] == null && !blockedIds.contains(u['id']))
        .toList();
  }
}
