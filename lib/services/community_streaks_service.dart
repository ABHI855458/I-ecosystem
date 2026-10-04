import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// CommunityStreaksService — wraps the `community_leaderboard(uuid)` RPC
// (see supabase/migrations/20260904010000_community_streaks.sql) that backs
// the entire STREAKS tab in one round trip, plus a realtime subscription on
// `community_streaks` so rank/streak/rival move live as other members post
// or react.
//
// Reminder for whoever wires this up in the UI: the underlying streak/XP
// only advances from ANONYMOUS posts to this community made through the
// existing camera composer's Anon destination (posts.visibility=
// 'anonymous' AND posts.community_id = this community) — never from
// CommunityFeedService's member noticeboard. That split is intentional,
// confirmed with the product owner, not a bug to "fix" later.
// ---------------------------------------------------------------------------

class CommunityLeaderboardEntry {
  const CommunityLeaderboardEntry({
    required this.rank,
    required this.handle,
    this.initial,
    this.avatarUrl,
    this.streak,
    this.weekXp,
    this.progress,
    this.postCount,
    this.isYou = false,
    this.isRival = false,
    this.isTop = false,
    this.level,
    this.days,
  });

  final int rank;
  final String handle;
  final String? initial;
  final String? avatarUrl;
  final int? streak;
  final int? weekXp;
  final double? progress;
  final int? postCount;
  final bool isYou;
  final bool isRival;
  final bool isTop;
  final int? level;
  final List<double>? days;

  /// [handle] without its leading '@' — the podium/leader rows in the
  /// mockup show a bare name (e.g. "night_owl"), while TOP STREAKS/AROUND
  /// YOU keep the '@' (e.g. "@segfault_"). Both read the same `handle`
  /// field; this getter is for the former.
  String get nameWithoutAt => handle.startsWith('@') ? handle.substring(1) : handle;

  factory CommunityLeaderboardEntry.fromJson(Map<String, dynamic> j) => CommunityLeaderboardEntry(
        rank: j['rank'] as int,
        handle: j['handle'] as String? ?? '@unknown',
        initial: j['initial'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        streak: j['streak'] as int?,
        weekXp: j['week_xp'] as int?,
        progress: (j['progress'] as num?)?.toDouble(),
        postCount: j['post_count'] as int?,
        isYou: j['is_you'] as bool? ?? false,
        isRival: j['is_rival'] as bool? ?? false,
        isTop: j['is_top'] as bool? ?? false,
        level: j['level'] as int?,
        days: (j['days'] as List?)?.map((d) => (d as num).toDouble()).toList(),
      );
}

class CommunityRival {
  const CommunityRival({
    required this.handle,
    required this.rank,
    required this.streak,
    required this.firesBehind,
  });

  final String handle;
  final int rank;
  final int streak;
  final int firesBehind;

  factory CommunityRival.fromJson(Map<String, dynamic> j) => CommunityRival(
        handle: j['handle'] as String? ?? '@unknown',
        rank: j['rank'] as int,
        streak: j['streak'] as int,
        firesBehind: j['fires_behind'] as int,
      );
}

class CommunityMe {
  const CommunityMe({
    required this.rank,
    required this.handle,
    required this.streak,
    required this.longest,
    required this.xp,
    required this.level,
    required this.levelName,
    required this.nextLevelXp,
    required this.nextLevelName,
    required this.weekXp,
    required this.weekRank,
    required this.days,
  });

  final int rank;
  final String handle;
  final int streak;
  final int longest;
  final int xp;
  final int level;
  final String levelName;
  final int nextLevelXp;
  final String nextLevelName;
  final int weekXp;
  final int weekRank;
  final List<double> days;

  double get levelProgress {
    // Both thresholds are monotonic in xp; guard div-by-zero for level 1
    // when xp is already >= nextLevelXp edge case (shouldn't happen, but a
    // NaN progress bar is worse than a clamped one).
    final span = nextLevelXp;
    if (span <= 0) return 0;
    return (xp / nextLevelXp).clamp(0.0, 1.0);
  }

