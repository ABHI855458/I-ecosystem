import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../../../shared/camera_pinch_zoom.dart';
import '../../../shared/volume_shutter.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../../../core/constants.dart';
import '../../../features/face_filter/face_input_image_converter.dart'
    show kFaceMaskImageFormatGroup;
import '../../../features/face_filter/face_mask_overlay.dart';
import '../../../features/face_filter/face_mask_presets.dart';
import 'center_select_rail.dart';
import 'reaction_camera_filters.dart';

// ---------------------------------------------------------------------------
// FaceReactionCapture — "Send a reaction" full-screen camera, rebuilt to
// design-refs/design_handoff_group_post_cards 2/README-camera.md +
// reference-camera.html: circular viewfinder, horizontally scrolling filter
// rail with a fixed center shutter, and (when the emoji hasn't already been
// chosen upstream) a second center-selection carousel for the reaction.
//
// Public API unchanged from the old bottom-sheet version — every existing
// caller (RealmojiTray's empty-slot capture, the preset-add flow) keeps
// working untouched; only the presentation moved from showModalBottomSheet
// to a full-screen push (see each call site), matching "a full-screen
// capture flow" in the spec's Overview.
// ---------------------------------------------------------------------------

class FaceReactionResult {
  const FaceReactionResult({required this.selfie, required this.emoji});
  final File selfie;
  final String emoji;
}

/// Reactions, in spec order — only ever reachable when [FaceReactionCapture
/// .presetEmoji] is null (no caller currently does this; every existing
/// call site picks the RealmojiType/emoji before opening the camera, so
/// this rail exists for a future "pick emoji here" caller without breaking
/// today's locked-emoji flow).
const kReactionCameraEmojis = [
  '👍', '❤️', '😂', '😍', '🔥', '😮', '🥲', '😭', '🥳', '💯',
  '👏', '🙌', '🤯', '😎', '🫶', '😴', '🤝', '✨', '🙃', '😤',
];

class FaceReactionCapture extends StatefulWidget {
  const FaceReactionCapture({
    super.key,
    required this.onFallbackToEmoji,
    this.presetEmoji,
    this.title = 'Send a reaction',
    this.accentColor = AppColors.coral,
  });

  /// Called when the front camera isn't available (denied permission, no
  /// front lens, init failure) and the user chooses to react with an emoji
  /// instead. The widget pops itself with null right after.
  final VoidCallback onFallbackToEmoji;

  /// When set, the emoji was already chosen UPSTREAM (RealmojiTray's
  /// per-type empty slot) — the reaction rail is replaced with a small
  /// fixed badge showing it instead of a pickable carousel, since there's
  /// nothing left to choose. Null shows the full reaction rail.
  final String? presetEmoji;

  final String title;

  /// Selected-state ring/pill tint — defaults to the coral every existing
  /// caller already expects; RealMoji's own callers pass neonCyan.
  final Color accentColor;

  @override
  State<FaceReactionCapture> createState() => _FaceReactionCaptureState();
}

enum _CamState { idle, initializing, live, captured, unavailable }

class _FaceReactionCaptureState extends State<FaceReactionCapture> {
  CameraController? _controller;
  _CamState _state = _CamState.idle;
  String? _errorMessage;
  Uint8List? _captureBytes;
  File? _captureFile;
  bool _processing = false;

  // 0 = 'none': a RealMoji starts as a normal photo; filters are opt-in.
  int _filterIndex = 0;
  int _reactionIndex = 3;

  /// Face-mask filter, off by default — a RealMoji is your own face, so
  /// concealing it is opt-in rather than the default. Same overlay and same
  /// bake the composer uses, so a RealMoji shot with it on looks identical
  /// to an anon post shot with it on.
  bool _maskOn = false;
  final _maskOverlayKey = GlobalKey<FaceMaskOverlayState>();

  /// Front (selfie) by default; the flip button switches to the back lens.
  bool _useBackLens = false;

  Future<void> _flipCamera() async {
    if (_state != _CamState.live) return;
    HapticFeedback.selectionClick();
    final old = _controller;
    setState(() {
      _controller = null;
      _state = _CamState.idle;
      _useBackLens = !_useBackLens;
    });
    await old?.dispose();
    await _openCamera();
  }

