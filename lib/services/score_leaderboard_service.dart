import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// ScoreLeaderboardService — the app-wide leaderboard for the COMBINED score
// (anon + ping), shown in the Community Board.
//
// Backed by the `score_leaderboard` RPC (20260907050000), which returns an
// anon name, a rank, a score and a level — and deliberately nothing else. No
// user id, no real name, no avatar, so a client holding the full list still
// cannot map a row back to an account. That is why this is an RPC rather
// than a view: a view would have to expose users.id to be joinable, and the
// leaderboard has no use for it.
// ---------------------------------------------------------------------------

class ScoreLeaderboardEntry {
  const ScoreLeaderboardEntry({
    required this.rank,
    required this.anonName,
    required this.totalScore,
    required this.level,
    required this.isMe,
    this.avatarUrl,
  });

  factory ScoreLeaderboardEntry.fromRow(Map<String, dynamic> row) =>
      ScoreLeaderboardEntry(
        rank: (row['rank'] as num?)?.toInt() ?? 0,
        anonName: (row['anon_name'] as String?)?.trim().isNotEmpty == true
            ? (row['anon_name'] as String).trim()
            : 'anonymous',
        totalScore: (row['total_score'] as num?)?.toInt() ?? 0,
        level: (row['level'] as num?)?.toInt() ?? 1,
        isMe: row['is_me'] as bool? ?? false,
        avatarUrl: row['anon_photo_url'] as String?,
      );

  final int rank;

  /// `users.anon_name` — never the real name. This board is public.
  final String anonName;
  final int totalScore;
  final int level;

  /// Whether this row is the caller, so their own row can be highlighted
  /// without the client needing to know any ids.
  final bool isMe;

  /// The anon persona photo (`users.anon_photo_url`) — same field the
  /// community-scoped podium already shows, never the real profile photo.
  /// Null for anyone who hasn't set one; the podium falls back to an
  /// initial in that case.
  final String? avatarUrl;
}

class ScoreLeaderboardService {
  ScoreLeaderboardService._();
  static final instance = ScoreLeaderboardService._();

  /// Fails soft to an empty list — the board is one section of the Streaks
  /// tab, and a failure there should not take the tab down with it.
  ///
  /// [limit] is the size of the TOP block only. The RPC additionally returns
  /// a window of the caller's own neighbours (+/-3 around them) whenever
  /// they rank below that block — see migration
  /// 20260926100000_score_leaderboard_me_window. So a limit of 8 yields up
  /// to 8 + 7 rows, not 8, and the returned list is NOT contiguous: callers
  /// rendering it must detect the rank gap between the top block and the
  /// window rather than assuming rank == index + 1. See
  /// community_streaks_tab.dart's STANDINGS section for that split.
  Future<List<ScoreLeaderboardEntry>> fetch({int limit = 8}) async {
    try {
      final rows = await supabase
          .rpc('score_leaderboard', params: {'p_limit': limit})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          ScoreLeaderboardEntry.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (e, st) {
      debugPrint('[ScoreLeaderboardService.fetch] failed: $e\n$st');
      return const [];
    }
  }
}
