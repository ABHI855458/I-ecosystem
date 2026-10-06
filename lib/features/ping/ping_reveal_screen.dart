import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../shared/volume_shutter.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../composer/camera_capture_ui.dart';
import '../composer/capture_widgets.dart';
import '../face_filter/face_input_image_converter.dart'
    show kFaceMaskImageFormatGroup;
import '../face_filter/face_mask_overlay.dart';

// ---------------------------------------------------------------------------
// Data model (shared with ping_screen.dart)
// ---------------------------------------------------------------------------

class PingItem {
  const PingItem({
    required this.senderName,
    required this.avatarColor,
    required this.timeAgo,
    this.prompt = 'Show me your view 👀',
    required this.sentAt,
    this.windowHours = 6,
  });

  final String senderName;
  final Color avatarColor;
  final String timeAgo;
  final String prompt;

  /// When this ping was sent. The reply/re-entry window (see [windowHours])
  /// is measured from here — mirrors the `pings.expires_at` column in
  /// supabase/schema.sql (created_at + the sender-chosen window).
  final DateTime sentAt;

  /// Hours the recipient has to reply before the ping is gone for good.
  /// Sender-configurable at send time (see PingSendSheet); defaults to 6h.
  final int windowHours;
}

// ---------------------------------------------------------------------------
// PingRevealScreen — full-screen immersive hold-to-reveal
//
// Returns bool via pop(true) = pinged back, pop(false) = closed without reply
// ---------------------------------------------------------------------------

class PingRevealScreen extends StatefulWidget {
  const PingRevealScreen({
    super.key,
    required this.ping,
    this.onViewed,
  });

  final PingItem ping;
  final VoidCallback? onViewed;

  @override
  State<PingRevealScreen> createState() => _PingRevealScreenState();
}

