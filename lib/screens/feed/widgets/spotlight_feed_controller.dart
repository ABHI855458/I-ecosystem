import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Drives the "reveal on center" mechanic for the Spotlight Feed:
/// - tracks each visible card's distance from the viewport center as a
///   0..1 focus factor (1 = dead center), fanned out via small per-card
///   ValueNotifiers so only the cards whose focus actually changed rebuild
/// - tracks which post is currently the spotlight (max focus)
/// - on scroll end, gently eases the nearest card to center if the release
///   was slow and it's already close (magnetic settle) — never on a fast
///   flick, which stays completely free
class SpotlightFeedController {
  // <1.0 so the next (and previous) post's edge peeks into view at the
  // top/bottom of the screen — the existing focus-based blur/dim below
  // naturally darkens/blurs that sliver since it's off-center.
  final PageController scrollController = PageController(viewportFraction: 0.92);
  final GlobalKey viewportKey = GlobalKey();
  final ValueNotifier<String?> spotlightPostId = ValueNotifier(null);

  final Map<String, GlobalKey> _cardKeys = {};
  final Map<String, ValueNotifier<double>> _focusNotifiers = {};

  bool _frameScheduled = false;
  double _lastOffset = 0;
  DateTime? _lastSampleTime;
  double _velocity = 0;
  bool _settling = false;

  ValueNotifier<double> focusNotifierFor(String postId) =>
      _focusNotifiers.putIfAbsent(postId, () => ValueNotifier(0));

  void registerCard(String postId, GlobalKey key) {
    _cardKeys[postId] = key;
  }

  void unregisterCard(String postId) {
    _cardKeys.remove(postId);
    _focusNotifiers.remove(postId)?.dispose();
  }

  void onScroll() {
    _sampleVelocity();
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      _recompute();
    });
  }

  void _sampleVelocity() {
    if (!scrollController.hasClients) return;
    final now = DateTime.now();
    final offset = scrollController.offset;
    final last = _lastSampleTime;
    if (last != null) {
      final dtSeconds = now.difference(last).inMicroseconds / 1e6;
      if (dtSeconds > 0) {
        _velocity = (offset - _lastOffset) / dtSeconds;
      }
    }
    _lastOffset = offset;
    _lastSampleTime = now;
  }

  /// GlobalKey.currentContext can point at a deactivated (mid-unmount)
  /// element during ListView recycling — findRenderObject() throws in that
  /// window rather than returning null, so this must swallow that case.
  static RenderBox? _safeBox(GlobalKey key) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return null;
    try {
      final box = context.findRenderObject();
      return (box is RenderBox && box.attached) ? box : null;
    } catch (_) {
      return null;
    }
  }

  void _recompute() {
    final viewportBox = _safeBox(viewportKey);
    if (viewportBox == null) return;
    final viewportHeight = viewportBox.size.height;
    final viewportCenter = viewportBox.localToGlobal(Offset.zero).dy + viewportHeight / 2;
    final halfWindow = viewportHeight * 0.55;
    final cullDistance = viewportHeight * 1.5;

    String? bestId;
    double bestFocus = -1;

    for (final entry in _cardKeys.entries) {
      final box = _safeBox(entry.value);
      if (box == null) continue;
      final cardCenter = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
      final distance = (cardCenter - viewportCenter).abs();

      final focus = distance > cullDistance ? 0.0 : 1 - (distance / halfWindow).clamp(0.0, 1.0);
      final notifier = _focusNotifiers.putIfAbsent(entry.key, () => ValueNotifier(0));
      if (notifier.value != focus) notifier.value = focus;
      if (focus > bestFocus) {
        bestFocus = focus;
        bestId = entry.key;
      }
    }

    if (spotlightPostId.value != bestId) spotlightPostId.value = bestId;
  }

  /// Gentle ease-to-center on a slow release near a post; does nothing on a
  /// fast flick or when nothing is close enough to "catch".
  void onScrollEnd() {
    if (_velocity.abs() > 200) return;
    final id = spotlightPostId.value;
    if (id == null || !scrollController.hasClients) return;

    final cardKey = _cardKeys[id];
    if (cardKey == null) return;
    final viewportBox = _safeBox(viewportKey);
    final cardBox = _safeBox(cardKey);
    if (viewportBox == null || cardBox == null) return;

    final viewportCenter = viewportBox.localToGlobal(Offset.zero).dy + viewportBox.size.height / 2;
    final cardCenter = cardBox.localToGlobal(Offset.zero).dy + cardBox.size.height / 2;
    final delta = cardCenter - viewportCenter;
    if (delta.abs() < 2 || delta.abs() > 120) return;

    final position = scrollController.position;
    final target = (scrollController.offset + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    // animateTo() must not be called synchronously from inside a
    // ScrollEndNotification handler: starting the new (animated) scroll
    // activity ends the current one, which re-dispatches ScrollEndNotification
    // into this same handler before animateTo() even returns — infinite
    // synchronous recursion / stack overflow. Deferring to a microtask breaks
    // the chain.
    if (_settling) return;
    _settling = true;
    scheduleMicrotask(() {
      if (!scrollController.hasClients) {
        _settling = false;
        return;
      }
      scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _settling = false);
    });
  }

  void dispose() {
    scrollController.dispose();
    for (final n in _focusNotifiers.values) {
      n.dispose();
    }
    spotlightPostId.dispose();
  }
}
