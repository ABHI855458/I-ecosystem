import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:deepar_flutter_plus/deepar_flutter_plus.dart';
// CameraDirection isn't re-exported by the package's own barrel file
// (deepar_flutter_plus.dart only exports deep_ar_controller_plus.dart,
// which imports — but doesn't export — utils.dart, where the enum actually
// lives) — checked the installed package source directly, not a guess.
import 'package:deepar_flutter_plus/src/utils.dart' show CameraDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../notifications/notifications_screen.dart';
import '../../core/glass.dart';
import '../../services/camera_prefs_service.dart';
import '../../services/current_user_service.dart';
import '../../services/deepar_service.dart';
import '../../services/post_service.dart';
import '../../services/prompt_service.dart';
import '../../core/supabase_config.dart';
import '../../screens/feed/widgets/anon_post_card_clipper.dart';
import 'deepar_filter_strip.dart';

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

/// Composites [back] and [front] into one flattened image for upload —
/// whichever of the two is NOT [frontIsBig] is the full-bleed background,
/// the other is the rounded, white-bordered inset bubble pinned to the
/// top-left corner (matching design-refs/camera feature's fixed PiP
/// position — no drag-to-corner). Mirrors exactly what _CandidMediaPreview
/// shows on the confirm screen, so the posted photo matches whatever the
/// user last arranged. Deferred to send time (not capture time) so the
/// confirm screen can show both raw photos live instead of a pre-flattened
/// image.
Future<XFile> _compositeDualPhotos(
  XFile back,
  XFile front, {
  required bool frontIsBig,
}) async {
  try {
    final bigFile = frontIsBig ? front : back;
    final smallFile = frontIsBig ? back : front;
    final bigBytes = await File(bigFile.path).readAsBytes();
    final smallBytes = await File(smallFile.path).readAsBytes();

    final bigCodec = await ui.instantiateImageCodec(bigBytes);
    final smallCodec = await ui.instantiateImageCodec(smallBytes);
    final bigImg = (await bigCodec.getNextFrame()).image;
    final smallImg = (await smallCodec.getNextFrame()).image;

    final w = bigImg.width.toDouble();
    final h = bigImg.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(bigImg, Offset.zero, Paint());

    final bubbleW = w * 0.28;
    final bubbleH = bubbleW * smallImg.height / smallImg.width;
    const margin = 24.0;
    const borderWidth = 4.0;
    const left = margin;
    const top = margin;
    final bubbleRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, bubbleW, bubbleH),
      const Radius.circular(18),
    );

    canvas.drawRRect(
      bubbleRRect.shift(const Offset(0, 3)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
    );

    canvas.save();
    canvas.clipRRect(bubbleRRect);
    canvas.drawImageRect(
      smallImg,
      Rect.fromLTWH(0, 0, smallImg.width.toDouble(), smallImg.height.toDouble()),
      Rect.fromLTWH(left, top, bubbleW, bubbleH),
      Paint(),
    );
    canvas.restore();

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

    bigImg.dispose();
    smallImg.dispose();

    final dir = File(back.path).parent;
    final path = '${dir.path}/dual_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(pngData!.buffer.asUint8List());
    return XFile(path);
  } catch (_) {
    return back;
  }
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class ComposerScreen extends StatefulWidget {
  const ComposerScreen({
    super.key,
    this.testPhase,
    this.testAnonymous = false,
    this.testBackPhotoPath,
    this.testFrontPhotoPath,
  });

  final ComposerPhase? testPhase;
  final bool testAnonymous;
  // Screenshot-mode-only: preloads the dual-photo confirm preview without
  // a real camera capture. See main.dart's _ScreenshotRoot.
  final String? testBackPhotoPath;
  final String? testFrontPhotoPath;

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  late ComposerPhase _phase;
  late bool _isAnonymous;
  XFile? _capturedPhoto;

  // Dual-mode result: kept as two RAW files (not composited) until send
  // time, so the confirm screen can show an interactive, repositionable
  // front-inset preview (_CandidMediaPreview) instead of a pre-flattened
  // image. Null in single-camera mode — _capturedPhoto is used there.
  XFile? _capturedBackPhoto;
  XFile? _capturedFrontPhoto;

  // Real DeepAR AR camera pipeline (replaces the old plain `camera`-package
  // CameraController) — one shared singleton session (DeepArService.instance)
  // for the whole screen's lifetime. Unlike the old per-direction
  // CameraController (which had to be fully disposed and recreated to swap
  // front/back — see the old comment this replaced), DeepAR's controller
  // manages one native session internally and exposes direction-flipping
  // (flipCamera()) as a first-class op, so no dispose/reinit dance is needed
  // for either manual swap or the dual-capture back->front sequence.
  bool _cameraReady = false;
  // True as soon as DeepAR's own initialize() succeeds — separate from
  // _cameraReady (which only flips true once flipCamera() has ALSO
  // finished). Controls whether _CameraViewfinder actually mounts
  // DeepArPreviewPlus. This split exists because of a real circular
  // dependency on iOS: the native texture (_textureId, what
  // controller.isInitialized checks) is only set inside
  // DeepArPreviewPlus's own UiKitView.onPlatformViewCreated callback — i.e.
  // the preview widget has to actually be BUILT before the controller can
  // ever report itself ready. Gating the preview's mounting behind
  // _cameraReady (which itself waits on isInitialized) was a deadlock that
  // could never resolve — reproduced live on-device as "camera opens but
  // nothing ever appears, no picture, no filters." _previewMounted breaks
  // the cycle: mount the preview immediately on init success, THEN wait for
  // isInitialized (now able to actually become true), THEN flip camera,
  // THEN flip _cameraReady to reveal the filter strip/shutter.
  bool _previewMounted = false;
  String? _cameraError;
  bool _usingRear = true;
  bool _cameraSwapping = false;
  // Owned by DeepArFilterStrip now (see deepar_filter_strip.dart) — this
  // screen just mirrors the live label for its top-of-card pill and holds a
  // key to trigger the capture flash, it no longer tracks/applies lenses
  // itself (that used to be _activeLens/_selectLens/_clearLens).
  String _activeFilterLabel = 'NO FILTER';
  final _flashKey = GlobalKey<CaptureFlashOverlayState>();
  _SelectedMusic? _selectedMusic;

  // ── Dual camera (BeReal-style back+front) ───────────────────────────────
  bool _dualCameraEnabled = false;
  _DualStep _dualStep = _DualStep.back;
  XFile? _pendingBackPhoto;
  bool _frontCapturing = false;
  String? _frontCaptureError;

  @override
  void initState() {
    super.initState();
    final p = widget.testPhase;
    _phase = (p == ComposerPhase.confirm) ? ComposerPhase.send : (p ?? ComposerPhase.camera);
    _isAnonymous = widget.testAnonymous;
    if (widget.testBackPhotoPath != null && widget.testFrontPhotoPath != null) {
      _capturedBackPhoto = XFile(widget.testBackPhotoPath!);
      _capturedFrontPhoto = XFile(widget.testFrontPhotoPath!);
    }
    if (_phase == ComposerPhase.camera) _bootstrapCamera();
  }

  @override
  void dispose() {
    // Fire-and-forget, matching the pattern the DeepAR service's own
    // original standalone screen used — destroy() is idempotent and safe to
    // call unawaited (checked package source: it no-ops if already
    // destroyed/destroying), and the next screen to call
    // initializeWithDefaults() safely re-initializes regardless of whether
    // this completes first.
    DeepArService.instance.dispose();
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
    await _initDeepAr();
  }

  Future<void> _toggleDualCamera() async {
    HapticFeedback.selectionClick();
    final next = !_dualCameraEnabled;
    setState(() => _dualCameraEnabled = next);
    await CameraPrefsService.setDualCameraEnabled(next);
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  /// Which lenses this screen offers — Anonymous posts get the face-masking
  /// set (matches the whole point of DeepArLens.anonymousMaskOne/Two);
  /// non-anonymous posting has no dedicated lens category of its own, so it
  /// reuses the ping filter set as a reasonable placeholder rather than
  /// inventing a third unbacked category.
  List<DeepArLens> get _lensSet => _isAnonymous
      ? const [DeepArLens.anonymousMaskOne, DeepArLens.anonymousMaskTwo]
      : const [DeepArLens.pingFilterOne, DeepArLens.pingFilterTwo];

  Future<void> _initDeepAr() async {
    final result = await DeepArService.instance.initializeWithDefaults();
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _previewMounted = false;
        _cameraReady = false;
        _cameraError = result.message;
      });
      return;
    }
    // Mount the preview NOW, before waiting for isInitialized — on iOS the
    // native texture is only set inside this very widget's own
    // onPlatformViewCreated callback, so waiting for "ready" before showing
    // it can never resolve. See _previewMounted's own doc for the full
    // reasoning; this was a real, reproduced-on-device deadlock.
    setState(() => _previewMounted = true);
    // Must wait for the native view to actually exist before touching the
    // controller further — see waitUntilViewReady's own doc for the real
    // on-device crash this prevents (iOS-specific, harmless/instant no-op
    // on Android where the texture is already set synchronously).
    final ready = await DeepArService.instance.waitUntilViewReady();
    if (!mounted) return;
    if (!ready) {
      setState(() {
        _previewMounted = false;
        _cameraReady = false;
        _cameraError = "Camera didn't finish starting — try again.";
      });
      return;
    }
    // DeepAR always starts on the FRONT camera after init/destroy (checked
    // package source: _resetState() hardcodes CameraDirection.front) — flip
    // once to match this app's existing rear-first default for both single
    // and dual capture mode.
    await DeepArService.instance.controller.flipCamera();
    if (!mounted) return;
    setState(() {
      _cameraReady = true;
      _cameraError = null;
      _usingRear = true;
    });
  }

  Future<void> _swapCamera() async {
    // Manual swap only applies to single-camera mode — in dual mode the
    // back->front sequence is fully automatic (see _captureBackShot).
    if (_cameraSwapping || _dualCameraEnabled || !_cameraReady) return;
    setState(() => _cameraSwapping = true);
    try {
      final dir = await DeepArService.instance.controller.flipCamera();
      if (!mounted) return;
      setState(() {
        _usingRear = dir == CameraDirection.rear;
        _cameraSwapping = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cameraSwapping = false);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    _flashKey.currentState?.flash();
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
      if (_cameraReady) {
        final file = await DeepArService.instance.controller.takeScreenshot();
        image = XFile(file.path);
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

  /// Dual camera ON, step 1: capture the back photo, then flip to front —
  /// unlike the old plain-`camera`-package flow, DeepAR's single session
  /// handles this via flipCamera() instead of a full dispose+recreate (see
  /// the state-fields comment above for why that dance existed originally
  /// and why it's no longer needed).
  Future<void> _captureBackShot() async {
    if (!_cameraReady) return;
    HapticFeedback.mediumImpact();
    try {
      final file = await DeepArService.instance.controller.takeScreenshot();
      final backPhoto = XFile(file.path);
      if (!mounted) return;
      setState(() {
        _pendingBackPhoto = backPhoto;
        _dualStep = _DualStep.front;
      });
      await _switchToFrontForDualCapture();
    } catch (_) {
      // Back shot failed — nothing captured yet, camera stays as-is so the
      // user can just tap the shutter again.
    }
  }

  /// Dual camera ON, step 2 setup: flips the already-live session to the
  /// front camera (no new controller to create — see _captureBackShot).
  Future<void> _switchToFrontForDualCapture() async {
    try {
      final dir = await DeepArService.instance.controller.flipCamera();
      if (!mounted) return;
      setState(() {
        _usingRear = dir == CameraDirection.rear;
        _frontCaptureError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _frontCaptureError = "Couldn't start the front camera.");
    }
  }

  /// Dual camera ON, step 3: capture the front photo. Composting is
  /// deferred to send time (see _compositeDualPhotos) — the confirm screen
  /// shows both raw photos live so the front inset stays draggable/
  /// tappable there instead of already being baked into a flat image. If
  /// this throws, the front controller is left exactly as it was (still
  /// live, still previewing) and _pendingBackPhoto is untouched, so the
  /// shutter staying tappable IS the retry path — nothing extra to wire up.
  Future<void> _captureFrontShot() async {
    if (!_cameraReady || _frontCapturing || _pendingBackPhoto == null) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _frontCapturing = true;
      _frontCaptureError = null;
    });
    try {
      final file = await DeepArService.instance.controller.takeScreenshot();
      final frontPhoto = XFile(file.path);
      if (!mounted) return;
      setState(() {
        _frontCapturing = false;
        _capturedBackPhoto = _pendingBackPhoto;
        _capturedFrontPhoto = frontPhoto;
        _pendingBackPhoto = null;
        _phase = ComposerPhase.send;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _frontCapturing = false;
        _frontCaptureError = "Couldn't capture the front shot — try again.";
      });
    }
  }

  /// Escape hatch for when the front camera genuinely isn't available —
  /// use the already-captured back photo alone rather than strand the user
  /// with no way to finish posting.
  void _useBackPhotoOnly() {
    final back = _pendingBackPhoto;
    if (back == null) return;
    setState(() {
      _capturedPhoto = back;
      _pendingBackPhoto = null;
      _frontCaptureError = null;
      _phase = ComposerPhase.send;
    });
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
      _capturedBackPhoto = null;
      _capturedFrontPhoto = null;
    });
    // No reinit needed — unlike the old CameraController (disposed after
    // every dual-flow front shot, so returning to the camera phase had to
    // recreate it), DeepAR's single session stays live for this whole
    // screen's lifetime; _cameraReady/_usingRear already reflect its
    // current real state.
  }

  /// Throws on failure (auth not resolved, image upload failed, or the
  /// posts insert was rejected) — the caller (_SendInterface's send button)
  /// catches this to show the real error and let the user retry, instead of
  /// silently pretending the post went through.
  Future<void> _send(String caption, double aspectRatio, XFile? photo) async {
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
        // posts.id is a UUID column — a millisecond-timestamp string
        // ("1786590070107") was being rejected outright by Postgres
        // (22P02 invalid input syntax for type uuid), failing every real
        // post insert. Same generator group_service.dart/memory_service.dart
        // etc. already use for their own client-generated ids.
        id: const Uuid().v4(),
        userId: userId,
        username: username,
        visibility: _isAnonymous ? 'anonymous' : 'everyone',
        caption: caption,
        photoPath: photo?.path,
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
                      cameraReady: _cameraReady,
                      previewMounted: _previewMounted,
                      cameraError: _cameraError,
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
                      lenses: _lensSet,
                      activeFilterLabel: _activeFilterLabel,
                      onActiveFilterLabelChanged: (l) => setState(() => _activeFilterLabel = l),
                      flashKey: _flashKey,
                    ),
                  ComposerPhase.send || ComposerPhase.confirm => _SendInterface(
                      key: const ValueKey('send'),
                      photo: _capturedPhoto,
                      backPhoto: _capturedBackPhoto,
                      frontPhoto: _capturedFrontPhoto,
                      isAnonymous: _isAnonymous,
                      selectedMusic: _selectedMusic,
                      onAnonChanged: (v) => setState(() => _isAnonymous = v),
                      onBack: _backToCamera,
                      onSend: _send,
                      onMusicChanged: (m) => setState(() => _selectedMusic = m),
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
    required this.cameraReady,
    required this.previewMounted,
    required this.cameraError,
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
    required this.lenses,
    required this.activeFilterLabel,
    required this.onActiveFilterLabelChanged,
    required this.flashKey,
  });

  final bool cameraReady;
  final bool previewMounted;
  final String? cameraError;
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
  final List<DeepArLens> lenses;
  final String activeFilterLabel;
  final ValueChanged<String> onActiveFilterLabelChanged;
  final GlobalKey<CaptureFlashOverlayState> flashKey;

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
          // ── Camera area fills the rest ────────────────────────────────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera viewfinder
                _CameraViewfinder(ready: previewMounted, error: cameraError),

                // Capture flash — brief white opacity pulse, triggered by
                // the parent's _capture() via flashKey.
                Positioned.fill(child: CaptureFlashOverlay(key: flashKey)),

                // Active filter name pill — top-center, only shown when it
                // won't collide with the front-step spinner/error banner
                // (same visibility gating those already use).
                if (cameraReady && !(_inFrontStep && frontCapturing) && frontCaptureError == null)
                  Positioned(
                    top: 14,
                    left: 60,
                    right: 60,
                    child: Center(child: ActiveFilterPill(label: activeFilterLabel)),
                  ),

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

                // Filter strip + shutter ring — replaces the old separate
                // DeepArLensPicker (was bottom:100) and _ShutterBtn (was the
                // center child of the [←][●][···] row). The ring is the
                // strip's own fixed center, landing in the same visual spot
                // the old shutter used to (between the still-present back/
                // gallery buttons), so no manual width math is needed to
                // keep them aligned — both live in one Stack, vertically
                // centered by the Stack's own alignment. Back/gallery stay
                // visible even when the camera ISN'T ready (unlike the strip
                // itself, which needs a live DeepAR session) — matches the
                // old unconditional bottom-controls row, so a camera error
                // still leaves the user a way to close or fall back to the
                // gallery.
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  height: 118, // matches DeepArFilterStrip's own height
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (cameraReady)
                        DeepArFilterStrip(
                          lenses: lenses,
                          onCapture: onCapture,
                          onActiveLabelChanged: onActiveFilterLabelChanged,
                        ),
                      Positioned(
                        left: 24,
                        child: _SmallCircleBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onClose, size: 44, iconSize: 16),
                      ),
                      Positioned(
                        right: 24,
                        child: _SmallCircleBtn(icon: Icons.more_horiz_rounded, onTap: onGallery, size: 44, iconSize: 20),
                      ),
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
    this.backPhoto,
    this.frontPhoto,
    this.selectedMusic,
    this.onMusicChanged,
  });

  final XFile? photo;
  // Dual-camera capture — when both are non-null, the media preview shows
  // the interactive front inset (_CandidMediaPreview) instead of the single
  // flattened photo.
  final XFile? backPhoto;
  final XFile? frontPhoto;
  final bool isAnonymous;
  final ValueChanged<bool> onAnonChanged;
  final VoidCallback onBack;
  final Future<void> Function(String caption, double aspectRatio, XFile? photo) onSend;
  final _SelectedMusic? selectedMusic;
  final ValueChanged<_SelectedMusic?>? onMusicChanged;

  @override
  State<_SendInterface> createState() => _SendInterfaceState();
}

