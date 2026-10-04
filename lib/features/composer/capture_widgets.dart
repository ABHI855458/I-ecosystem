import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Plain circular shutter button — camera/ping capture screens.
class PlainShutterButton extends StatelessWidget {
  const PlainShutterButton({super.key, required this.onCapture});
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onCapture();
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
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
