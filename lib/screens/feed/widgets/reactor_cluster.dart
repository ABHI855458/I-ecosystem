import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// ReactorCluster — floating cluster of the most recent reactors on a photo,
// per the Feed Post Card v1 spec (EveryonePostCard). Shows the newest
// reactor's face on top (34px), the other two stepped behind it (30px,
// lower z-index — painted first), each with a 2px white ring and a small
// red heart badge at its edge. Every face bobs independently on its own
// 4.4s ease loop, staggered 0/0.5/1s so the three never move in sync. If
// there are more reactors than fit, a "+N" chip in the same ring style
// trails the stack as a 4th, furthest-back step.
//
// Data comes from ReactionService.fetchRecentReactors (reaction_service.
// dart) — already sorted by created_at descending and sliced to 3 by the
// caller; this widget just lays out and animates whatever it's given.
// ---------------------------------------------------------------------------

class ReactorInfo {
  const ReactorInfo({
    required this.id,
    required this.name,
    required this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;
}

class ReactorCluster extends StatelessWidget {
  const ReactorCluster({
    super.key,
    required this.reactors,
    this.totalCount,
    this.onReactorTap,
  });

  /// Newest-first, already sliced to at most 3.
  final List<ReactorInfo> reactors;

  /// Total distinct reactor count (e.g. ReactionSummary.totalEmojiCount) —
  /// drives the "+N" overflow chip when it exceeds [reactors].length. Null
  /// or <= reactors.length hides the chip entirely.
  final int? totalCount;

  /// Fired with the tapped reactor's id — Friends/Everyone feed only, per
  /// global profile routing. Null leaves faces non-tappable.
  final ValueChanged<String>? onReactorTap;

  static const double _kBoxWidth = 76;
  static const double _kBoxHeight = 92;
  static const double _kFrontSize = 34;
  static const double _kBackSize = 30;
  static const double _kStepDx = 14;
  static const double _kStepDy = 16;

  @override
  Widget build(BuildContext context) {
    if (reactors.isEmpty) return const SizedBox.shrink();

    final overflow = (totalCount ?? reactors.length) - reactors.length;
    final hasOverflowChip = overflow > 0;

    // Step 0 = frontmost (newest reactor, painted last/on top). Reactors
    // are already newest-first, so reactors[0] is step 0. The overflow
    // chip, if any, becomes the furthest-back step, trailing the real
    // faces like a 4th, oldest member of the stack.
    final steps = <Widget>[];
    for (var i = reactors.length - 1; i >= 0; i--) {
      steps.add(_buildFace(reactors[i], step: i));
    }
    if (hasOverflowChip) {
      steps.add(_buildOverflowChip(overflow, step: reactors.length));
    }

    return SizedBox(
      width: _kBoxWidth,
      height: _kBoxHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: steps,
      ),
    );
  }

  Widget _buildFace(ReactorInfo reactor, {required int step}) {
    final isNewest = step == 0;
    final size = isNewest ? _kFrontSize : _kBackSize;
    return Positioned(
      right: step * _kStepDx,
      bottom: step * _kStepDy,
      child: Semantics(
        label: '${reactor.name} reacted',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onReactorTap == null ? null : () => onReactorTap!(reactor.id),
          child: _ReactorFace(
            key: ValueKey(reactor.id),
            avatarUrl: reactor.avatarUrl,
            size: size,
            staggerMs: step * 500,
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowChip(int overflow, {required int step}) {
    return Positioned(
      right: step * _kStepDx,
      bottom: step * _kStepDy,
      child: _OverflowChip(count: overflow, size: _kBackSize),
    );
  }
}

// ---------------------------------------------------------------------------
// _ReactorFace — one bobbing face: white ring, small red heart badge at the
// edge (~46% of face size), CachedNetworkImage with a plain-silhouette
// fallback. The bob is a plain AnimationController (not a popKey/key-remount
// trick) started after [staggerMs] so the three run out of phase — cleaner
// in Flutter than trying to offset a shared clock.
// ---------------------------------------------------------------------------

class _ReactorFace extends StatefulWidget {
  const _ReactorFace({
    super.key,
    required this.avatarUrl,
    required this.size,
    required this.staggerMs,
  });

  final String? avatarUrl;
  final double size;
  final int staggerMs;

  @override
  State<_ReactorFace> createState() => _ReactorFaceState();
}

class _ReactorFaceState extends State<_ReactorFace> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bob;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 4400));
    _bob = Tween<double>(begin: 0, end: -5)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_ctrl);
    Future.delayed(Duration(milliseconds: widget.staggerMs), () {
      if (!_disposed && mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeSize = widget.size * 0.46;

    return AnimatedBuilder(
      animation: _bob,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _bob.value),
        child: child,
      ),
      child: SizedBox(
        width: widget.size + badgeSize / 2,
        height: widget.size + badgeSize / 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: widget.avatarUrl == null
                    ? _fallback(widget.size)
                    : CachedNetworkImage(
              memCacheWidth: 1080,
                        imageUrl: widget.avatarUrl!,
                        width: widget.size,
                        height: widget.size,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _fallback(widget.size),
                        errorWidget: (_, _, _) => _fallback(widget.size),
                      ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFF0322F),
                  border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
                ),
                child: Icon(Icons.favorite, size: badgeSize * 0.6, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(double size) => Container(
        color: const Color(0xFFEDEBE8),
        child: Icon(Icons.person, size: size * 0.55, color: const Color(0xFFA6A09B)),
      );
}

// ---------------------------------------------------------------------------
// _OverflowChip — "+N" indicator, same ring styling as a real reactor face
// so it reads as a natural continuation of the stack rather than a
// different kind of element.
// ---------------------------------------------------------------------------

class _OverflowChip extends StatelessWidget {
  const _OverflowChip({required this.count, required this.size});
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1C1816),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '+${count > 99 ? 99 : count}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
