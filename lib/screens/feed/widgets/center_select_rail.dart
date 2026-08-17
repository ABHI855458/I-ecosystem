import 'dart:async';

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// CenterSelectRail — the horizontal center-selection carousel mechanics
// shared by the reaction camera screen's filter rail and reaction rail (see
// design-refs/design_handoff_group_post_cards 2/README-camera.md,
// "Carousel behavior (both rails — get this exact)"):
//   1. Selection follows whichever item's center is nearest the rail's
//      horizontal midpoint — never independent of scroll position.
//   2. Tap-to-center: animates the tapped item to center over 300ms
//      easeOutCubic (== 1-(1-t)^3, Flutter's Curves.easeOutCubic).
//   3. Tap lock: scroll-driven reselection is suppressed for 650ms after a
//      tap so the tap's target wins while the animation runs.
//   4. Rest centered on [initialIndex] on first layout.
//   5. Snap-to-center is proximity only — no hard scroll-snap physics.
// This widget owns the ScrollController + selection index; the fixed
// center overlay (shutter / ring) is a sibling the caller layers on top in
// its own Stack, since the two rails' center pieces look nothing alike.
// ---------------------------------------------------------------------------

class CenterSelectRail extends StatefulWidget {
  const CenterSelectRail({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
    this.onSelectedChanged,
    this.initialIndex = 3,
    this.height = 96,
  });

  final int itemCount;

  /// Reserved width per item (tap target + gap) — items are centered
  /// within this extent.
  final double itemExtent;
  final Widget Function(BuildContext context, int index, bool selected) itemBuilder;
  final ValueChanged<int>? onSelectedChanged;
  final int initialIndex;
  final double height;

  @override
  State<CenterSelectRail> createState() => CenterSelectRailState();
}

class CenterSelectRailState extends State<CenterSelectRail> {
  late final ScrollController _scrollCtrl;
  int _selected = 0;
  bool _locked = false;
  Timer? _lockTimer;
  double _railWidth = 0;

  int get selected => _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialIndex.clamp(0, widget.itemCount - 1);
    _scrollCtrl = ScrollController();
    _scrollCtrl.addListener(_onScroll);
    _restCenter(attemptsLeft: 5);
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // Re-asserted across several frames, not just once — layout (and this
  // screen's own async camera-permission setState churn) can settle late,
  // per spec's "re-assert this until the measured centered index matches
  // the target." Capped at 5 attempts so a genuinely-shorter rail (fewer
  // items than would reach the target offset) can't loop forever.
  void _restCenter({required int attemptsLeft}) {
    if (attemptsLeft <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final target = widget.initialIndex * widget.itemExtent;
      final matched = (_scrollCtrl.offset - target).abs() < 0.5;
      if (!matched) {
        _scrollCtrl.jumpTo(target);
        _restCenter(attemptsLeft: attemptsLeft - 1);
      }
    });
  }

  void _onScroll() {
    if (_locked) return;
    _recomputeSelection();
  }

  void _recomputeSelection() {
    if (!_scrollCtrl.hasClients) return;
    final raw = _scrollCtrl.offset / widget.itemExtent;
    final idx = raw.round().clamp(0, widget.itemCount - 1);
    if (idx != _selected) {
      setState(() => _selected = idx);
      widget.onSelectedChanged?.call(idx);
    }
  }

  void selectByTap(int index) {
    _lockTimer?.cancel();
    setState(() {
      _selected = index;
      _locked = true;
    });
    widget.onSelectedChanged?.call(index);
    _scrollCtrl.animateTo(
      index * widget.itemExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    _lockTimer = Timer(const Duration(milliseconds: 650), () {
      _locked = false;
      if (mounted) _recomputeSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _railWidth = constraints.maxWidth;
        final pad = (_railWidth / 2) - (widget.itemExtent / 2);
        return SizedBox(
          height: widget.height,
          child: ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.2, 0.8, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: _scrollCtrl,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: pad),
              itemCount: widget.itemCount,
              itemBuilder: (context, i) => SizedBox(
                width: widget.itemExtent,
                child: Center(
                  child: GestureDetector(
                    onTap: () => selectByTap(i),
                    child: widget.itemBuilder(context, i, i == _selected),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
