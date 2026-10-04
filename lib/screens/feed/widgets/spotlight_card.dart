import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/ping_service.dart';

import '../../../core/glass.dart';
import '../../../services/feed_service.dart';
import '../../../services/reaction_service.dart';
import '../../../widgets/emoji_burst.dart';
import '../../../widgets/hot_glow_border.dart';
import '../../../widgets/reaction_picker_popup.dart';
import 'post_card_shared.dart';
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
    this.showActionOverlay = true,
    this.enableFocusEffect = true,
  });

  final FeedItem item;
  final SpotlightFeedController controller;
  final SpotlightPrivilegesController privileges;
  final VoidCallback onTap;
  final Widget child;

  /// The floating reaction/comment/ping/share pill this card draws over its
  /// own bottom-right corner once fully in focus. Set false when [child]
  /// already renders its own action row (EveryonePostCard) — otherwise the
  /// two visibly duplicate each other.
  final bool showActionOverlay;

  /// The blur/dim/scale-on-focus treatment (this widget's original raison
  /// d'être) was built for a PageView-per-post "one thing centered at a
  /// time" layout — every non-centered card sits at distance-from-center
  /// focus < 1 and reads as blurred/dimmed BY DESIGN there. The Everyone
  /// feed is now a plain continuous ListView (Instagram-style free scroll,
  /// no page-per-post centering) where content-sized cards stack directly
  /// against each other — under the OLD focus math, that leaves every card
  /// except whichever one happens to be dead-center permanently blurred,
  /// which reads as "the whole feed is blurred" rather than a deliberate
  /// spotlight. Set false there: every card renders at full brightness, no
  /// blur, no scale, regardless of its focus value — a normal feed, nothing
  /// blurred as you scroll past it. Gestures (tap/double-tap/long-press)
  /// and the hot-glow border still work either way; only the visual
  /// blur/dim/scale is gated by this.
  final bool enableFocusEffect;

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
    widget.controller.unregisterCard(widget.item.postId, _cardKey);
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

  // widget.item.postId is a group_posts.id, not a posts.id, whenever this
  // card is wrapping DesignGroupCard (see everyone_feed_screen.dart's own
  // `item.groupName != null` branch, which this mirrors) — reactions has a
  // separate group_post_id column precisely for that case (see
  // ReactionService.setEmojiReaction). Routing every double-tap/long-press
  // through the legacy react(postId, …) wrapper regardless of that ignored
  // the column entirely: every group-post reaction upserted post_id against
  // a group_posts id, which reactions.post_id's FK to posts(id) rejects —
  // an uncaught, un-awaited failure with nothing shown to the user.
  Future<void> _react(String emoji) async {
    final isGroupPost = widget.item.groupName != null;
    try {
      await ReactionService.instance.setEmojiReaction(
        postId: isGroupPost ? null : widget.item.postId,
        groupPostId: isGroupPost ? widget.item.postId : null,
        emoji: emoji,
      );
      // Tell whichever card is rendering this post's counts to refetch —
      // the write and the display live in different widgets. See
      // reactionsChangedForPost's own doc.
      notifyReactionsChanged(widget.item.postId);
    } catch (e) {
      // Was a dropped Future: the write could fail (this is exactly how
      // the group-post FK violation stayed invisible) and the user saw the
      // burst animation play as though it had worked. Awaited and surfaced
      // now, so a failure looks like a failure.
      if (!mounted) return;
      showGlassToast(context, "Couldn't save that reaction.", isError: true);
    }
  }

  // Heart, not fire, and always from the card's CENTRE — a double-tap
  // anywhere on the photo splashes in the middle (explicit request). The
  // burst layer is Positioned.fill in this widget's root Stack, so its
  // origin space is this State's own size.
  void _onDoubleTapDown(TapDownDetails d) {
    HapticFeedback.mediumImpact();
    _react('❤️');
    final key = UniqueKey();
    final origin = context.size?.center(Offset.zero) ?? d.localPosition;
    setState(() => _bursts.add(_Burst(key, origin, '❤️')));
  }

  void _removeBurst(Key key) {
    if (!mounted) return;
    setState(() => _bursts.removeWhere((b) => b.key == key));
  }

  void _togglePicker() {
    HapticFeedback.selectionClick();
    setState(() => _showPicker = !_showPicker);
  }

  /// One tap = pinged, no prompt sheet (user decision, 2026-09-30 — only
  /// Dip keeps prompts). ping_post_author resolves the recipient(s) from
  /// the post, so a Duo post pings both authors.
  Future<void> _ping() async {
    HapticFeedback.lightImpact();
    final who = widget.item.username ?? 'someone';
    try {
      await PingService.instance.pingPostAuthor(
        postId: widget.item.postId,
        prompt: '',
        anonymous: false,
      );
      if (mounted) showGlassToast(context, 'Pinged $who ✓');
    } on Object catch (e) {
      if (!mounted) return;
      showGlassToast(
        context,
        e is PingLimitExceeded ||
                e is PingAlreadyOpen ||
                e is PingSelfNotAllowed ||
                e is PingBlocked
            ? e.toString()
            : "Couldn't send that ping.",
        isError: true,
      );
    }
  }

  static double _quantize(double sigma) => (sigma / 2).round() * 2;

  /// Never changes — used in place of the per-card focus notifier when the
  /// focus effect is off, so the card isn't rebuilt on every scroll frame
  /// for a value it ignores anyway (_buildVisual treats focus as 1.0).
  static final ValueNotifier<double> _fullFocus = ValueNotifier(1.0);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.enableFocusEffect
          ? widget.controller.focusNotifierFor(widget.item.postId)
          : _fullFocus,
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
                // Gated by showActionOverlay for the same reason _ActionRow
                // itself already is (see that field's own doc): when the
                // wrapped card draws its own reaction UI (PostReactionCorner
                // + its "Reactions" viewer pill), this old fixed-emoji
                // long-press picker only duplicated it — popping up
                // overlapping the card's own pill instead of replacing it.
                // Every live SpotlightCard caller passes showActionOverlay:
                // false, so this was firing unconditionally everywhere.
                onLongPress: widget.showActionOverlay ? _togglePicker : null,
                child: _buildVisual(focus, isSpotlight),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVisual(double focus, bool isSpotlight) {
    final effectiveFocus = widget.enableFocusEffect ? focus : 1.0;
    final scale = 1.0 + 0.03 * effectiveFocus;
    final sigma = _quantize(16 * (1 - effectiveFocus));
    final brightness = 0.55 + 0.45 * effectiveFocus;

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
            if (isSpotlight && widget.showActionOverlay)
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
            // Positioned.fill: EmojiBurst's own inner Stack has every child
            // wrapped in Positioned (particles placed by absolute offset
            // from a tap point), which means it can only size itself from
            // its incoming constraints, not its children. As a bare,
            // non-positioned child of THIS Stack it was inheriting
            // whatever ambient constraints this card's own layout state
            // happened to hand down — usually fine, but unbounded in at
            // least one real reachable state ("A Stack requires bounded
            // constraints from its parent", live crash-loop on tapping a
            // reaction). Positioned.fill guarantees it always gets this
            // outer Stack's own already-resolved, always-bounded size.
            for (final b in _bursts)
              Positioned.fill(
                child: EmojiBurst(key: b.key, origin: b.origin, emoji: b.emoji, onComplete: () => _removeBurst(b.key)),
              ),
            if (_showPicker && isSpotlight && widget.showActionOverlay)
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
