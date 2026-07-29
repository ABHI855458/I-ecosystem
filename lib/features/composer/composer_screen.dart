import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';

import '../notifications/notifications_screen.dart';
import '../../services/camera_prefs_service.dart';
import '../../services/current_user_service.dart';
import '../../services/post_service.dart';
import '../../services/prompt_service.dart';
import '../../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// Route — opaque:false, feed shows through, card slides up from bottom
// ---------------------------------------------------------------------------

Route<void> openCameraRoute() {
  return PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, anim, secAnim) => const ComposerScreen(),
    transitionsBuilder: (context, anim, secAnim, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Phase enum
// ---------------------------------------------------------------------------

enum ComposerPhase {
  camera,
  send,
  confirm, // alias kept for screenshot-mode compat — same as send
  reward,
}

/// Only meaningful while dual camera mode is on and _phase == camera.
enum _DualStep { back, front }

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class ComposerScreen extends StatefulWidget {
  const ComposerScreen({
    super.key,
    this.testPhase,
    this.testAnonymous = false,
  });

  final ComposerPhase? testPhase;
  final bool testAnonymous;

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  late ComposerPhase _phase;
  late bool _isAnonymous;
  XFile? _capturedPhoto;

  // Single active preview controller — iOS only supports one session at a time.
  // Swapping disposes current and inits the other camera. This invariant is
  // also what the dual-capture sequence below depends on: the back
  // controller is fully disposed before the front one is ever created.
  List<CameraDescription> _cameras = [];
  CameraController? _previewCtrl;
  bool _usingRear = true;
  bool _cameraSwapping = false;
  _SelectedMusic? _selectedMusic;

  // ── Dual camera (BeReal-style back+front) ───────────────────────────────
  bool _dualCameraEnabled = false;
  _DualStep _dualStep = _DualStep.back;
  XFile? _pendingBackPhoto;
  bool _frontCapturing = false;
  String? _frontCaptureError;
  Timer? _frontAutoCaptureTimer;

  @override
  void initState() {
    super.initState();
    final p = widget.testPhase;
    _phase = (p == ComposerPhase.confirm) ? ComposerPhase.send : (p ?? ComposerPhase.camera);
    _isAnonymous = widget.testAnonymous;
    if (_phase == ComposerPhase.camera) _bootstrapCamera();
  }

  @override
  void dispose() {
    _frontAutoCaptureTimer?.cancel();
    _previewCtrl?.dispose();
    super.dispose();
  }

  /// Loads the persisted dual-camera preference before the first camera
  /// init, so cold start respects whatever the user last set — the toggle
  /// itself only affects what happens at the *next* shutter tap (see
  /// _toggleDualCamera), so there's nothing else to reconcile here.
  Future<void> _bootstrapCamera() async {
    final enabled = await CameraPrefsService.loadDualCameraEnabled();
    if (!mounted) return;
    setState(() {
      _dualCameraEnabled = enabled;
      _dualStep = _DualStep.back;
    });
    await _initPreviewCamera(rear: true);
  }

  Future<void> _toggleDualCamera() async {
    HapticFeedback.selectionClick();
    final next = !_dualCameraEnabled;
    setState(() => _dualCameraEnabled = next);
    await CameraPrefsService.setDualCameraEnabled(next);
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initPreviewCamera({bool rear = true}) async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      final dir = rear ? CameraLensDirection.back : CameraLensDirection.front;
      final matches = _cameras.where((c) => c.lensDirection == dir).toList();
      if (matches.isEmpty) {
        if (mounted) setState(() => _cameraSwapping = false);
        return;
      }
      final old = _previewCtrl;
      final ctrl = CameraController(matches.first, ResolutionPreset.medium, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      await old?.dispose();
      setState(() { _previewCtrl = ctrl; _usingRear = rear; _cameraSwapping = false; });
    } catch (_) {
      if (mounted) setState(() => _cameraSwapping = false);
    }
  }

  void _swapCamera() {
    // Manual swap only applies to single-camera mode — in dual mode the
    // back->front sequence is fully automatic (see _captureBackShot).
    if (_cameraSwapping || _dualCameraEnabled) return;
    setState(() => _cameraSwapping = true);
    _initPreviewCamera(rear: !_usingRear);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    if (_dualCameraEnabled) {
      switch (_dualStep) {
        case _DualStep.back:
          await _captureBackShot();
        case _DualStep.front:
          await _captureFrontShot();
      }
      return;
    }
    await _captureSingleShot();
  }

  /// Dual camera OFF: exactly one photo, whichever camera is currently
  /// live. No overlay, no second shot.
  Future<void> _captureSingleShot() async {
    HapticFeedback.mediumImpact();
    XFile? image;
    try {
      if (_previewCtrl != null && _previewCtrl!.value.isInitialized) {
        image = await _previewCtrl!.takePicture();
      } else {
        image = await ImagePicker().pickImage(
            source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
      }
    } catch (_) {
      try {
        image = await ImagePicker().pickImage(
            source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _capturedPhoto = image;
      _phase = ComposerPhase.send;
    });
  }

  /// Dual camera ON, step 1: capture the back photo, then fully dispose the
  /// back controller BEFORE touching the front camera. The previous
  /// implementation created+initialized a second (front) CameraController
  /// while the back one was still alive — iOS only reliably drives one
  /// AVCaptureSession at a time, so for the ~350ms the front controller
  /// spent initializing, the still-mounted back CameraPreview widget could
  /// show front-camera frames bleeding through. Disposing first removes
  /// that window entirely: at most one controller exists at any moment.
  Future<void> _captureBackShot() async {
    if (_previewCtrl == null || !_previewCtrl!.value.isInitialized) return;
    HapticFeedback.mediumImpact();
    try {
      final backPhoto = await _previewCtrl!.takePicture();
      await _previewCtrl?.dispose();
      if (!mounted) return;
      setState(() {
        _previewCtrl = null;
        _pendingBackPhoto = backPhoto;
        _dualStep = _DualStep.front;
      });
      await _initFrontForDualCapture();
    } catch (_) {
      // Back shot failed — nothing captured yet, camera stays as-is so the
      // user can just tap the shutter again.
    }
  }

  /// Dual camera ON, step 2 setup: the back controller is already disposed
  /// (see above) — only now does the front camera get created, so it's
  /// genuinely inactive/uninitialized until this point, not just visually
  /// hidden.
  Future<void> _initFrontForDualCapture() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      final front = _cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .toList();
      if (front.isEmpty) {
        if (!mounted) return;
        setState(() => _frontCaptureError =
            'No front camera available on this device.');
        return;
      }
      final ctrl =
          CameraController(front.first, ResolutionPreset.medium, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _previewCtrl = ctrl;
        _usingRear = false;
        _frontCaptureError = null;
      });
      _scheduleFrontAutoCapture();
    } catch (_) {
      if (!mounted) return;
      setState(() => _frontCaptureError = "Couldn't start the front camera.");
    }
  }

  /// Front shot auto-fires a short beat after the preview comes up if the
  /// user hasn't already tapped the shutter — mirrors the old PiP grab's
  /// warm-up-then-auto-capture timing, just long enough this time for the
  /// user to actually see themselves and react, since the preview is now
  /// genuinely visible instead of happening invisibly in the background.
  void _scheduleFrontAutoCapture() {
    _frontAutoCaptureTimer?.cancel();
    _frontAutoCaptureTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || _frontCapturing) return;
      _captureFrontShot();
    });
  }

  /// Dual camera ON, step 3: capture the front photo and composite. If this
  /// throws, the front controller is left exactly as it was (still live,
  /// still previewing) and _pendingBackPhoto is untouched, so the shutter
  /// staying tappable IS the retry path — nothing extra to wire up.
  Future<void> _captureFrontShot() async {
    if (_previewCtrl == null ||
        !_previewCtrl!.value.isInitialized ||
        _frontCapturing ||
        _pendingBackPhoto == null) {
      return;
    }
    _frontAutoCaptureTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _frontCapturing = true;
      _frontCaptureError = null;
    });
    try {
      final frontPhoto = await _previewCtrl!.takePicture();
      final composited =
          await _compositeImages(_pendingBackPhoto!, frontPhoto);
      await _previewCtrl?.dispose();
      if (!mounted) return;
      setState(() {
        _previewCtrl = null;
        _frontCapturing = false;
        _capturedPhoto = composited;
        _pendingBackPhoto = null;
        _phase = ComposerPhase.send;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _frontCapturing = false;
        _frontCaptureError = "Couldn't capture the front shot — try again.";
      });
      _scheduleFrontAutoCapture();
    }
  }

  /// Escape hatch for when the front camera genuinely isn't available —
  /// use the already-captured back photo alone rather than strand the user
  /// with no way to finish posting.
  void _useBackPhotoOnly() {
    final back = _pendingBackPhoto;
    if (back == null) return;
    _frontAutoCaptureTimer?.cancel();
    setState(() {
      _capturedPhoto = back;
      _pendingBackPhoto = null;
      _frontCaptureError = null;
      _phase = ComposerPhase.send;
    });
  }

  /// Composites [back] as the full background with [front] as a small
  /// rounded, white-bordered bubble — BeReal's actual layout: top-left
  /// corner, roughly 28% of the main photo's width, thin white stroke, soft
  /// drop shadow (the previous version used a translucent backing rect
  /// instead of a real stroke+shadow, and placed it top-right).
  Future<XFile> _compositeImages(XFile back, XFile front) async {
    try {
      final backBytes = await File(back.path).readAsBytes();
      final frontBytes = await File(front.path).readAsBytes();

      final backCodec = await ui.instantiateImageCodec(backBytes);
      final frontCodec = await ui.instantiateImageCodec(frontBytes);
      final backImg = (await backCodec.getNextFrame()).image;
      final frontImg = (await frontCodec.getNextFrame()).image;

      final w = backImg.width.toDouble();
      final h = backImg.height.toDouble();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Full background — back-camera photo
      canvas.drawImage(backImg, Offset.zero, Paint());

      // Selfie bubble — top-left, ~28% width, matching BeReal's proportions
      final bubbleW = w * 0.28;
      final bubbleH = bubbleW * frontImg.height / frontImg.width;
      const margin = 24.0;
      const borderWidth = 4.0;
      final bubbleRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(margin, margin, bubbleW, bubbleH),
        const Radius.circular(18),
      );

      // Soft drop shadow behind the bubble
      canvas.drawRRect(
        bubbleRRect.shift(const Offset(0, 3)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
      );

      // Front photo, clipped to the bubble
      canvas.save();
      canvas.clipRRect(bubbleRRect);
      canvas.drawImageRect(
        frontImg,
        Rect.fromLTWH(0, 0, frontImg.width.toDouble(), frontImg.height.toDouble()),
        Rect.fromLTWH(margin, margin, bubbleW, bubbleH),
        Paint(),
      );
      canvas.restore();

      // Thin white border stroke on top
      canvas.drawRRect(
        bubbleRRect,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );

      final picture = recorder.endRecording();
      final composite = await picture.toImage(w.toInt(), h.toInt());
      final pngData = await composite.toByteData(format: ui.ImageByteFormat.png);

      backImg.dispose();
      frontImg.dispose();

      final dir = File(back.path).parent;
      final path = '${dir.path}/dual_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(pngData!.buffer.asUint8List());
      return XFile(path);
    } catch (_) {
      return back;
    }
  }

  Future<void> _pickGallery() async {
    try {
      final image = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
      if (!mounted) return;
      setState(() {
        _capturedPhoto = image;
        _phase = ComposerPhase.send;
      });
    } catch (_) {}
  }

  void _backToCamera() {
    setState(() {
      _phase = ComposerPhase.camera;
      _capturedPhoto = null;
    });
    if (_previewCtrl == null || !_previewCtrl!.value.isInitialized) {
      _initPreviewCamera(rear: _usingRear);
    }
  }

  Future<void> _openMusicPicker() async {
    final music = await showModalBottomSheet<_SelectedMusic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MusicPickerSheet(),
    );
    if (music != null && mounted) setState(() => _selectedMusic = music);
  }

  /// Throws on failure (auth not resolved, image upload failed, or the
  /// posts insert was rejected) — the caller (_SendInterface's send button)
  /// catches this to show the real error and let the user retry, instead of
  /// silently pretending the post went through.
  Future<void> _send(String caption, double aspectRatio) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in — cannot post.');
    }

    // Resolves the app-level `users.id` via the auth_id indirection.
    // posts.user_id FKs to users.id, NOT auth.users.id, and the
    // posts_insert RLS policy checks auth.uid() against users.auth_id — so
    // sending the raw auth uid here (as this used to) can never match and
    // the insert is rejected on every attempt.
    final userId = await CurrentUserService.instance.resolveId();
    final username = user.email?.split('@').first ?? 'you';

    HapticFeedback.heavyImpact();

    await PostService.instance.addPost(
      LocalPost(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        username: username,
        visibility: _isAnonymous ? 'anonymous' : 'everyone',
        caption: caption,
        photoPath: _capturedPhoto?.path,
        aspectRatio: aspectRatio,
        musicTitle: _selectedMusic?.title,
        musicArtist: _selectedMusic?.artist,
        musicUrl: _selectedMusic?.url,
      ),
    );

    setState(() => _phase = ComposerPhase.reward);
    PromptService.instance.advance();
    notifState.fireBigScore(10);
    await Future<void>.delayed(const Duration(milliseconds: 920));
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    // Send phase needs extra height for portrait-ratio photo previews
    final cardH = _phase == ComposerPhase.send
        ? screenH * 0.88
        : screenH * 0.65;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    const cardPad = 12.0;
    const cardRadius = Radius.circular(48);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Tap dimmed feed above to close (capture phase only)
          if (_phase == ComposerPhase.camera)
            Positioned(
              top: 0, left: 0, right: 0,
              bottom: cardH + cardPad,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.expand(),
              ),
            ),

          // ── The card ──────────────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: cardPad, right: cardPad,
            bottom: _phase == ComposerPhase.send ? kb + cardPad : cardPad,
            height: cardH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(cardRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.42),
                    blurRadius: 28,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: switch (_phase) {
                  ComposerPhase.camera => _CaptureCard(
                      key: const ValueKey('capture'),
                      controller: _previewCtrl,
                      usingRear: _usingRear,
                      swapping: _cameraSwapping,
                      onCapture: _capture,
                      onGallery: _pickGallery,
                      onSwap: _swapCamera,
                      onClose: () => Navigator.of(context).pop(),
                      dualCameraEnabled: _dualCameraEnabled,
                      onToggleDualCamera: _toggleDualCamera,
                      dualStep: _dualStep,
                      frontCapturing: _frontCapturing,
                      frontCaptureError: _frontCaptureError,
                      onUseBackPhotoOnly: _useBackPhotoOnly,
                    ),
                  ComposerPhase.send || ComposerPhase.confirm => _SendInterface(
                      key: const ValueKey('send'),
                      photo: _capturedPhoto,
                      isAnonymous: _isAnonymous,
                      selectedMusic: _selectedMusic,
                      onAnonChanged: (v) => setState(() => _isAnonymous = v),
                      onBack: _backToCamera,
                      onSend: _send,
                      onMusicTap: _openMusicPicker,
                    ),
                  ComposerPhase.reward => const _RewardCard(
                      key: ValueKey('reward'),
                      points: 10,
                    ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PHASE 1 — Capture card  (Image-1 / Locket style)
//
//   ┌──────────────────────────────┐
//   │  "What's happening?"         │  ← prompt, top, subtle
//   │                              │
//   │   [camera feed — fills]      │
//   │          [PiP corner]        │
//   │                              │
//   │  [←]      [●]      [···]    │  ← controls at bottom
//   └──────────────────────────────┘
//   NO audience toggle here.
// ---------------------------------------------------------------------------

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    super.key,
    required this.controller,
    required this.usingRear,
    required this.swapping,
    required this.onCapture,
    required this.onGallery,
    required this.onSwap,
    required this.onClose,
    required this.dualCameraEnabled,
    required this.onToggleDualCamera,
    required this.dualStep,
    required this.frontCapturing,
    required this.frontCaptureError,
    required this.onUseBackPhotoOnly,
  });

  final CameraController? controller;
  final bool usingRear;
  final bool swapping;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onSwap;
  final VoidCallback onClose;
  final bool dualCameraEnabled;
  final VoidCallback onToggleDualCamera;
  final _DualStep dualStep;
  final bool frontCapturing;
  final String? frontCaptureError;
  final VoidCallback onUseBackPhotoOnly;

  bool get _inFrontStep => dualCameraEnabled && dualStep == _DualStep.front;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pipW = size.width * 0.22;
    final pipH = size.width * 0.28;

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(48)),
      child: Column(
        children: [
          // ── Prompt section — ABOVE camera ────────────────────────────
          Container(
            color: const Color(0xFF0C0E14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag pill
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 2, 24, 14),
                  child: Text(
                    _inFrontStep
                        ? 'Back photo captured — now you! 🤳'
                        : PromptService.instance.current,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // ── Camera area fills the rest ────────────────────────────────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera viewfinder
                _CameraViewfinder(controller: controller),

                // Bottom gradient scrim
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  height: 130,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.78),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // PiP — tap to swap between rear / front camera. Manual
                // swap only makes sense in single-camera mode; dual mode
                // drives back->front automatically.
                if (!dualCameraEnabled)
                  Positioned(
                    top: 14, right: 14,
                    child: GestureDetector(
                      onTap: swapping ? null : onSwap,
                      child: Container(
                        width: pipW, height: pipH,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E0E16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: swapping
                              ? const Center(
                                  child: SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white38)),
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      usingRear ? Icons.camera_front_outlined : Icons.camera_rear_outlined,
                                      size: 22,
                                      color: Colors.white.withValues(alpha: 0.35),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      usingRear ? 'selfie' : 'rear',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 8,
                                        color: Colors.white.withValues(alpha: 0.28),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),

                // Dual camera toggle — top-left, hidden once the front step
                // is underway (mid-sequence isn't a sensible time to change
                // your mind about it).
                if (!_inFrontStep)
                  Positioned(
                    top: 14, left: 14,
                    child: _DualCameraToggle(
                      enabled: dualCameraEnabled,
                      onTap: onToggleDualCamera,
                    ),
                  ),

                // Front-capture-in-progress indicator
                if (_inFrontStep && frontCapturing)
                  const Positioned(
                    top: 14, left: 0, right: 0,
                    child: Center(
                      child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),
                    ),
                  ),

                // Front capture failed — retry (shutter stays live) or fall
                // back to the back photo alone.
                if (frontCaptureError != null)
                  Positioned(
                    top: 60, left: 20, right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            frontCaptureError!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: onUseBackPhotoOnly,
                            child: Text(
                              'Use back photo only',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom controls: [←] [●] [···]
                Positioned(
                  bottom: 24, left: 24, right: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _SmallCircleBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onClose, size: 44, iconSize: 16),
                      _ShutterBtn(onTap: onCapture),
                      _SmallCircleBtn(icon: Icons.more_horiz_rounded, onTap: onGallery, size: 44, iconSize: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dual camera toggle — persisted via CameraPrefsService, read/written by
// the parent (_toggleDualCamera). Sits opposite the swap-camera control.
// ---------------------------------------------------------------------------

class _DualCameraToggle extends StatelessWidget {
  const _DualCameraToggle({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: enabled
              ? Colors.white.withValues(alpha: 0.20)
              : const Color(0xFF0E0E16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled
                ? Colors.white.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_2_rounded,
              size: 14,
              color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.40),
            ),
            const SizedBox(width: 4),
            Text(
              'DUAL',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.40),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PHASE 2 — Send interface  (Image-2 / BeReal style)
//
//   ┌──────────────────────────────┐
//   │ i.                      [←] │  ← top bar
//   │                              │
//   │  ┌────────────────────────┐  │
//   │  │  photo preview         │  │
//   │  │     [PiP]              │  │
//   │  └────────────────────────┘  │
//   │  Add a caption...            │  ← text input
//   │                              │
//   │  [Everyone] [Anonymous] [♫] │  ← audience row
//   │                              │
//   │  [        SEND  >         ] │  ← big send button
//   └──────────────────────────────┘
// ---------------------------------------------------------------------------

class _SendInterface extends StatefulWidget {
  const _SendInterface({
    super.key,
    required this.photo,
    required this.isAnonymous,
    required this.onAnonChanged,
    required this.onBack,
    required this.onSend,
    this.selectedMusic,
    this.onMusicTap,
  });

  final XFile? photo;
  final bool isAnonymous;
  final ValueChanged<bool> onAnonChanged;
  final VoidCallback onBack;
  final Future<void> Function(String caption, double aspectRatio) onSend;
  final _SelectedMusic? selectedMusic;
  final VoidCallback? onMusicTap;

  @override
  State<_SendInterface> createState() => _SendInterfaceState();
}

class _SendInterfaceState extends State<_SendInterface> {
  final _captionCtrl = TextEditingController();
  bool _sending = false;
  double _selectedRatio = 4.0 / 5.0;
  final _musicPlayer = AudioPlayer();
  bool _musicPlaying = false;

  @override
  void initState() {
    super.initState();
    _configureAudioSession();
  }

  Future<void> _configureAudioSession() async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
    } catch (_) {}
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleMusicPreview() async {
    if (widget.selectedMusic == null) return;
    try {
      if (_musicPlaying) {
        await _musicPlayer.pause();
        setState(() => _musicPlaying = false);
      } else {
        await _musicPlayer.play(UrlSource(widget.selectedMusic!.url));
        setState(() => _musicPlaying = true);
        _musicPlayer.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _musicPlaying = false);
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(_SendInterface old) {
    super.didUpdateWidget(old);
    if (old.selectedMusic != widget.selectedMusic) {
      _musicPlayer.stop();
      setState(() => _musicPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(48)),
      child: Container(
        color: const Color(0xFF0D0D12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Top bar: "i."  +  back arrow ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    'i.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onBack,
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── Aspect ratio picker ────────────────────────────────────
            _RatioPicker(
              selected: _selectedRatio,
              onChanged: (r) => setState(() => _selectedRatio = r),
            ),

            const SizedBox(height: 10),

            // ── Photo preview — Expanded so it never overflows ─────────
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, bc) {
                  // Compute photo dimensions that fit the available space
                  // while respecting the selected aspect ratio.
                  final aW = bc.maxWidth - 32; // 16pt padding each side
                  final aH = bc.maxHeight;
                  var pW = aW;
                  var pH = aW / _selectedRatio;
                  if (pH > aH) {
                    pH = aH;
                    pW = aH * _selectedRatio;
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: pW,
                        height: pH,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildPhotoView(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (widget.selectedMusic != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _toggleMusicPreview,
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: _musicPlaying ? 0.18 : 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _musicPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.selectedMusic!.title,
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.selectedMusic!.artist,
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.50)),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.30), size: 14),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Caption input ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _captionCtrl,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white,
                ),
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: 'Add a caption…',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),

            const SizedBox(height: 14),

            // ── Audience row ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _AudiencePill(
                    label: 'Everyone',
                    icon: Icons.public_rounded,
                    isActive: !widget.isAnonymous,
                    onTap: () => widget.onAnonChanged(false),
                  ),
                  const SizedBox(width: 8),
                  _AudiencePill(
                    label: 'Anonymous',
                    icon: Icons.visibility_off_outlined,
                    isActive: widget.isAnonymous,
                    onTap: () => widget.onAnonChanged(true),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onMusicTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: widget.selectedMusic != null
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.selectedMusic != null
                              ? Colors.white.withValues(alpha: 0.35)
                              : Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.music_note_rounded,
                            size: 14,
                            color: widget.selectedMusic != null
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.45),
                          ),
                          if (widget.selectedMusic != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              widget.selectedMusic!.title,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── SEND button ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: GestureDetector(
                onTap: _sending
                    ? null
                    : () async {
                        setState(() => _sending = true);
                        try {
                          await widget.onSend(_captionCtrl.text.trim(), _selectedRatio);
                        } catch (e, st) {
                          debugPrint('[Composer] Post failed: $e\n$st');
                          if (!mounted) return;
                          setState(() => _sending = false);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to post: $e')),
                          );
                        }
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 54,
                  decoration: BoxDecoration(
                    color: _sending
                        ? Colors.white.withValues(alpha: 0.75)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.15),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: _sending
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SEND',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                  letterSpacing: 2.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.black,
                                size: 18,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoView() {
    if (widget.photo == null) {
      return Container(
        color: const Color(0xFF141420),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      );
    }

    Widget img = Image.file(
      File(widget.photo!.path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );

    if (widget.isAnonymous) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: img,
      );
    }
    return img;
  }
}

// ---------------------------------------------------------------------------
// Audience pill button
// ---------------------------------------------------------------------------

class _AudiencePill extends StatelessWidget {
  const _AudiencePill({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.10),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.38),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera viewfinder placeholder
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Aspect ratio picker
// ---------------------------------------------------------------------------

class _RatioPicker extends StatelessWidget {
  const _RatioPicker({required this.selected, required this.onChanged});

  final double selected;
  final ValueChanged<double> onChanged;

  static const _options = <(String, double)>[
    ('4:5', 4.0 / 5.0),
    ('1:1', 1.0),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _options.map((opt) {
        final isSelected = (opt.$2 - selected).abs() < 0.01;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onChanged(opt.$2);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // tiny ratio icon
                  _RatioIcon(ratio: opt.$2, active: isSelected),
                  const SizedBox(width: 6),
                  Text(
                    opt.$1,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.black
                          : Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RatioIcon extends StatelessWidget {
  const _RatioIcon({required this.ratio, required this.active});

  final double ratio;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // ratio = width/height; icon size: normalize to 14px height
    const h = 14.0;
    final w = (h * ratio).clamp(8.0, 14.0);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? Colors.black : Colors.white.withValues(alpha: 0.75),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera viewfinder placeholder
// ---------------------------------------------------------------------------

class _CameraViewfinder extends StatelessWidget {
  const _CameraViewfinder({this.controller});

  final CameraController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller != null && controller!.value.isInitialized) {
      final size = controller!.value.previewSize;
      if (size != null) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.height,
              height: size.width,
              child: CameraPreview(controller!),
            ),
          ),
        );
      }
    }
    return Container(
      color: const Color(0xFF0C0E12),
      child: Center(
        child: Icon(
          Icons.camera_alt_outlined,
          color: Colors.white.withValues(alpha: 0.05),
          size: 72,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shutter button
// ---------------------------------------------------------------------------

class _ShutterBtn extends StatefulWidget {
  const _ShutterBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ShutterBtn> createState() => _ShutterBtnState();
}

class _ShutterBtnState extends State<_ShutterBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3.5),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.20),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 56, height: 56,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small circle button (back, menu, etc.)
// ---------------------------------------------------------------------------

class _SmallCircleBtn extends StatelessWidget {
  const _SmallCircleBtn({
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.40),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 0.8,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PHASE 3 — Reward card (+10 pts celebration)
// ---------------------------------------------------------------------------

class _RewardCard extends StatefulWidget {
  const _RewardCard({super.key, required this.points});
  final int points;

  @override
  State<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends State<_RewardCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _scale = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(48)),
      child: Container(
        color: const Color(0xFF0A0A10),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF6B2B).withValues(alpha: 0.12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B2B).withValues(alpha: 0.35),
                          blurRadius: 40, spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '+${widget.points}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 42, fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '🔥  points earned',
                    style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Keep posting for more rewards',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                  ),
                  const SizedBox(height: 36),
                  _MiniScoreRing(points: widget.points),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniScoreRing extends StatefulWidget {
  const _MiniScoreRing({required this.points});
  final int points;

  @override
  State<_MiniScoreRing> createState() => _MiniScoreRingState();
}

class _MiniScoreRingState extends State<_MiniScoreRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _prog;

  static const _base = 0.317;
  static const _boost = 0.04;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _prog = Tween<double>(begin: _base, end: _base + _boost)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _prog,
      builder: (context, child) => SizedBox(
        width: 72, height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 72, height: 72,
              child: CircularProgressIndicator(
                value: _prog.value,
                strokeWidth: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B4A)),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AP',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '230',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9, color: const Color(0xFFFF6B4A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Music — data + picker sheet
// ---------------------------------------------------------------------------

class _SelectedMusic {
  const _SelectedMusic({required this.title, required this.artist, required this.url});
  final String title;
  final String artist;
  final String url;
}

const _kMusicTracks = <(String, String, String)>[
  ('Midnight Drive', 'Neon Skyline', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'),
  ('Summer Haze', 'Vista Dreams', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3'),
  ('Golden Hour', 'Atlas & Co.', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3'),
  ('City Lights', 'The Wanderers', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3'),
  ('Ocean Floor', 'Deep Blue', 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3'),
];

class _MusicPickerSheet extends StatefulWidget {
  const _MusicPickerSheet();

  @override
  State<_MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<_MusicPickerSheet> {
  final _player = AudioPlayer();
  int? _playingIdx;

  @override
  void initState() {
    super.initState();
    _player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      android: AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: false,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain,
      ),
    ));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(int idx) async {
    try {
      if (_playingIdx == idx) {
        await _player.pause();
        setState(() => _playingIdx = null);
      } else {
        await _player.play(UrlSource(_kMusicTracks[idx].$3));
        setState(() => _playingIdx = idx);
        _player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _playingIdx = null);
        });
      }
    } catch (_) {}
  }

  void _pickTrack(int idx) async {
    await _player.stop();
    if (!mounted) return;
    final t = _kMusicTracks[idx];
    Navigator.of(context).pop(_SelectedMusic(title: t.$1, artist: t.$2, url: t.$3));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Text(
                    'Add music',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 15),
                    ),
                  ),
                ],
              ),
            ),
            ...List.generate(_kMusicTracks.length, (i) {
              final (title, artist, _) = _kMusicTracks[i];
              final isPlaying = _playingIdx == i;
              return GestureDetector(
                onTap: () => _pickTrack(i),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _togglePreview(i),
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: isPlaying ? 0.18 : 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                            Text(artist, style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.50))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Text('Use', style: GoogleFonts.inter(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              );
            }),
            SizedBox(height: bottomPad + 12),
          ],
        ),
      ),
    );
  }
}

