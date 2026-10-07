import 'dart:async';
import '../../core/feature_flags.dart';
import '../../screens/onboarding/onboarding_duo_screen.dart'
    show maybeAskForFirstDuo;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../shared/volume_shutter.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

// FACE MASK FILTER: remove this block + every other `FACE MASK FILTER:`
// line in this file to fully remove the feature (see
// lib/features/face_filter/face_mask_presets.dart for the rest of the
// removal steps).
import '../face_filter/face_input_image_converter.dart';
import '../face_filter/face_mask_overlay.dart';
import '../../core/glass.dart';
import '../qr/qr_scanner_screen.dart';
import '../../core/ping_haptics.dart';
import '../../services/anon_persona_service.dart';
import '../../services/camera_prefs_service.dart';
import '../../services/circle_service.dart';
import '../../services/community_service.dart';
import '../../services/current_user_service.dart';
import '../../services/dip_service.dart';
import '../../services/group_service.dart';
import '../../services/moment_service.dart';
import '../../services/ping_service.dart';
import '../../services/storage_service.dart';
import '../../services/score_gain_service.dart';
import '../../services/post_service.dart';
import '../ping/ping_turns.dart';
import '../profile_v2/profile_v2_icons.dart';
import '../ping/score_reward_dropdown.dart';
import '../../screens/feed/widgets/moment_card.dart'
    show MomentPalette, kMomentPalettes, kMomentCaptionMaxChars;
import '../../services/content_moderation_service.dart';
import '../../services/prompt_service.dart';
import '../../shared/score_tier.dart';
import '../../core/supabase_config.dart';
import 'camera_capture_ui.dart';
import 'capture_widgets.dart';
import 'video_capture.dart';
import '../../widgets/app_video.dart';
import 'dual_photo_compositor.dart';

// ---------------------------------------------------------------------------
// Route — opaque:false, feed shows through, card slides up from bottom
// ---------------------------------------------------------------------------

/// [isAnonymous] sets the composer's STARTING mode (which lens set the
/// camera phase shows — masks vs. fun filters+beautification — see
/// ComposerScreen._lensSet) — the confirm screen's own Anon/Everyone toggle
/// still lets the poster override this before sending either way. Defaults
/// false (Everyone) for call sites with no tab context of their own.
///
/// [answeringPrompt]: the prompt this capture is a response to, when the
/// camera was opened from a prompt bar rather than the plain camera button.
/// It becomes the post's `posts.prompt` (the anon feed's peek-bar text), and
/// the composer hides its own heading field — the person already answered a
/// prompt, so asking them to invent a second one is redundant.
///
/// [lockToDipGroupId]: skips the same picker but pre-selects Group with
/// this id fixed — for the group profile's own Dip camera entry point,
/// which already knows which group it's posting to. See _send()'s
/// `_Destination.group` branch: Group now always creates a Dip (not a
/// `group_posts` row), so this and the main composer's Group pill both
/// funnel through the same code.
///
/// [lockToMomentPostId]: the Moments "Add yours" camera — one photo, no
/// caption, no pills, wired straight to that Moment as a reply
/// (`moment_replies`, via MomentService.addReply). It never creates a
/// `posts` row: a Moment reply lives inside its Moment and appears in no
/// feed. See _send()'s `_Destination.momentReply` branch.
///
/// The destination pill row therefore exists in exactly ONE place — the task
/// bar camera, the only entry point that passes none of these three flags.
/// Every other camera in the app is single-purpose.
Route<void> openCameraRoute({
  bool isAnonymous = false,
  String? answeringPrompt,
  String? answeringCommunityId,
  String? answeringPromptId,
  String? lockToDipGroupId,
  String? lockToMomentPostId,
  bool lockToAnonPost = false,
}) {
  return PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, anim, secAnim) => ComposerScreen(
      testAnonymous: isAnonymous,
      answeringPrompt: answeringPrompt,
      answeringCommunityId: answeringCommunityId,
      answeringPromptId: answeringPromptId,
      lockToDipGroupId: lockToDipGroupId,
      lockToMomentPostId: lockToMomentPostId,
      lockToAnonPost: lockToAnonPost,
    ),
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
}

/// The composer sheet's height, as a fraction of the screen — ONE value for
/// every phase, so the container the camera opens in is the same container
/// the compose step uses. Was 0.65 (camera) / 0.88 (send); 0.8125 is the
/// camera figure raised 25%.
const _kCardHeightFactor = 0.8125;

/// Where a capture is being sent. Picked with the pill row on the send card
/// — one screen, no extra route.
///
/// [group] and [moment] both still surface in the Everyone feed: a Moment is
/// an `everyone`-visibility post (rendered as the gradient MomentCard), and
/// group posts are merged into the same feed by FeedService.fetchGroupFeed.
///
/// [momentReply] is the exception: it is NOT a post at all. It is reachable
/// only through openCameraRoute's lockToMomentPostId (the Moments screen's
/// "Add yours"), never from the pill row, and writes a `moment_replies` row
/// instead of a `posts` row — see _send().
enum _Destination { anon, group, moment, momentReply }

/// Everything the send button collected, handed to the parent in one piece
/// so the routing (which table, which columns) lives in one place.
class _ComposerSubmission {
  const _ComposerSubmission({
    required this.dest,
    required this.caption,
    required this.aspectRatio,
    required this.photo,
    this.videoPath,
    this.videoMs,
    this.secondaryPhoto,
    this.extraPhotos = const [],
    this.prompt,
    this.communityId,
    this.promptId,
    this.groupId,
    this.momentColor,
    this.momentPostId,
    this.momentFriendsOnly = false,
    this.momentCommunityIds = const [],
    this.momentCircleIds = const [],
    this.momentAsAnon = false,
    this.momentReplyAsAnon = false,
    this.extraCommunityIds = const [],
    this.anonCircleIds = const [],
  });

  /// Anon only — circles this anon post also goes to (post_audiences
  /// 'circle' rows; posts_feed shows it to those circles' members, still
  /// masked — 20261003130000_anon_posts_to_circles.sql).
  final List<String> anonCircleIds;

  /// A Dip posted to several communities: [communityId] is the first pick,
  /// these are the rest. Still ONE post — the extras become post_audiences
  /// rows (see 20260929010000_dip_multi_community.sql).
  final List<String> extraCommunityIds;

  final _Destination dest;
  final String caption;
  final double aspectRatio;
  final XFile? photo;

  /// A recorded clip (2026-10-06). [photo] is then its poster still.
  final String? videoPath;
  final int? videoMs;

  /// The dual capture's inset, kept as its OWN layer instead of baked into
  /// [photo] — set only for a friends post, which renders through
  /// DualPhotoView (draggable inset, geometry applied at display time).
  /// Null for anon, which still flattens through compositeDualPhotos.
  final XFile? secondaryPhoto;

  /// Extra photos beyond [photo] (the cover) — see
  /// _ComposerScreenState._extraPhotos. Empty for every destination except
  /// wherever the send screen's "add photo" tile was used.
  final List<XFile> extraPhotos;

  /// Anon only — the peek-bar heading (typed here, or the prompt this
  /// capture answers). Writes `posts.prompt`.
  final String? prompt;

  /// Anon only — `posts.community_id`.
  final String? communityId;

  /// Anon only — `posts.prompt_id`, set when this capture answers the
  /// prompt bar's rotating daily prompt rather than a typed heading.
  final String? promptId;

  /// Group only — the target `groups.id`. Group posts go to the separate
  /// `group_posts` table via GroupService, NOT to `posts`.
  final String? groupId;

  /// Moment only — the chosen palette id (`posts.moment_color`).
  final String? momentColor;

  /// momentReply only — the `posts.id` of the Moment being replied to.
  final String? momentPostId;

  /// Moment only — audience. False posts to 'everyone' (unchanged default);
  /// true posts 'friends', which can_view_post() then widens to any
  /// community in [momentCommunityIds]. Matches the picker
  /// AddMomentScreen already has, brought to the task-bar camera so a
  /// Moment isn't audience-less depending on where you started it.
  final bool momentFriendsOnly;
  final List<String> momentCommunityIds;

  /// Moment only — same combined-audience widening as [momentCommunityIds],
  /// through the poster's own circles instead of communities. Silent to
  /// everyone but the poster — see CircleService's own doc.
  final List<String> momentCircleIds;

  /// Moment only — post as your anon persona instead of your real name.
  final bool momentAsAnon;