  factory CommunityMe.fromJson(Map<String, dynamic> j) => CommunityMe(
        rank: j['rank'] as int,
        handle: j['handle'] as String? ?? '@unknown',
        streak: j['streak'] as int,
        longest: j['longest'] as int,
        xp: j['xp'] as int,
        level: j['level'] as int,
        levelName: j['level_name'] as String,
        nextLevelXp: j['next_level_xp'] as int,
        nextLevelName: j['next_level_name'] as String,
        weekXp: j['week_xp'] as int,
        weekRank: j['week_rank'] as int,
        days: (j['days'] as List? ?? const []).map((d) => (d as num).toDouble()).toList(),
      );
}

class CommunityLeaderboard {
  const CommunityLeaderboard({
    required this.memberCount,
    required this.me,
    required this.podium,
    required this.leaders,
    required this.topStreaks,
    required this.aroundYou,
    required this.rival,
  });

  final int memberCount;
  final CommunityMe me;
  final List<CommunityLeaderboardEntry> podium;
  final List<CommunityLeaderboardEntry> leaders;
  final List<CommunityLeaderboardEntry> topStreaks;
  final List<CommunityLeaderboardEntry> aroundYou;
  /// Null when the caller is already rank 1 — the nudge card should hide
  /// entirely rather than render a null-derived string.
  final CommunityRival? rival;

  factory CommunityLeaderboard.fromJson(Map<String, dynamic> j) {
    List<CommunityLeaderboardEntry> list(String key) =>
        (j[key] as List? ?? const [])
            .map((e) => CommunityLeaderboardEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
    final rivalJson = j['rival'] as Map?;
    return CommunityLeaderboard(
      memberCount: (j['community'] as Map)['member_count'] as int? ?? 0,
      me: CommunityMe.fromJson(Map<String, dynamic>.from(j['me'] as Map)),
      podium: list('podium'),
      leaders: list('leaders'),
      topStreaks: list('top_streaks'),
      aroundYou: list('around_you'),
      rival: rivalJson == null ? null : CommunityRival.fromJson(Map<String, dynamic>.from(rivalJson)),
    );
  }
}

class CommunityStreaksService {
  CommunityStreaksService._();
  static final instance = CommunityStreaksService._();

  final _sb = Supabase.instance.client;

  /// Throws on failure — unlike most fetches in this app, a broken
  /// leaderboard has no sane empty-state fallback (the whole STREAKS tab
  /// needs `me` to render its header numbers), so the caller must show a
  /// real error + retry rather than silently rendering zeros.
  Future<CommunityLeaderboard> leaderboard(String communityId) async {
    final result = await _sb
        .rpc('community_leaderboard', params: {'p_community': communityId})
        .timeout(const Duration(seconds: 10));
    return CommunityLeaderboard.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Live inserts/updates on `community_streaks` for [communityId] — fires
  /// whenever ANY member's streak/XP row changes (including someone else
  /// posting or reacting), which is what makes rank and the rival nudge
  /// move without a manual refresh. Callers should debounce their refetch
  /// (~600ms) rather than calling [leaderboard] once per event — a burst of
  /// members posting at once would otherwise fire one RPC per row.
  RealtimeChannel subscribe(
    String communityId,
    void Function(PostgresChangePayload) onChange,
  ) {
    void handle(PostgresChangePayload payload) {
      try {
        onChange(payload);
      } catch (e, st) {
        debugPrint('[CommunityStreaksService.subscribe] handler failed: $e\n$st');
      }
    }

    return _sb
        .channel('community_streaks_$communityId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'community_streaks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'community_id',
            value: communityId,
          ),
          callback: handle,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'community_streaks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'community_id',
            value: communityId,
          ),
          callback: handle,
        )
        .subscribe();
  }
}
