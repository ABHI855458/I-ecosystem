import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants.dart';
import 'group_card_shared.dart';

// ---------------------------------------------------------------------------
// GroupCardStack — swipeable photo deck cycling through the group's real
// recent posts. Physics match design_handoff_group_post_cards/reference.html
// exactly: drag → translateX(dx) + rotate(dx/26deg) on the top card,
// progress = min(|dx|/140, 1) interpolates the two cards behind it; release
// under 80px commit distance snaps back (320ms, cubic(.22,.61,.36,1)), at/
// over it flies the top card off at ±560px over the same duration, then
// advances the index and resets dx with NO transition (so the new top card
// doesn't visibly fly in from the old off-screen position) — same as the
// JS's setTimeout-after-transition sequencing, just chained off the
// AnimationController's own completion instead of a separate timer.
//
// Falls back to a plain non-interactive single photo when the group has
// fewer than 2 real posts — nothing to swipe between.
// ---------------------------------------------------------------------------

class GroupCardStack extends StatefulWidget {
  const GroupCardStack({super.key, required this.data});
  final GroupCardData data;

  @override
  State<GroupCardStack> createState() => _GroupCardStackState();
}

class _GroupCardStackState extends State<GroupCardStack> with SingleTickerProviderStateMixin {
  static const _snapCurve = Cubic(0.22, 0.61, 0.36, 1.0);
  static const _snapDuration = Duration(milliseconds: 320);
  static const _commitThreshold = 80.0;
  static const _flyOutDistance = 560.0;
  static const _progressSpan = 140.0;
  static const _fadeThreshold = 400.0;

  late final AnimationController _snapCtrl;
  double _dx = 0;
  int _i = 0;
  double _dxAtSnapStart = 0;
  double _dxTarget = 0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this, duration: _snapDuration)
      ..addListener(() {
        final t = _snapCurve.transform(_snapCtrl.value);
        setState(() => _dx = _dxAtSnapStart + (_dxTarget - _dxAtSnapStart) * t);
      });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  GroupCardPost _at(List<GroupCardPost> photos, int k) => photos[(_i + k) % photos.length];

  void _onDragStart(DragStartDetails d) {
    _snapCtrl.stop();
    setState(() => _dx = 0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d, int photoCount) {
    if (_dx.abs() >= _commitThreshold) {
      final dir = _dx > 0 ? 1 : -1;
      _animateTo(dir * _flyOutDistance, onDone: () {
        setState(() {
          _i = (_i + 1) % photoCount;
          _dx = 0;
        });
      });
    } else {
      _animateTo(0);
    }
  }

  void _animateTo(double target, {VoidCallback? onDone}) {
    _dxAtSnapStart = _dx;
    _dxTarget = target;
    _snapCtrl.forward(from: 0).whenComplete(() {
      if (mounted) onDone?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.data.posts;

    if (photos.length < 2) {
      return GroupCardShell(
        data: widget.data,
        body: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 380,
            child: Stack(
              children: [
                Positioned.fill(child: CachedNetworkImage(imageUrl: widget.data.mainPhotoUrl, fit: BoxFit.cover)),
                Positioned(bottom: 4, right: 4, child: const GroupCardIconButtons()),
              ],
            ),
          ),
        ),
      );
    }

    final progress = (_dx.abs() / _progressSpan).clamp(0.0, 1.0);
    final top = _at(photos, 0);
    final mid = _at(photos, 1);
    final back = _at(photos, 2 % photos.length);
    final topOpacity = _dx.abs() > _fadeThreshold ? 0.0 : 1.0;

    return GroupCardShell(
      data: widget.data,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 380,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Back layer.
                  Transform.rotate(
                    angle: (-9 + 3 * progress) * math.pi / 180,
                    child: Transform.translate(
                      offset: Offset(-26 + 8 * progress, 0),
                      child: Transform.scale(
                        scale: 0.9 + 0.04 * progress,
                        child: _StackFace(post: back, width: 250, height: 320, opacity: 0.9),
                      ),
                    ),
                  ),
                  // Middle layer.
                  Transform.rotate(
                    angle: (6 - 6 * progress) * math.pi / 180,
                    child: Transform.translate(
                      offset: Offset(24 - 24 * progress, 0),
                      child: Transform.scale(
                        scale: 0.94 + 0.06 * progress,
                        child: _StackFace(post: mid, width: 250, height: 320),
                      ),
                    ),
                  ),
                  // Top (draggable) layer.
                  Transform.translate(
                    offset: Offset(_dx, 0),
                    child: Transform.rotate(
                      angle: (_dx / 26) * math.pi / 180,
                      child: Opacity(
                        opacity: topOpacity,
                        child: GestureDetector(
                          onHorizontalDragStart: _onDragStart,
                          onHorizontalDragUpdate: _onDragUpdate,
                          onHorizontalDragEnd: (d) => _onDragEnd(d, photos.length),
                          child: _StackFace(
                            post: top,
                            width: 258,
                            height: 330,
                            elevated: true,
                            counter: '${_i % photos.length + 1} / ${photos.length}',
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(bottom: 4, right: 4, child: const GroupCardIconButtons()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var d = 0; d < photos.length; d++) ...[
                  if (d > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 6,
                    width: d == _i % photos.length ? 18 : 6,
                    decoration: BoxDecoration(
                      color: d == _i % photos.length ? AppColors.textPrimary : AppColors.textMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StackFace extends StatelessWidget {
  const _StackFace({
    required this.post,
    required this.width,
    required this.height,
    this.opacity = 1,
    this.elevated = false,
    this.counter,
  });

  final GroupCardPost post;
  final double width;
  final double height;
  final double opacity;
  final bool elevated;
  final String? counter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: elevated
            ? const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.6), blurRadius: 60, offset: Offset(0, 24))]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: opacity,
            child: CachedNetworkImage(imageUrl: post.photoUrl, fit: BoxFit.cover),
          ),
          if (counter != null)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(10, 12, 18, 0.66),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(counter!, style: GoogleFonts.ibmPlexMono(fontSize: 11, color: AppColors.textPrimary)),
              ),
            ),
        ],
      ),
    );
  }
}