  @override
  void initState() {
    super.initState();
    // Open the lens immediately. This screen exists to take one photo, and
    // it used to land on an inert "tap to open camera" disc — a step with
    // no decision in it, between the person and the only thing the screen
    // does. Denial/no-front-lens still lands in _CamState.unavailable with
    // its own copy and its react-with-an-emoji way out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
    // Volume buttons take the photo too.
    unawaited(_volumeShutter.start(() {
      if (mounted && _state == _CamState.live) _capture();
    }));
  }

  final _volumeShutter = VolumeShutter();

  @override
  void dispose() {
    unawaited(_volumeShutter.stop());
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    if (_state == _CamState.initializing || _state == _CamState.live) return;
    setState(() {
      _state = _CamState.initializing;
      _errorMessage = null;
    });
    try {
      // Cached for the app's lifetime: the lens list never changes, and
      // re-querying it on every open was part of the slow first preview.
      final cameras = await (_camerasCache ??= availableCameras());
      final wanted = _useBackLens
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      var front = cameras.where((c) => c.lensDirection == wanted).toList();
      // Missing the requested lens: fall back to whatever exists.
      if (front.isEmpty) front = cameras;
      if (front.isEmpty) {
        if (!mounted) return;
        setState(() {
          _state = _CamState.unavailable;
          _errorMessage = "This device doesn't have a camera available.\nYou can send an emoji reaction instead.";
        });
        return;
      }
      // imageFormatGroup: the face-mask filter analyses this same stream
      // (see FaceMaskOverlay), and its converter requires a single-plane
      // format. Harmless to takePicture(), which is unaffected by it.
      final ctrl = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
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
        _state = _CamState.live;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.toLowerCase().contains('denied') ||
          e.code.toLowerCase().contains('permission');
      setState(() {
        _state = _CamState.unavailable;
        _errorMessage = denied
            ? 'Camera blocked — allow access in Settings'
            : "This device doesn't have a camera available.\nYou can send an emoji reaction instead.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _CamState.unavailable;
        _errorMessage = "This device doesn't have a camera available.\nYou can send an emoji reaction instead.";
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _processing) return;
    HapticFeedback.mediumImpact();
    setState(() => _processing = true);
    try {
      // BUG FIX ("capturing full white and taking too much time") — the ML
      // Kit analysis stream (started whenever the mask is on) used to keep
      // running straight through takePicture(), fighting it for the same
      // capture session. See FaceMaskOverlayState.pauseStreamingForCapture
      // for the full mechanism.
      if (_maskOn) {
        await _maskOverlayKey.currentState?.pauseStreamingForCapture();
      }
      var raw = await controller.takePicture();

      // BAKE FIRST, CROP SECOND. Order matters and used to be the other way
      // round, which is the whole reason the mask sat correctly in the live
      // preview but landed off the face in the saved RealMoji.
      //
      // bakeFaceMaskIntoPhoto maps the mask from the face-detection frame
      // onto the photo with a cover-fit (see computeMaskPlacement), so it
      // needs a photo that still has the FULL camera frame's dimensions.
      // Handing it the square-cropped, mirrored, filtered image meant it
      // solved that mapping against an image that no longer had anything to
      // do with the frame the face was detected in.
      //
      // Baking on the raw frame also means the crop/mirror below moves the
      // mask with the face, instead of the two being transformed apart.
      if (_maskOn) {
        final masked =
            await _maskOverlayKey.currentState?.bakeIntoPhoto(raw);
        if (masked != null) raw = masked;
      }

      final bytes = await File(raw.path).readAsBytes();
      // OFF THE UI THREAD. decode -> crop -> flip -> filter -> encode is
      // pure-Dart pixel work from package:image, and on a full-resolution
      // frame it blocked the main isolate for seconds — the camera froze
      // between tapping the shutter and the photo appearing. Reported as
      // "the RealMoji photo clicker is taking too much time to click".
      var jpg = await compute(
        _processCapture,
        _CaptureJob(bytes: bytes, filterIndex: _filterIndex),
      );

      // ONE retry, on a blank frame only. _processCapture returns null when
      // the capture came back as a uniform white field (see _looksBlank) —
      // the AVFoundation reconfigure race that pauseStreamingForCapture's
      // settle delay is there to prevent. That delay closes the window in
      // normal use; this catches the tail, because saving a blank white
      // RealMoji to someone's library is a much worse outcome than one
      // extra shutter cycle. Deliberately bounded to a single attempt: if
      // the second frame is blank too, something other than timing is
      // wrong and silently looping would hide it.
      if (jpg == null) {
        final retryRaw = await controller.takePicture();
        var retryFile = retryRaw;
        if (_maskOn) {
          final masked =
              await _maskOverlayKey.currentState?.bakeIntoPhoto(retryRaw);
          if (masked != null) retryFile = masked;
        }
        jpg = await compute(
          _processCapture,
          _CaptureJob(
            bytes: await File(retryFile.path).readAsBytes(),
            filterIndex: _filterIndex,
          ),
        );
      }
      if (jpg == null) throw StateError('capture came back blank');

      final tmp = File(
        '${Directory.systemTemp.path}/reaction_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes(jpg);

      if (!mounted) return;
      setState(() {
        _captureBytes = jpg;
        _captureFile = tmp;
        _state = _CamState.captured;
        _processing = false;
      });
    } catch (e, st) {
      debugPrint('[FaceReactionCapture._capture] failed: $e\n$st');
      if (mounted) setState(() => _processing = false);
    }
  }

  void _retake() {
    setState(() {
      _captureBytes = null;
      _captureFile = null;
      _state = _CamState.live;
    });
  }

  /// The confirm action, and the ONLY way out of the captured state with a
  /// result. Hands the file to whoever pushed this screen —
  /// RealmojiService.captureSelfieOnly (library) or captureAndReact (react
  /// from a post) — which uploads it and upserts the user_realmojis row.
  ///
  /// There is deliberately no camera-roll write here any more. The screen
  /// used to offer "Save photo", which wrote to the device gallery and, two
  /// seconds later, was also the only thing that returned the capture —
  /// "saving the emoji isn't saving to the gallery, it's saving the emoji
  /// into the RealMoji section". Saving a RealMoji means putting it in your
  /// RealMoji library, and that is what this does.
  void _useCapture() {
    final file = _captureFile;
    if (file == null) return;
    HapticFeedback.mediumImpact();
    final emoji = widget.presetEmoji ?? kReactionCameraEmojis[_reactionIndex];
    Navigator.of(context).pop(FaceReactionResult(selfie: file, emoji: emoji));
  }

  void _useEmojiInstead() {
    widget.onFallbackToEmoji();
    Navigator.of(context).pop();
  }

  /// Accumulated downward drag this gesture, in logical pixels — reset on
  /// every new drag. Explicit request: "when camera opens, swiping it down
  /// shall close it." A plain sum rather than tracking absolute position
  /// is enough here: this is a one-shot swipe-to-dismiss, not a resizable
  /// sheet with a settled height to spring back to.
  double _dragDownDy = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111114),
      body: SafeArea(
        child: GestureDetector(
          // opaque: without it, a swipe starting on empty space between
          // controls (not a button) wouldn't register at all.
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _dragDownDy = 0,
          onVerticalDragUpdate: (d) => _dragDownDy += d.delta.dy,
          onVerticalDragEnd: (d) {
            // Either a clear downward swipe (~1/6 of the screen) or a fast
            // downward flick, matching the everyday "drag a sheet away"
            // feel rather than requiring a full-screen drag.
            final flungDown = (d.primaryVelocity ?? 0) > 600;
            final draggedFarEnough =
                _dragDownDy > MediaQuery.of(context).size.height * 0.16;
            if (flungDown || draggedFarEnough) {
              Navigator.of(context).maybePop();
            }
          },
          child: Column(
          children: [
            const SizedBox(height: 8),
            // Explicit report — this screen had no way out at all: no
            // close button, and (on a device with no usable camera) no
            // successful-capture path to pop it either, so the only escape
            // was the OS back gesture. A close control belongs on any
            // full-screen camera surface regardless of whether the camera
            // itself came up.
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFFF2F2F4), size: 24),
                  tooltip: 'Close',
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF2F2F4),
                    ),
                  ),
                ),
                // Balances the close button so the title stays centred.
                // The mask toggle used to live here; it sits on the
                // viewfinder now, where you can see what it does.
                const SizedBox(width: 48, height: 48),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _maskOn
                    ? 'Mask on — your RealMoji will be saved with it.'
                    : widget.presetEmoji == null
                        ? 'Capture your own take on the reaction, then pick which one to send.'
                        : 'Take a selfie for this reaction — it becomes your RealMoji for it.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: const Color(0xFF9A9AA5),
                ),
              ),
            ),
            // BUG FIX (explicit report — screenshot showed it cut off at
            // the frame's edge): this used to sit INSIDE the viewfinder's
            // own `ClipOval` (Positioned bottom-left over the live
            // preview), which clipped it to the circle the instant it
            // strayed near the edge — visible in the same screenshot as a
            // sliver of "…sk" and half a thumbs-up. Its own comment said
            // "the mask control lives ON the viewfinder, not up in the
            // header," which is exactly what put it inside the clip. It
            // now sits between the subtitle and the viewfinder instead —
            // still right next to what it controls, but nothing left to
            // clip it.
            if (_state == _CamState.live) ...[
              const SizedBox(height: 14),
              Center(
                child: _MaskToggleChip(
                  on: _maskOn,
                  accent: widget.accentColor,
                  onTap: () => setState(() => _maskOn = !_maskOn),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Expanded(child: Center(child: _buildViewfinder())),
            // Filter rail + shutter are live-camera controls; once there's
            // a capture on screen the only two things left to do are keep
            // it or shoot again, so the row below swaps to those rather
            // than stacking a dead shutter above them.
            if (_state != _CamState.captured)
            SizedBox(
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CenterSelectRail(
                    itemCount: ReactionFilter.all.length,
                    itemExtent: 74,
                    initialIndex: _filterIndex,
                    onSelectedChanged: (i) => setState(() => _filterIndex = i),
                    itemBuilder: (context, i, selected) =>
                        _FilterChip(filter: ReactionFilter.all[i], selected: selected),
                  ),
                  _ShutterButton(
                    filter: ReactionFilter.all[_filterIndex],
                    busy: _processing,
                    onTap: () {
                      if (_state == _CamState.idle || _state == _CamState.unavailable) {
                        _openCamera();
                      } else if (_state == _CamState.live) {
                        _capture();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            if (_state != _CamState.captured)
              Text(
                ReactionFilter.all[_filterIndex].name.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  letterSpacing: 0.08 * 11,
                  color: const Color(0xFFF2F2F4),
                ),
              ),
            if (_state == _CamState.captured) ...[
              const SizedBox(height: 14),
              _RetakeSaveRow(
                accentColor: widget.accentColor,
                onRetake: _retake,
                onUse: _useCapture,
              ),
            ],
            const SizedBox(height: 14),
            // Locked-emoji flow shows the reaction on the viewfinder rim
            // instead (see _buildViewfinder) — a second copy of it down
            // here was the same information twice.
            if (widget.presetEmoji == null)
              _ReactionRailSection(
                accentColor: widget.accentColor,
                initialIndex: _reactionIndex,
                onSelectedChanged: (i) => setState(() => _reactionIndex = i),
              ),
            const SizedBox(height: 12),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    // Sized off the viewport rather than a fixed 248: on a large phone the
    // old disc floated in the middle of a lot of empty dark, and on a small
    // one it crowded the rail below it.
    final w = MediaQuery.sizeOf(context).width;
    final side = math.min(math.max(w - 96, 200.0), 320.0);
    final live = _state == _CamState.live;
    final captured = _state == _CamState.captured;
    final ring = captured
        ? widget.accentColor
        : live
            ? widget.accentColor.withValues(alpha: 0.55)
            : const Color(0xFF1C1C22);

    return SizedBox(
      width: side + 24,
      height: side + 24,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: side,
            height: side,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
              border: Border.all(color: ring, width: captured ? 3.5 : 3),
              boxShadow: live || captured
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.22),
                        blurRadius: 34,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ClipOval(child: _viewfinderContent()),
          ),
          // Flip camera: on the viewfinder's bottom-right rim — right where
          // the thumb is, outside the round clip so it's never cut off, and
          // a full 48px target.
          if (live)
            Positioned(
              right: 0,
              bottom: 10,
              child: GestureDetector(
                onTap: _flipCamera,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF16161B),
                    border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 10),
                    ],
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          // The reaction being shot, on the rim — so it's obvious WHICH
          // RealMoji this capture becomes. Only for the locked-emoji flow;
          // when the rail below is pickable it would contradict it.
          if (widget.presetEmoji != null)
            Positioned(
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161B),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: widget.accentColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  widget.presetEmoji!,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _viewfinderContent() {
    switch (_state) {
      case _CamState.idle:
        return GestureDetector(
          onTap: _openCamera,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📷', style: TextStyle(fontSize: 34)),
                const SizedBox(height: 8),
                Text(
                  'tap to open camera',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF5C5C66)),
                ),
              ],
            ),
          ),
        );
      case _CamState.initializing:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        );
      case _CamState.unavailable:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚫', style: TextStyle(fontSize: 30)),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? "This device doesn't have a camera available.\nYou can send an emoji reaction instead.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    height: 1.5,
                    color: const Color(0xFFFF8A7A),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _useEmojiInstead,
                  child: Text(
                    'React with an emoji instead',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _CamState.live:
        final controller = _controller!;
        return GestureDetector(
          onTap: _capture,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _livePreview(controller),
              // FACE MASK FILTER — same overlay the composer uses.
              if (_maskOn)
                Positioned.fill(
                  child: FaceMaskOverlay(
                    key: _maskOverlayKey,
                    controller: controller,
                    maskAssetPath: kFaceMaskPresetC,
                    // previewMirrored is gone (defaults to false):
                    // _livePreview no longer flips the preview, so the
                    // overlay's own platform rule applies unaided — same as
                    // the composer and the ping camera. See _livePreview.
                  ),
                ),
              // The toggle itself now renders ABOVE the viewfinder (see the
              // build method) — the ClipOval this Stack sits inside clipped
              // it whenever it neared the circle's edge.
            ],
          ),
        );
      case _CamState.captured:
        return Image.memory(_captureBytes!, fit: BoxFit.cover);
    }
  }

  /// NOT mirrored — same as every other camera in the app.
  ///
  /// This used to wrap the preview in `Transform.scale(scaleX: -1)`, which
  /// made the RealMoji camera the ONLY one that showed you a mirror image:
  /// the composer's viewfinder and the ping camera's both render the plain
  /// sensor frame (ping_reveal_screen says so explicitly — "NOT wrapped in
  /// a mirroring Transform here, unlike face_reaction_capture"). Reported
  /// as the RealMoji camera showing a mirrored image where the other tabs
  /// don't.
  ///
  /// Removing the flip is a three-part change, all of which move together
  /// or the mask and the saved photo come apart:
  ///   1. this Transform,
  ///   2. FaceMaskOverlay's `previewMirrored` (now the default false —
  ///      with the host no longer mirroring, the overlay's own platform
  ///      rule is correct unaided),
  ///   3. _processCapture's flipHorizontal, which existed only to make the
  ///      saved photo match this mirrored preview.
  Widget _livePreview(CameraController controller) {
    return CameraPinchZoom(
      controller: controller,
      child: _filteredPreview(controller),
    );
  }

  Widget _filteredPreview(CameraController controller) {
    return ColorFiltered(
      colorFilter:
          ColorFilter.matrix(ReactionFilter.all[_filterIndex].colorFilterMatrix),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter rail chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.filter, required this.selected});
  final ReactionFilter filter;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFF2F2F4) : const Color(0xFF23232B),
          width: 2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: filter.swatchGradient,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixed shutter button, pinned at the filter rail's exact center.
