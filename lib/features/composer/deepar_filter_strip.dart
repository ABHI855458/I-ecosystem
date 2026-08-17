import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/deepar_service.dart';

// ---------------------------------------------------------------------------
// DeepArFilterStrip — center-locked, scroll-snapping filter picker + shutter.
// Replaces the old horizontal chip-row DeepArLensPicker AND each camera
// screen's separate circular shutter button with one unified widget: a
// horizontally scrollable row of circular filter thumbnails with a FIXED
// white ring at the strip's true horizontal center (never itself moves —
// it's a Stack sibling of the scrolling row, not a scrolling child). The
// thumbnail nearest that ring center is the "active" filter — it scales up,
// reaches full opacity, and its lens is applied to the live DeepAR preview.
// Tapping the ring captures; tapping any other thumbnail smooth-scrolls it
// to center.
//
// No live-filtered thumbnail previews: this app's filters are real DeepAR
// .deepar lens files applied via async native calls (switchFilter/
// switchFaceMask), not CSS filters on a static frame — some are AR face
// masks with no meaningful static-image representation at all. Each
// thumbnail is a plain circular tile with a short label instead.
// ---------------------------------------------------------------------------

class DeepArFilterStrip extends StatefulWidget {
  const DeepArFilterStrip({
    super.key,
    required this.lenses,
    required this.onCapture,
    this.onActiveLabelChanged,
  });

  final List<DeepArLens> lenses;
  final VoidCallback onCapture;

  /// Fired with the active filter's uppercase display name every time the
  /// nearest-to-center item changes (including the initial "NO FILTER" on
  /// mount) — cheap/live, not debounced, since this is pure Dart state, not
  /// a native call. Caller renders this as the top-of-screen pill.
  final ValueChanged<String>? onActiveLabelChanged;

  @override
  State<DeepArFilterStrip> createState() => _DeepArFilterStripState();
}

class _DeepArFilterStripState extends State<DeepArFilterStrip> {
  static const double _itemSize = 58;
  static const double _gap = 14;
  static const double _step = _itemSize + _gap;
  static const double _activeScale = 1.5; // 58 -> 87, fills the 96px ring
  static const double _minOpacity = 0.55;
  static const double _falloff = 130; // px, matches the reference spec
  static const double _ringSize = 96;
  static const double _stripHeight = 118;

  static const _fills = [
    Color(0xFF2A2A38),
    Color(0xFF34283A),
    Color(0xFF243444),
    Color(0xFF283A2E),
  ];

  late final List<DeepArLens?> _items; // index 0 = null = "no filter"
  late final ScrollController _scrollController;
  bool _isSettling = false;
  int? _lastAppliedIndex;
  String? _lastLabel;

