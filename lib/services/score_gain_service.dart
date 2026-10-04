import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// ScoreGainService — "what did that action just earn me?"
//
// Points are granted by database TRIGGERS (award_ping_sent_score,
// award_ping_reply_score, award_anon_post_score, award_comment_given_score,
// award_reaction_given_score, ...), not by the client. So the app cannot know
// what an action was worth by counting what it did — the numbers live in one
// place on purpose, and every reward popup used to guess "+10" regardless of
// what the rules actually pay.
//
// The pattern is: stamp a mark BEFORE the action, then ask what landed since.
//
//   final mark = ScoreGainService.mark();
//   await doTheThing();
//   final gain = await ScoreGainService.instance.since(mark);
//
// Backed by my_score_gain_since (20260907200000), which is scoped to the
// caller by auth.uid() — there is no parameter for whose score to read.
// ---------------------------------------------------------------------------

/// One action's worth of score.
class ScoreGain {
  const ScoreGain({
    required this.gained,
    required this.reasons,
    required this.totalScore,
    required this.level,
  });

  static const none = ScoreGain(
    gained: 0,
    reasons: [],
    totalScore: 0,
    level: 1,
  );

  /// Points credited since the mark. 0 means the action paid nothing —
  /// render nothing rather than a celebratory "+0".
  final int gained;

  /// Human-readable reasons, in the order they were credited, e.g.
  /// ['Ping sent']. Usually one entry; a single action can credit more than
  /// once (posting also bumps a streak).
  final List<String> reasons;

  final int totalScore;
  final int level;

  bool get isEmpty => gained <= 0;
}

class ScoreGainService {
  ScoreGainService._();
  static final instance = ScoreGainService._();

  /// A timestamp to measure from. UTC because the RPC compares against
  /// `score_events.created_at`, which is stored in UTC — passing a local
  /// time would silently widen or narrow the window by the offset.
  ///
  /// Backdated by [_skewSlack]. The mark is stamped from the DEVICE clock but
  /// filtered against `score_events.created_at`, which the DATABASE stamps —
  /// two different clocks. A phone running even a second ahead of Postgres
  /// puts the mark in the server's future, so the row the action just wrote
  /// fails `created_at >= p_since` and the read comes back empty: the points
  /// are credited, the reward never appears. That is exactly the reported
  /// "I can't see the reward dropdown when I ping someone" — the ping_sent
  /// +25 rows are in the table, the popup just never opened. The slack costs
  /// nothing worse than occasionally folding an action from a few seconds
  /// earlier into the same reward.
  static DateTime mark() =>
      DateTime.now().toUtc().subtract(_skewSlack);

  /// Device-vs-database clock tolerance. Generous enough for ordinary NTP
  /// drift, short enough that a separate earlier action is rarely swept in.
  static const _skewSlack = Duration(seconds: 5);

  /// Fails soft to [ScoreGain.none]: a reward popup that can't load its
  /// number should simply not appear, never block or break the action that
  /// earned it.
  Future<ScoreGain> since(DateTime mark) async {
    try {
      final rows = await supabase
          .rpc(
            'my_score_gain_since',
            params: {'p_since': mark.toIso8601String()},
          )
          .timeout(const Duration(seconds: 6));
      final list = rows as List;
      if (list.isEmpty) return ScoreGain.none;
      final m = Map<String, dynamic>.from(list.first as Map);
      return ScoreGain(
        gained: (m['gained'] as num?)?.toInt() ?? 0,
        reasons: [
          for (final e in (m['events'] as List? ?? const []))
            _label((e as Map)['event_type'] as String? ?? ''),
        ],
        totalScore: (m['total_score'] as num?)?.toInt() ?? 0,
        level: (m['level'] as num?)?.toInt() ?? 1,
      );
    } catch (e, st) {
      debugPrint('[ScoreGainService.since] failed: $e\n$st');
      return ScoreGain.none;
    }
  }

  /// score_events.event_type -> what to show a person. Unknown types fall
  /// back to a generic label rather than leaking a database identifier into
  /// the UI.
  static String _label(String type) => switch (type) {
        'ping_sent' => 'Ping sent',
        'ping_reply' => 'Ping answered',
        'anon_post' => 'Anon post',
        'comment_given' => 'Comment',
        'reaction_given' => 'Reaction',
        'engagement_received' => 'Someone engaged',
        'community_xp' => 'Community XP',
        'daily_open' => 'Daily check-in',
        'moment_post' => 'Moment posted',
        'moment_reply' => 'Moment answered',
        // 'dip_post' is a legacy event type from the old group-Dip feature
        // (hidden app-wide — group_profile_v2_screen.dart), not the main
        // Anon feed's own 'anon_post' above. Renamed alongside it for
        // consistency now that "Dip" -> "Anon" everywhere else.
        'dip_post' => 'Anon posted',
        'group_post' => 'Group post',
        'duo_photo' => 'Duo photo',
        _ => 'Activity',
      };
}
