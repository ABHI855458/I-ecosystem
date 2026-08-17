import 'package:supabase_flutter/supabase_flutter.dart';

import 'current_user_service.dart';

// ---------------------------------------------------------------------------
// PostSubscriptionService — backs the per-post bell (top-left corner control
// on PhotoPostCard/TextPostCard, see post_card_shared.dart's
// PostSubscription mixin + PostBellButton). A user "subscribes" to a post to
// get notified about its future activity (new reactions/comments); presence
// of a row in `post_subscriptions` IS the subscription — there's no
// separate boolean column to drift out of sync with.
//
// Mirrors ReactionPresetService's shape (in-memory cache keyed per post,
// populated on first read, kept in sync by toggle) for the same reason: the
// bell needs to render its correct filled/outline state instantly on every
// card in a feed without an isolated network round-trip per card.
// ---------------------------------------------------------------------------

class PostSubscriptionService {
  PostSubscriptionService._();
  static final instance = PostSubscriptionService._();

  final _sb = Supabase.instance.client;

  final Map<String, bool> _cache = {};

  /// Subscription state already known for [postId] this session, or null if
  /// never fetched.
  bool? cached(String postId) => _cache[postId];

  Future<bool> isSubscribed(String postId) async {
    final cached = _cache[postId];
    if (cached != null) return cached;

    final userId = await CurrentUserService.instance.resolveId();
    final row = await _sb
        .from('post_subscriptions')
        .select('id')
        .eq('post_id', postId)
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));

    final subscribed = row != null;
    _cache[postId] = subscribed;
    return subscribed;
  }

  Future<void> subscribe(String postId) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb.from('post_subscriptions').upsert(
      {'post_id': postId, 'user_id': userId},
      onConflict: 'post_id,user_id',
    );
    _cache[postId] = true;
  }

  Future<void> unsubscribe(String postId) async {
    final userId = await CurrentUserService.instance.resolveId();
    await _sb
        .from('post_subscriptions')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId);
    _cache[postId] = false;
  }

  /// Toggles and returns the new state. Throws on failure — callers must
  /// not swallow this (see PostSubscription mixin's toggleSubscription,
  /// which reverts the optimistic UI update and surfaces a toast on error).
  Future<bool> toggle(String postId) async {
    final subscribed = await isSubscribed(postId);
    if (subscribed) {
      await unsubscribe(postId);
      return false;
    } else {
      await subscribe(postId);
      return true;
    }
  }

  /// Clears the cache — call on sign-out so a subsequent sign-in (as a
  /// different user) doesn't show the previous user's subscription state.
  void reset() => _cache.clear();
}