  /// momentReply only — contribute under the anon persona instead of the
  /// real name. Separate from [momentAsAnon]: whether the MOMENT was posted
  /// anonymously has nothing to do with how someone chooses to reply to it.
  final bool momentReplyAsAnon;
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
    this.answeringPrompt,
    this.answeringCommunityId,
    this.answeringPromptId,
    this.lockToDipGroupId,
    this.lockToMomentPostId,
    this.lockToAnonPost = false,
  });

  /// See openCameraRoute's [answeringPrompt] — non-null means this capture
  /// answers an existing prompt, so the anon destination skips its own
  /// heading field and posts this text as `posts.prompt` instead.
  final String? answeringPrompt;

  /// See openCameraRoute's [answeringCommunityId] — the community whose
  /// rotating prompt bar this capture was opened from. Pre-fills the anon
  /// destination's community picker so tapping the prompt bar attributes
  /// the post without an extra manual step.
  final String? answeringCommunityId;

  /// See openCameraRoute's [answeringPromptId] — the `daily_prompts` row
  /// [answeringPrompt] came from. Written to `posts.prompt_id`. Null when
  /// the prompt bar fell back to PromptService's hardcoded, DB-less list.
  final String? answeringPromptId;

  /// See openCameraRoute's [lockToDipGroupId].
  final String? lockToDipGroupId;

  /// See openCameraRoute's [lockToMomentPostId].
  final String? lockToMomentPostId;

  /// True for the "+" create chooser's ANON entry (explicit request,
  /// 2026-10-03: "when opened anon in plus mark the camera shall open for
  /// anon posting ... and then posting it"). Locks the destination to Anon
  /// and composes a POST, instead of the plain camera's
  /// send-this-photo-to-people mode.
  final bool lockToAnonPost;

  final ComposerPhase? testPhase;

  /// Despite the name (kept as-is so existing call sites/tests need no
  /// rename), this now also drives real production navigation —
  /// openCameraRoute's isAnonymous forwards straight through to this.
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

  /// Hold-to-record (explicit request, 2026-10-06): when set, [_capturedPhoto]
  /// is the clip's POSTER still and these are the clip itself. A recorded
  /// clip is the whole capture — no extras, no dual.
  XFile? _capturedVideo;
  int? _capturedVideoMs;
  bool _recordingVideo = false;
  bool _videoStarting = false;
  DateTime? _recordStartedAt;

  /// Extra photos BEYOND `_capturedPhoto` (the cover) — mirrors
  /// LocalPost.photoPath/photoUrls' own split. Populated only via
  /// `_pickGallery`'s append branch, from the send screen's own "add
  /// photo" tile, so single-photo posting (the common case, and the only
  /// path dual-camera capture ever takes) is completely unaffected.
  final _extraPhotos = <XFile>[];

  /// Matches profile_v2_create_flows.dart's group-post `_maxPhotos` — same
  /// cap, same reasoning ("not a requirement — any count from 1 up posts
  /// fine"), kept in sync by hand since the two flows share no base class.
  static const _maxPhotos = 15;

  // Dual-mode result: kept as two RAW files (not composited) until send
  // time, so the confirm screen can show an interactive, repositionable
  // front-inset preview (_CandidMediaPreview) instead of a pre-flattened
  // image. Null in single-camera mode — _capturedPhoto is used there.
  XFile? _capturedBackPhoto;
  XFile? _capturedFrontPhoto;

  // Plain `camera`-package CameraController — disposed and recreated to
  // swap front/back (see _swapCamera / _switchToFrontForDualCapture),
  // matching the pattern in face_reaction_capture.dart.
  CameraController? _controller;
  bool _cameraReady = false;
  String? _cameraError;
  bool _usingRear = true;
  bool _cameraSwapping = false;
  final _flashKey = GlobalKey<CaptureFlashOverlayState>();
  _SelectedMusic? _selectedMusic;

  // FACE MASK FILTER: front-camera, single-shot only (see CaptureCard's
  // maskFilterOn usage and _captureSingleShot's bake branch below).
  bool _maskFilterOn = false;
  final _maskOverlayKey = GlobalKey<FaceMaskOverlayState>();

  // ── Dual camera (BeReal-style back+front) ───────────────────────────────
  // Default ON — matches CameraPrefsService.loadDualCameraEnabled's own
  // default, so the very first frame (before the pref resolves) already
  // shows the dual-mode UI instead of flickering from single to dual.
  // Was `true` — CameraPrefsService.loadDualCameraEnabled() only resolves
  // AFTER this first builds (it's an async SharedPreferences read in
  // _bootstrapCamera), so anyone who had already turned dual OFF saw a
  // flash of dual-mode chrome (the front-camera toggle badge, the hidden
  // swap-camera PiP) on every single open, until the real `false` loaded a
  // frame or two later. Reported as "if I turn dual off, why is there
  // still a preview of dual camera". Defaulting to false means that flash
  // now only affects the opposite, unreported case (dual left ON), and
  // only for the couple of frames before the real preference resolves.
  bool _dualCameraEnabled = false;
  DualStep _dualStep = DualStep.back;
  XFile? _pendingBackPhoto;
  bool _frontCapturing = false;
  String? _frontCaptureError;

  @override
  void initState() {
    super.initState();
    // Warm the send screen's people list while the camera is still up.
    if (widget.answeringPrompt == null &&
        widget.lockToDipGroupId == null &&
        widget.lockToMomentPostId == null &&
        !widget.lockToAnonPost) {
      _photoTargetsPreload = _fetchPhotoTargets();
    }
    final p = widget.testPhase;
    _phase = (p == ComposerPhase.confirm)
        ? ComposerPhase.send
        : (p ?? ComposerPhase.camera);
    _isAnonymous = widget.testAnonymous;
    if (widget.testBackPhotoPath != null && widget.testFrontPhotoPath != null) {
      _capturedBackPhoto = XFile(widget.testBackPhotoPath!);
      _capturedFrontPhoto = XFile(widget.testFrontPhotoPath!);
    }
    if (_phase == ComposerPhase.camera) _bootstrapCamera();
    // Volume buttons take the photo too, while the viewfinder is up.
    unawaited(
      _volumeShutter.start(() {
        if (mounted && _phase == ComposerPhase.camera && _cameraReady)
          _capture();
      }),
    );
  }

  final _volumeShutter = VolumeShutter();

  @override
  void dispose() {
    unawaited(_volumeShutter.stop());
    _controller?.dispose();
    super.dispose();
  }

  /// Loads the persisted dual-camera preference before the first camera
  /// init, so cold start respects whatever the user last set — the toggle
  /// itself only affects what happens at the *next* shutter tap (see
  /// _toggleDualCamera), so there's nothing else to reconcile here.
  Future<void> _bootstrapCamera() async {
    // Always opens on ONE camera (by request) — "Both cams" is a per-shot
    // choice you switch on in the viewfinder, not something that sticks.
    if (!mounted) return;
    setState(() {
      _dualCameraEnabled = false;
      _dualStep = DualStep.back;
    });
    await _initCamera();
  }

  Future<void> _toggleDualCamera() async {
    HapticFeedback.selectionClick();
    final next = !_dualCameraEnabled;
    setState(() => _dualCameraEnabled = next);
    await CameraPrefsService.setDualCameraEnabled(next);
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        rear,
        ResolutionPreset.high,
        // Audio ON so a held-shutter video has sound (2026-10-06).
        enableAudio: true,
        // FACE MASK FILTER: harmless to takePicture() (JPEG capture is
        // unaffected by imageFormatGroup, which only governs
        // startImageStream frames) — lets FaceMaskOverlay analyze this same
        // controller's stream without a second CameraController.
        imageFormatGroup: kFaceMaskImageFormatGroup,
      );
      await ctrl.initialize();
      // Pin the buffer to portrait.
      //
      // Without this the plugin re-orients the analysis frame as the phone
      // tilts, while the face-mask converter assumes portrait — so tilting
      // the device changed the coordinate space out from under the mask and
      // it slid off the face. Reported as "if we keep the phone straight
      // it's detecting; if it's tilted the photo as well moves".
      //
      // Locked, the frame is stable and any tilt the detector sees is REAL
      // head tilt, which the eye-line rotation already handles.
      try {
        await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Not fatal — some devices refuse; tracking just degrades to the
        // old behaviour rather than failing outright.
      }
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _cameraReady = true;
        _cameraError = null;
        _usingRear = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _cameraError = "Camera didn't finish starting — try again.";
      });
    }
  }

  /// Swaps the live camera by disposing the current controller and creating
  /// a new one on the opposite lens direction — the `camera` package has no
  /// in-place flip, unlike DeepAR's old flipCamera().
  ///
  /// BUG FIX: this used to initialize the NEW controller (a second, distinct
  /// AVCaptureSession on iOS) before disposing the OLD one — for a window
  /// between that `ctrl.initialize()` call and the `old?.dispose()` after
  /// it, two capture sessions were simultaneously live. iOS's camera
  /// subsystem does not reliably support that: on real hardware this made
  /// the new session's `initialize()` hang or throw, which is exactly what
  /// broke the front camera specifically in the dual-capture flow (the back
  /// shot's controller was still fully alive, mid-teardown, when the swap
  /// to front tried to start a second session on top of it) — the iOS
  /// Simulator's own camera passthrough is forgiving enough that this
  /// mostly went unnoticed there. Disposing the old controller FIRST, and
  /// only THEN creating/initializing the new one, means at most one
  /// AVCaptureSession is ever live at a time. CameraViewfinder already
  /// renders a plain placeholder (no crash) while `controller` is
  /// null/uninitialized, so the brief gap is safe.
  Future<void> _swapToDirection(bool wantRear) async {
    final old = _controller;
    if (mounted) setState(() => _controller = null);
    await old?.dispose();

    final cameras = await availableCameras();
    final desc = cameras.firstWhere(
      (c) =>
          c.lensDirection ==
          (wantRear ? CameraLensDirection.back : CameraLensDirection.front),
      orElse: () => cameras.first,
    );
    final ctrl = CameraController(
      desc,
      ResolutionPreset.high,
      // Audio ON — same as _initCamera (video has sound, 2026-10-06).
      enableAudio: true,
      // FACE MASK FILTER: see matching comment in _initCamera.
      imageFormatGroup: kFaceMaskImageFormatGroup,
    );
    await ctrl.initialize();
    // Same portrait lock as _initCamera — see its comment. This is the
    // swap path (rear<->front, and dual's automatic back->front leg), which
    // creates a fresh controller and so needs the lock applied again.
    try {
      await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    setState(() {
      _controller = ctrl;
      _usingRear = wantRear;
    });
  }

  Future<void> _swapCamera() async {
    // Manual swap only applies to single-camera mode — in dual mode the
    // back->front sequence is fully automatic (see _captureBackShot).
    if (_cameraSwapping || _dualCameraEnabled || !_cameraReady) return;
    setState(() => _cameraSwapping = true);
    try {
      await _swapToDirection(!_usingRear);
      if (mounted) setState(() => _cameraSwapping = false);
    } catch (_) {
      if (mounted) setState(() => _cameraSwapping = false);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    _flashKey.currentState?.flash();
    if (_dualCameraEnabled) {
      switch (_dualStep) {
        case DualStep.back:
          await _captureBackShot();
        case DualStep.front:
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
      if (_cameraReady && _controller != null) {
        // Same fix as FaceReactionCapture's own (RealMoji) capture path —
        // see FaceMaskOverlayState.pauseStreamingForCapture's doc for why
        // takePicture() racing the mask's live analysis stream produced a
        // slow, sometimes blank capture.
        if (_maskFilterOn && !_usingRear) {
          await _maskOverlayKey.currentState?.pauseStreamingForCapture();
        }
        image = await _controller!.takePicture();
      } else {
        image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1080,
          imageQuality: 85,
        );
      }
    } catch (_) {
      try {
        image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1080,
          imageQuality: 85,
        );
      } catch (_) {}
    }
    // FACE MASK FILTER: bakes the mask into the just-captured front-camera
    // photo. No-op (returns image unchanged) if the filter's off, the shot
    // came from the gallery fallback, or no face was tracked at capture
    // time — see FaceMaskOverlayState.bakeIntoPhoto.
    if (image != null && _maskFilterOn && !_usingRear) {
      image = await _maskOverlayKey.currentState?.bakeIntoPhoto(image) ?? image;
    }
    if (!mounted) return;
    setState(() {
      _capturedPhoto = image;
      _phase = ComposerPhase.send;
    });
  }

  /// Dual camera ON, step 1: capture the back photo, then switch to front
  /// (dispose + recreate the controller — see _swapToDirection).
  Future<void> _captureBackShot() async {
    if (!_cameraReady || _controller == null) return;
    HapticFeedback.mediumImpact();
    try {
      final backPhoto = await _controller!.takePicture();
      if (!mounted) return;
      setState(() {
        _pendingBackPhoto = backPhoto;
        _dualStep = DualStep.front;
      });
      await _switchToFrontForDualCapture();
    } catch (_) {
      // Back shot failed — nothing captured yet, camera stays as-is so the
      // user can just tap the shutter again.
    }
  }

  /// Dual camera ON, step 2 setup: switches the controller to the front
  /// camera (see _swapToDirection).
  Future<void> _switchToFrontForDualCapture() async {
    try {
      await _swapToDirection(false);
      if (!mounted) return;
      setState(() => _frontCaptureError = null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _frontCaptureError = "Couldn't start the front camera.");
    }
  }

  /// Dual camera ON, step 3: capture the front photo. Composting is
  /// deferred to send time (see compositeDualPhotos) — the confirm screen
  /// shows both raw photos live so the front inset stays draggable/
  /// tappable there instead of already being baked into a flat image. If
  /// this throws, the front controller is left exactly as it was (still
  /// live, still previewing) and _pendingBackPhoto is untouched, so the
  /// shutter staying tappable IS the retry path — nothing extra to wire up.
  Future<void> _captureFrontShot() async {
    if (!_cameraReady ||
        _frontCapturing ||
        _pendingBackPhoto == null ||
        _controller == null) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _frontCapturing = true;
      _frontCaptureError = null;
    });
    try {
      // Same fix as _captureSingleShot's own — see
      // FaceMaskOverlayState.pauseStreamingForCapture's doc.
      if (_maskFilterOn) {
        await _maskOverlayKey.currentState?.pauseStreamingForCapture();
      }
      var frontPhoto = await _controller!.takePicture();
      // FACE MASK FILTER in dual mode: the front shot is the selfie half,
      // so it gets the same bake the single-shot path does. Without this
      // the mask was live-only in dual mode — the preview showed it and the
      // posted photo didn't have it at all.
      if (_maskFilterOn) {
        frontPhoto =
            await _maskOverlayKey.currentState?.bakeIntoPhoto(frontPhoto) ??
            frontPhoto;
      }
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

  /// How long a hold may run in THIS camera: a clip headed to people is a
  /// ping answer (15s); every other destination here is a post (60s) —
  /// "15s pings, 60s posts", decided with the user 2026-10-06.
  Duration get _videoLimit {
    // Same condition as _SendInterfaceState._peopleMode.
    final people =
        widget.answeringPrompt == null &&
        widget.lockToDipGroupId == null &&
        widget.lockToMomentPostId == null &&
        !widget.lockToAnonPost;
    return people ? kHoldVideoLimit : kPostVideoLimit;
  }

  /// Hold-to-record. Returns false when the camera can't take it, which tells
  /// the shutter not to draw the recording ring (and fires the failure toast).
  Future<bool> _startVideo() async {
    final c = _controller;
    if (!_cameraReady || c == null || _recordingVideo || _videoStarting) {
      return false;
    }
    // Dual capture is two stills; a clip doesn't fit it.
    if (_dualCameraEnabled) return false;
    _videoStarting = true;
    try {
      // The face-mask overlay's image stream can't coexist with recording —
      // pausing it isn't enough, it restarts on rebuild — so it is
      // unmounted for the duration (see maskFilterOn below).
      if (_maskFilterOn && !_usingRear) {
        await _maskOverlayKey.currentState?.pauseStreamingForCapture();
      }
      if (mounted) setState(() => _recordingVideo = true);
      await WidgetsBinding.instance.endOfFrame;
      await c.startVideoRecording();
      _recordStartedAt = DateTime.now();
      return true;
    } catch (e, st) {
      debugPrint('[Composer._startVideo] failed: $e\n$st');
      if (mounted) setState(() => _recordingVideo = false);
      return false;
    } finally {
      _videoStarting = false;
    }
  }

  Future<void> _stopVideo() async {
    final c = _controller;
    if (!_recordingVideo || c == null) return;
    if (mounted) setState(() => _recordingVideo = false);
    final started = _recordStartedAt;
    _recordStartedAt = null;
    XFile clip;
    try {
      clip = await c.stopVideoRecording();
    } catch (e, st) {
      debugPrint('[Composer._stopVideo] failed: $e\n$st');
      return;
    }
    if (!mounted) return;
    final ms = started == null
        ? null
        : DateTime.now().difference(started).inMilliseconds;
    final done = await finishClip(clip, ms);
    if (!mounted) return;
    if (done == null) {
      showGlassToast(context, 'Hold a little longer to record a video.');
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      _capturedPhoto = done.poster; // the poster — always a real image
      _capturedVideo = done.video;
      _capturedVideoMs = done.ms;
      _capturedBackPhoto = null;
      _capturedFrontPhoto = null;
      _extraPhotos.clear();
      _phase = ComposerPhase.send;
    });
  }

  Future<void> _pickGallery() async {
    // Reused from the send screen's own "add photo" tile once a cover
    // exists — append rather than replace it, capped at _maxPhotos total
    // (cover + extras). The camera phase's first pick (below) is untouched.
    if (_capturedPhoto != null) {
      if (_extraPhotos.length + 1 >= _maxPhotos) return;
      try {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1080,
          imageQuality: 85,
        );
        if (!mounted || image == null) return;
        setState(() => _extraPhotos.add(image));
      } catch (_) {}
      return;
    }
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
      if (!mounted) return;
      setState(() {
        _capturedPhoto = image;
        _phase = ComposerPhase.send;
      });
    } catch (_) {}
  }

  void _removeExtraPhoto(int index) {
    setState(() => _extraPhotos.removeAt(index));
  }

  void _backToCamera() {
    setState(() {
      _phase = ComposerPhase.camera;
      _capturedPhoto = null;
      _capturedVideo = null;
      _capturedVideoMs = null;
      _capturedBackPhoto = null;
      _capturedFrontPhoto = null;
      _extraPhotos.clear();
    });
    // No reinit needed — the controller stays live across this screen's
    // whole lifetime; _cameraReady/_usingRear already reflect its current
    // real state.
  }

  /// Throws on failure (auth not resolved, image upload failed, or the
  /// posts insert was rejected) — the caller (_SendInterface's send button)
  /// catches this to show the real error and let the user retry, instead of
  /// silently pretending the post went through.
  Future<void> _send(_ComposerSubmission spec) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in — cannot post.');
    }

    // Pre-post content check — deliberately lenient (ordinary swearing
    // passes; slurs, explicit content and direct threats don't). See
    // ContentModerationService's own doc for why the bar sits there.
    final moderation = ContentModerationService.instance.check(spec.caption);
    if (moderation.blocked) {
      if (mounted) {
        showGlassToast(context, moderation.reason!, isError: true);
        setState(() => _phase = ComposerPhase.send);
      }
      return;
    }

    // MOMENT REPLY — the Moments "Add yours" camera. Not a post at all: one
    // `moment_replies` row and nothing else, so this returns before the
    // PostService.addPost below ever runs. A reply appears inside its
    // Moment and in no feed or profile grid.
    if (spec.dest == _Destination.momentReply) {
      final photo = spec.photo;
      final momentPostId = spec.momentPostId;
      if (photo == null || momentPostId == null) {
        throw StateError('No photo to add to this moment.');
      }
      HapticFeedback.heavyImpact();
      // Measured, not assumed. This said "+10" regardless of what the
      // action actually paid — see ScoreGainService.
      final mark = ScoreGainService.mark();
      _closeAndReward(
        write: MomentService.instance.addReply(
          momentPostId: momentPostId,
          photo: File(photo.path),
          asAnon: spec.momentReplyAsAnon,
        ),
        mark: mark,
        failureMessage: "Couldn't add to that moment.",
      );
      return;
    }

    // GROUP now means Dip, not a `group_posts` row — the durable group
    // post/Memory ("group_posts") is created ONLY from the group profile's
    // own "Add" button (GroupPostScreen) now; this pill's destination was
    // repointed here so the main composer can't create that table anymore.
    // Dip is single-photo (`dips.photo_url`, no array column), so
    // spec.extraPhotos is deliberately dropped rather than forwarded.
    if (spec.dest == _Destination.group) {
      final photo = spec.photo;
      final groupId = spec.groupId;
      if (photo == null || groupId == null) {
        throw StateError('Pick a group first.');
      }
      HapticFeedback.heavyImpact();
      final mark = ScoreGainService.mark();
      _closeAndReward(
        write: DipService.instance.addDip(
          groupId: groupId,
          photo: File(photo.path),
          caption: spec.caption,
        ),
        mark: mark,
        failureMessage: "Couldn't post that dip.",
      );
      return;
    }

    // Resolves the app-level `users.id` via the auth_id indirection.
    // posts.user_id FKs to users.id, NOT auth.users.id, and the
    // posts_insert RLS policy checks auth.uid() against users.auth_id — so
    // sending the raw auth uid here (as this used to) can never match and
    // the insert is rejected on every attempt.
    final userId = await CurrentUserService.instance.resolveId();
    // The REAL handle, not the email prefix this used to guess at. That
    // guess only ever showed on the optimistic pre-refetch card, so a
    // just-posted post displayed a different name than the same post did
    // one refresh later (once FeedService._attachAuthors resolved
    // users.username). Falls back the same way _attachAuthors does:
    // username, then name.
    String username = 'you';
    try {
      final me = await supabase
          .from('users')
          .select('username, name')
          .eq('id', userId)
          .maybeSingle();
      final handle = (me?['username'] as String?)?.trim();
      final name = (me?['name'] as String?)?.trim();
      if (handle != null && handle.isNotEmpty) {
        username = handle;
      } else if (name != null && name.isNotEmpty) {
        username = name;
      }
    } catch (_) {
      username = user.email?.split('@').first ?? 'you';
    }

    HapticFeedback.heavyImpact();

    // Marked before the insert so the reward reflects exactly what this
    // post credited (an anon post pays 25 and bumps the daily streak).
    final postMark = ScoreGainService.mark();
    final write = PostService.instance.addPost(
      LocalPost(
        // posts.id is a UUID column — a millisecond-timestamp string
        // ("1786590070107") was being rejected outright by Postgres
        // (22P02 invalid input syntax for type uuid), failing every real
        // post insert. Same generator group_service.dart/memory_service.dart
        // etc. already use for their own client-generated ids.
        id: const Uuid().v4(),
        userId: userId,
        username: username,
        // Personal (Everyone) posts were removed — Group and MomentReply
        // both return early above, so the only destinations that ever reach
        // this LocalPost are Anon and Moment; the ternary chain below covers
        // both exhaustively.
        visibility: spec.dest == _Destination.anon
            ? 'anonymous'
            // A Moment posted as anon is an anonymous post that still
            // carries post_type 'moment' — same masking every other anon
            // post gets from posts_feed, so the Moment card renders the
            // persona rather than the real name.
            : spec.momentAsAnon
            ? 'anonymous'
            : 'friends',
        caption: spec.caption,
        photoPath: spec.photo?.path,
        videoPath: spec.videoPath,
        videoMs: spec.videoMs,
        photoUrls: spec.extraPhotos.isEmpty
            ? null
            : [for (final extra in spec.extraPhotos) extra.path],
        secondaryPhotoPath: spec.secondaryPhoto?.path,
        // Same fixed corner on every destination that keeps live dual
        // layers (friends and now anon — see keepsLiveDualLayers above).
        // Only read when secondaryPhotoPath is actually set.
        insetOnRight: FriendsDualInsetGeometry.onRight,
        aspectRatio: spec.aspectRatio,
        // A Moment is an everyone-visibility post with a post_type — that
        // discriminator is what makes the feed draw the gradient MomentCard
        // instead of an ordinary solo card.
        postType: spec.dest == _Destination.moment ? 'moment' : null,
        momentColor: spec.momentColor,
        prompt: spec.prompt,
        communityId: spec.communityId,
        promptId: spec.promptId,
        musicTitle: _selectedMusic?.title,
        musicArtist: _selectedMusic?.artist,
        musicUrl: _selectedMusic?.url,
        // Moments carry their audience; everything else has no picker and
        // so carries no extra community rows (see _buildChipTray).
        audienceCommunityIds: spec.dest == _Destination.anon
            ? spec.extraCommunityIds
            : spec.dest == _Destination.moment && spec.momentFriendsOnly
            ? spec.momentCommunityIds
            : const [],
        audienceCircleIds: spec.dest == _Destination.anon
            ? spec.anonCircleIds
            : spec.dest == _Destination.moment && spec.momentFriendsOnly
            ? spec.momentCircleIds
            : const [],
        showInFeed: true,
      ),
    );

    PromptService.instance.advance();
    _closeAndReward(
      write: write,
      mark: postMark,
      failureMessage: 'Failed to post.',
      // Real Anon Score: +25 lands server-side (trg_award_anon_post_score)
      // for an anon post — pull it in as soon as the write returns rather
      // than waiting for the Anon tab to next mount, so the reward moment
      // matches the badge.
      afterWrite: spec.dest == _Destination.anon
          ? () => unawaited(ViewerScoreService.instance.refresh())
          : null,
    );
  }

  /// Swaps the composer to its reward card the instant Send is tapped, then
  /// closes a beat after the points land.
  ///
  /// The reward fills the SAME card the camera and compose steps live in —
  /// explicit instruction: "this should have been the same size of compose
  /// camera... when clicked compose and posted this shall appear". So the
  /// switch happens before the upload, not after it: there is no spinner on
  /// the send button and nothing to sit through, because the thing you are
  /// looking at while the photo uploads IS the reward, filling its number in
  /// when the server answers.
  ///
  /// The close is deliberately not instant — "delay the closure of posting a
  /// little by one sec, not so much instant".
  Future<void> _closeAndReward({
    required Future<void> write,
    required DateTime mark,
    required String failureMessage,
    VoidCallback? afterWrite,
  }) async {
    // Both captured while mounted — the pop below makes this context
    // unusable, and the reward and any error outlive the screen.
    final overlay = Overlay.of(context, rootOverlay: true);
    final messenger = ScaffoldMessenger.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);

    // The upload runs behind the close, and the reward waits for the points
    // rather than the composer waiting for either. The screen goes after a
    // beat, not instantly — "delay the closure of posting a little by one
    // sec, not so much instant" — which is short enough that the send button
    // never reads as stuck.
    showScoreRewardOverlay(
      overlay: overlay,
      large: true,
      loadGain: () async {
        try {
          await write;
        } catch (e, st) {
          debugPrint('[Composer] background write failed: $e\n$st');
          messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
          // Nothing earned, so the reward never draws itself.
          return null;
        }
        afterWrite?.call();
        // First post landed → the one-time, skippable "start a Duo" ask,
        // once the reward has had its moment on screen.
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 2600),
            () => maybeAskForFirstDuo(rootNav),
          ),
        );
        return ScoreGainService.instance.since(mark);
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    // Send phase needs extra height for portrait-ratio photo previews
    // ONE container for every phase — camera, capture, compose, reward.
    // Only the contents swap (via the AnimatedSwitcher below); the sheet
    // itself never resizes or moves under the person mid-flow, which is
    // what made capture→compose read as two different screens.
    //
    // 0.8125 = the old CAMERA height (0.65) plus 25%. The send phase used
    // to be taller at 0.88 and now shares this one value, so composing is
    // ~7% shorter than it was while capture is 25% taller.
    final kb = MediaQuery.of(context).viewInsets.bottom;
    const cardPad = 12.0;
    // With the keyboard up the card lifts by the full inset, and at its
    // resting height that pushes its own top — the caption field you are
    // typing into — off the top of the screen ("pushing the entire ui up
    // unable to see what we type"). Give the card only the room that's
    // actually left instead. The photo preview inside sizes itself from
    // its constraints, so it's what gives up the height, not the caption.
    final cardH = math.min(
      screenH * _kCardHeightFactor,
      screenH - kb - cardPad * 2 - MediaQuery.of(context).padding.top,
    );
    const cardRadius = Radius.circular(48);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Tap anywhere outside the sheet to close it — EVERY phase now,
          // not just capture. This is the only dismiss affordance left: the
          // header's chevron button is gone, so tapping off the card is how
          // you back out of composing as well as out of the camera.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
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
            left: cardPad,
            right: cardPad,
            // Same resting position in every phase. The only movement left
            // is the keyboard lift, which is a response to the keyboard —
            // not a phase change — and without it the caption/heading
            // fields would sit behind it (resizeToAvoidBottomInset is off).
            bottom: kb + cardPad,
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
                  ComposerPhase.camera => CaptureCard(
                    key: const ValueKey('capture'),
                    controller: _controller,
                    cameraReady: _cameraReady,
                    cameraError: _cameraError,
                    usingRear: _usingRear,
                    swapping: _cameraSwapping,
                    onCapture: _capture,
                    onGallery: _pickGallery,
                    // QR scanning lives in the TASK BAR camera only
                    // (explicit request, 2026-10-03: "the duo and group QR
                    // can be scanned by the task bar's camera only") — the
                    // plain camera with no Dip / Moment / anon / prompt
                    // lock. One scanner detects both a Duo code and a
                    // group code and does the right thing for each.
                    onStartVideo: _startVideo,
                    onStopVideo: () => unawaited(_stopVideo()),
                    videoLimit: _videoLimit,
                    onVideoStartFailed: () => showGlassToast(
                      context,
                      "Couldn't start recording — try again.",
                      isError: true,
                    ),
                    onScanQr:
                        widget.lockToDipGroupId == null &&
                            widget.lockToMomentPostId == null &&
                            !widget.lockToAnonPost &&
                            widget.answeringPrompt == null
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const QrScannerScreen(),
                            ),
                          )
                        : null,
                    onSwap: _swapCamera,
                    onClose: () => Navigator.of(context).pop(),
                    dualCameraEnabled: _dualCameraEnabled,
                    onToggleDualCamera: _toggleDualCamera,
                    // Dip (anon) posts are single-photo only, by request —
                    // no Dual option to even discover. _isAnonymous is fixed
                    // for the whole camera phase (only _SendInterface, a
                    // later screen, can flip it), so this is safe to read
                    // once here rather than re-checking per frame.
                    allowDualToggle: !_isAnonymous,
                    dualStep: _dualStep,
                    frontCapturing: _frontCapturing,
                    frontCaptureError: _frontCaptureError,
                    onUseBackPhotoOnly: _useBackPhotoOnly,
                    flashKey: _flashKey,
                    // FACE MASK FILTER:
                    // Off while recording — the analysis stream can't
                    // coexist with a video (see _startVideo).
                    maskFilterOn: _maskFilterOn && !_recordingVideo,
                    onToggleMaskFilter: () =>
                        setState(() => _maskFilterOn = !_maskFilterOn),
                    maskOverlayKey: _maskOverlayKey,
                  ),
                  ComposerPhase.send || ComposerPhase.confirm => _SendInterface(
                    key: const ValueKey('send'),
                    answeringPrompt: widget.answeringPrompt,
                    answeringCommunityId: widget.answeringCommunityId,
                    answeringPromptId: widget.answeringPromptId,
                    lockToDipGroupId: widget.lockToDipGroupId,
                    lockToMomentPostId: widget.lockToMomentPostId,
                    lockToAnonPost: widget.lockToAnonPost,
                    photo: _capturedPhoto,
                    video: _capturedVideo,
                    videoMs: _capturedVideoMs,
                    backPhoto: _capturedBackPhoto,
                    frontPhoto: _capturedFrontPhoto,
                    extraPhotos: _extraPhotos,
                    maxPhotos: _maxPhotos,
                    // A Moment reply is exactly one photo — passing null
                    // here is what suppresses the "add photo" tile and the
                    // whole extras strip (see _buildPhotoView's own
                    // onAddPhoto == null branch), so there is nothing extra
                    // to strip out downstream.
                    onAddPhoto:
                        (widget.lockToMomentPostId != null ||
                            _capturedVideo != null)
                        ? null
                        : _pickGallery,
                    onRemovePhoto: _removeExtraPhoto,
                    isAnonymous: _isAnonymous,
                    selectedMusic: _selectedMusic,
                    onAnonChanged: (v) => setState(() => _isAnonymous = v),
                    onBack: _backToCamera,
                    onSend: _send,
                    onMusicChanged: (m) => setState(() => _selectedMusic = m),
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
    this.video,
    this.videoMs,
    required this.isAnonymous,
    required this.onAnonChanged,
    required this.onBack,
    required this.onSend,
    this.backPhoto,
    this.frontPhoto,
    this.extraPhotos = const [],
    this.maxPhotos = 15,
    this.onAddPhoto,
    this.onRemovePhoto,
    this.selectedMusic,
    this.onMusicChanged,
    this.answeringPrompt,
    this.answeringCommunityId,
    this.answeringPromptId,
    this.lockToDipGroupId,
    this.lockToMomentPostId,
    this.lockToAnonPost = false,
  });

  /// See ComposerScreen.lockToAnonPost — hides the destination pills and
  /// fixes the destination to Anon, so this card composes an anonymous
  /// POST rather than the plain camera's photo-to-people send.
  final bool lockToAnonPost;

  /// Non-null when this capture answers a prompt the person already picked
  /// (opened from a prompt bar) — the Anon destination then hides its
  /// heading field and posts this text as the peek-bar prompt.
  final String? answeringPrompt;

  /// See ComposerScreen.answeringCommunityId's own doc — pre-fills the anon
  /// destination's community picker.
  final String? answeringCommunityId;

  /// See ComposerScreen.answeringPromptId's own doc — written to
  /// `posts.prompt_id`.
  final String? answeringPromptId;

  /// See openCameraRoute's [lockToMomentPostId] — hides the destination
  /// pills AND the caption field, forces a single photo, and routes _send
  /// to MomentService instead of PostService.
  final String? lockToMomentPostId;

  /// See openCameraRoute's [lockToDipGroupId] — hides the destination pills
  /// the same way, but pre-selects Group with this id so `initState` sets
  /// `_dest`/`_groupId` instead of leaving them at their default.
  final String? lockToDipGroupId;

  final XFile? photo;

  /// A recorded clip (2026-10-06) — [photo] is its poster. Null for every
  /// ordinary photo capture.
  final XFile? video;
  final int? videoMs;
  // Dual-camera capture — when both are non-null, the media preview shows
  // the interactive front inset (_CandidMediaPreview) instead of the single
  // flattened photo.
  final XFile? backPhoto;
  final XFile? frontPhoto;

  /// Extra photos beyond [photo] — see _ComposerScreenState._extraPhotos.
  /// Single-camera (!isDual) only; dual capture never populates this.
  final List<XFile> extraPhotos;
  final int maxPhotos;

  /// Appends one more photo via the same gallery picker the camera phase
  /// uses (_ComposerScreenState._pickGallery's append branch). Null hides
  /// the "add" tile — every real call site passes it; only absent for
  /// completeness where a caller might not want the affordance.
  final VoidCallback? onAddPhoto;
  final void Function(int index)? onRemovePhoto;

  final bool isAnonymous;
  final ValueChanged<bool> onAnonChanged;

  /// Return to the camera WITHOUT closing the sheet (keeps the composer
  /// open, drops the capture). Currently unwired: the chevron that called it
  /// was removed, and tapping outside the sheet closes the whole composer
  /// instead. Kept because it's the only "retake in place" path there is —
  /// re-attach it to a gesture (swipe-down on the card, tap the photo) if
  /// that turns out to be missed.
  final VoidCallback onBack;
  final Future<void> Function(_ComposerSubmission spec) onSend;
  final _SelectedMusic? selectedMusic;
  final ValueChanged<_SelectedMusic?>? onMusicChanged;

  @override
  State<_SendInterface> createState() => _SendInterfaceState();
}

