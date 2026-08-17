import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Score event model
// ---------------------------------------------------------------------------

class ScoreEvent {
  const ScoreEvent({
    required this.postId,
    required this.amount,
    required this.fromCommunity,
  });

  final int postId;
  final int amount;
  final String fromCommunity;
}

// ---------------------------------------------------------------------------
// Score service — Supabase Realtime + local demo simulation
//
// Usage:
//   final svc = ScoreService();
//   svc.subscribeRealtime(supabase);
//   svc.startDemo(postIds);
//   svc.stream.listen(...);
//   svc.dispose();  // in widget dispose
// ---------------------------------------------------------------------------

class ScoreService {
  ScoreService() : _rng = Random() {
    _ctrl = StreamController<ScoreEvent>.broadcast();
  }

  final Random _rng;
  late final StreamController<ScoreEvent> _ctrl;
  RealtimeChannel? _channel;
  Timer? _demoTimer;

  Stream<ScoreEvent> get stream => _ctrl.stream;

  // Weighted score picker: 5% chance of +50, otherwise [1,3,5,7,10]
  static const _amounts = [1, 3, 5, 7, 10];
  static const _communities = ['CSE', '3rd Year', 'Photography', 'Campus'];

  int pickAmount() {
    if (_rng.nextDouble() < 0.05) return 50;
    return _amounts[_rng.nextInt(_amounts.length)];
  }

  // ---------------------------------------------------------------------------
  // Supabase Realtime subscription (no-op if table doesn't exist yet)
  // ---------------------------------------------------------------------------

  void subscribeRealtime(SupabaseClient client) {
    try {
      _channel = client
          .channel('score_events')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'score_events',
            callback: (payload) {
              final data = payload.newRecord;
              if (_ctrl.isClosed) return;
              _ctrl.add(ScoreEvent(
                postId: (data['post_id'] as num).toInt(),
                amount: (data['amount'] as num).toInt(),
                fromCommunity: (data['from_community'] as String?) ?? 'Campus',
              ));
            },
          )
          .subscribe();
    } catch (_) {
      // Realtime unavailable — demo mode handles it
    }
  }

  // ---------------------------------------------------------------------------
  // Demo simulation — fires score events locally for testing
  // ---------------------------------------------------------------------------

  void startDemo(List<int> postIds) {
    _demoTimer?.cancel();
    if (postIds.isEmpty) return;
    _scheduleNext(postIds, firstEvent: true);
  }

  void _scheduleNext(List<int> postIds, {bool firstEvent = false}) {
    // First event: 2–4 s. Subsequent: 4–9 s.
    final delayMs = firstEvent
        ? 2000 + _rng.nextInt(2000)
        : 4000 + _rng.nextInt(5000);

    _demoTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_ctrl.isClosed) return;
      _ctrl.add(ScoreEvent(
        postId: postIds[_rng.nextInt(postIds.length)],
        amount: pickAmount(),
        fromCommunity: _communities[_rng.nextInt(_communities.length)],
      ));
      _scheduleNext(postIds);
    });
  }

  void dispose() {
    _demoTimer?.cancel();
    _channel?.unsubscribe();
    if (!_ctrl.isClosed) _ctrl.close();
  }
}