  @override
  void initState() {
    super.initState();
    _items = [null, ...widget.lenses];
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    // Item 0 ("no filter") sits exactly centered at scrollOffset 0 by
    // construction (see the leadingPadding math in build()) — no explicit
    // jump-to-center needed on mount, unlike a generic snap-list.
    _lastAppliedIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() {}); // picks up ScrollController.hasClients now being true
      // initializeWithDefaults() (see DeepArService) already applied the
      // beautification lens as part of camera init, before this widget ever
      // mounted — override that here so native state matches this strip's
      // own default UI position (item 0, no filter), rather than the
      // preview silently starting beautified with the strip showing "NO
      // FILTER" as active.
      await DeepArService.instance.clearLens();
      if (!mounted) return;
      widget.onActiveLabelChanged?.call(_labelFor(null));
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() {}); // cheap: only drives per-item scale/opacity transforms
    final label = _labelFor(_items[_nearestIndex]);
    if (label != _lastLabel) {
      _lastLabel = label;
      widget.onActiveLabelChanged?.call(label);
    }
  }

  int get _nearestIndex {
    if (!_scrollController.hasClients) return 0;
    final raw = _scrollController.offset / _step;
    return raw.round().clamp(0, _items.length - 1);
  }

  double _tFor(int index) {
    if (!_scrollController.hasClients) {
      return index == 0 ? 1.0 : 0.0;
    }
    final dist = ((index * _step) - _scrollController.offset).abs();
    return (1 - dist / _falloff).clamp(0.0, 1.0);
  }

  /// Scroll has settled (drag released with no residual velocity, or a
  /// fling's ballistic deceleration finished) — hard-snap to the nearest
  /// item's exact centered offset, then (only once truly settled) fire the
  /// native lens-apply call. This is the ONE place native calls happen —
  /// never per scroll frame, so a fast swipe-through can't spam DeepAR's
  /// native IPC.
  Future<void> _settle() async {
    if (_isSettling) return;
    _isSettling = true;
    final target = _nearestIndex;
    final targetOffset = target * _step;
    if (_scrollController.hasClients &&
        (_scrollController.offset - targetOffset).abs() > 0.5) {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    _isSettling = false;
    await _applyIfChanged(target);
  }

  Future<void> _tapItem(int index) async {
    if (_isSettling || index == _nearestIndex) return;
    _isSettling = true;
    await _scrollController.animateTo(
      index * _step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    _isSettling = false;
    await _applyIfChanged(index);
  }

  Future<void> _applyIfChanged(int index) async {
    if (index == _lastAppliedIndex) return;
    _lastAppliedIndex = index;
    final lens = _items[index];
    if (lens == null) {
      await DeepArService.instance.clearLens();
    } else {
      await DeepArService.instance.applyLens(lens);
    }
  }

  String _labelFor(DeepArLens? lens) {
    if (lens == null) return 'NO FILTER';
    // camelCase enum name -> spaced words, e.g. anonymousMaskOne ->
    // "ANONYMOUS MASK ONE" — matches this app's existing DeepArLensPicker
    // convention of using the enum name directly as the display label.
    final spaced = lens.name.replaceAllMapped(
      RegExp('(?<=[a-z0-9])(?=[A-Z])'),
      (m) => ' ',
    );
    return spaced.toUpperCase();
  }

  String _shortLabelFor(DeepArLens lens) {
    final words = _labelFor(lens).split(' ');
    return words.last; // "ONE" / "TWO" / "BEAUTIFICATION"
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _stripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final leadingPadding = (constraints.maxWidth - _itemSize) / 2;
          return Stack(
            alignment: Alignment.center,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollEndNotification) _settle();
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: leadingPadding),
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : _gap),
                          child: _buildItem(i),
                        ),
                      SizedBox(width: leadingPadding),
                    ],
                  ),
                ),
              ),
              // Fixed center ring — never scrolls, this is the shutter's
              // real hit target (the item it happens to be framing has
              // already scrolled itself here).
              GestureDetector(
                onTap: widget.onCapture,
                child: Container(
                  width: _ringSize,
                  height: _ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildItem(int index) {
    final t = _tFor(index);
    final scale = 1.0 + (_activeScale - 1.0) * t;
    final opacity = _minOpacity + (1 - _minOpacity) * t;
    final lens = _items[index];
    return GestureDetector(
      onTap: () => _tapItem(index),
      child: SizedBox(
        width: _itemSize,
        height: _itemSize,
        child: Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: _itemSize,
                height: _itemSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: lens == null
                      ? Colors.white.withValues(alpha: 0.12)
                      : _fills[index % _fills.length],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: lens == null
                    ? Icon(Icons.block_rounded, color: Colors.white.withValues(alpha: 0.7), size: 22)
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _shortLabelFor(lens),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ActiveFilterPill — uppercase pill for the active filter's name, rendered
// by the parent screen near its own top chrome (spatially separate from the
// strip at the bottom, so this can't just be the strip's own child).
// ---------------------------------------------------------------------------

class ActiveFilterPill extends StatelessWidget {
  const ActiveFilterPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CaptureFlashOverlay — brief white opacity flash over the viewfinder on
// capture. Public State (not underscore-prefixed) so a parent screen can
// hold a GlobalKey<CaptureFlashOverlayState> and call .flash() from its own
// existing capture method, without this widget needing to know anything
// about how/when capture happens.
// ---------------------------------------------------------------------------

class CaptureFlashOverlay extends StatefulWidget {
  const CaptureFlashOverlay({super.key});

  @override
  State<CaptureFlashOverlay> createState() => CaptureFlashOverlayState();
}

class CaptureFlashOverlayState extends State<CaptureFlashOverlay> {
  double _opacity = 0;

  void flash() {
    if (!mounted) return;
    setState(() => _opacity = 1);
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _opacity = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(color: Colors.white),
      ),
    );
  }
}