enum _SheetKind { groups, audience, music }

// Mock recipients list — matches design-refs/camera feature's static
// GROUPS sample exactly. Purely a UI shell (selection is local, not
// persisted/posted): real group/community backing was explicitly deferred
// earlier ("hold off on groups — I'll provide a separate design for group
// posts/profile shortly"), so this chip/sheet exists for visual parity with
// the reference design without wiring up group posting.
const _kGroups = <(String id, String kind, String name, String meta)>[
  ('roommates', 'group', 'Roommates', 'Group · 4 people'),
  ('circle', 'group', 'Close circle', 'Group · 8 people'),
  ('film', 'community', 'Film Club', 'Community · 812 members'),
  ('runners', 'community', 'Dawn Runners', 'Community · 2.1k members'),
  ('following', 'following', 'People you follow', '126 accounts'),
];

const _kAudiences = <String>[
  'My friends only',
  'Friends of friends',
  'Everyone',
  'Anonymous',
];
const _kAudienceShort = <String, String>{
  'My friends only': 'My Friends',
  'Friends of friends': 'Friends+',
  'Everyone': 'Everyone',
  'Anonymous': 'Anon',
};

const _kAccentLime = Color(0xFFD8FF3E);

class _SendInterfaceState extends State<_SendInterface> {
  final _captionCtrl = TextEditingController();
  bool _sending = false;
  double _selectedRatio = 4.0 / 5.0;
  final _musicPlayer = AudioPlayer();
  int? _musicPreviewIdx;

