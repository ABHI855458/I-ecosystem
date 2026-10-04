import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// PingPromptService — the ping sheet's prompt list, authored in the admin
// dashboard (`ping_sheet_prompts`, migration 20260907070000).
//
// Four scopes, one per sheet. Since 20260927210000 'everyone' and
// 'ping_page' share ONE Friends pool and 'group' has its own, each rotated
// daily server-side (rotating_ping_prompts); 'anonymous' is unchanged:
//   'everyone'  -> Friends feed / profile
//   'anonymous' -> the anon feed's ping sheet
//   'group'     -> the group feed card and group wall
//   'ping_page' -> the Ping page's own composer
//
// The last two used to be folded into 'everyone', so a moderator editing
// the friends list silently rewrote all three. Each is independently
// editable now and falls back to 'everyone' when unset.
//
// The sheet keeps its hardcoded lists as an OFFLINE FALLBACK. An empty table
// or a failed fetch therefore degrades to exactly today's behaviour rather
// than to an empty picker — which matters because this list is the only way
// to send a ping without typing.
//
// Cached per scope for the process: the sheet is opened repeatedly and the
// list changes about as often as a moderator edits it.
// ---------------------------------------------------------------------------

class PingSheetPrompt {
  const PingSheetPrompt({
    required this.text,
    required this.cardColorHex,
    this.kind = 'photo',
  });

  final String text;

  /// 'photo' | 'text' — how the RECIPIENT is expected to reply.
  ///
  /// The library is authored at a deliberate ~50/50 split: all-photo reads
  /// as a chore, all-text reads as DMs, and alternating is what keeps a
  /// ping from feeling like either. Carried through so the reply composer
  /// can open in the right mode instead of always assuming a camera.
  final String kind;

  /// '0xFF1A2B3C' or null — null means "let the client pick from its own
  /// palette", so the dashboard never has to choose a colour.
  final String? cardColorHex;

  int? get cardColorValue {
    final hex = cardColorHex?.trim();
    if (hex == null || hex.isEmpty) return null;
    return int.tryParse(hex.replaceFirst('#', '').replaceFirst('0x', ''), radix: 16);
  }
}

class PingPromptService {
  PingPromptService._();
  static final instance = PingPromptService._();

  /// The NEXT hand per scope, preloaded so a sheet opens instantly. The
  /// server deals from each person's own shuffled deck
  /// (deal_ping_prompts, 20260929050000), so every hand is different; a
  /// hand is used once and the following one is fetched in the background.
  final Map<String, List<PingSheetPrompt>> _cache = {};
  final Set<String> _refilling = {};

  /// Per-post hands are dealt fresh on every open (never reused), so there
  /// is nothing to cache — kept so callers need no special case.
  List<PingSheetPrompt>? cachedForPost(String postId) => null;

  /// Preloads a hand for each scope at app start (see MainShell).
  Future<void> prefetch() async {
    for (final s in const ['ping_page', 'everyone', 'group', 'anonymous']) {
      await _refill(s);
    }
  }

  Future<void> _refill(String scope) async {
    if (_cache.containsKey(scope) || !_refilling.add(scope)) return;
    try {
      final hand = await _dealScope(scope);
      if (hand.isNotEmpty) _cache[scope] = hand;
    } finally {
      _refilling.remove(scope);
    }
  }

  /// Takes the preloaded hand for [scope] (null if none is ready yet) and
  /// starts loading the next one, so the following open is new AND instant.
  List<PingSheetPrompt>? cached(String scope) {
    final hand = _cache.remove(scope);
    unawaited(_refill(scope));
    return hand;
  }

  /// The prompts THIS post should offer, tier-resolved server-side.
  ///
  /// Three tiers, decided by `ping_prompts_for_post` (migration
  /// 20260908080000) rather than here, so the two feeds that need this rule
  /// cannot drift apart:
  ///   1. the prompt-bar question the post answered, if any
  ///   2. the community's set, when a NON-friend reached a community-tagged
  ///      friends post
  ///   3. the generic set for the post's scope
  ///
  /// Friendship beats community: a friend always gets the friends set.
  ///
  /// Falls back to the cached generic [scope] list if the call fails, so the
  /// ping sheet is never empty because of a network blip.
  Future<List<PingSheetPrompt>> fetchForPost({
    required String postId,
    required String scope,
  }) async {
    try {
      final rows = await supabase
          .rpc('ping_prompts_for_post', params: {'p_post_id': postId})
          .timeout(const Duration(seconds: 8));
      final list = [
        for (final r in (rows as List))
          PingSheetPrompt(
            text: (r as Map)['prompt_text'] as String,
            // The resolver returns no colour; the client picks one from
            // its own palette, same as a null card_color from the table.
            cardColorHex: null,
            kind: (r['prompt_kind'] as String?) ?? 'photo',
          ),
      ];
      if (list.isNotEmpty) return list;
    } catch (e, st) {
      debugPrint('[PingPromptService.fetchForPost] $postId failed: $e\n$st');
    }
    return fetch(scope);
  }

  /// A fresh hand for [scope] (used when nothing was preloaded), and the
  /// next one starts loading behind it.
  Future<List<PingSheetPrompt>> fetch(String scope) async {
    final hand = await _dealScope(scope);
    unawaited(_refill(scope));
    return hand;
  }

  Future<List<PingSheetPrompt>> _dealScope(String scope) async {
    try {
      // Through ping_prompts_for_scope, not a direct table read: it deals
      // from the caller's own deck, applies the dashboard's prompt LIMIT,
      // and falls back to the 'everyone' pool for an unauthored scope.
      final rows = await supabase
          .rpc('ping_prompts_for_scope', params: {'p_scope': scope})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          PingSheetPrompt(
            text: ((r as Map)['prompt_text'] as String? ?? '').trim(),
            cardColorHex: r['card_color'] as String?,
            kind: (r['prompt_kind'] as String?) ?? 'photo',
          ),
      ].where((p) => p.text.isNotEmpty).toList();
    } catch (e, st) {
      debugPrint('[PingPromptService.fetch] $scope failed: $e\n$st');
      return const [];
    }
  }

  void clearCache() {
    _cache.clear();
  }
}
