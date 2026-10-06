import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long a held-shutter video may run before it stops itself — the
/// Snap-style cap (explicit request, 2026-10-06: "holding to record a video,
/// set a limit just like Snap"). The server refuses anything over 20s (see
/// ping_replies_video_duration_ck), so this stays comfortably under it.
const kHoldVideoLimit = Duration(seconds: 15);

/// The cap for a video that becomes a POST (anon, friends, group, Duo) —
/// longer than a ping answer, decided with the user 2026-10-06 ("15s pings,
/// 60s posts"). The server CHECKs sit a little above this.
const kPostVideoLimit = Duration(seconds: 60);

/// Plain circular shutter button — camera/ping capture screens.
///
/// Tap takes a photo. HOLD records video, up to [kHoldVideoLimit], with the
/// ring filling as the clip runs and stopping itself at the cap — release
/// earlier to keep what you have. Screens that pass no [onStartVideo] keep
/// tap-only behaviour exactly as before.
class PlainShutterButton extends StatefulWidget {
  const PlainShutterButton({
    super.key,
    required this.onCapture,
    this.onStartVideo,
    this.onStopVideo,
    this.videoLimit = kHoldVideoLimit,
    this.onStartFailed,
  });

  final VoidCallback onCapture;

  /// How long a hold may run before it stops itself.
  final Duration videoLimit;

  /// Called when [onStartVideo] reports it couldn't start, so the host can
  /// say so — a silent failure is indistinguishable from "holding does
  /// nothing", which is exactly what was reported (2026-10-06).
  final VoidCallback? onStartFailed;

  /// Called when the hold begins. Returning false (e.g. the camera is busy)
  /// cancels the recording UI.
  final Future<bool> Function()? onStartVideo;

  /// Called on release or at the cap.
  final VoidCallback? onStopVideo;

  @override
  State<PlainShutterButton> createState() => _PlainShutterButtonState();
}

class _PlainShutterButtonState extends State<PlainShutterButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: widget.videoLimit,
  )..addStatusListener((st) {
      // Hit the cap: stop exactly as a release would.
      if (st == AnimationStatus.completed && _recording) _stop();
    });

  bool _recording = false;
  bool _starting = false;

  /// The finger came up while [_start] was still awaiting the camera. The
  /// recording that then starts has nobody left to stop it, so it is stopped
  /// the moment it begins.
  bool _releasedWhileStarting = false;

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (widget.onStartVideo == null || _recording || _starting) return;
    _starting = true;
    _releasedWhileStarting = false;
    final ok = await widget.onStartVideo!.call();
    _starting = false;
    if (!ok) {
      if (mounted) widget.onStartFailed?.call();
      return;
    }
    if (!mounted) {
      // The camera is already recording but this button is gone: stop it.
      widget.onStopVideo?.call();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _recording = true);
    _ring.forward(from: 0);
    if (_releasedWhileStarting) _stop();
  }

  void _stop() {
    if (_starting) {
      _releasedWhileStarting = true;
      return;
    }
    if (!_recording) return;
    _ring.stop();
    setState(() => _recording = false);
    HapticFeedback.lightImpact();
    widget.onStopVideo?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_recording) return;
        HapticFeedback.mediumImpact();
        widget.onCapture();
      },
      onLongPressStart: widget.onStartVideo == null ? null : (_) => _start(),
      onLongPressEnd: widget.onStartVideo == null ? null : (_) => _stop(),
      onLongPressCancel: widget.onStartVideo == null ? null : _stop,
      child: SizedBox(
        width: 84,
        height: 84,
        child: Center(
          child: AnimatedBuilder(
            animation: _ring,
            builder: (context, _) => SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // How much of the 15s is gone.
                  if (_recording)
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: _ring.value,
                        strokeWidth: 4,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFFFA2D64),
                        ),
                      ),
                    ),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _recording ? Colors.transparent : Colors.white,
                        width: 4,
                      ),
                    ),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: _recording ? 30 : 58,
                        height: _recording ? 30 : 58,
                        decoration: BoxDecoration(
                          color: _recording
                              ? const Color(0xFFFA2D64)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(
                            _recording ? 8 : 29,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