// ---------------------------------------------------------------------------

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.filter, required this.busy, required this.onTap});
  final ReactionFilter filter;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: busy,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0E0E11),
            border: Border.all(color: const Color(0xFFF2F2F4), width: 5),
            boxShadow: const [
              BoxShadow(color: Color(0xE60A0A0C), blurRadius: 0, spreadRadius: 4),
              BoxShadow(color: Color(0x8C000000), blurRadius: 26, offset: Offset(0, 10)),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: filter.swatchGradient,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x47FFFFFF), blurRadius: 10, offset: Offset(0, 3)),
                BoxShadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, -6)),
              ],
            ),
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Retake / Save row — only shown after a capture.
// ---------------------------------------------------------------------------

/// Post-capture actions: go again, or keep it.
///
/// The old pair was Retake + "Save photo" — the latter wrote to the camera
/// roll and was, confusingly, also the only control that finished the flow.
/// Keeping a RealMoji means saving it into your RealMoji library, so that
/// is what the primary says and does; there is no gallery write left.
class _RetakeSaveRow extends StatelessWidget {
  const _RetakeSaveRow({
    required this.accentColor,
    required this.onRetake,
    required this.onUse,
  });

  final Color accentColor;
  final VoidCallback onRetake;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onRetake,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C22),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.refresh_rounded, size: 17, color: Colors.white),
                const SizedBox(width: 7),
                Text(
                  'Retake',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onUse,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.34),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, size: 18, color: Color(0xFF0E0E11)),
                const SizedBox(width: 7),
                Text(
                  'Save RealMoji',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0E0E11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction rail — only reachable when presetEmoji is null (see class doc).
// ---------------------------------------------------------------------------

class _ReactionRailSection extends StatelessWidget {
  const _ReactionRailSection({
    required this.accentColor,
    required this.initialIndex,
    required this.onSelectedChanged,
  });

  final Color accentColor;
  final int initialIndex;
  final ValueChanged<int> onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'SWIPE TO CHOOSE A REACTION',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            letterSpacing: 0.1 * 11,
            color: const Color(0xFF6F6F7A),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 66,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CenterSelectRail(
                itemCount: kReactionCameraEmojis.length,
                itemExtent: 68,
                initialIndex: initialIndex,
                onSelectedChanged: onSelectedChanged,
                itemBuilder: (context, i, selected) => Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1C1C22)),
                  child: Center(
                    child: Text(kReactionCameraEmojis[i], style: const TextStyle(fontSize: 23)),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF2F2F4), width: 4),
                    boxShadow: const [
                      BoxShadow(color: Color(0x24F2F2F4), blurRadius: 0, spreadRadius: 3),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// Inputs for [_processCapture]. Must be a plain value type — it crosses an
/// isolate boundary, so it can hold no widgets, controllers or closures.
class _CaptureJob {
  const _CaptureJob({required this.bytes, required this.filterIndex});
  final Uint8List bytes;
  final int filterIndex;
}

/// decode -> square-crop -> mirror -> colour filter -> JPEG, on a background
/// isolate (see the compute() call in _capture).
///
/// Top-level, not a method: compute() can only run a function with no
/// captured state.
/// True when [src] is essentially a blank/blown-out frame — the "capturing
/// full white" failure (see FaceMaskOverlayState.pauseStreamingForCapture).
///
/// Sampled on a sparse grid rather than every pixel: this runs on the
/// capture path, and ~400 samples is plenty to tell a real photo from a
/// uniform white field. A genuine photo — even a bright, backlit selfie —
/// has *some* variation across the frame; a frame the sensor never
/// properly exposed does not.
bool _looksBlank(img.Image src) {
  const steps = 20;
  var min = 255;
  var max = 0;
  for (var i = 0; i < steps; i++) {
    for (var j = 0; j < steps; j++) {
      final p = src.getPixel(
        (src.width - 1) * i ~/ (steps - 1),
        (src.height - 1) * j ~/ (steps - 1),
      );
      final lum = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b).round();
      if (lum < min) min = lum;
      if (lum > max) max = lum;
    }
  }
  // Near-uniform AND near-white. Both conditions matter: a legitimately
  // flat dark shot (lens covered) is a real capture the person can see and
  // retake themselves, and shouldn't trigger an automatic retry.
  return (max - min) <= 6 && min >= 236;
}