// groups/community pickers are inline now (see _InlinePicker), so the
// only sheets left are audience and music.
enum _SheetKind { music }

/// Caption cap for an ANON post. The anon card renders the caption at 24px
/// (AnonFeedType.t8) across the card's full width with no maxLines — about
/// 28 characters per line there, so this is two lines before it starts
/// eating the meta row's space below it.
const _kAnonCaptionMaxChars = 60;

/// Cap for the anon HEADING (the peek-bar text, `posts.prompt`). That bar is
/// hard-limited to ONE line — `Text(next!.prompt, maxLines: 1, ellipsis)` at
/// 24px/w700 in a box inset 26px each side (_AnonBottomBlock) — so anything
/// past roughly this length is simply never readable by the person it's
/// meant to bait.
const _kAnonHeadingMaxChars = 30;

/// Cap for a Dip note. Kept in lockstep with the `dips_caption_len` CHECK
/// added by migration 20260908210000 — if one moves, the other has to.
/// Roomier than the feed captions because a Dip note is read on its own
/// detail sheet, not inside a fixed-height card.
const _kDipCaptionMaxChars = 200;

// The app-wide cyan (Ping page kCyan, AnonFeedColors.accentCyan) — the
// composer used to be the one lime-green screen in an otherwise blue app.
const _kAccent = Color(0xFF29D3E8);

