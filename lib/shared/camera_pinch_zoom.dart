import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pinch-to-zoom for any camera preview.
///
/// Built on a raw [Listener] rather than a scale GestureDetector on purpose:
/// a scale recognizer also claims ONE-finger drags, which would steal the
/// swipes and taps every camera screen already uses. Here only a genuine
/// two-finger pinch changes the zoom; everything else passes straight
/// through. Pinching either direction (fingers apart = in, fingers
/// together = out) already moves the zoom both ways — the pill in the
/// center is also a tappable shortcut: it stays on screen while zoomed in
/// and a tap on it resets straight back to 1× (zooming all the way out in
/// one motion, no pinch needed).
class CameraPinchZoom extends StatefulWidget {
  const CameraPinchZoom({
    super.key,
    required this.controller,
    required this.child,
  });

  final CameraController? controller;
  final Widget child;

  @override
  State<CameraPinchZoom> createState() => _CameraPinchZoomState();
}

class _CameraPinchZoomState extends State<CameraPinchZoom> {
  static const double _cap = 8; // beyond this, phone zoom is just mush

  final Map<int, Offset> _pointers = {};
  double _min = 1, _max = 1, _zoom = 1;
  double _baseZoom = 1, _baseDistance = 0;
  bool _showLabel = false;
  Timer? _hideLabel;
  CameraController? _boundTo;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(CameraPinchZoom old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) _bind();
  }

  /// New camera (flip, re-init): read its zoom range and start at 1×.
  Future<void> _bind() async {
    final c = widget.controller;
    _boundTo = c;
    _zoom = 1;
    if (c == null || !c.value.isInitialized) return;
    try {
      final lo = await c.getMinZoomLevel();
      final hi = await c.getMaxZoomLevel();
      if (!mounted || _boundTo != c) return;
      setState(() {
        _min = lo;
        _max = math.min(hi, _cap);
        _zoom = lo.clamp(1.0, _max);
      });
    } catch (_) {
      // Zoom unsupported on this lens: pinching simply does nothing.
    }
  }

  double get _distance {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _baseDistance = _distance;
      _baseZoom = _zoom;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length != 2 || _baseDistance <= 0) return;
    final c = widget.controller;
    if (c == null || !c.value.isInitialized || _max <= _min) return;
    final next = (_baseZoom * (_distance / _baseDistance)).clamp(_min, _max);
    if ((next - _zoom).abs() < 0.01) return;
    _zoom = next;
    unawaited(c.setZoomLevel(next).catchError((_) {}));
    _hideLabel?.cancel();
    setState(() => _showLabel = true);
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _baseDistance = 0;
      _hideLabel?.cancel();
      _hideLabel = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _showLabel = false);
      });
    }
  }

  /// True once zoomed past baseline — the pill stays up (no fade timer) so
  /// there is always something on screen to tap back down to 1×.
  bool get _zoomedIn => _zoom - _min > 0.05;

  void _resetZoom() {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      _zoom = _min;
      _showLabel = true;
    });
    unawaited(c.setZoomLevel(_min).catchError((_) {}));
    _hideLabel?.cancel();
    _hideLabel = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showLabel = false);
    });
  }

  @override
  void dispose() {
    _hideLabel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            // Only tappable while actually visible — otherwise this
            // invisible full-size layer would sit over the whole
            // viewfinder and swallow every capture tap underneath it.
            child: IgnorePointer(
              ignoring: !(_showLabel || _zoomedIn),
              child: Center(
                child: AnimatedOpacity(
                  opacity: (_showLabel || _zoomedIn) ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onTap: _zoomedIn ? _resetZoom : null,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_zoom.toStringAsFixed(1)}×',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          // Only once actually zoomed in — tapping resets
                          // straight to 1×, the explicit "zoom out" shortcut
                          // alongside pinching fingers together.
                          if (_zoomedIn) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.zoom_out_map_rounded,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