class _PingRevealScreenState extends State<PingRevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdownCtrl;
  bool _pingBackSent = false;

  @override
  void initState() {
    super.initState();
    _countdownCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener(_onDone);
    _countdownCtrl.forward();
    widget.onViewed?.call();
  }

  @override
  void dispose() {
    _countdownCtrl.dispose();
    super.dispose();
  }

  void _onDone(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      Navigator.of(context).pop(widget.ping.senderName);
    }
  }

  void _pauseCountdown() {
    if (_countdownCtrl.isAnimating) _countdownCtrl.stop();
  }

  void _resumeCountdown() {
    if (!_countdownCtrl.isCompleted && mounted) _countdownCtrl.forward();
  }

  void _pingBack() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<XFile?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PingCameraScreen(
        recipientName: widget.ping.senderName,
      ),
    ).then((photo) {
      if (photo != null && mounted) {
        setState(() => _pingBackSent = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _pingBackSent = false);
        });
      }
    });
  }

  void _close() => Navigator.of(context).pop(widget.ping.senderName);

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: (_) => _pauseCountdown(),
        onPointerUp: (_) => _resumeCountdown(),
        onPointerCancel: (_) => _resumeCountdown(),
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 400) _close();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: widget.ping.avatarColor),
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // Story countdown bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: AnimatedBuilder(
                        animation: _countdownCtrl,
                        builder: (context, child) => ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: 1.0 - _countdownCtrl.value,
                            minHeight: 3.5,
                            backgroundColor: Colors.white.withValues(alpha: 0.22),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),

                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _close,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                            ),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'reply from',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.48)),
                              ),
                              Text(
                                widget.ping.senderName,
                                style: GoogleFonts.jetBrainsMono(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Photo card — locket style
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: AspectRatio(
                          aspectRatio: 3.0 / 4.0,
                          child: Container(
                            color: widget.ping.avatarColor,
                            child: Center(
                              child: Text(
                                widget.ping.senderName[0].toUpperCase(),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 120,
                                  color: Colors.white.withValues(alpha: 0.10),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    Text(
                      'Hold to pause',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.40)),
                    ),

                    const Spacer(),

                    // Ping-back button
                    Padding(
                      padding: EdgeInsets.fromLTRB(28, 0, 28, bottomPad + 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.ping.timeAgo,
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white.withValues(alpha: 0.36)),
                          ),
                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: _pingBackSent ? null : _pingBack,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                gradient: _pingBackSent
                                    ? null
                                    : const LinearGradient(
                                        colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                color: _pingBackSent ? Colors.white.withValues(alpha: 0.18) : null,
                                borderRadius: BorderRadius.circular(50),
                                boxShadow: _pingBackSent
                                    ? []
                                    : [BoxShadow(color: const Color(0xFF833AB4).withValues(alpha: 0.55), blurRadius: 28, offset: const Offset(0, 8))],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _pingBackSent ? 'Sent ✓' : 'PING BACK?',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 14,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  if (!_pingBackSent) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PingCameraScreen — 85% bottom-sheet, one-tap dual capture: a single tap
// on the shutter takes the back-camera photo, then automatically swaps to
// the front camera and takes the selfie half, then sends both together —
// no compose/caption step, no filters. Pick from gallery instead for a
// single photo with no selfie (an album pick has no second frame to
// capture, by definition).
//
// This used to be a forced TWO-tap back-then-front dual capture (one tap
// per camera, despite an earlier doc here claiming "one tap fires the
// whole sequence" — it didn't) with a 900ms "Sent!" gradient overlay
// before popping. That was removed down to a plain single shot; this
// restores the dual capture as a single automatic sequence instead of
// reintroducing the old two-tap confusion. The caller (ping_page.dart)
// still gives its own send feedback once the reply lands (via
// PingSentAnchor), so this screen still doesn't need its own "Sent!"
// overlay.
//
// If the front shot fails after the back shot already succeeded, this
// sends the back photo alone rather than losing the reply — every render
// site treats a null selfie the same as an album pick (no inset shown).
//
// Returns PingCapture? via pop(capture) = sent, pop(null) = closed without
// sending.
// ---------------------------------------------------------------------------

/// Result of a completed ping-reply capture. [selfie] is the front-camera
/// half of a dual capture — null for a gallery pick, or when the back shot
/// sent but the front shot itself failed (see the class doc above).
class PingCapture {
  const PingCapture({required this.photo, this.selfie, this.video, this.videoMs});

  /// For a VIDEO capture this is the first frame's stand-in: callers that
  /// only handle photos still get something, and [video] is what actually
  /// gets sent. Hold-to-record was an explicit request (2026-10-06).
  final XFile photo;
  final XFile? selfie;

  /// The recorded clip, capped at [kHoldVideoLimit] by the shutter.
  final XFile? video;
  final int? videoMs;

  bool get isVideo => video != null;
}

/// The ping reply camera.
///
/// Chrome is the shared [CaptureCard] — the composer's camera, not a
/// second implementation of it. [recipientName] is kept for callers and
/// for future use; the shared card shows no per-recipient caption, the
/// same as the composer.
class PingCameraScreen extends StatefulWidget {
  const PingCameraScreen({
    super.key,
    required this.recipientName,
  });

  final String recipientName;

  @override
  State<PingCameraScreen> createState() => _PingCameraScreenState();
}

class _PingCameraScreenState extends State<PingCameraScreen> {
  bool _sending = false;
  bool _initFailed = false;
  bool _cameraReady = false;
  // True from the moment the back shot lands until the front (selfie) shot
  // either lands or fails — blocks a second shutter tap mid-sequence, same
  // role _sending plays post-send.
  bool _capturingSelfie = false;

  /// Dual capture is now OPT-IN. Explicit request: "remove the dual camera
  /// default in ping page, give option dual or single; if selected dual,
  /// first back or front photo, then for the front camera photo you shall
  /// wait for user to click".
  ///
  /// Single (the default) sends one photo from whichever lens is framed.
  /// Dual takes the framed lens first, flips, and then WAITS for a second
  /// shutter tap rather than firing it automatically.
  bool _dualMode = false;

  /// Hold-to-record state (explicit request, 2026-10-06: "holding to record
  /// a video, set a limit just like Snap, and sending it to pinged people").
  /// The shutter's ring enforces the 15s cap; this side only has to start
  /// and stop the camera and hand back the file.
  bool _recordingVideo = false;
  DateTime? _recordStartedAt;

  /// The first half of a dual capture, held while the second is composed.
  /// Non-null means the shutter is armed for the second shot.
  XFile? _pendingFirst;

  /// Which lens [_pendingFirst] came from, so the two halves land in the
  /// right slots: the BACK shot is the background, the FRONT one the inset.
  bool _pendingFirstWasFront = false;
  CameraController? _controller;

  /// Which lens the viewfinder is showing right now. The capture sequence
  /// still ends on the front lens (it needs the selfie half), but the user
  /// can now choose which one they FRAME with — there was no flip control
  /// at all, so a reply always had to be composed through the back camera.
  CameraLensDirection _lens = CameraLensDirection.back;

  /// Face filter, front lens only — the mask is anchored on detected eyes,
  /// so there is nothing for it to track on the rear camera.
  bool _maskOn = false;
  final _maskOverlayKey = GlobalKey<FaceMaskOverlayState>();

  bool get _isFront => _lens == CameraLensDirection.front;

  final _flashKey = GlobalKey<CaptureFlashOverlayState>();

  @override
  void initState() {
    super.initState();
    _initCamera();
    // Volume buttons take the photo too.
    unawaited(_volumeShutter.start(() {
      if (mounted) _capture();
    }));
    // Fallback: if camera hasn't opened after 7 s, show gallery option
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      if (!_cameraReady) {
        setState(() => _initFailed = true);
      }
    });
  }

  final _volumeShutter = VolumeShutter();

  @override
  void dispose() {
    unawaited(_volumeShutter.stop());
    _controller?.dispose();
    super.dispose();
  }

  /// The ONE place a CameraController is built, for every lens and every
  /// path (first open, dual's automatic flip, the manual flip button).
  ///
  /// REBUILT on composer_screen.dart's proven recipe. This screen used to
  /// construct a controller inline in three separate places, and the
  /// hardening the composer had accumulated never made it into any of
  /// them — which is how a camera that "doesn't click pictures" survived
  /// several rounds of fixes. Everything below is deliberate:
  ///
  ///  * `ResolutionPreset.high`, not `veryHigh` — what the composer ships.
  ///    veryHigh negotiates a capture format some devices stall or fail
  ///    outright on, and it buys nothing for a photo that ends up scaled
  ///    into a reply card.
  ///  * `imageFormatGroup` is what lets FaceMaskOverlay stream frames to
  ///    ML Kit at all — without it the filter silently never detects a
  ///    face. It does NOT affect takePicture(); JPEG capture is unaffected.
  ///  * `lockCaptureOrientation(portraitUp)` pins the analysis buffer to
  ///    portrait. Without it the plugin re-orients frames as the phone
  ///    tilts while the mask converter assumes portrait, so the mask slid
  ///    off the face on any tilt. Was missing here entirely.
  ///
  /// Throws on failure; every caller decides what that means for it.
  Future<CameraController> _openController(CameraLensDirection lens) async {
    final cameras = await availableCameras();
    final desc = cameras.firstWhere(
      (c) => c.lensDirection == lens,
      orElse: () => cameras.first,
    );
    final ctrl = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: kFaceMaskImageFormatGroup,
    );
    await ctrl.initialize();
    try {
      await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {
      // Not fatal — some devices refuse; mask tracking just degrades to
      // the old tilt behaviour rather than the camera failing to open.
    }
    return ctrl;
  }

  Future<void> _initCamera() async {
    try {
      final ctrl = await _openController(_lens);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _cameraReady = true;
        _initFailed = false;
      });
    } catch (e, st) {
      debugPrint('[PingCameraScreen._initCamera] failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _initFailed = true;
      });
    }
  }

  /// Swaps the live controller to the front lens — the `camera` package has
  /// no in-place flip (same approach as composer_screen.dart's own
  /// _swapToDirection, minus the manual-swap-only guard that doesn't apply
  /// here: this is always the second half of an automatic sequence).
  ///
  /// BUG FIX (matches composer_screen.dart's identical fix): the old order
  /// initialized the NEW front-camera controller (a second, distinct
  /// AVCaptureSession on iOS) before disposing the back camera's OLD
  /// controller, so for a window both sessions were live simultaneously —
  /// which iOS's camera subsystem doesn't reliably support, and is exactly
  /// why the front camera failed to start specifically in this automatic
  /// back-then-front sequence on real hardware. Dispose first, then
  /// initialize, so at most one session is ever live. `_buildCameraArea`
  /// already renders a plain (non-crashing) fallback while `_controller` is
  /// null, and every caller of `_controller!` here is already wrapped in a
  /// try/catch (see `_capture`'s own fallback-to-back-photo-only path).
  Future<void> _swapToFront() => _swapTo(CameraLensDirection.front);

  Future<void> _swapToBack() => _swapTo(CameraLensDirection.back);

  /// Lens-agnostic because dual capture can start from EITHER lens now
  /// (see [_dualMode]) — the second half is always "the other one".
  Future<void> _swapTo(CameraLensDirection lens) async {
    // The mask's frame stream holds the OLD controller. Stop it before the
    // controller goes away, or the stream outlives its session and the
    // next takePicture() on the new one comes back blank.
    if (_maskOn) {
      await _maskOverlayKey.currentState?.pauseStreamingForCapture();
    }
    final old = _controller;
    if (mounted) setState(() => _controller = null);
    await old?.dispose();

    final ctrl = await _openController(lens);
    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    setState(() {
      _controller = ctrl;
      _lens = lens;
    });
  }

  /// Manual lens flip.
  ///
  /// Same dispose-then-initialize order _swapToFront documents: two live
  /// AVCaptureSessions at once is what broke the automatic swap on real
  /// hardware, and a manual flip has exactly the same hazard.
  Future<void> _flipCamera() async {
    if (_sending || _capturingSelfie || !_cameraReady) return;
    final next = _isFront
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    HapticFeedback.selectionClick();

    // Stop the mask's frame stream before its controller is disposed —
    // same reason as _swapTo's.
    if (_maskOn) {
      await _maskOverlayKey.currentState?.pauseStreamingForCapture();
    }
    final old = _controller;
    if (mounted) {
      setState(() {
        _controller = null;
        _cameraReady = false;
      });
    }
    await old?.dispose();
    try {
      final ctrl = await _openController(next);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _lens = next;
        _cameraReady = true;
        // The mask has nothing to track on the rear lens.
        if (next == CameraLensDirection.back) _maskOn = false;
      });
    } catch (_) {
      if (mounted) setState(() => _initFailed = true);
    }
  }

  /// Shutter. Behaviour depends on [_dualMode]:
  ///
  ///  * SINGLE (default) — one photo from whichever lens is framed, sent
  ///    immediately. No flip, no second shot, no inset.
  ///  * DUAL — first tap holds that half and flips to the other lens;
  ///    the SECOND tap takes the pair and sends both.
  ///
  /// This doc previously described a single automatic back-then-front
  /// sequence, which is what the code did BEFORE dual became opt-in — it
  /// had been left behind and contradicted both [_dualMode]'s own doc and
  /// the logic below.
  Future<void> _capture() async {
    if (_sending || _capturingSelfie || !_cameraReady || _controller == null) {
      return;
    }
    _flashKey.currentState?.flash();
    HapticFeedback.mediumImpact();

    final XFile shot;
    try {
      // THE ACTUAL FAULT behind "the camera doesn't click pictures" and
      // "it captures full white".
      //
      // FaceMaskOverlay runs a live ML Kit analysis stream on this very
      // controller. takePicture() fired against a running stream returns a
      // frame the sensor exposed for the STREAM's configuration — slow,
      // and on a bright front-facing subject blown out to pure white.
      // composer_screen.dart and the RealMoji capture both pause the
      // stream first and have for a while; this screen never did, which is
      // why the shutter kept "not working" no matter what else was fixed.
      //
      // pauseStreamingForCapture also carries the 220ms settle delay that
      // lets AVFoundation finish re-metering for stills — see its own doc
      // on why stopping the stream alone only narrowed the race.
      if (_maskOn && _isFront) {
        await _maskOverlayKey.currentState?.pauseStreamingForCapture();
      }
      shot = await _controller!.takePicture();
    } catch (e, st) {
      // A failed capture used to `catch (_) { return; }` — no error, no
      // log, no visible change, so the shutter simply appeared dead.
      // Still non-fatal (the camera stays live for another tap), but now
      // logged and surfaced.
      debugPrint('[PingCameraScreen._capture] takePicture failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't take that photo — try again.")),
        );
      }
      return;
    }
    if (!mounted) return;

    final baked = await _bakeMaskIfOn(shot);
    if (!mounted) return;

    // Single: one photo, no inset, done.
    if (!_dualMode) {
      _doSend(baked, null);
      return;
    }

    // Dual, second tap: pair it with the held first half and send.
    final first = _pendingFirst;
    if (first != null) {
      final firstWasFront = _pendingFirstWasFront;
      setState(() => _pendingFirst = null);
      _doSend(
        firstWasFront ? baked : first,
        firstWasFront ? first : baked,
      );
      return;
    }

    // Dual, first tap: hold this half, flip, and wait for the second tap.
    setState(() {
      _pendingFirst = baked;
      _pendingFirstWasFront = _isFront;
      _capturingSelfie = true;
    });
    try {
      await (_isFront ? _swapToBack() : _swapToFront());
    } catch (_) {
      // Couldn't flip — send what we already have rather than stranding
      // the user on a shutter that can't complete the pair.
      if (!mounted) return;
      final held = _pendingFirst;
      setState(() {
        _pendingFirst = null;
        _capturingSelfie = false;
      });
      if (held != null) _doSend(held, null);
      return;
    }
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _capturingSelfie = false);
  }

  /// Burns the face filter into a front-lens shot, so what gets SENT
  /// matches what was on screen. A failed bake returns the original, so it
  /// can never lose the photo.
  Future<XFile> _bakeMaskIfOn(XFile shot) async {
    if (!_maskOn || !_isFront) return shot;
    try {
      final state = _maskOverlayKey.currentState;
      return state == null ? shot : await state.bakeIntoPhoto(shot);
    } catch (_) {
      return shot;
    }
  }

  Future<void> _pickGallery() async {
    if (_sending) return;
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      // No selfie for an album pick — there's no second frame to capture.
      if (image != null && mounted) _doSend(image, null);
    } catch (_) {}
  }

  /// Pops with the capture immediately — no "Sent!" overlay first. The
  /// caller (ping_page.dart's _openCamera) already gives its own feedback
  /// once the reply lands (PingSentAnchor), so this screen doesn't need a
  /// redundant send animation of its own.
  /// Starts recording. Returns false when the camera can't take it, which
  /// tells the shutter not to show the recording ring.
  Future<bool> _startVideo() async {
    final c = _controller;
    if (_sending || _capturingSelfie || !_cameraReady || c == null) {
      return false;
    }
    if (_recordingVideo) return false;
    try {
      // A live ML Kit stream and video recording can't share the camera —
      // same conflict takePicture() hits (see _capture's own note).
      if (_maskOn && _isFront) {
        await _maskOverlayKey.currentState?.pauseStreamingForCapture();
      }
      await c.startVideoRecording();
      _recordingVideo = true;
      _recordStartedAt = DateTime.now();
      return true;
    } catch (e, st) {
      debugPrint('[PingCameraScreen._startVideo] failed: $e\n$st');
      return false;
    }
  }

  Future<void> _stopVideo() async {
    final c = _controller;
    if (!_recordingVideo || c == null) return;
    _recordingVideo = false;
    final started = _recordStartedAt;
    _recordStartedAt = null;
    XFile clip;
    try {
      clip = await c.stopVideoRecording();
    } catch (e, st) {
      debugPrint('[PingCameraScreen._stopVideo] failed: $e\n$st');
      return;
    }
    if (!mounted) return;
    final ms = started == null
        ? null
        : DateTime.now().difference(started).inMilliseconds;
    // Too short to be a deliberate clip — treat it as a mis-hold, not a
    // send, so a slightly-long tap doesn't fire off a quarter-second video.
    if (ms != null && ms < 700) return;
    if (_sending) return;
    _sending = true;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop(
      PingCapture(photo: clip, video: clip, videoMs: ms),
    );
  }

  void _doSend(XFile photo, XFile? selfie) {
    if (_sending) return;
    _sending = true;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop(PingCapture(photo: photo, selfie: selfie));
  }


  /// The camera chrome is now the SHARED [CaptureCard] — the same widget
  /// the composer's camera uses, not a look-alike.
  ///
  /// This screen used to carry ~480 lines of its own chrome: a custom
  /// header, its own scrims, its own SINGLE/DUAL toggle (_ModeToggle), its
  /// own mask pill, its own flip/gallery buttons (_GlassCamBtn) and its own
  /// shutter row. All of it was a second implementation of the composer's
  /// camera that then drifted from it. Deleted outright per the explicit
  /// instruction to use the task-bar camera's design here.
  ///
  /// What stays ping-specific is only the wiring: this sheet returns a
  /// [PingCapture] through Navigator.pop instead of advancing to a send
  /// phase, and its dual mode waits for a real second shutter tap rather
  /// than firing the front shot automatically.
  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final ready = _cameraReady && ctrl != null && ctrl.value.isInitialized;
    final midDual = _pendingFirst != null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        color: const Color(0xFF080810),
        child: CaptureCard(
          controller: _controller,
          cameraReady: ready,
          cameraError: _initFailed
              ? "Camera didn't finish starting — try again."
              : null,
          usingRear: !_isFront,
          swapping: _capturingSelfie,
          onCapture: _capture,
          onStartVideo: _startVideo,
          onStopVideo: () => unawaited(_stopVideo()),
          onGallery: _pickGallery,
          onSwap: _flipCamera,
          onClose: () => Navigator.of(context).pop(),
          dualCameraEnabled: _dualMode,
          // Locked mid-sequence so the mode can't change between the two
          // halves of a pair.
          onToggleDualCamera: () {
            if (midDual || _capturingSelfie || _sending) return;
            setState(() => _dualMode = !_dualMode);
          },
          // Drives CaptureCard's mid-dual chrome: hides the mode switch and
          // the flip button once a pair is underway.
          dualStep: midDual ? DualStep.front : DualStep.back,
          flashKey: _flashKey,
          maskFilterOn: _maskOn,
          onToggleMaskFilter: () => setState(() => _maskOn = !_maskOn),
          maskOverlayKey: _maskOverlayKey,
          // The sheet's own container already rounds the top corners.
          borderRadius: 0,
          // Dual here takes the FRAMED lens first and waits for a second
          // tap, so which lens you start on is a real choice.
          allowFlipInDual: true,
          hint: midDual
              ? (_capturingSelfie
                    ? 'flipping…'
                    : 'now the ${_isFront ? 'front' : 'back'} one — tap again')
              : null,
        ),
      ),
    );
  }
}
