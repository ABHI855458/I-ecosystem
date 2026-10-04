import 'dart:io';

import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

/// Dip: a per-group, member-only photo that expires 24h after posting and
/// is never saved to Memories. Distinct from `GroupService`'s `group_posts`
/// (permanent, shared album) — Dips live in their own `dips` table with a
/// real `expires_at` column (see migration
/// 20260903020000_dips_and_group_streaks.sql), unlike Moments'
/// `posts.post_type = 'moment'`, whose "24h" is only a client-side label
/// with no actual query filter.
///
/// Also the single source for the per-group daily streak (`group_streaks`),
/// separate from the existing Ping streak (`StreakService`, purely
/// client-side/shared_preferences, no DB table). A group's streak is
/// maintained entirely server-side by the `dips_bump_streak` trigger; this
/// class only ever reads it, via the `group_public_profile` SECURITY
/// DEFINER RPC — the same RPC a non-member's limited group view uses, and
/// the only thing group_card_shared.dart's streak display is backed by.
class DipService {
  /// Read timeout, matching every other service in this app.
  ///
  /// This file had NONE. The group profile awaits six of these calls
  /// with no deadline, so one stalled request left the screen on its
  /// spinner forever — no error, and therefore no Retry button either,
  /// since that only renders once _loadError is set.
  static const _kRead = Duration(seconds: 10);

  DipService._();
  static final instance = DipService._();

  // ---------------------------------------------------------------------------
  // Dips
  // ---------------------------------------------------------------------------

  /// Live (non-expired) dips for a group, newest first. RLS
  /// (`dips_select`) already restricts this to members, so no client-side
  /// membership check is needed here — mirrors GroupService.fetchPosts.
  Future<List<Map<String, dynamic>>> fetchDips(String groupId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await supabase
        .from('dips')
        .select('*, users(name, profile_photo_url)')
        .eq('group_id', groupId)
        .gt('expires_at', nowIso)
        .order('created_at', ascending: false)
            .timeout(_kRead);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Uploads [photo] to the same `group-photos` bucket GroupService.addPost
  /// uses, then inserts one `dips` row. The `dips_bump_streak` trigger
  /// handles the caller's `group_streaks` row — nothing else to do here.
  /// [caption] is the optional note typed in the composer's Dip box. The
  /// column is new (migration 20260908210000_dip_caption) — before it, the
  /// composer hid its caption field for this destination entirely because
  /// there was nowhere to put the text. Empty is stored as NULL rather than
  /// '' so "no note" is one value, not two.
  Future<void> addDip({
    required String groupId,
    required File photo,
    String? caption,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    final url = await StorageService.uploadGroupPhoto(
      file: photo,
      groupId: groupId,
      userId: userId,
    );
    if (url == null) {
      throw StateError('Photo upload failed');
    }
    final note = caption?.trim();
    // .select() is not optional on this project: an RLS refusal returns zero
    // rows and NO error, so an insert with no returned row is a silent
    // failure that would leave the composer showing its reward animation
    // for a Dip that was never stored.
    final rows = await supabase
        .from('dips')
        .insert({
          'group_id': groupId,
          'user_id': userId,
          'photo_url': url,
          if (note != null && note.isNotEmpty) 'caption': note,
        })
        .select('id');
    if (rows.isEmpty) {
      throw StateError("Couldn't post that dip.");
    }
  }

  // ---------------------------------------------------------------------------
  // Streaks + non-member access
  // ---------------------------------------------------------------------------

  /// The only data a non-member of a group may see: identity, roster, and
  /// each member's streak — no dips, no posts, by construction (this RPC
  /// is SECURITY DEFINER but never selects from `dips` or `group_posts`).
  /// Returns null if the group doesn't exist. Members may call this too —
  /// it doesn't check membership itself, since it leaks nothing a member
  /// couldn't already see via the real tables.
  Future<Map<String, dynamic>?> publicProfile(String groupId) async {
    final result = await supabase.rpc(
      'group_public_profile',
      params: {'p_group_id': groupId},
    )
        .timeout(_kRead);
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  /// Each member's own GROUP-PING REPLY streak within [groupId], keyed by
  /// `users.id` — the blue per-person counter shown under each person's Dip
  /// in group posts. A member absent from the map has no run going; treat
  /// as 0, same convention as GroupCardData.streaks.
  ///
  /// STREAK SYSTEM v4: this used to report the per-user DIP streak, read
  /// out of group_public_profile's `streak` field. That mechanic is gone —
  /// `group_streaks` and its trigger were removed in migration
  /// 20260914030000_streak_system_v4.sql (Dip posting itself is untouched,
  /// only its streak tracking), and that field now returns 0 for everyone.
  /// The counter this surface shows is BLUE 3: how many consecutive days
  /// this person answered their group's daily ping, maintained server-side
  /// by resolve_group_ping_day and read here through
  /// group_ping_member_streak_map (member-gated inside the RPC).
  ///
  /// Fails closed to an empty map, same as the feed fetches elsewhere
  /// (FeedService) — a streak lookup failure should render a plain avatar
  /// row, never crash the group card.
  Future<Map<String, int>> streaksForGroup(String groupId, List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await supabase
          .rpc<dynamic>(
            'group_ping_member_streak_map',
            params: {'p_group_id': groupId},
          )
          .timeout(_kRead);
      final wanted = userIds.toSet();
      return {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          if (wanted.contains(r['user_id']))
            r['user_id'] as String: (r['streak'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }
}
