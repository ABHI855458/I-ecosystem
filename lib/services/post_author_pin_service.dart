import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// PostAuthorPinService — backs the pin control on a named (Friends)
// profile page (see profile_screen.dart's _ProfileHeaderState). Pins that
// profile's owner to the viewer's `pinned_people` list, which unlocks
// identity reveal on notifications for that person (is_pinned_by(),
// schema.sql). Pinning does not apply to anonymous posts — there's no
// identity to pin — so this is never reached from the post card.
//
// Reads/writes go through SECURITY DEFINER RPCs keyed by post_id
// (toggle_pin_post_author / is_post_author_pinned) rather than a raw
// user_id, because there's no direct "pin this user_id" entry point —
// resolving via any post authored by that profile's owner works just as
// well (same author either way) and reuses the same trust boundary
// is_pinned_by() already enforces server-side. `pinned_people` itself has
// RLS enabled with no client policies, by design; these RPCs are the only
// way in.
//
// Mirrors PostSubscriptionService's shape (in-memory cache keyed per post)
// so a profile page renders its pinned/unpinned state instantly without a
// network round-trip on every rebuild.
// ---------------------------------------------------------------------------

class PostAuthorPinService {
  PostAuthorPinService._();
  static final instance = PostAuthorPinService._();

  final _sb = Supabase.instance.client;

  final Map<String, bool> _cache = {};

  /// Pin state already known for [postId] this session, or null if never
  /// fetched.
  bool? cached(String postId) => _cache[postId];

  Future<bool> isPinned(String postId) async {
    final cached = _cache[postId];
    if (cached != null) return cached;

    final result = await _sb
        .rpc('is_post_author_pinned', params: {'p_post_id': postId})
        .timeout(const Duration(seconds: 8));
    final pinned = result as bool;
    _cache[postId] = pinned;
    return pinned;
  }

  /// Toggles and returns the new state. Throws on failure — callers must
  /// not swallow this (see _ProfileHeaderState._togglePin in
  /// profile_screen.dart, which reverts the optimistic UI update and
  /// surfaces a toast on error).
  Future<bool> toggle(String postId) async {
    final result = await _sb.rpc(
      'toggle_pin_post_author',
      params: {'p_post_id': postId},
    );
    final pinned = result as bool;
    _cache[postId] = pinned;
    return pinned;
  }

  /// Clears the cache — call on sign-out so a subsequent sign-in (as a
  /// different user) doesn't show the previous user's pin state.
  void reset() => _cache.clear();

  /// Everyone the current user has pinned — Settings screen's Pinned
  /// People section. Goes through list_pinned_people() (schema.sql), not a
  /// direct `.from('pinned_people')` select — that table has RLS enabled
  /// with no client policies, same reason toggle/isPinned above go through
  /// RPCs instead of raw queries.
  Future<List<Map<String, dynamic>>> listPinned() async {
    final result = await _sb.rpc('list_pinned_people');
    return (result as List).cast<Map<String, dynamic>>();
  }

  /// Unpins by user_id directly (unlike [toggle], which is keyed by
  /// post_id) — the Settings list already has the pinned user's id, no
  /// post context involved. Returns true if a row was actually deleted.
  Future<bool> unpin(String pinnedUserId) async {
    final result = await _sb.rpc(
      'unpin_person',
      params: {'p_pinned_user_id': pinnedUserId},
    );
    return result as bool;
  }
}