  // Front-inset state (dual-camera mode only) — which shot is currently the
  // big background. Composited into one flattened image at send time. The
  // reference design pins the inset to the top-left corner only (no drag).
  bool _frontIsBig = false;

  // "Send it to" sheet — cosmetic-only selection, see _kGroups above.
  final Set<String> _pickedGroupIds = {};

  // Audience — only 'Everyone' and 'Anonymous' change real posting
  // behavior (widget.onAnonChanged); the two friends-scoped tiers don't
  // have backend support yet, so they're selectable for visual parity with
  // the reference design but currently post as 'Everyone' under the hood.
  late String _audience = widget.isAnonymous ? 'Anonymous' : 'Everyone';

  String _musicQuery = '';
  _SheetKind? _openSheetKind;

  @override
  void dispose() {
    _captionCtrl.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  void _openSheet(_SheetKind k) {
    HapticFeedback.selectionClick();
    _musicPlayer.stop();
    setState(() {
      _musicPreviewIdx = null;
      _openSheetKind = k;
    });
  }

  void _closeSheet() {
    _musicPlayer.stop();
    setState(() {
      _musicPreviewIdx = null;
      _openSheetKind = null;
    });
  }

  void _pickAudience(String a) {
    setState(() => _audience = a);
    widget.onAnonChanged(a == 'Anonymous');
    _closeSheet();
  }

  void _toggleGroup(String id) {
    setState(() {
      if (_pickedGroupIds.contains(id)) {
        _pickedGroupIds.remove(id);
      } else {
        _pickedGroupIds.add(id);
      }
    });
  }

  String? get _groupsChipLabel {
    if (_pickedGroupIds.isEmpty) return null;
    if (_pickedGroupIds.length == 1) {
      final id = _pickedGroupIds.first;
      return _kGroups.firstWhere((g) => g.$1 == id).$3;
    }
    return '${_pickedGroupIds.length} groups';
  }

  Future<void> _toggleMusicPreview(int idx) async {
    try {
      if (_musicPreviewIdx == idx) {
        await _musicPlayer.pause();
        setState(() => _musicPreviewIdx = null);
      } else {
        await _musicPlayer.play(UrlSource(_kMusicTracks[idx].$3));
        setState(() => _musicPreviewIdx = idx);
        _musicPlayer.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _musicPreviewIdx = null);
        });
      }
    } catch (_) {}
  }

  void _pickTrack(int idx) {
    _musicPlayer.stop();
    final t = _kMusicTracks[idx];
    widget.onMusicChanged?.call(_SelectedMusic(title: t.$1, artist: t.$2, url: t.$3));
    _closeSheet();
  }

  void _clearMusic() {
    widget.onMusicChanged?.call(null);
    _closeSheet();
  }

  @override
  Widget build(BuildContext context) {
    final isDual = widget.backPhoto != null && widget.frontPhoto != null;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(48)),
      child: Container(
        color: const Color(0xFF0D0D0F),
        child: LayoutBuilder(
          builder: (context, hostBc) {
            return Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header — dismiss chevron, no title ──────────────
                    SizedBox(
                      height: 58,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 14,
                            top: 5,
                            child: GestureDetector(
                              onTap: widget.onBack,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Caption field ────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                      child: TextField(
                        controller: _captionCtrl,
                        style: GoogleFonts.archivo(
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.01 * 21,
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Add a caption...',
                          hintStyle: GoogleFonts.archivo(
                            fontSize: 21,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.01 * 21,
                            color: Colors.white.withValues(alpha: 0.42),
                          ),
                        ),
                      ),
                    ),

                    if (!isDual) ...[
                      _RatioPicker(
                        selected: _selectedRatio,
                        onChanged: (r) => setState(() => _selectedRatio = r),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Photo card ───────────────────────────────────────
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Container(
                            color: const Color(0xFF1A1A1C),
                            child: isDual
                                ? _CandidMediaPreview(
                                    backPhoto: widget.backPhoto!,
                                    frontPhoto: widget.frontPhoto!,
                                    isAnonymous: widget.isAnonymous,
                                    frontIsBig: _frontIsBig,
                                    onToggleBig: () => setState(() => _frontIsBig = !_frontIsBig),
                                    tray: _buildChipTray(),
                                  )
                                : LayoutBuilder(
                                    builder: (ctx, bc) {
                                      final aW = bc.maxWidth;
                                      final aH = bc.maxHeight;
                                      var pW = aW;
                                      var pH = aW / _selectedRatio;
                                      if (pH > aH) {
                                        pH = aH;
                                        pW = aH * _selectedRatio;
                                      }
                                      return Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Center(
                                            child: SizedBox(
                                              width: pW,
                                              height: pH,
                                              child: widget.isAnonymous
                                                  ? ClipPath(
                                                      clipper: const AnonPostCardClipper(),
                                                      child: _buildPhotoView(),
                                                    )
                                                  : _buildPhotoView(),
                                            ),
                                          ),
                                          _buildChipTray(),
                                        ],
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),

                    // ── Send — kept as this app's own pill button (white
                    // boundary/halo), not the reference design's giant
                    // text+triangle treatment.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: GestureDetector(
                        onTap: _sending
                            ? null
                            : () async {
                                setState(() => _sending = true);
                                try {
                                  XFile? finalPhoto = widget.photo;
                                  if (isDual) {
                                    finalPhoto = await _compositeDualPhotos(
                                      widget.backPhoto!,
                                      widget.frontPhoto!,
                                      frontIsBig: _frontIsBig,
                                    );
                                  }
                                  await widget.onSend(_captionCtrl.text.trim(), _selectedRatio, finalPhoto);
                                } catch (e, st) {
                                  debugPrint('[Composer] Post failed: $e\n$st');
                                  if (!mounted) return;
                                  setState(() => _sending = false);
                                  if (!context.mounted) return;
                                  showGlassToast(context, 'Failed to post: $e', isError: true);
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

                // ── Scrim + bottom sheet overlay ────────────────────────
                if (_openSheetKind != null) ...[
                  _SheetScrim(onTap: _closeSheet),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 0,
                    child: _SheetSlideIn(
                      key: ValueKey(_openSheetKind),
                      child: _DraggableSheet(
                        hostHeight: hostBc.maxHeight,
                        onClose: _closeSheet,
                        title: switch (_openSheetKind!) {
                          _SheetKind.groups => 'Send it to',
                          _SheetKind.audience => 'Select your audience',
                          _SheetKind.music => 'Add a sound',
                        },
                        trailing: switch (_openSheetKind!) {
                          _SheetKind.groups => GestureDetector(
                              onTap: _closeSheet,
                              child: Text('Done',
                                  style: GoogleFonts.archivo(
                                      fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.01 * 15, color: _kAccentLime)),
                            ),
                          _SheetKind.music => widget.selectedMusic != null
                              ? GestureDetector(
                                  onTap: _clearMusic,
                                  child: Text('Remove',
                                      style: GoogleFonts.archivo(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.01 * 15,
                                          color: Colors.white.withValues(alpha: 0.6))),
                                )
                              : null,
                          _SheetKind.audience => null,
                        },
                        child: switch (_openSheetKind!) {
                          _SheetKind.groups => _buildGroupsSheet(),
                          _SheetKind.audience => _buildAudienceSheet(),
                          _SheetKind.music => _buildMusicSheet(),
                        },
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Chip tray — bottom-of-photo gradient strip with the 3 chips ────────
  Widget _buildChipTray() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 46, 10, 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0x8C000000), Color(0x00000000)],
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            _ComposerChip(
              icon: Icons.groups_2_rounded,
              label: _groupsChipLabel,
              accented: true,
              onTap: () => _openSheet(_SheetKind.groups),
            ),
            _ComposerChip(
              icon: Icons.group_rounded,
              label: _kAudienceShort[_audience],
              accented: false,
              onTap: () => _openSheet(_SheetKind.audience),
            ),
            _ComposerChip(
              icon: Icons.music_note_rounded,
              label: widget.selectedMusic?.title,
              accented: true,
              onTap: () => _openSheet(_SheetKind.music),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsSheet() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _kGroups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final (id, kind, name, meta) = _kGroups[i];
        final icon = switch (kind) {
          'group' => Icons.group_rounded,
          'community' => Icons.diversity_3_rounded,
          _ => Icons.person_add_alt_1_rounded,
        };
        return _SheetRow(
          icon: icon,
          title: name,
          subtitle: meta,
          selected: _pickedGroupIds.contains(id),
          onTap: () => _toggleGroup(id),
        );
      },
    );
  }

  Widget _buildAudienceSheet() {
    const subtitles = <String, String>{
      'My friends only': 'Visible till the next window closes',
      'Friends of friends': 'One hop past your circle',
      'Everyone': 'Anyone can see it on your profile',
      'Anonymous': 'Posted without your name attached',
    };
    const icons = <String, IconData>{
      'My friends only': Icons.group_rounded,
      'Friends of friends': Icons.diversity_3_rounded,
      'Everyone': Icons.public_rounded,
      'Anonymous': Icons.masks_rounded,
    };
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _kAudiences.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = _kAudiences[i];
        return _SheetRow(
          icon: icons[a]!,
          title: a,
          subtitle: subtitles[a]!,
          selected: _audience == a,
          onTap: () => _pickAudience(a),
        );
      },
    );
  }

  Widget _buildMusicSheet() {
    final q = _musicQuery.trim().toLowerCase();
    final filtered = <int>[
      for (var i = 0; i < _kMusicTracks.length; i++)
        if (q.isEmpty || '${_kMusicTracks[i].$1} ${_kMusicTracks[i].$2}'.toLowerCase().contains(q)) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(23),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 17, color: Colors.white.withValues(alpha: 0.55)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _musicQuery = v),
                  style: GoogleFonts.archivo(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search songs',
                    hintStyle: GoogleFonts.archivo(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.42)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final i = filtered[idx];
              final (title, artist, _) = _kMusicTracks[i];
              final selected = widget.selectedMusic?.url == _kMusicTracks[i].$3;
              final previewing = _musicPreviewIdx == i;
              return GestureDetector(
                onTap: () => _pickTrack(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _toggleMusicPreview(i),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _kAccentLime.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            previewing ? Icons.pause_rounded : Icons.music_note_rounded,
                            color: _kAccentLime,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.archivo(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.01 * 17, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text(artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.archivo(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.45))),
                          ],
                        ),
                      ),
                      selected
                          ? Container(
                              width: 26, height: 26,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Icon(Icons.check, size: 14, color: Colors.black),
                            )
                          : Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.32), width: 2),
                              ),
                            ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
      img = ColorFiltered(colorFilter: _kGreyscaleFilter, child: img);
    }
    return img;
  }
}

/// Greyscale matrix used to preview how an Anonymous post's photo will
/// render (photo_post_card.dart applies the same treatment feed-side).
const _kGreyscaleFilter = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0,      0,      0,      1, 0,
]);

