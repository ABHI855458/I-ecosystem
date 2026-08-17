import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// View event model
// ---------------------------------------------------------------------------

class ViewEvent {
  const ViewEvent({
    required this.postId,
    required this.viewerName,
    this.isMystery = false,
  });

  final int postId;
  final String viewerName;
  final bool isMystery;
}

// ---------------------------------------------------------------------------
// Viewer service — Supabase Realtime + demo simulation
// ---------------------------------------------------------------------------

class ViewerService {
  ViewerService() : _rng = Random() {
    _ctrl = StreamController<ViewEvent>.broadcast();
  }

  final Random _rng;
  late final StreamController<ViewEvent> _ctrl;
  RealtimeChannel? _channel;
  Timer? _demoTimer;

  Stream<ViewEvent> get stream => _ctrl.stream;

  static const _names = [
    'abhishek', 'sarah', 'rohan', 'priya',
    'alex', 'meera', 'kiran', 'ananya',
  ];

  // ---------------------------------------------------------------------------
  // Supabase Realtime
  // ---------------------------------------------------------------------------

  void subscribeRealtime(SupabaseClient client) {
    try {
      _channel = client
          .channel('view_events')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'view_events',
            callback: (payload) {
              final data = payload.newRecord;
              if (_ctrl.isClosed) return;
              _ctrl.add(ViewEvent(
                postId: (data['post_id'] as num).toInt(),
                viewerName: (data['viewer_name'] as String?) ?? 'someone',
                isMystery: (data['is_mystery'] as bool?) ?? false,
              ));
            },
          )
          .subscribe();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Demo simulation — realistic viewer arrivals
  // ---------------------------------------------------------------------------

  void startDemo(List<int> postIds) {
    _demoTimer?.cancel();
    if (postIds.isEmpty) return;
    _schedule(postIds, firstEvent: true);
  }

  void _schedule(List<int> postIds, {bool firstEvent = false}) {
    final delayMs = firstEvent
        ? 2500 + _rng.nextInt(2500)   // 2.5–5 s first
        : 5000 + _rng.nextInt(9000);  // 5–14 s subsequent

    _demoTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_ctrl.isClosed) return;
      final isMystery = _rng.nextDouble() < 0.25;
      _ctrl.add(ViewEvent(
        postId: postIds[_rng.nextInt(postIds.length)],
        viewerName: isMystery
            ? 'mystery'
            : _names[_rng.nextInt(_names.length)],
        isMystery: isMystery,
      ));
      _schedule(postIds);
    });
  }

  void dispose() {
    _demoTimer?.cancel();
    _channel?.unsubscribe();
    if (!_ctrl.isClosed) _ctrl.close();
  }
}