class _SendInterfaceState extends State<_SendInterface> {
  final _captionCtrl = TextEditingController();
  bool _sending = false;

  /// The pill row + inline picker were removed from this card entirely —
  /// tapping SEND now advances to a dedicated audience step (this flag)
  /// instead of posting straight away. See _buildAudienceStep.
  bool _showAudienceStep = false;
  // 4:5 is the only post ratio now — 1:1 was removed, and a picker with one
  // option is just a label. Kept as a named constant rather than inlining
  // 0.8, since it's still the posted `posts.aspect_ratio` value and the
  // preview's own sizing basis.
  static const _postRatio = 4.0 / 5.0;
  final _musicPlayer = AudioPlayer();
  int? _musicPreviewIdx;

  // Front-inset state (dual-camera mode only) — which shot is currently the
  // big background. Composited into one flattened image at send time. The
  // reference design pins the inset to the top-left corner only (no drag).
  bool _frontIsBig = false;

  // ── Destination (the pill row over the photo) ───────────────────────────
  // Anon is the default destination — it's the feed this app is built
  // around. Every locked-mode entry point below still overrides this
  // (moment reply, Dip, prompt-answer), so only the free-form camera is
  // affected.
  _Destination _dest = _Destination.anon;

  /// Anon heading → `posts.prompt`. Unused when widget.answeringPrompt is
  /// set (the prompt was already chosen upstream).
  final _headingCtrl = TextEditingController();

  MomentPalette _palette = kMomentPalettes.first;

  /// Real groups (GroupService.fetchMyGroups) — the same source
  /// GroupPostScreen's picker uses, replacing the hardcoded mock list this
  /// sheet showed before, whose selection was never posted anywhere.
  List<Map<String, dynamic>>? _groups;
  String? _groupId;

  /// Moment audience.
  ///
  /// Pinned TRUE — explicit request ("include friends, not everyone"). A
  /// Moment used to default to 'everyone' with a Friends chip beside it,
  /// which made the campus-wide scope the accidental choice. Friends is now
  /// the only audience; communities narrow it further, they don't widen it.
  /// Kept as a field rather than inlined because every downstream consumer
  /// (_ComposerSubmission.momentFriendsOnly → MomentSpec) still takes it.
  final bool _momentFriendsOnly = true;
  final Set<String> _momentCommunityIds = {};
  final Set<String> _momentCircleIds = {};

  /// Anon audience step — circles ticked alongside communities.
  final Set<String> _anonCircleIds = {};
  List<CircleOption>? _circles;

  /// Post the Moment as your anon persona rather than your real name.
  /// Defaults to your real name — "by default 'as you' shall be selected".
  bool _momentAsAnon = false;

  /// "Reply as" for a Moment contribution — see MomentSpec.momentReplyAsAnon.
  bool _momentReplyAsAnon = false;

  List<CommunityOption>? _communities;
  String? _communitiesError;
  String? _communityId;

  /// Communities ticked on the audience step, in tap order (the first one
  /// becomes the post's own community_id).
  final Set<String> _pickedCommunityIds = <String>{};

  /// The plain camera (no prompt, not locked to a Dip/Moment) sends the
  /// photo to people, not a post (explicit request, 2026-09-30): anon posts
  /// are made only by answering a prompt bar.
  bool get _peopleMode =>
      widget.answeringPrompt == null &&
      widget.lockToDipGroupId == null &&
      widget.lockToMomentPostId == null &&
      !widget.lockToAnonPost;

  /// People who pinged me (their open ping gets this photo as my reply)
  /// first, then my Friends circle (they get a new photo ping). Null while
  /// loading.
  List<_PhotoTarget>? _targets;
  final Set<String> _pickedTargets = <String>{};

  /// The "Anon" bubble on the send screen: also post this photo to the
  /// anon feed (explicit request, 2026-10-06: "after photo clicking include
  /// a bubble which makes it post to anon feed ... no selecting audience,
  /// general is default, no peeking prompt nothing"). No caption, no
  /// prompt, no community picker — see [_postAnonPhoto].
  bool _pickedAnon = false;

  String _musicQuery = '';
  _SheetKind? _openSheetKind;

  @override
  void initState() {
    super.initState();
    // Prompt bar tap already knows which community the rotating prompt
    // belongs to — pre-fill so the anon destination's community picker
    // doesn't ask the person to re-pick it after they already answered.
    // Also pre-select the Anon destination pill itself: without this,
    // _dest stayed at its default even when opened by answering
    // a prompt, so _communityId/promptId (both gated on
    // `_dest == _Destination.anon`) were silently dropped from the
    // submission unless the person happened to tap the Anon pill
    // themselves first.
    if (widget.answeringPrompt != null) {
      // TODO(personal-posts-removal): widget.isAnonymous:false means this
      // capture answers the FRIENDS feed's own prompt bar (home_screen.dart
      // _openCamera, isAnonymous: _tabIndex == 0), which used to become a
      // named Everyone post. Personal (Everyone) posts were removed and
      // there is no longer an obvious destination for a NAMED prompt
      // answer — defaulting to Moment (closest remaining "real name, real
      // content" destination) rather than guessing something more specific.
      // Revisit: either retire the Friends-tab prompt bar's non-anonymous
      // path entirely, or decide what it should become.
      _dest = widget.isAnonymous || !kMomentsEnabled
          ? _Destination.anon
          : _Destination.moment;
    }
    if (widget.answeringCommunityId != null) {
      _communityId = widget.answeringCommunityId;
      // Pre-ticked on the "Send to" step, which now always shows.
      _pickedCommunityIds.add(widget.answeringCommunityId!);
    }
    if (widget.lockToMomentPostId != null) {
      // Fixed destination, fixed Moment — same one-shot assignment as the
      // Dip-locked entry below. No pill row ever renders for this mode, so
      // _dest can never move off it.
      _dest = _Destination.momentReply;
    }
    if (widget.lockToAnonPost) {
      // Fixed destination — the "+" chooser already said Anon, so no pill
      // row renders and _dest can never move off it.
      _dest = _Destination.anon;
    }
    if (widget.lockToDipGroupId != null) {
      // Fixed destination, fixed group — the chip tray (and its inline
      // group picker) never renders when locked, so _groupId is set here
      // once rather than via the tap-to-select flow those pickers use.
      _dest = _Destination.group;
      _groupId = widget.lockToDipGroupId;
    }
    // The send button's enabled-ness is derived from these fields, so they
    // have to rebuild as the person types.
    _captionCtrl.addListener(_onTextChanged);
    _headingCtrl.addListener(_onTextChanged);
    // The pickers are also loaded from _pickDestination, but that only
    // covers destinations reached by TAPPING a pill. Whatever destination
    // this card opens in has to load its own list too, or its inline strip
    // spins forever with no way out (tap-to-retry only shows on error).
    // Skipped when locked — the picker that list would feed never renders.
    // Skipped for the Moment-reply camera too: it has no picker at all.
    if (_peopleMode) {
      _loadTargets();
    } else if (widget.lockToDipGroupId == null &&
        widget.lockToMomentPostId == null) {
      _loadPickerFor(_dest);
    }
  }

  Future<void> _loadTargets() async {
    // The Anon tile wears the person's anon picture.
    unawaited(AnonPersonaService.instance.load());
    // Last list shows instantly; the preload started when the camera
    // opened replaces it.
    _targets = _lastPhotoTargets;
    final fresh = await (_photoTargetsPreload ?? _fetchPhotoTargets());
    _photoTargetsPreload = null;
    if (!mounted) return;
    setState(() {
      _targets = fresh;
      _pickedTargets.removeWhere((k) => !fresh.any((t) => t.key == k));
    });
  }

  Future<XFile?> _flatPhoto() async {
    final isDual = widget.backPhoto != null && widget.frontPhoto != null;
    return isDual
        ? compositeDualPhotos(
            widget.backPhoto!,
            widget.frontPhoto!,
            frontIsBig: _frontIsBig,
          )
        : widget.photo;
  }

  /// Closes at once; the upload and sends run behind it. One upload serves
  /// everyone (reads go through signed URLs keyed on the stored path, not
  /// the folder). Pingers get it as their ping's reply, friends as one new
  /// photo ping, groups as a group ping.
  Future<void> _sendToPeople() async {
    if (_sending || (_pickedTargets.isEmpty && !_pickedAnon)) return;
    final toAnon = _pickedAnon;
    // The reply reward fires on the tap itself — every target here is a
    // ping I'm answering. It used to fire only after the photo had
    // uploaded and every reply had been written, which read as a lag
    // (explicit report, 2026-10-03). Anon-only sends answer no ping.
    if (_pickedTargets.isNotEmpty) unawaited(pingReward());
    setState(() => _sending = true);
    final picked = [
      for (final t in _targets ?? const <_PhotoTarget>[])
        if (_pickedTargets.contains(t.key)) t,
    ];
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final photoFuture = _flatPhoto();
    Navigator.of(context).pop();
    // Both run off the same captured photo; neither waits on the other.
    final anonFuture = toAnon
        ? _postAnonPhoto(
            photoFuture,
            video: widget.video,
            videoMs: widget.videoMs,
          )
        : null;
    final (sent, error) = picked.isEmpty
        ? (0, null)
        : await _deliverPhoto(
            photoFuture,
            picked,
            video: widget.video,
            videoMs: widget.videoMs,
          );
    final anonOk = anonFuture == null ? null : await anonFuture;
    // Replies are written now (not when the screen closed): tell anything
    // showing "whose turn" to look again — the Friends feed's YOUR TURN row.
    if (sent > 0) pingInboxChanged.value++;
    if (!rootCtx.mounted) return;
    if (picked.isEmpty) {
      // Anon only.
      showPingToast(
        rootCtx,
        anonOk == true ? 'Posted to Anon ✓' : "Couldn't post that — try again.",
        isError: anonOk != true,
      );
      return;
    }
    final anonNote = anonOk == null
        ? ''
        : anonOk
        ? ' · posted to Anon'
        : " · Anon post didn't go through";
    if (sent == 0) {
      if (anonOk == true) {
        showPingToast(rootCtx, "Posted to Anon ✓ · photo didn't send");
        return;
      }
      showPingToast(
        rootCtx,
        error ?? "Couldn't send that photo — try again.",
        isError: true,
      );
    } else {
      showPingToast(
        rootCtx,
        (error == null && sent == picked.length
                ? 'Sent to $sent ✓'
                : 'Sent to $sent of ${picked.length}${error == null ? '' : ' · $error'}') +
            anonNote,
      );
    }
  }