// ---------------------------------------------------------------------------
// Dual-photo preview — design-refs/camera feature's "Photo card" anatomy:
// full-bleed big photo, a small rounded/bordered inset for the other shot
// pinned to the top-left corner (tap swaps which is big — the reference
// design has no drag-to-corner), plus a tray slot for the caller's chip row.
// ---------------------------------------------------------------------------

class _CandidMediaPreview extends StatelessWidget {
  const _CandidMediaPreview({
    required this.backPhoto,
    required this.frontPhoto,
    required this.isAnonymous,
    required this.frontIsBig,
    required this.onToggleBig,
    required this.tray,
  });

  final XFile backPhoto;
  final XFile frontPhoto;
  final bool isAnonymous;
  final bool frontIsBig;
  final VoidCallback onToggleBig;
  final Widget tray;

  static const _insetW = 112.0;
  static const _insetH = 158.0;
  static const _margin = 14.0;

  Widget _photo(XFile file) {
    Widget img = Image.file(
      File(file.path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
    if (isAnonymous) {
      img = ColorFiltered(colorFilter: _kGreyscaleFilter, child: img);
    }
    return img;
  }

  @override
  Widget build(BuildContext context) {
    final bigFile = frontIsBig ? frontPhoto : backPhoto;
    final smallFile = frontIsBig ? backPhoto : frontPhoto;

    return Stack(
      children: [
        Positioned.fill(child: _photo(bigFile)),
        Positioned(
          left: _margin,
          top: _margin,
          child: GestureDetector(
            onTap: onToggleBig,
            child: Container(
              width: _insetW,
              height: _insetH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _photo(smallFile),
            ),
          ),
        ),
        tray,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chip tray button — design-refs/camera feature's chip shell: translucent
// blurred pill, icon + optional label (label hidden entirely when null,
// lime when [accented] and a value is set, white otherwise).
// ---------------------------------------------------------------------------

class _ComposerChip extends StatelessWidget {
  const _ComposerChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accented,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: Colors.white),
                if (label != null) ...[
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 104),
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivo(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01 * 15,
                        color: accented ? _kAccentLime : Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet scrim + entry slide, shared by all 3 sheets.
// ---------------------------------------------------------------------------

class _SheetScrim extends StatelessWidget {
  const _SheetScrim({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: ClipRRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetSlideIn extends StatelessWidget {
  const _SheetSlideIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Offset>(
      tween: Tween(begin: const Offset(0, 1), end: Offset.zero),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) => FractionalTranslation(translation: offset, child: child),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Draggable bottom sheet shell — peek (34% of host height) / full (82%)
// detents, matching design-refs/camera feature's drag physics.
// ---------------------------------------------------------------------------

class _DraggableSheet extends StatefulWidget {
  const _DraggableSheet({
    required this.title,
    required this.hostHeight,
    required this.onClose,
    required this.child,
    this.trailing,
  });

  final String title;
  final double hostHeight;
  final VoidCallback onClose;
  final Widget child;
  final Widget? trailing;

  @override
  State<_DraggableSheet> createState() => _DraggableSheetState();
}

class _DraggableSheetState extends State<_DraggableSheet> {
  double? _height;
  bool _dragging = false;
  double _dragStartY = 0;
  double _dragStartHeight = 0;

  double get _peek => widget.hostHeight * 0.34;
  double get _full => widget.hostHeight * 0.82;

  @override
  Widget build(BuildContext context) {
    final h = _height ?? _peek;
    return AnimatedContainer(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      height: h,
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) {
                _dragStartY = d.globalPosition.dy;
                _dragStartHeight = h;
                setState(() => _dragging = true);
              },
              onVerticalDragUpdate: (d) {
                final dy = _dragStartY - d.globalPosition.dy;
                setState(() => _height = (_dragStartHeight + dy).clamp(_peek * 0.55, _full));
              },
              onVerticalDragEnd: (_) {
                final cur = _height ?? _peek;
                setState(() {
                  _dragging = false;
                  if (cur < _peek * 0.75) {
                    widget.onClose();
                  } else {
                    _height = cur > (_peek + _full) / 2 ? _full : _peek;
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    widget.title,
                    style: GoogleFonts.archivo(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.02 * 20, color: Colors.white),
                  ),
                  if (widget.trailing != null) Positioned(right: 2, child: widget.trailing!),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet list row — shared by the groups and audience sheets.
// ---------------------------------------------------------------------------

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivo(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.01 * 17, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivo(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.45))),
                ],
              ),
            ),
            selected
                ? Container(
                    width: 26, height: 26,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 14, color: Colors.black),
                  )
                : Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.32), width: 2),
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
  const _CameraViewfinder({required this.ready, this.error});

  final bool ready;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (ready) {
      final ctrl = DeepArService.instance.controller;
      // DeepArPreviewPlus already self-sizes via an internal
      // AspectRatio(1 / ctrl.aspectRatio) — i.e. its own natural box has
      // width/height == 1/ctrl.aspectRatio (portrait, since aspectRatio
      // itself is width/height). Wrapping that same ratio in an explicit
      // finite SizedBox lets FittedBox(cover) crop-fill the whole
      // viewfinder, matching the old CameraPreview's full-bleed behavior
      // instead of DeepArPreviewPlus's own letterboxed centering.
      final ratio = ctrl.aspectRatio;
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 1000 / ratio,
            height: 1000,
            child: DeepArPreviewPlus(ctrl),
          ),
        ),
      );
    }
    return Container(
      color: const Color(0xFF0C0E12),
      child: Center(
        child: error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              )
            : Icon(
                Icons.camera_alt_outlined,
                color: Colors.white.withValues(alpha: 0.05),
                size: 72,
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

