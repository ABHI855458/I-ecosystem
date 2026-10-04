import 'package:flutter/foundation.dart';
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
    // IDENTITY-REVOCATION LEAK FIX. This used to update only _cache, which
    // is keyed by POST id. _pinnedIdsCache is keyed by USER id and is what
    // PresenceService, the viewer lists and isPersonPinnedCached read to
    // decide whether to surface a real name. Unpinning here therefore left
    // the unpinned person's id sitting in _pinnedIdsCache, so they kept
    // rendering named in presence/seen lists for the rest of the session
    // even though the server had already revoked the pin.
    //
    // Both caches are dropped wholesale rather than surgically patched:
    // a pin change is rare and a full refetch is one RPC, whereas a
    // partial patch is exactly how the two caches drifted apart in the
    // first place.
    invalidate();
    return pinned;
  }

  /// Drops every cached pin fact. Call after ANY pin mutation — anything
  /// that keeps a stale pinned-set is a named-identity leak, not just a
  /// cosmetic staleness bug.
  void invalidate() {
    _cache.clear();
    _pinnedIdsCache = null;
    changes.value++;
  }

  /// Bumps on every pin change (pin, unpin, slot set/clear, sign-out).
  /// Anything already SHOWING a pinned list — a card's seen/"here" dropdown,
  /// the Ping page strip — listens and re-fetches, so an open dropdown
  /// updates the moment pins change instead of only on its next open.
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// Clears the cache — call on sign-out so a subsequent sign-in (as a
  /// different user) doesn't show the previous user's pin state.
  void reset() => invalidate();

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
    final removed = result as bool;
    // Whole-cache drop, not _pinnedIdsCache.remove(): _cache (post_id ->
    // bool) would otherwise still answer "pinned" for every post authored
    // by this person. Same leak as in [toggle].
    if (removed) invalidate();
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Profile-section pin flow — the eye-sheet "Pinned" tab (see
  // features/profile_v2/pinned_section.dart). Distinct from toggle/isPinned
  // above (which pin an anon post's author by post_id); this pins a known
  // user_id directly, requires a shared community (enforced server-side by
  // pin_person()), and is capped at 5 (enforced both there and by a
  // BEFORE INSERT trigger on `pinned_people` as a backstop).
  // ---------------------------------------------------------------------------

  Set<String>? _pinnedIdsCache;

  /// Ids of everyone the current user has pinned, cached for the session.
  /// Used to answer `isPersonPinned` synchronously once warmed and to
  /// sort pinned people first in presence lists (see PresenceService).
  Future<Set<String>> pinnedIds({bool forceRefresh = false}) async {
    if (!forceRefresh && _pinnedIdsCache != null) return _pinnedIdsCache!;
    final rows = await listPinned();
    final ids = rows.map((r) => r['pinned_user_id'] as String).toSet();
    _pinnedIdsCache = ids;
    return ids;
  }

  bool isPersonPinnedCached(String userId) => _pinnedIdsCache?.contains(userId) ?? false;

  /// Pins [userId]. Throws on failure (self-pin, no shared community, at
  /// the 5-pin cap) — callers show the server's message via a toast rather
  /// than guessing which rule was hit. Returns the new pin count.
  Future<int> pinPerson(String userId) async {
    final result = await _sb.rpc('pin_person', params: {'p_pinned_user_id': userId});
    invalidate();
    return result as int;
  }

  Future<int> pinCount() async => (await pinnedIds()).length;

  // ---------------------------------------------------------------------------
  // Slot API — the 5 pin slots and their per-slot 7-day cooldowns.
  //
  // Distinct from pinPerson/unpin above, which pick a slot for you. These
  // address a slot directly, which is what the dashboard needs: a locked
  // slot has to render its own countdown, and an empty-but-never-used slot
  // has to be distinguishable from an empty-because-you-just-cleared-it
  // one (the first fills instantly, the second is locked for 7 days).
  //
  // Never cached. The countdown is time-sensitive and the pinned set is
  // identity-bearing — see [invalidate].
  // ---------------------------------------------------------------------------

  Future<List<PinSlot>> pinSlots() async {
    final rows = await _sb.rpc('my_pin_slots').timeout(const Duration(seconds: 8));
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PinSlot.fromRow)
        .toList();
  }

  /// Pins [userId] into [slot], replacing whoever is there. Throws the
  /// server's message if the slot is still on cooldown — callers surface it
  /// rather than guessing which rule was hit.
  Future<void> setSlot(int slot, String userId) async {
    await _sb.rpc('set_pin_slot', params: {'p_slot': slot, 'p_pinned_user_id': userId});
    invalidate();
  }

  /// Empties [slot]. Starts that slot's 7-day cooldown — clearing counts as
  /// a change, which is what stops unpin-then-repin-someone-else.
  Future<void> clearSlot(int slot) async {
    await _sb.rpc('clear_pin_slot', params: {'p_slot': slot});
    invalidate();
  }
}

/// One of the 5 pin slots, as returned by my_pin_slots().
class PinSlot {
  const PinSlot({
    required this.slot,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.unlocksAt,
    required this.everUsed,
  });

  final int slot;

  /// Who occupies this slot, or null if it is empty.
  final String? userId;
  final String? name;
  final String? avatarUrl;

  /// When this slot may next change, or null if it has never been used.
  final DateTime? unlocksAt;

  /// False only for a genuinely virgin slot — the one case that fills
  /// instantly with no cooldown.
  final bool everUsed;

  bool get isEmpty => userId == null;

  /// Recomputed from the clock on every call rather than trusting the
  /// server's `locked` boolean, so a slot whose countdown expires while
  /// the sheet is open unlocks on the next tick without a refetch.
  bool get isLocked {
    final u = unlocksAt;
    return u != null && u.isAfter(DateTime.now());
  }

  Duration get remaining {
    final u = unlocksAt;
    if (u == null) return Duration.zero;
    final d = u.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// "3d 4h" / "4h 12m" / "9m" — matches fmt_cooldown_remaining() in SQL so
  /// the countdown and any server error message agree.
  String get remainingLabel {
    final d = remaining;
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes < 1 ? 1 : d.inMinutes}m';
  }

  static PinSlot fromRow(Map<String, dynamic> r) {
    DateTime? parse(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toLocal();
    return PinSlot(
      slot: (r['slot'] as num).toInt(),
      userId: r['pinned_user_id'] as String?,
      name: r['name'] as String?,
      avatarUrl: r['profile_photo_url'] as String?,
      unlocksAt: parse(r['unlocks_at']),
      everUsed: r['ever_used'] as bool? ?? false,
    );
  }
}
