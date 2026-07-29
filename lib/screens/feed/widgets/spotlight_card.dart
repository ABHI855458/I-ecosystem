import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/glass.dart';
import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../services/feed_service.dart';
import '../../../services/reaction_service.dart';
import '../../../widgets/emoji_burst.dart';
import '../../../widgets/hot_glow_border.dart';
import '../../../widgets/reaction_picker_popup.dart';
import 'spotlight_feed_controller.dart';
import 'spotlight_privileges_controller.dart';

/// Wraps a pure-content card (MemoryFeedCard/SinglePostCard) with the
/// scroll-driven reveal mechanic, spotlight chrome, and gestures. This is
/// the only place blur/dim/scale/glow/action-row/gestures live — the
/// content widgets stay dumb.
class SpotlightCard extends StatefulWidget {
  const SpotlightCard({
    super.key,
    required this.item,
    required this.controller,
    required this.privileges,
    required this.onTap,
    required this.child,
  });

  final FeedItem item;
  final SpotlightFeedController controller;
  final SpotlightPrivilegesController privileges;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<SpotlightCard> createState() => _SpotlightCardState();
}

class _SpotlightCardState extends State<SpotlightCard> {
  final GlobalKey _cardKey = GlobalKey();
  StreamSubscription<ReactionEvent>? _reactionSub;
  final List<_Floater> _floaters = [];
  final List<_Burst> _bursts = [];
  bool _showPicker = false;

  @override
  void initState() {
    super.initState();
    widget.controller.registerCard(widget.item.postId, _cardKey);
    _reactionSub = widget.privileges.reactionEvents
        .where((e) => e.postId == widget.item.postId)
        .listen(_onLiveReaction);
  }

  @override
  void dispose() {
    widget.controller.unregisterCard(widget.item.postId);
    _reactionSub?.cancel();
    super.dispose();
  }

  void _onLiveReaction(ReactionEvent e) {
    if (!mounted) return;
    final key = UniqueKey();
    setState(() => _floaters.add(_Floater(key, e.emoji)));
  }

  void _removeFloater(Key key) {
    if (!mounted) return;
    setState(() => _floaters.removeWhere((f) => f.key == key));
  }

  void _react(String emoji) => ReactionService.instance.react(widget.item.postId, emoji);

  void _onDoubleTapDown(TapDownDetails d) {
    HapticFeedback.mediumImpact();
    _react('🔥');
    final key = UniqueKey();
    setState(() => _bursts.add(_Burst(key, d.localPosition, '🔥')));
  }

  void _removeBurst(Key key) {
    if (!mounted) return;
    setState(() => _bursts.removeWhere((b) => b.key == key));
  }

  void _togglePicker() {
    HapticFeedback.selectionClick();
    setState(() => _showPicker = !_showPicker);
  }

  void _ping() {
    HapticFeedback.lightImpact();
    showPingPromptSheet(
      context,
      targetName: widget.item.username ?? 'someone',
      pingContext: PingContext.everyone,
      glass: true,
    );
  }

  static double _quantize(double sigma) => (sigma / 2).round() * 2;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.controller.focusNotifierFor(widget.item.postId),
      builder: (context, focus, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: widget.controller.spotlightPostId,
          builder: (context, spotlightId, _) {
            final isSpotlight = spotlightId == widget.item.postId && widget.item.postId.isNotEmpty;
            return RepaintBoundary(
              key: _cardKey,
              child: GestureDetector(
                onTap: widget.onTap,
                onDoubleTapDown: _onDoubleTapDown,
                onLongPress: _togglePicker,
                child: _buildVisual(focus, isSpotlight),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVisual(double focus, bool isSpotlight) {
    final scale = 1.0 + 0.03 * focus;
    final sigma = _quantize(16 * (1 - focus));
    final brightness = 0.55 + 0.45 * focus;

    Widget inner = Opacity(opacity: brightness, child: widget.child);
    if (sigma > 0) {
      inner = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: inner,
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: widget.privileges.hot,
      builder: (context, hot, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            HotGlowBorder(
              hot: isSpotlight && hot,
              child: Transform.scale(
                scale: scale,
                child: ClipRRect(borderRadius: BorderRadius.circular(24), child: inner),
              ),
            ),
            if (isSpotlight)
              Positioned(
                right: 12,
                bottom: 12,
                child: IgnorePointer(
                  ignoring: focus <= 0.85,
                  child: AnimatedOpacity(
                    opacity: focus > 0.85 ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: _ActionRow(
                      onReact: _togglePicker,
                      onComment: widget.onTap,
                      onPing: _ping,
                      onShare: () => showGlassToast(context, 'Sharing coming soon'),
                    ),
                  ),
                ),
              ),
            for (final f in _floaters)
              _FloatingReaction(key: f.key, emoji: f.emoji, onComplete: () => _removeFloater(f.key)),
            for (final b in _bursts)
              EmojiBurst(key: b.key, origin: b.origin, emoji: b.emoji, onComplete: () => _removeBurst(b.key)),
            if (_showPicker && isSpotlight)
              Positioned(
                bottom: 64,
                left: 12,
                child: ReactionPickerPopup(
                  onSelect: (emoji) {
                    _react(emoji);
                    setState(() => _showPicker = false);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Floater {
  _Floater(this.key, this.emoji);
  final Key key;
  final String emoji;
}

class _Burst {
  _Burst(this.key, this.origin, this.emoji);
  final Key key;
  final Offset origin;
  final String emoji;
}

/// A single reaction drifting up and fading — spawned per live realtime
/// reaction insert while this card is the spotlight.
class _FloatingReaction extends StatefulWidget {
  const _FloatingReaction({super.key, required this.emoji, required this.onComplete});
  final String emoji;
  final VoidCallback onComplete;

  @override
  State<_FloatingReaction> createState() => _FloatingReactionState();
}

class _FloatingReactionState extends State<_FloatingReaction> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward().whenComplete(widget.onComplete);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 70,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            return Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -70 * Curves.easeOut.transform(t)),
                child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Icon-only reactions/comment/ping row — spotlight post only, no counts.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onReact,
    required this.onComment,
    required this.onPing,
    required this.onShare,
  });
  final VoidCallback onReact;
  final VoidCallback onComment;
  final VoidCallback onPing;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _icon(Icons.emoji_emotions_outlined, onReact),
            const SizedBox(width: 18),
            _icon(Icons.mode_comment_outlined, onComment),
            const SizedBox(width: 18),
            _icon(Icons.notifications_active_rounded, onPing),
            const SizedBox(width: 18),
            _icon(Icons.ios_share_rounded, onShare),
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
