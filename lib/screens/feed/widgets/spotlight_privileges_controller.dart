import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/feed_service.dart';
import '../../../services/reaction_service.dart';

/// Owns everything the *current spotlight post* gets that other posts
/// don't: music autoplay (one shared player, not per-card), a live
/// realtime subscription to that post's reactions, and the "hot" (5+
/// reactions/10min) check. Re-evaluated once per spotlight change.
class SpotlightPrivilegesController {
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<bool> hot = ValueNotifier(false);
  final _reactionCtrl = StreamController<ReactionEvent>.broadcast();
  Stream<ReactionEvent> get reactionEvents => _reactionCtrl.stream;

  RealtimeChannel? _channel;
  String? _currentPostId;
  int _baselineCount = 0;
  int _liveCount = 0;

  static const _hotThreshold = 5;

  Future<void> updateSpotlight(FeedItem? item) async {
    if (item?.postId == _currentPostId) return;
    _currentPostId = item?.postId;

    await _player.stop();
    hot.value = false;
    _baselineCount = 0;
    _liveCount = 0;
    unawaited(_channel?.unsubscribe());
    _channel = null;

    if (item == null) return;

    if (item.musicUrl != null) {
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.play(UrlSource(item.musicUrl!));
      } catch (_) {
        // Bad/unreachable URL — feed keeps working silently.
      }
    }

    final targetPostId = item.postId;
    final count = await ReactionService.instance.countRecentReactions(targetPostId);
    if (_currentPostId != targetPostId) return; // spotlight moved on while awaiting
    _baselineCount = count;
    if (_baselineCount >= _hotThreshold) hot.value = true;

    _channel = ReactionService.instance.subscribeToPost(targetPostId, (event) {
      if (_currentPostId != targetPostId) return;
      _liveCount++;
      if (_baselineCount + _liveCount >= _hotThreshold) hot.value = true;
      _reactionCtrl.add(event);
    });
  }

  void dispose() {
    _player.dispose();
    unawaited(_channel?.unsubscribe());
    unawaited(_reactionCtrl.close());
    hot.dispose();
  }
}