Uint8List? _processCapture(_CaptureJob job) {
  var decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;
  // Bail early so the caller can retry the capture once — see _capture.
  if (_looksBlank(decoded)) return null;
  final side = math.min(decoded.width, decoded.height);
  decoded = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  // A RealMoji only ever renders as a small circle, so filter + encode at
  // 720px, not the full sensor frame — the bulk of the "takes too much time
  // to capture" wait was pixel work on detail nobody sees.
  if (side > 720) {
    decoded = img.copyResize(
      decoded,
      width: 720,
      height: 720,
      interpolation: img.Interpolation.average,
    );
  }
  // No horizontal flip any more. It existed solely to make the saved photo
  // match a MIRRORED preview; the preview isn't mirrored now (see
  // _livePreview), so flipping here would put the photo back out of step
  // with what the person actually saw — and drag the already-baked mask
  // with it, since the bake happens upstream on the raw frame.
  decoded = ReactionFilter.all[job.filterIndex].apply(decoded);
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
}

/// The face-mask toggle, as a labelled pill on the viewfinder.
///
/// Labelled rather than icon-only: "masks" as a bare glyph reads as a
/// medical mask, a filter, or nothing at all, and this control decides
/// whether your face is in the photo.
class _MaskToggleChip extends StatelessWidget {
  const _MaskToggleChip({
    required this.on,
    required this.accent,
    required this.onTap,
  });

  final bool on;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? accent : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? accent : Colors.white.withValues(alpha: 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.masks_rounded,
              size: 15,
              color: on ? const Color(0xFF0E0E11) : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              on ? 'Mask on' : 'Mask',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: on ? const Color(0xFF0E0E11) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The device's cameras, looked up once — see _openCamera.
Future<List<CameraDescription>>? _camerasCache;

/// Warm the camera list early (e.g. when a feed shows) so the first
/// RealMoji capture opens its preview without the lookup.
void prewarmRealmojiCamera() {
  _camerasCache ??= availableCameras();
}