  void _loadPickerFor(_Destination d) {
    if (d == _Destination.group) _loadGroups();
    // Moment needs the community list too now — its audience picker offers
    // the same "also show to" chips the anon destination does.
    if (d == _Destination.anon || d == _Destination.moment) {
      _loadCommunities();
    }
    if (d == _Destination.moment || d == _Destination.anon) _loadCircles();
  }

  /// Best-effort, like _loadCommunities — no circles just means no circle
  /// pills on the Moment audience row, never blocks posting.
  Future<void> _loadCircles() async {
    if (_circles != null) return;
    try {
      final circles = await CircleService.instance.fetchMyCircles();
      if (mounted) setState(() => _circles = circles);
    } catch (_) {}
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _captionCtrl.removeListener(_onTextChanged);
    _headingCtrl.removeListener(_onTextChanged);
    _captionCtrl.dispose();
    _headingCtrl.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  // In-flight guards: the same list can be asked for twice (opening in a
  // destination, then tapping back to it before the first fetch returns),
  // and a second concurrent fetch would just race the first.
  bool _loadingGroups = false;
  bool _loadingCommunities = false;

  Future<void> _loadGroups() async {
    if (_loadingGroups || _groups != null) return;
    _loadingGroups = true;
    try {
      final groups = await GroupService.instance.fetchMyGroups();
      if (mounted) setState(() => _groups = groups);
    } catch (_) {
      // Group destination has no picker UI any more (see _buildChipTray) —
      // nothing left to show an error in.
    } finally {
      _loadingGroups = false;
    }
  }

  Future<void> _loadCommunities() async {
    if (_loadingCommunities || _communities != null) return;
    _loadingCommunities = true;
    try {
      final communities = await CommunityService.instance.fetchMyCommunities();
      if (mounted) setState(() => _communities = communities);
    } catch (e) {
      if (mounted) setState(() => _communitiesError = '$e');
    } finally {
      _loadingCommunities = false;
    }
  }

  /// The caption is capped only where something downstream truncates it —
  /// a Moment's caption IS its single-line card headline, an anon caption
  /// gets two lines on the anon card, and a plain post's caption is now a
  /// fixed single line too (see maxLines below). Group stays uncapped —
  /// GroupPostScreen's own, separate caption field is the one product
  /// surface for that post type; this composer "Group" pill is a distinct,
  /// less-used path and wasn't part of this fix's scope.
  int? get _captionMaxChars => switch (_dest) {
    _Destination.moment => kMomentCaptionMaxChars,
    _Destination.anon => _kAnonCaptionMaxChars,
    // Matches the dips_caption_len CHECK exactly (migration
    // 20260908210000). Without a client cap a longer note would be
    // rejected by Postgres with a 23514 at insert time, i.e. after the
    // photo had already uploaded.
    _Destination.group => _kDipCaptionMaxChars,
    // Never reached — the caption field itself is hidden for a Moment
    // reply (a reply is a photo, nothing else).
    _Destination.momentReply => null,
  };

  /// What the typing box is FOR, stated on the box itself. Explicit request:
  /// "use proper words what the box is about" — every destination used to
  /// share one vague "Add a caption..." placeholder and no label at all.
  String get _captionLabel => switch (_dest) {
    _Destination.moment => 'MOMENT NAME',
    _Destination.anon => 'CAPTION',
    _Destination.group => 'NOTE',
    _ => 'CAPTION',
  };

  String get _captionHint => switch (_dest) {
    _Destination.moment => 'Name this moment',
    _Destination.anon => 'Say more about it (optional)',
    _Destination.group => 'Add a note for the group (optional)',
    _ => 'Say something about this photo',
  };

  /// The prompt this anon post will carry — whatever was answered upstream,
  /// else the heading typed here.
  String? get _effectivePrompt {
    final upstream = widget.answeringPrompt?.trim();
    if (upstream != null && upstream.isNotEmpty) return upstream;
    final typed = _headingCtrl.text.trim();
    return typed.isEmpty ? null : typed;
  }

  /// Why SEND is disabled, or null when it's ready. Shown under the button
  /// so a blocked send always says what's missing (same rule Add Moment's
  /// footer follows) instead of just looking broken.
  ///
  /// Community choice is NOT checked here any more — that's the audience
  /// step's own [_audienceBlockedReason], reached only after this button is
  /// tapped.
  String? get _blockedReason => switch (_dest) {
    _Destination.moment =>
      _captionCtrl.text.trim().isEmpty ? 'Name your moment to post it' : null,
    _Destination.anon =>
      _effectivePrompt == null
          ? 'Add a heading — it\'s what people see before they tap'
          : null,
    _Destination.group => _groupId == null ? 'Pick a group to post to' : null,
    // A photo is the only requirement, and SEND is unreachable before one
    // exists (this card only renders after a capture).
    _Destination.momentReply => null,
  };

  /// Why POST is disabled on the audience step, or null when it's ready.
  String? get _audienceBlockedReason =>
      _pickedCommunityIds.isEmpty && _anonCircleIds.isEmpty
      ? 'Pick a community or circle'
      : null;

  /// The actual post — moved here from the old SEND button's onTap. Now
  /// triggered by the audience step's POST button, once a community is
  /// chosen, instead of running the moment SEND is tapped.
  Future<void> _finishSend() async {
    if (_sending || _audienceBlockedReason != null) return;
    // The ticks are the whole audience: first community becomes
    // posts.community_id (null for a circles-only post).
    _communityId = _pickedCommunityIds.isNotEmpty
        ? _pickedCommunityIds.first
        : null;
    setState(() => _sending = true);
    try {
      final isDual = widget.backPhoto != null && widget.frontPhoto != null;
      XFile? finalPhoto = widget.photo;
      XFile? secondaryPhoto;
      // Anon dual posts get live, un-flattened layers — "how in friends
      // feed click on the other dual camera photo interchanges its
      // position, make the same in anon feed as well" needs two real
      // layers to interchange, not a baked-in composite.
      final keepsLiveDualLayers = _dest == _Destination.anon;
      if (isDual) {
        final big = _frontIsBig ? widget.frontPhoto! : widget.backPhoto!;
        final small = _frontIsBig ? widget.backPhoto! : widget.frontPhoto!;
        if (keepsLiveDualLayers) {
          // Keep the two layers apart so the feed can lay the inset out
          // at display time — a flattened JPEG freezes whatever geometry
          // was current at post time, which is what left every earlier
          // dual post stuck in the old corner and proportions. The anon
          // card's own frame ratio — there is no size picker on that
          // destination.
          // Uncropped: the photo keeps its own shape (see postAspect below).
          finalPhoto = big;
          secondaryPhoto = small;
        } else {
          finalPhoto = await compositeDualPhotos(
            widget.backPhoto!,
            widget.frontPhoto!,
            frontIsBig: _frontIsBig,
            outputAspect: await photoAspectOf(widget.backPhoto!),
          );
        }
      }
      // The real shape of what's uploaded — stored as the post's aspect so
      // every card frames it without cutting. It used to be the fixed 4:5
      // for every photo, which cropped landscape and tall shots alike.
      final postAspect = await photoAspectOf(finalPhoto ?? widget.photo!);
      await widget.onSend(
        _ComposerSubmission(
          dest: _dest,
          caption: _captionCtrl.text.trim(),
          aspectRatio: postAspect,
          photo: finalPhoto,
          videoPath: widget.video?.path,
          videoMs: widget.videoMs,
          secondaryPhoto: secondaryPhoto,
          // Dual capture composites to one photo at send time (above) and
          // never populates extras — isDual is orthogonal to this list,
          // not a guard on it.
          extraPhotos: widget.extraPhotos,
          // Anon carries all three unconditionally (own community picker,
          // own typed heading) — no other remaining destination has a
          // prompt/community to attach.
          prompt: _dest == _Destination.anon ? _effectivePrompt : null,
          communityId: _dest == _Destination.anon ? _communityId : null,
          extraCommunityIds: _dest == _Destination.anon
              ? [
                  for (final id in _pickedCommunityIds)
                    if (id != _communityId) id,
                ]
              : const [],
          promptId: _dest == _Destination.anon
              ? widget.answeringPromptId
              : null,
          anonCircleIds: _dest == _Destination.anon
              ? _anonCircleIds.toList()
              : const [],
          groupId: _dest == _Destination.group ? _groupId : null,
          momentColor: _dest == _Destination.moment ? _palette.id : null,
          momentPostId: widget.lockToMomentPostId,
          momentFriendsOnly: _momentFriendsOnly,
          momentCommunityIds: _momentCommunityIds.toList(),
          momentCircleIds: _momentCircleIds.toList(),
          momentAsAnon: _momentAsAnon,
          momentReplyAsAnon: _momentReplyAsAnon,
          // No audience picker exists in any camera any more (see
          // _buildChipTray): the personal-post camera is friends-only by
          // default, decided in _send, and the task bar can only reach
          // Anon/Dip/Moments. So these keep their defaults — no extra
          // community audience, always shown in the feed.
        ),
      );
    } catch (e, st) {
      debugPrint('[Composer] Post failed: $e\n$st');
      if (!mounted) return;
      setState(() => _sending = false);
      if (!context.mounted) return;
      showGlassToast(context, 'Failed to post: $e', isError: true);
    }
  }

  void _closeSheet() {
    _musicPlayer.stop();
    setState(() {
      _musicPreviewIdx = null;
      _openSheetKind = null;
    });
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
    widget.onMusicChanged?.call(
      _SelectedMusic(title: t.$1, artist: t.$2, url: t.$3),
    );
    _closeSheet();
  }

  void _clearMusic() {
    widget.onMusicChanged?.call(null);
    _closeSheet();
  }

  @override
  Widget build(BuildContext context) {
    if (_peopleMode) return _buildPeopleSend();
    if (_showAudienceStep) return _buildAudienceStep();
    final isDual = widget.backPhoto != null && widget.frontPhoto != null;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
                    // ── Identity row — its own strip ABOVE the photo.
                    //
                    // BUG FIX ("still the pills overlap"): this used to be
                    // painted INTO the photo's Stack at top: 0, while the
                    // audience tray painted into the same Stack at
                    // bottom: 0. That was fine on a tall photo box and
                    // collided on a short one — and the box got shorter the
                    // moment the caption/heading boxes moved below the
                    // photo, so POST AS landed on top of the destination
                    // pills, the palette and the community chips all at
                    // once. Two rows that must never overlap shouldn't be
                    // two overlays on the same finite box; this one is a
                    // real Column child now, so the layout keeps them apart
                    // by construction instead of by luck.
                    _buildIdentityBar(),

                    if (!isDual) const SizedBox(height: 10),

                    // ── Photo card ───────────────────────────────────────
                    //
                    // BUG FIX (explicit report — "what is that black like
                    // extra cover of the photo, let it fit correctly to the
                    // photo"): the dark plate used to be a
                    // Container(color: 0xFF1A1A1C) wrapping the WHOLE
                    // Expanded, while the photo inside it was CENTRED at
                    // the 4:5 height. Whenever the available box was TALLER
                    // than 4:5 — the common case on a tall phone with the
                    // keyboard down — the leftover height above and below
                    // the photo painted as that dark plate. That band is
                    // the "extra cover".
                    //
                    // There is no plate any more. The card is sized TO the
                    // photo (full width, 4:5 tall, capped by whatever
                    // height is actually available) and _buildPhotoView
                    // fills it with BoxFit.cover, so the card's rounded
                    // edge IS the photo's edge and there is nothing left
                    // over to show through. The POST is still submitted at
                    // _postRatio (see the aspectRatio passed to
                    // _ComposerSubmission) — only the preview box changed.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: isDual
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(26),
                                child: _CandidMediaPreview(
                                  backPhoto: widget.backPhoto!,
                                  frontPhoto: widget.frontPhoto!,
                                  frontIsBig: _frontIsBig,
                                  onToggleBig: () => setState(
                                    () => _frontIsBig = !_frontIsBig,
                                  ),
                                  tray: _buildChipTray(),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (ctx, bc) {
                                  final postRatio = _postRatio;
                                  final aW = bc.maxWidth;
                                  final aH = bc.maxHeight;
                                  final pH = aH < (aW / postRatio)
                                      ? aH
                                      : (aW / postRatio);
                                  return Center(
                                    child: SizedBox(
                                      width: aW,
                                      height: pH,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(26),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            // Plain rectangle while
                                            // composing. The anon card's
                                            // notched border is a
                                            // FEED-render treatment (the
                                            // feed card applies
                                            // AnonPostCardClipper itself)
                                            // — previewing it here just
                                            // crops the photo the person
                                            // is still framing.
                                            _buildPhotoView(),
                                            // Only the audience tray
                                            // overlays the photo now. The
                                            // identity row moved OUT to a
                                            // real Column child above the
                                            // card — see the SizedBox
                                            // before this Expanded, and
                                            // _buildIdentityBar's own doc
                                            // for why overlaying both
                                            // collided.
                                            _buildChipTray(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),

                    // BUG FIX (explicit report — "let photo take space not
                    // as such, let the boxes come down of the photo"): the
                    // caption/heading boxes used to sit ABOVE the photo
                    // card in this Column, so opening the composer showed
                    // two text boxes first and the photo pushed down below
                    // them — exactly backwards from how a camera composer
                    // should read. Moved below the photo instead: the shot
                    // you just took is the first and dominant thing on
                    // screen, and what you type about it follows. Nothing
                    // in this block changed except its POSITION — same
                    // conditions, same _ComposerField boxes, same order
                    // relative to each other (heading, then caption, then
                    // the "answering a prompt" line).
                    //
                    // Explicit request: "in Dip, in Anon and Moments, the
                    // space where we type — make it a box, enclosed."
                    // These used to be bare TextFields floating on the
                    // sheet with InputBorder.none, so there was no visible
                    // edge to tell you where the typing area started or
                    // that it was a field at all. Both are now
                    // _ComposerField boxes with a named label saying what
                    // the box is for, which is the same request's other
                    // half ("use proper words what the box is about").
                    //
                    // Order matters for Anon: the HEADING is what the peek
                    // bar shows, so it is asked for first and the optional
                    // caption second. Every other destination has no
                    // heading and starts at the caption.
                    //
                    // ── Anon heading — required, and skipped entirely when
                    // this capture already answers a prompt picked
                    // upstream (the prompt IS the heading then).
                    if (_dest == _Destination.anon &&
                        widget.answeringPrompt == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: _ComposerField(
                          label: 'HEADLINE',
                          required: true,
                          currentLength: _headingCtrl.text.characters.length,
                          maxLength: _kAnonHeadingMaxChars,
                          child: TextField(
                            controller: _headingCtrl,
                            maxLength: _kAnonHeadingMaxChars,
                            maxLines: 1,
                            // null suppresses the decorator's counter row —
                            // _ComposerField draws the count on its label
                            // row instead. See its own doc.
                            buildCounter: _noCounter,
                            style: GoogleFonts.archivo(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.01 * 16,
                              color: _kAccent,
                            ),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              hintText: 'The line people see in the peek bar',
                              hintStyle: GoogleFonts.archivo(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.01 * 16,
                                color: _kAccent.withValues(alpha: 0.38),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // ── Caption.
                    //
                    // Hidden for a Moment REPLY: the reply IS the photo
                    // ("no caption, just sending as such").
                    //
                    // Hidden for DIP as well — explicit correction: "in Dip
                    // you can't write anything, so only photo it will be."
                    // A Dip is a bare photo drop into a group, and the box
                    // was taking height from the photo for text that isn't
                    // part of the format. The `dips.caption` column added
                    // earlier stays (nullable, unread now) rather than
                    // being dropped again — the data costs nothing and a
                    // second schema round-trip to remove it would.
                    if (_dest != _Destination.momentReply &&
                        _dest != _Destination.group)
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: _ComposerField(
                          label: _captionLabel,
                          required: _dest == _Destination.moment,
                          currentLength: _captionCtrl.text.characters.length,
                          maxLength: _captionMaxChars,
                          child: TextField(
                            controller: _captionCtrl,
                            // Capped only where the caption is actually
                            // truncated downstream — see _captionMaxChars.
                            maxLength: _captionMaxChars,
                            // Fixed single line for every destination — a
                            // plain TextField with maxLines: 1 scrolls
                            // horizontally once the text outgrows the
                            // field, which keeps the box a constant height
                            // and the photo above it a constant size.
                            maxLines: 1,
                            buildCounter: _noCounter,
                            style: GoogleFonts.archivo(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.01 * 16,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              hintText: _captionHint,
                              hintStyle: GoogleFonts.archivo(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.01 * 16,
                                color: Colors.white.withValues(alpha: 0.38),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Answering an existing prompt — show what will appear
                    // in the peek bar, so it's never a surprise.
                    if (_dest == _Destination.anon &&
                        widget.answeringPrompt != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                        child: Text(
                          'Answering · ${widget.answeringPrompt}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.archivo(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _kAccent.withValues(alpha: 0.85),
                          ),
                        ),
                      ),

                    // ── Send — kept as this app's own pill button (white
                    // boundary/halo), not the reference design's giant
                    // text+triangle treatment.
                    //
                    // Collapsed while the keyboard is up — explicit request:
                    // "while typing there is no need of send button, let it
                    // stay below, after typing it can be seen." With the
                    // keyboard open the sheet has very little height left,
                    // and spending a chunk of it on a button you can't
                    // sensibly press mid-sentence squeezed the photo and
                    // the field you're actually typing into.
                    //
                    // AnimatedSize + AnimatedOpacity, not the hard
                    // `if (viewInsets.bottom == 0)` this replaces — that
                    // dropped the button from the tree outright, so it
                    // popped in at full size the instant the keyboard
                    // cleared zero instead of settling in alongside it.
                    // Explicit follow-up: "the transition from keyboard to
                    // clicking the send button shall be smooth."
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: keyboardOpen ? 0 : 1,
                        child: IgnorePointer(
                          ignoring: keyboardOpen,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: GestureDetector(
                              // Answering an existing prompt already carries its
                              // community (widget.answeringCommunityId, copied
                              // into _communityId in initState) — no need to ask
                              // again, so SEND posts straight away there. The
                              // free-form camera (no prompt) has no community yet,
                              // so SEND advances to the audience step instead
                              // (_buildAudienceStep), which is what calls
                              // _finishSend once a community is picked.
                              onTap: _sending || _blockedReason != null
                                  ? null
                                  : () {
                                      HapticFeedback.selectionClick();
                                      // Always the "Send to" step now —
                                      // a prompt-bar answer too, with its
                                      // community pre-ticked — so circles
                                      // can be added (explicit request,
                                      // 2026-10-03).
                                      setState(() => _showAudienceStep = true);
                                    },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                height: 54,
                                decoration: BoxDecoration(
                                  // Visible-but-disabled, the same "show what's
                                  // missing" rule the create flows follow — never
                                  // a hidden or absent send button.
                                  color: _blockedReason != null
                                      ? Colors.white.withValues(alpha: 0.28)
                                      : _sending
                                      ? Colors.white.withValues(alpha: 0.75)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(27),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      blurRadius: 18,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _sending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black,
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              widget.answeringCommunityId !=
                                                      null
                                                  ? 'SEND'
                                                  : 'NEXT',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
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
                        ),
                      ),
                    ),

                    // Why send is blocked — reserves its own line so the
                    // card doesn't jump as the reason appears/clears.
                    SizedBox(
                      height: 30,
                      child: Center(
                        child: Text(
                          _blockedReason ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.55),
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
                          _SheetKind.music => 'Add a sound',
                        },
                        trailing: switch (_openSheetKind!) {
                          _SheetKind.music =>
                            widget.selectedMusic != null
                                ? GestureDetector(
                                    onTap: _clearMusic,
                                    child: Text(
                                      'Remove',
                                      style: GoogleFonts.archivo(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.01 * 15,
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                        },
                        child: switch (_openSheetKind!) {
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

  /// Suppresses Flutter's built-in counter entirely.
  ///
  /// Returning null (not an empty widget) is what actually stops the
  /// InputDecorator reserving its counter/helper sub-row — an empty
  /// SizedBox still occupies that row's padding, which is what made these
  /// boxes taller than their content ("the boxes are way too big"). The
  /// count itself is drawn by _ComposerField on the label row.
  Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    int? maxLength,
  }) => null;

  /// One tap here both picks the community AND posts — no separate
  /// POST button, matching "like in snap for each user name... click and
  /// send" — each row IS the send action.
  void _togglePick(String communityId) {
    if (_sending) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!_pickedCommunityIds.remove(communityId)) {
        _pickedCommunityIds.add(communityId);
      }
    });
  }

  // ── Audience step — replaces the old inline pill row + community picker.
  // Reached by tapping SEND (see the send button's onTap above). A vertical
  // list of full-width rows, one per community — tapping a row sends to it
  // tick any number of communities, then POST once (one post, tagged to
  // every ticked community — see _togglePick / _finishSend).
  String _audienceButtonLabel() {
    final n = _pickedCommunityIds.length + _anonCircleIds.length;
    if (n == 0) return 'Pick a community or circle';
    return n == 1 ? 'POST' : 'POST TO $n';
  }

  /// Plain-camera send screen: the shot, who to send it to, one button.
  // ── Send to (people mode) ───────────────────────────────────────────────
  //
  // Third pass (2026-10-07). The 4-across grid of faces read as clutter
  // ("too clumsy ... in one go they shall be able to send everyone easy ...
  // anon shall be distinctively placed, not along the ping profiles"), so:
  //
  //  * QUICK PICKS at the top tick a whole set in one tap, no ticking by
  //    hand: "Pinged you" = everyone whose ping is open (people, anonymous
  //    senders AND groups); "Everyone" = every person and every group.
  //  * a plain LIST underneath for picking by hand — name beside the face,
  //    so it reads even when most people have no photo.
  //  * ANON is its own bar above the button, in its own colour, never a
  //    face among the people.
  //  * ONE Send button sends to everything ticked.

  /// Anon's own colour, so its bar can't be mistaken for one more person.
  static const _kAnonTint = Color(0xFF9B83FF);

  Widget _buildPeopleSend() {
    final targets = _targets;
    final all = targets ?? const <_PhotoTarget>[];
    final pingers = [
      for (final t in all)
        if (t.pingedMe) t,
    ];
    final n = _pickedTargets.length;
    final canSend = n > 0 || _pickedAnon;
    final label = !canSend
        ? 'Pick who gets it'
        : n == 0
        ? 'Post to Anon'
        : _pickedAnon
        ? 'Send to $n + Anon'
        : 'Send to $n';
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(48)),
      child: Container(
        color: const Color(0xFF0D0D0F),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 14),
              child: Text(
                'Send to',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            if (all.isNotEmpty) _quickPicks(all, pingers),
            Expanded(
              child: targets == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white54,
                      ),
                    )
                  : targets.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                      child: Text(
                        'Nobody to send to yet.\n'
                        'Add friends to your circle and they\'ll show up here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      itemCount: targets.length,
                      itemBuilder: (context, i) => _targetRow(targets[i]),
                    ),
            ),
            _anonBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: GestureDetector(
                key: const ValueKey('send-to-button'),
                onTap: _sending || !canSend ? null : _sendToPeople,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(27),
                    color: !canSend ? Colors.white.withValues(alpha: 0.10) : null,
                    gradient: !canSend
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF4A5BDE), Color(0xFFD1406E)],
                          ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.send_rounded,
                              size: 20,
                              color: !canSend
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : Colors.white,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              label,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: !canSend
                                    ? Colors.white.withValues(alpha: 0.45)
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ticks every one of [set] in one tap; tapping again when they are all
  /// ticked unticks them.
  void _toggleAll(List<_PhotoTarget> set) {
    if (_sending || set.isEmpty) return;
    HapticFeedback.selectionClick();
    final keys = {for (final t in set) t.key};
    setState(() {
      if (_pickedTargets.containsAll(keys)) {
        _pickedTargets.removeAll(keys);
      } else {
        _pickedTargets.addAll(keys);
      }
    });
  }

  /// "Pinged you" and "Everyone" — a whole set in one tap, groups included.
  Widget _quickPicks(List<_PhotoTarget> all, List<_PhotoTarget> pingers) {
    Widget chip({
      required Key key,
      required Widget lead,
      required String label,
      required List<_PhotoTarget> set,
    }) {
      final on =
          set.isNotEmpty && set.every((t) => _pickedTargets.contains(t.key));
      return Expanded(
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleAll(set),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              color: on
                  ? _kAccent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.06),
              border: Border.all(
                color: on ? _kAccent : Colors.white.withValues(alpha: 0.12),
                width: on ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                lead,
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${set.length}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: on ? _kAccent : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          if (pingers.isNotEmpty) ...[
            chip(
              key: const ValueKey('pick-pinged'),
              lead: const Text('👋', style: TextStyle(fontSize: 15)),
              label: 'Pinged you',
              set: pingers,
            ),
            const SizedBox(width: 10),
          ],
          chip(
            key: const ValueKey('pick-everyone'),
            lead: Icon(
              Icons.groups_2_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            label: 'Everyone',
            set: all,
          ),
        ],
      ),
    );
  }

  /// The round tick on the right of a row (and of the Anon bar).
  Widget _tick(bool on, {Color color = _kAccent}) => AnimatedContainer(
    duration: const Duration(milliseconds: 140),
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? color : Colors.transparent,
      border: Border.all(
        color: on ? color : Colors.white.withValues(alpha: 0.26),
        width: 1.8,
      ),
    ),
    child: on
        ? const Icon(Icons.check_rounded, size: 16, color: Colors.black)
        : null,
  );

  /// Anon, apart from the people: its own bar, its own colour, the person's
  /// own anon picture ("for anon post use the user's anon dp"; the mask
  /// until they've set one).
  Widget _anonBar() {
    final on = _pickedAnon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        key: const ValueKey('send-anon-bar'),
        behavior: HitTestBehavior.opaque,
        onTap: _sending
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() => _pickedAnon = !_pickedAnon);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: on
                ? _kAnonTint.withValues(alpha: 0.16)
                : const Color(0xFF15151A),
            border: Border.all(
              color: on ? _kAnonTint : _kAnonTint.withValues(alpha: 0.28),
              width: on ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              ListenableBuilder(
                listenable: AnonPersonaService.instance,
                builder: (context, _) {
                  final url = AnonPersonaService.instance.photoUrl;
                  final has = url != null && url.isNotEmpty;
                  return CircleAvatar(
                    radius: 19,
                    backgroundColor: const Color(0xFF1F1B2E),
                    backgroundImage: has ? NetworkImage(url) : null,
                    child: has
                        ? null
                        : const Icon(
                            Icons.masks_rounded,
                            size: 20,
                            color: _kAnonTint,
                          ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Also post to Anon',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'the anon feed, without your name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              _tick(on, color: _kAnonTint),
            ],
          ),
        ),
      ),
    );
  }

  /// One person or group in the list: face (👋 if they pinged, blue flame
  /// name, and the tick. The whole row is the tap target.
  Widget _targetRow(_PhotoTarget t) {
    final picked = _pickedTargets.contains(t.key);
    final isGroup = t.isGroup || t.groupId != null;
    final sub = t.pingedMe
        ? (t.isAnon
              ? 'pinged you anonymously'
              : isGroup
              ? 'group · pinged you'
              : 'pinged you')
        : isGroup
        ? 'group'
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _sending
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() {
                if (!_pickedTargets.remove(t.key)) _pickedTargets.add(t.key);
              });
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: t.pingedMe
                          ? _kAccent.withValues(alpha: picked ? 1 : 0.6)
                          : Colors.white.withValues(alpha: 0.12),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF16161A),
                    backgroundImage: t.avatarUrl == null
                        ? null
                        : NetworkImage(t.avatarUrl!),
                    child: t.avatarUrl == null
                        ? t.isAnon
                              // Masked: an anonymous pinger — nothing about
                              // who.
                              ? Icon(
                                  Icons.masks_rounded,
                                  size: 20,
                                  color: Colors.white.withValues(alpha: 0.8),
                                )
                              : isGroup
                              ? Icon(
                                  Icons.groups_rounded,
                                  size: 21,
                                  color: Colors.white.withValues(alpha: 0.8),
                                )
                              : Text(
                                  t.name.isEmpty
                                      ? '?'
                                      : t.name[0].toUpperCase(),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                )
                        : null,
                  ),
                ),
                // 👋 — pinged you and still open.
                if (t.pingedMe)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1B1B22),
                        border: Border.all(
                          color: _kAccent.withValues(alpha: 0.85),
                          width: 1.4,
                        ),
                      ),
                      child: const Text('👋', style: TextStyle(fontSize: 10.5)),
                    ),
                  ),
                // My streak with them, on their DP — the same blue flame
                // the Ping page puts on a face (every streak flame in the
                // app is blue; this was an orange 🔥 chip).
                if (t.streak > 0)
                  Positioned(
                    left: -9,
                    bottom: -6,
                    child: PV2Icons.blueFlameStreak(t.streak, flameSize: 22),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: picked ? FontWeight.w800 : FontWeight.w600,
                      color: Colors.white.withValues(alpha: picked ? 1 : 0.9),
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: t.pingedMe
                            ? _kAccent.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.42),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _tick(picked),
          ],
        ),
      ),
    );
  }

  /// COMMUNITIES then CIRCLES — tick any mix (explicit request,
  /// 2026-10-03: "post to communities, and include circles here as well").
  /// An anon post sent to a circle shows to its members, still anonymous.
  Widget _audienceList() {
    final communities = _communities ?? const <CommunityOption>[];
    final circles = (_circles ?? const <CircleOption>[])
        .where((c) => c.memberCount > 0)
        .toList();
    if (communities.isEmpty && circles.isEmpty) {
      return Center(
        child: Text(
          'Join a community or make a circle to post',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    Widget header(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(
        t,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      children: [
        if (communities.isNotEmpty) header('COMMUNITIES'),
        for (final c in communities)
          _audienceRow(
            picked: _pickedCommunityIds.contains(c.id),
            onTap: () => _togglePick(c.id),
            title: c.name,
            avatar: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              backgroundImage: c.iconUrl == null
                  ? null
                  : NetworkImage(c.iconUrl!),
              child: c.iconUrl == null
                  ? Icon(
                      Icons.groups_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                    )
                  : null,
            ),
          ),
        if (circles.isNotEmpty) header('CIRCLES'),
        for (final c in circles)
          _audienceRow(
            picked: _anonCircleIds.contains(c.id),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (!_anonCircleIds.remove(c.id)) _anonCircleIds.add(c.id);
              });
            },
            title: c.name,
            subtitle: c.memberCount == 1
                ? '1 person'
                : '${c.memberCount} people',
            avatar: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              child: Icon(
                c.isFriends
                    ? Icons.people_alt_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 20,
              ),
            ),
          ),
      ],
    );
  }

  Widget _audienceRow({
    required bool picked,
    required VoidCallback onTap,
    required String title,
    required Widget avatar,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: _sending ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: picked ? _kAccent : Colors.transparent,
                border: Border.all(
                  color: picked
                      ? _kAccent
                      : Colors.white.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: picked
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.black,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudienceStep() {
    final loading = _communities == null && _communitiesError == null;
    final nothingPicked = _pickedCommunityIds.isEmpty && _anonCircleIds.isEmpty;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(48)),
      child: Container(
        color: const Color(0xFF0D0D0F),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _sending
                          ? null
                          : () => setState(() => _showAudienceStep = false),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Send to',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _communitiesError != null
                    ? Center(
                        child: TextButton(
                          onPressed: () {
                            setState(() => _communitiesError = null);
                            _loadCommunities();
                          },
                          child: Text(
                            'Couldn\'t load communities — tap to retry',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      )
                    : _audienceList(),
              ),
              // One post, however many communities are ticked — the first
              // becomes its community, the rest are extra audience rows.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: GestureDetector(
                  onTap: _sending || nothingPicked
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          _finishSend();
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: nothingPicked
                          ? Colors.white.withValues(alpha: 0.10)
                          : _kAccent,
                      borderRadius: BorderRadius.circular(27),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            _audienceButtonLabel(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: nothingPicked
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : Colors.black,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Identity bar — TOP-of-photo strip, identity and nothing else ──────
  //
  // Explicit request: "post as you and anon — let that pill be in the top,
  // not along with the audience selector." Who a Moment comes FROM is a
  // different question from who it goes TO, and stacking both in the same
  // bottom row read as one four-way choice where two of the chips silently
  // meant something else. Identity now sits at the top of the frame on its
  // own; the bottom tray is purely destination + audience.
  //
  // The same strip serves a Moment REPLY, where identity is the ONLY choice
  // there is to make ("a third person replying to a Moment shall have a
  // reply-as button") — the Moment's audience was fixed by whoever posted
  // it.
  Widget _buildIdentityBar() {
    final isMoment = _dest == _Destination.moment;
    final isReply = _dest == _Destination.momentReply;
    if (!isMoment && !isReply) return const SizedBox.shrink();

    final asAnon = isReply ? _momentReplyAsAnon : _momentAsAnon;

    // A plain Column child, NOT a Positioned overlay — see the call site's
    // own note. No scrim gradient either: it sits on the sheet's own
    // background now, not over photo pixels that needed darkening.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      child: _IdentityPillRow(
        label: isReply ? 'REPLY AS' : 'POST AS',
        asAnon: asAnon,
        onChanged: (v) => setState(() {
          if (isReply) {
            _momentReplyAsAnon = v;
          } else {
            _momentAsAnon = v;
          }
        }),
      ),
    );
  }

  // ── Chip tray — bottom-of-photo gradient strip: destination pills on top,
  // then whichever chips that destination actually needs ────────────────
  // The pill row + inline community/group pickers that used to live here
  // were removed — community choice is now its own step after SEND (see
  // _buildAudienceStep), and Dip/Moments were already unreachable from this
  // camera (hidden pills — see _DestinationPills' own doc). Nothing renders
  // over the photo any more.
  Widget _buildChipTray() => const SizedBox.shrink();

  Widget _buildMusicSheet() {
    final q = _musicQuery.trim().toLowerCase();
    final filtered = <int>[
      for (var i = 0; i < _kMusicTracks.length; i++)
        if (q.isEmpty ||
            '${_kMusicTracks[i].$1} ${_kMusicTracks[i].$2}'
                .toLowerCase()
                .contains(q))
          i,
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
              Icon(
                Icons.search_rounded,
                size: 17,
                color: Colors.white.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _musicQuery = v),
                  style: GoogleFonts.archivo(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    hintText: 'Search songs',
                    hintStyle: GoogleFonts.archivo(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
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
                            color: _kAccent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            previewing
                                ? Icons.pause_rounded
                                : Icons.music_note_rounded,
                            color: _kAccent,
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
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.archivo(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.01 * 17,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.archivo(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      selected
                          ? Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.black,
                              ),
                            )
                          : Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.32),
                                  width: 2,
                                ),
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

    Widget img = widget.video != null
        // A recorded clip plays in the preview — autoplay muted, tap for
        // sound (2026-10-06).
        ? AppVideo(
            file: File(widget.video!.path),
            durationMs: widget.videoMs,
            autoPlay: true,
            fit: BoxFit.cover,
          )
        : Image.file(
            File(widget.photo!.path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );

    // Anon composer preview no longer grayscales the photo — matches the
    // real anon feed cards, which render in full color (item #6).

    // The extras strip lives at the TOP of the card, not below it: the
    // bottom is already _buildChipTray's gradient (destination pills,
    // moment palette, community picker) in the same Stack, and this card
    // is a fixed-aspect box with no spare vertical room to add a sibling
    // row without shrinking the photo itself. The "+" add tile is always
    // visible once a cover exists (onAddPhoto is non-null from every real
    // call site) — that's the discoverability Item 1 asked for. Only
    // dual-camera capture never reaches this: it renders through
    // _CandidMediaPreview instead of _buildPhotoView entirely.
    //
    // BUG FIX ("in moment only one photo can be added — see how things and
    // pills are getting mixed"): a fresh Moment (not a reply, which already
    // suppresses this via widget.onAddPhoto == null) shared this same top
    // strip with _buildIdentityBar's "POST AS" pills, and the two painted
    // on top of each other. A Moment is one photo, full stop — there was
    // never a real reason to offer "add another" here, only an oversight
    // that every OTHER destination wanted it. Suppressing it for Moment
    // removes the second occupant of that space entirely, rather than
    // trying to fit two rows into one.
    // Dips (anon) and Moments are single-photo posts — no "+" to add more.
    if (widget.onAddPhoto == null ||
        _dest == _Destination.moment ||
        _dest == _Destination.anon) {
      return img;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        img,
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _ExtrasStrip(
            photos: widget.extraPhotos,
            maxPhotos: widget.maxPhotos,
            onAdd: widget.onAddPhoto!,
            onRemove: widget.onRemovePhoto,
          ),
        ),
      ],
    );
  }
}

/// The cover photo's top overlay: an "add" tile, then a thumbnail per extra
/// photo with a remove ✕, then the "N of max · first is cover" label.
/// Self-contained (reuses this file's own SmallCircleBtn rather than
/// importing profile_v2's neumorphic AddTile, which belongs to a different
/// visual system) and stateless — all state lives in _ComposerScreenState.
/// One person on the plain camera's send screen. [pingId] set = they pinged
/// me and this photo answers it; [userId] set = a friend who gets a new
/// photo ping.
class _PhotoTarget {
  const _PhotoTarget({
    required this.key,
    required this.name,
    this.avatarUrl,
    this.pingId,
    this.userId,
    this.groupId,
    this.isGroup = false,
    this.isAnon = false,
    this.pingedMe = false,
    this.streak = 0,
  });

  final String key;
  final String name;
  final String? avatarUrl;
  final String? pingId;
  final String? userId;
  final String? groupId;

  /// They pinged me and it's still open — the tile wears a 👋 and sorts
  /// first. (Redesign 2026-10-06: the list now holds everyone you can send
  /// to, not only people who pinged.)
  final bool pingedMe;

  /// The ping was sent anonymously: shown as a masked "Someone". Answering
  /// goes through [pingId], so who it is stays hidden.
  final bool isAnon;

  /// My ping streak with this person (my_ping_streaks). 0 = none.
  final int streak;

  /// A GROUP's open ping (answered via [pingId] like a person's) — display
  /// only: the "groups" grid, the group icon, the "group pinged you" label.
  final bool isGroup;
}

Future<List<_PhotoTarget>>? _photoTargetsPreload;
List<_PhotoTarget>? _lastPhotoTargets;

/// Everyone a photo can go to — redesign 2026-10-06 ("don't show the pinged
/// users under a different category; keep the hand symbol on their DP;
/// include the other members who haven't pinged; show each person's streak").
///
/// ONE list, in the order the send screen shows it (2026-10-07 — the
/// people / groups headings are gone):
///
///  1. Whoever pinged me and is still open — people, anonymous senders and
///     groups together, newest first, each wearing a 👋. The photo answers
///     that ping (PingService.reply). Anonymous pingers are a masked
///     "Someone" — answering goes by ping id, so nothing about who they are
///     is revealed. A group ping takes one answer (the wall enforces it
///     server-side), so an answered one isn't here.
///  2. Everyone else in my Friends circle, longest streak first. The photo
///     reaches them as a NEW photo ping.
///  3. My other groups — a new group ping.
///
/// People I already have an open ping out to are left off, exactly as on the
/// Ping page (send_ping would refuse them: PING_ALREADY_OPEN).
Future<List<_PhotoTarget>> _fetchPhotoTargets() async {
  Future<Object?> safe(Future<Object?> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  final r = await Future.wait<Object?>([
    safe(PingService.instance.fetchToReply()),
    safe(CircleService.instance.fetchFriendsCircleUsers()),
    safe(PingService.instance.fetchSent()),
    safe(PingService.instance.fetchStreaks()),
    safe(GroupService.instance.fetchMyGroups()),
  ]);
  final inbox = (r[0] as List<InboundPingRow>?) ?? const <InboundPingRow>[];
  final friends =
      (r[1] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];
  final sent = (r[2] as List<OutboundPingRow>?) ?? const <OutboundPingRow>[];
  final streaks = (r[3] as Map<String, int>?) ?? const <String, int>{};
  final myGroups =
      (r[4] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];

  // Until the ping closes, replied or not — see openPingReceiverIds.
  final openSentTo = openPingReceiverIds(sent);
  final openSentGroups = <String>{
    for (final o in sent)
      if (o.isGroup && o.groupId != null && !o.replied) o.groupId!,
  };

  final pingers = <_PhotoTarget>[];
  final otherGroups = <_PhotoTarget>[];
  final seen = <String>{};
  // A group's ping carries its ASKER's photo. Shown on the group's row it
  // made two rows with one face — the person, and the group they asked in.
  final groupIcons = <String, String?>{
    for (final g in myGroups)
      if (g['id'] is String) g['id'] as String: g['icon_url'] as String?,
  };

  // 1. Pingers — newest open ping first (fetchToReply is newest-first).
  // Which of a sender's open pings stands for them is sendScreenPingers'
  // call: the one still waiting on a reply, so this photo answers it.
  for (final p in sendScreenPingers(inbox)) {
    seen.add(pingSenderKey(p));
    pingers.add(
      _PhotoTarget(
        key: 'ping:${p.id}',
        name: p.isGroup
            ? (p.groupName ?? p.senderName)
            : (p.isAnon ? 'Someone' : p.senderName),
        avatarUrl: p.isGroup
            ? groupIcons[p.groupId]
            : (p.isAnon ? null : p.senderAvatarUrl),
        pingId: p.id,
        isGroup: p.isGroup,
        isAnon: p.isAnon && !p.isGroup,
        pingedMe: true,
        streak: (p.isGroup || p.isAnon || p.senderId == null)
            ? 0
            : (streaks[p.senderId] ?? 0),
      ),
    );
  }

  // 2. Friends who haven't pinged me — a new photo ping, streak on the DP.
  final others = <_PhotoTarget>[];
  for (final f in friends) {
    final id = f['id'] as String?;
    if (id == null || seen.contains('user:$id') || openSentTo.contains(id)) {
      continue;
    }
    seen.add('user:$id');
    others.add(
      _PhotoTarget(
        key: 'user:$id',
        name: (f['name'] as String?) ?? 'someone',
        avatarUrl: f['profile_photo_url'] as String?,
        userId: id,
        streak: streaks[id] ?? 0,
      ),
    );
  }
  // Streaks first (the people you're keeping alive), then A-Z.
  others.sort((a, b) {
    final s = b.streak.compareTo(a.streak);
    return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  // 3. My other groups — a new group ping.
  for (final g in myGroups) {
    final id = g['id'] as String?;
    if (id == null ||
        seen.contains('group:$id') ||
        openSentGroups.contains(id)) {
      continue;
    }
    seen.add('group:$id');
    otherGroups.add(
      _PhotoTarget(
        key: 'group:$id',
        name: (g['name'] as String?) ?? 'Group',
        avatarUrl: g['icon_url'] as String?,
        groupId: id,
        isGroup: true,
      ),
    );
  }

  final out = [...pingers, ...others, ...otherGroups];
  _lastPhotoTargets = out;
  return out;
}

/// Posts [photoFuture]'s photo to the anon feed with nothing attached: no
/// caption, no prompt, no audience step. It goes to the General community
/// (every user is a member, so it reaches the whole anon feed), falling
/// back to the first joined community if General is ever missing.
Future<bool> _postAnonPhoto(
  Future<XFile?> photoFuture, {
  XFile? video,
  int? videoMs,
}) async {
  try {
    final photo = await photoFuture;
    if (photo == null) return false;
    final userId = await CurrentUserService.instance.resolveId();
    final joined = await CommunityService.instance.fetchMyCommunities();
    String? communityId;
    for (final c in joined) {
      if (c.name.trim().toLowerCase() == 'general') communityId = c.id;
    }
    communityId ??= joined.isEmpty ? null : joined.first.id;
    await PostService.instance.addPost(
      LocalPost(
        id: const Uuid().v4(),
        userId: userId,
        // Only ever shown on the optimistic card; the anon feed masks it.
        username: 'you',
        visibility: 'anonymous',
        caption: '',
        // For a clip, photo is its poster still (posts require one).
        photoPath: photo.path,
        videoPath: video?.path,
        videoMs: videoMs,
        communityId: communityId,
        showInFeed: true,
      ),
    );
    unawaited(ViewerScoreService.instance.refresh());
    return true;
  } catch (e) {
    debugPrint('[Composer] anon photo post failed: $e');
    return false;
  }
}

/// The width / height of an image file, read from its header. Falls back to
/// 4:5 if it can't be decoded, which is what posts used to be stored as.
Future<double> photoAspectOf(XFile file) async {
  try {
    final bytes = await File(file.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    final aspect = img.width / img.height;
    img.dispose();
    return aspect;
  } catch (_) {
    return 4 / 5;
  }
}

/// Returns how many recipients got it, plus a note for partial failures.
Future<(int, String?)> _deliverPhoto(
  Future<XFile?> photoFuture,
  List<_PhotoTarget> picked, {
  XFile? video,
  int? videoMs,
}) async {
  var sent = 0;
  String? note;
  try {
    final photo = await photoFuture;
    if (photo == null) return (0, null);
    // Re-check: a ping may have expired, or a group's (one answer each)
    // been answered elsewhere, while the camera was open. A person's ping
    // takes any number of replies until it expires.
    final inbox = await PingService.instance.fetchToReply();
    final live = {
      for (final p in inbox ?? const <InboundPingRow>[])
        if (!p.expired && !(p.isGroup && p.myReplies.isNotEmpty)) p.id,
    };
    final replies = [
      for (final t in picked)
        if (t.pingId != null && (inbox == null || live.contains(t.pingId)))
          t.pingId!,
    ];
    final people = [
      for (final t in picked)
        if (t.userId != null) t.userId!,
    ];
    final groups = [
      for (final t in picked)
        if (t.groupId != null) t.groupId!,
    ];

    // A recorded clip uploads ONCE and serves everyone. For a reply it goes
    // in video_url (kind stays 'photo'); for a NEW ping (a person or group
    // who hadn't pinged me) it rides in the ping's photo_url, recognised by
    // its extension — no schema change (2026-10-06).
    final String? url;
    if (video != null) {
      url = await StorageService.uploadPingVideo(
        file: File(video.path),
        pingId: 'outbound/${DateTime.now().millisecondsSinceEpoch}',
      );
    } else {
      url = await StorageService.uploadPingPhoto(
        file: File(photo.path),
        pingId: 'outbound/${DateTime.now().millisecondsSinceEpoch}',
      );
    }
    if (url == null) return (0, null);

    Future<bool> guard(Future<void> Function() f) async {
      try {
        await f();
        return true;
      } on PingLimitExceeded {
        note = "you've used today's 5 pings";
        return false;
      } catch (e) {
        debugPrint('[Composer] photo send failed: $e');
        // A group's wall takes one answer each (enforced server-side).
        if (e.toString().contains('already replied')) {
          note = 'a group already has your answer';
        }
        return false;
      }
    }

    final results = await Future.wait([
      for (final id in replies)
        guard(
          () => video != null
              ? PingService.instance.reply(
                  pingId: id,
                  videoUrl: url,
                  videoMs: videoMs,
                )
              : PingService.instance.reply(pingId: id, photoUrl: url),
        ),
      for (final g in groups)
        guard(
          () => PingService.instance.sendGroupPing(
            groupId: g,
            prompt: '',
            photoUrl: url,
          ),
        ),
    ]);
    sent += results.where((ok) => ok).length;

    if (people.isNotEmpty) {
      try {
        final res = await PingService.instance.sendMulti(
          receiverIds: people,
          prompt: '',
          photoUrl: url,
        );
        sent += res.sent;
        if (res.alreadyOpen > 0) {
          note = res.alreadyOpenNames.isEmpty
              ? 'already waiting on ${res.alreadyOpen}'
              : 'already waiting on ${res.alreadyOpenNames.join(', ')}';
        }
      } on PingLimitExceeded {
        note = "you've used today's 5 pings";
      }
    }
  } catch (e) {
    debugPrint('[Composer] deliver photo failed: $e');
  }
  return (sent, note);
}

class _ExtrasStrip extends StatelessWidget {
  const _ExtrasStrip({
    required this.photos,
    required this.maxPhotos,
    required this.onAdd,
    this.onRemove,
  });

  final List<XFile> photos;
  final int maxPhotos;
  final VoidCallback onAdd;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    final atCap = photos.length + 1 >= maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (!atCap)
                SmallCircleBtn(
                  icon: Icons.add_rounded,
                  onTap: onAdd,
                  size: 44,
                  iconSize: 20,
                ),
              for (var i = 0; i < photos.length; i++) ...[
                const SizedBox(width: 8),
                _ExtraThumb(
                  photo: photos[i],
                  onRemove: onRemove == null ? null : () => onRemove!(i),
                ),
              ],
            ],
          ),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${photos.length + 1} of $maxPhotos · first is the cover',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.75),
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ],
    );
  }
}

class _ExtraThumb extends StatelessWidget {
  const _ExtraThumb({required this.photo, this.onRemove});

  final XFile photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(photo.path),
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dual-photo preview — design-refs/camera feature's "Photo card" anatomy:
// full-bleed big photo, a small rounded/bordered inset for the other shot
// pinned to the top-left corner. Geometry (size/radius/border/margin) comes
// from DualInsetGeometry, shared with compositeDualPhotos so the flattened
// upload matches this preview exactly. Swapping which shot is big has two
// equivalent gestures: tap the small inset (original), or double-tap the
// big photo — both call [onToggleBig], plus a tray slot for the caller's
// chip row.
// ---------------------------------------------------------------------------

class _CandidMediaPreview extends StatelessWidget {
  const _CandidMediaPreview({
    required this.backPhoto,
    required this.frontPhoto,
    required this.frontIsBig,
    required this.onToggleBig,
    required this.tray,
  });

  final XFile backPhoto;
  final XFile frontPhoto;
  final bool frontIsBig;
  final VoidCallback onToggleBig;
  final Widget tray;

  static const _insetW = DualInsetGeometry.previewWidth;
  static const _insetH = DualInsetGeometry.previewHeight;
  static const _margin = DualInsetGeometry.previewMargin;
  static const _topMargin = DualInsetGeometry.previewTopMargin;

  // Anon composer preview no longer grayscales the dual-photo preview
  // either — full color, same as the real anon feed cards (item #6).
  Widget _photo(XFile file) {
    return Image.file(
      File(file.path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bigFile = frontIsBig ? frontPhoto : backPhoto;
    final smallFile = frontIsBig ? backPhoto : frontPhoto;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onDoubleTap: onToggleBig,
            child: _photo(bigFile),
          ),
        ),
        Positioned(
          // Mirrors the flattened composite exactly (DualInsetGeometry
          // .onRight) — the confirm preview and the posted photo have to
          // agree on which corner the inset lives in.
          right: DualInsetGeometry.onRight ? _margin : null,
          left: DualInsetGeometry.onRight ? null : _margin,
          top: _topMargin,
          child: GestureDetector(
            onTap: onToggleBig,
            child: Container(
              width: _insetW,
              height: _insetH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  DualInsetGeometry.previewRadius,
                ),
                border: Border.all(
                  color: DualInsetGeometry.previewBorderColor,
                  width: DualInsetGeometry.previewBorderWidth,
                ),
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
// _DestinationPills and _InlinePicker were both removed along with the pill
// row (see _buildChipTray) — the composer no longer shows a destination
// switcher at all; Anon is the only reachable free-form destination, and
// community choice moved to its own full-page step (_buildAudienceStep, a
// vertical list of rows — each row IS the send action). Dip/Moments were
// already unreachable from this camera before this change (see git history
// if either ever needs to come back).
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
      builder: (context, offset, child) =>
          FractionalTranslation(translation: offset, child: child),
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
                setState(
                  () => _height = (_dragStartHeight + dy).clamp(
                    _peek * 0.55,
                    _full,
                  ),
                );
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
                    style: GoogleFonts.archivo(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.02 * 20,
                      color: Colors.white,
                    ),
                  ),
                  if (widget.trailing != null)
                    Positioned(right: 2, child: widget.trailing!),
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
// Music — data + picker sheet
// ---------------------------------------------------------------------------

class _SelectedMusic {
  const _SelectedMusic({
    required this.title,
    required this.artist,
    required this.url,
  });
  final String title;
  final String artist;
  final String url;
}

const _kMusicTracks = <(String, String, String)>[
  (
    'Midnight Drive',
    'Neon Skyline',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
  ),
  (
    'Summer Haze',
    'Vista Dreams',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
  ),
  (
    'Golden Hour',
    'Atlas & Co.',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
  ),
  (
    'City Lights',
    'The Wanderers',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
  ),
  (
    'Ocean Floor',
    'Deep Blue',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
  ),
];

/// Moment audience + identity, inline in the composer's chip tray.
///
/// Same model AddMomentScreen uses: Everyone (default) or Friends, and when
/// Friends is picked, communities ADD to that audience rather than replace
/// it — can_view_post() admits an accepted friend regardless, so
/// "communities but not friends" isn't expressible server-side and offering
/// it would be a control that quietly does nothing.
/// An enclosed typing box: a labelled, bordered container around one
/// TextField.
///
/// Explicit request — "the space where we type, make it a box, enclosed,
/// and use proper words what the box is about". The composer's fields were
/// bare `InputBorder.none` TextFields sitting directly on the sheet, so
/// nothing marked where the typing area began and a field with no text in
/// it read as a stray line of grey copy rather than something to tap.
///
/// The label is the box's own caption, not a hint: it stays visible once
/// you have typed, which is exactly when a placeholder disappears and you
/// can no longer tell the heading box from the caption box.
class _ComposerField extends StatelessWidget {
  const _ComposerField({
    required this.label,
    required this.child,
    this.required = false,
    this.currentLength,
    this.maxLength,
  });

  final String label;
  final Widget child;

  /// Character count, rendered INLINE on the label row.
  ///
  /// BUG FIX ("the boxes are way too big, reduce the box size to what it
  /// actually needs and give photo space"): these used to pass
  /// `buildCounter` to the TextField, which makes Flutter's InputDecorator
  /// reserve a whole extra sub-row beneath the input for the counter —
  /// with its own padding — even under `isCollapsed: true`. That reserved
  /// row was the dead space under the text, and it cost the photo above
  /// the same height on every destination. Drawing the count myself on the
  /// label row (which already exists and has room to spare on its right)
  /// removes that row entirely.
  final int? currentLength;
  final int? maxLength;

  /// Draws the asterisk. The old copy carried it inline in the placeholder
  /// text ("Heading — what people see first *"), where it vanished the
  /// moment anything was typed.
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 7, 13, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
              if (required) ...[
                const SizedBox(width: 4),
                Text(
                  '*',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _kAccent.withValues(alpha: 0.8),
                  ),
                ),
              ],
              if (maxLength != null) ...[
                const Spacer(),
                Text(
                  '${currentLength ?? 0}/$maxLength',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: (currentLength ?? 0) >= maxLength!
                        ? _kAccent
                        : Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// The identity choice — your own name, or your anon persona.
///
/// Deliberately a two-chip choice rather than a single toggle: a toggle
/// reads as a setting you might not have noticed, and this one decides
/// whether your face goes out under your name. Lives at the TOP of the
/// photo (see _buildIdentityBar) so it is never read as part of the
/// audience row at the bottom, and serves both a Moment ("POST AS") and a
/// contribution to somebody else's ("REPLY AS").
class _IdentityPillRow extends StatelessWidget {
  const _IdentityPillRow({
    required this.label,
    required this.asAnon,
    required this.onChanged,
  });

  final String label;
  final bool asAnon;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Colors.white.withValues(alpha: 0.62),
          ),
        ),
        const SizedBox(width: 10),
        _chip('As you', !asAnon, () => onChanged(false)),
        const SizedBox(width: 7),
        _chip('As anon', asAnon, () => onChanged(true)),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _kAccent : Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _kAccent : Colors.white.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
