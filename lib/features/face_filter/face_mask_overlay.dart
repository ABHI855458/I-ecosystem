import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_input_image_converter.dart';
import 'face_mask_capture.dart';
import 'face_mask_painter.dart';
import 'face_mask_transform.dart';
import 'face_mask_presets.dart';
import 'landmark_smoother.dart';

/// Real-time face-tracked mask overlay. Paints ONLY the mask — draws no
/// preview of its own — so it can be layered on top of an existing
/// [CameraPreview] via a [Stack] without owning or competing for the
/// [controller]'s lifecycle. The host is responsible for creating that
/// controller WITH `imageFormatGroup: kFaceMaskImageFormatGroup` (see
/// face_input_image_converter.dart) and for disposing it.
///
/// For a fully standalone camera screen that owns its own controller, see
/// [FaceFilterCameraView] in face_filter_camera_view.dart, which wraps this
/// widget.
class FaceMaskOverlay extends StatefulWidget {
  const FaceMaskOverlay({
    super.key,
    required this.controller,
    required this.maskAssetPath,
    this.maskAllFaces = false,
    this.previewMirrored = false,
    // Higher alpha = follows the face faster (less lag), lower = smoother
    // but laggier. 0.4 at 10fps was sluggish; at 20fps 0.55 keeps the mask
    // on the face without reintroducing jitter.
    this.smoothingAlpha = 0.55,
    this.widthRatio = kMaskWidthToEyeDistanceRatio,
    // 100ms = 10fps, which reads as the mask lagging a beat behind the
    // face. 50ms (20fps) tracks smoothly and is affordable now that
    // contours are off and the detector is in fast mode.
    this.minProcessInterval = const Duration(milliseconds: 50),
  });

  /// Must already be initialized and streaming-capable (created with
  /// `imageFormatGroup: kFaceMaskImageFormatGroup`).
  final CameraController controller;

  /// Asset path of the mask PNG (alpha). Null disables detection entirely
  /// (no image stream started, nothing painted) — use this for an "off"
  /// state rather than unmounting the widget, so toggling doesn't restart
  /// the camera's image stream every time.
  final String? maskAssetPath;

  /// false = mask only the largest detected face; true = mask every face.
  final bool maskAllFaces;

  /// Set this when the host has flipped the CameraPreview itself — i.e. it
  /// wraps the preview in `Transform.scale(scaleX: -1)`.
  ///
  /// FaceFilterCameraView (the composer) does not; FaceReactionCapture (the
  /// RealMoji camera) does. Since the overlay is painted OUTSIDE that
  /// Transform, the picture underneath it was flipped and the mask was not,
  /// so the mask sat mirrored about the centre line from the face. That is
  /// why the same overlay tracked correctly in the composer and "isn't even
  /// aligning to face" in RealMoji — nothing was wrong with the detection,
  /// the two hosts just disagreed about which way round the preview was.
  ///
  /// Affects the live painter only. The captured photo is unaffected: a
  /// host's preview transform is not applied to what takePicture() returns.
  final bool previewMirrored;

  /// EMA smoothing weight, 0.3–0.5 recommended.
  final double smoothingAlpha;

  /// Mask width as a multiple of inter-eye distance.
  final double widthRatio;

  /// Minimum spacing between ML Kit detection calls — throttles analysis
  /// independently of the live preview's own frame rate.
  final Duration minProcessInterval;

  @override
  State<FaceMaskOverlay> createState() => FaceMaskOverlayState();
}

class _TrackedFace {
  _TrackedFace(this.smoother);
  final FaceLandmarkSmoother smoother;
  Offset lastCenter = Offset.zero;
  bool matchedThisFrame = false;
}

class FaceMaskOverlayState extends State<FaceMaskOverlay> {
  FaceDetector? _detector;
  ui.Image? _maskImage;
  String? _loadedMaskPath;

  bool _streaming = false;
  bool _busy = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  List<FaceMaskTransform> _transforms = const [];
  Size _analysisImageSize = Size.zero;

  late FaceLandmarkSmoother _singleFace;
  final _multiFaces = <_TrackedFace>[];

  @override
  void initState() {
    super.initState();
    _singleFace = FaceLandmarkSmoother(alpha: widget.smoothingAlpha);
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        // Landmarks are the only thing read (eyes + nose base — see
        // RawFacePoints.fromFace).
        enableLandmarks: true,
        // Contours OFF. Nothing consumes them, and they are by far the most
        // expensive thing ML Kit can be asked for — computing a full face
        // mesh every frame and throwing it away.
        enableContours: false,
        enableClassification: false,
        // FAST, not accurate. `accurate` is meant for stills; on a live
        // stream it costs far more per frame than the tracking gains, so
        // detections arrive late and the mask visibly trails the face —
        // part of why the filter reads as not sticking.
        performanceMode: FaceDetectorMode.fast,
        // Lets ML Kit track the same face across frames instead of
        // re-detecting cold each time, which is what actually produces
        // stable landmark positions rather than a jittering box.
        enableTracking: true,
      ),
    );
    _syncMaskAsset();
    // Deferred one frame. startImageStream() makes CameraController notify
    // its listeners synchronously, and this widget sits under a
    // ValueListenableBuilder<CameraValue> (CameraPreview's own) — so
    // calling it straight from initState marks that builder dirty while
    // the framework is still building, which throws "setState() or
    // markNeedsBuild() called during build". Caught live on device with
    // this exact stack (_syncStreaming <- initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncStreaming();
    });
  }

  @override
  void didUpdateWidget(covariant FaceMaskOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maskAssetPath != widget.maskAssetPath) {
      _syncMaskAsset();
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.maskAssetPath != widget.maskAssetPath) {
      // Same deferral as initState — didUpdateWidget also runs inside the
      // build phase, so starting/stopping the stream here synchronously
      // hits the identical "called during build" assertion.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncStreaming();
      });
    }
  }

  Future<void> _syncMaskAsset() async {
    final path = widget.maskAssetPath;
    if (path == null) {
      setState(() {
        _maskImage = null;
        _loadedMaskPath = null;
        _transforms = const [];
      });
      return;
    }
    if (path == _loadedMaskPath) return;
    try {
      final bytes = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      if (!mounted || widget.maskAssetPath != path) return;
      setState(() {
        _maskImage = frame.image;
        _loadedMaskPath = path;
      });
    } catch (_) {
      // Asset not bundled yet (e.g. preset_c.png hasn't been dropped into
      // assets/masks/ yet) — leave _maskImage null so the painter simply
      // draws nothing, same as "no face detected".
    }
  }

  Future<void> _syncStreaming() async {
    final shouldStream =
        widget.maskAssetPath != null &&
        widget.controller.value.isInitialized;
    if (shouldStream == _streaming) return;
    if (shouldStream) {
      _streaming = true;
      _singleFace.reset();
      _multiFaces.clear();
      try {
        await widget.controller.startImageStream(_onFrame);
      } catch (_) {
        _streaming = false;
      }
    } else {
      _streaming = false;
      try {
        await widget.controller.stopImageStream();
      } catch (_) {}
      if (mounted) {
        setState(() => _transforms = const []);
      }
    }
  }

  void _onFrame(CameraImage image) {
    if (_busy) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessed) < widget.minProcessInterval) return;
    _busy = true;
    _lastProcessed = now;
    _processFrame(image).whenComplete(() => _busy = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    final detector = _detector;
    if (detector == null) return;
    final inputImage = inputImageFromCameraImage(image, widget.controller);
    if (inputImage == null) return;

    List<Face> faces;
    try {
      faces = await detector.processImage(inputImage);
    } catch (_) {
      return;
    }
    if (!mounted) return;

    // The space ML Kit reports landmarks in, derived from the SAME rotation
    // the InputImage was built with — see analysisSizeFor. This used to be
    // an unconditional width/height swap, which was wrong on iOS (the
    // buffer is already portrait) and put the eye midpoint outside the
    // frame entirely.
    final analysisSize = analysisSizeFor(image, widget.controller);
    if (analysisSize == null) return;

    final transforms = widget.maskAllFaces
        ? _computeMultiFace(faces)
        : _computeSingleFace(faces);

    setState(() {
      _transforms = transforms;
      _analysisImageSize = analysisSize;
    });
  }

  List<FaceMaskTransform> _computeSingleFace(List<Face> faces) {
    if (faces.isEmpty) {
      _singleFace.reset();
      return const [];
    }
    Face primary = faces.first;
    for (final f in faces.skip(1)) {
      if (f.boundingBox.height > primary.boundingBox.height) primary = f;
    }
    final raw = RawFacePoints.fromFace(primary);
    if (raw == null) {
      _singleFace.reset();
      return const [];
    }
    final smoothed = _singleFace.update(
      leftEye: raw.leftEye,
      rightEye: raw.rightEye,
      noseBase: raw.noseBase,
      boxCenter: raw.boxCenter,
      boxWidth: raw.boxWidth,
      boxHeight: raw.boxHeight,
    );
    final transform = computeFaceMaskTransform(
      smoothed,
      widthRatio: widget.widthRatio,
    );
    return transform == null ? const [] : [transform];
  }

  List<FaceMaskTransform> _computeMultiFace(List<Face> faces) {
    for (final t in _multiFaces) {
      t.matchedThisFrame = false;
    }
    const matchThreshold = 150.0;
    final transforms = <FaceMaskTransform>[];

    for (final face in faces) {
      final raw = RawFacePoints.fromFace(face);
      if (raw == null) continue;
      final rawCenter = Offset(
        (raw.leftEye.dx + raw.rightEye.dx) / 2,
        (raw.leftEye.dy + raw.rightEye.dy) / 2,
      );

      _TrackedFace? best;
      double bestDist = matchThreshold;
      for (final t in _multiFaces) {
        if (t.matchedThisFrame) continue;
        final d = (t.lastCenter - rawCenter).distance;
        if (d < bestDist) {
          bestDist = d;
          best = t;
        }
      }
      if (best == null) {
        best = _TrackedFace(FaceLandmarkSmoother(alpha: widget.smoothingAlpha));
        _multiFaces.add(best);
      }
      best.matchedThisFrame = true;
      best.lastCenter = rawCenter;

      final smoothed = best.smoother.update(
        leftEye: raw.leftEye,
        rightEye: raw.rightEye,
        noseBase: raw.noseBase,
        boxCenter: raw.boxCenter,
        boxWidth: raw.boxWidth,
        boxHeight: raw.boxHeight,
      );
      final transform = computeFaceMaskTransform(
        smoothed,
        widthRatio: widget.widthRatio,
      );
      if (transform != null) transforms.add(transform);
    }

    _multiFaces.removeWhere((t) => !t.matchedThisFrame);
    return transforms;
  }

  /// Stops the ML Kit analysis stream so [CameraController.takePicture] can
  /// have the capture session to itself.
  ///
  /// BUG FIX (explicit report — "capturing full white and taking too much
  /// time"): nothing ever called `stopImageStream()` before a still
  /// capture, so `takePicture()` ran while `startImageStream()` was still
  /// actively pulling frames off the same session. On iOS in particular,
  /// AVFoundation does not cleanly serve a still-photo capture and a
  /// live video-data-output stream from one session at once — the capture
  /// forces an on-the-fly reconfiguration (the multi-second delay) and can
  /// hand back a photo taken before the sensor/exposure has caught up from
  /// that reconfiguration (the blank white frame). Call this, then
  /// `takePicture()`, then (if the mask is still wanted) [bakeIntoPhoto].
  ///
  /// Safe to call whether or not this widget is still mounted or was ever
  /// streaming — matches [dispose]'s own defensive shape. No corresponding
  /// "resume" is needed: this widget only exists for `_CamState.live`, and
  /// every path out of `live` either unmounts it (a kept capture) or
  /// remounts a fresh instance on retake, which restarts streaming in its
  /// own `initState` as normal.
  Future<void> pauseStreamingForCapture() async {
    if (!_streaming) return;
    _streaming = false;
    try {
      await widget.controller.stopImageStream();
      // SETTLE DELAY — not padding, load-bearing. Reported twice: "capturing
      // full white."
      //
      // stopImageStream()'s Future resolves when the method-channel call
      // returns, NOT when AVFoundation has finished tearing the video-data
      // output off the session and re-metering for stills. Firing
      // takePicture() inside that window returns a frame the sensor
      // exposed for the OLD configuration — on a bright/front-facing
      // subject that comes back blown out to pure white, which is exactly
      // the reported symptom and why simply stopping the stream (the first
      // fix) narrowed the race without closing it.
      //
      // 220ms is the smallest delay that reliably clears the reconfigure +
      // AE re-lock on this project's target hardware. It costs a fifth of
      // a second on a path that was previously taking multiple seconds.
      await Future<void>.delayed(const Duration(milliseconds: 220));
    } catch (_) {
      // Best-effort — a capture should proceed even if the stream was
      // already stopping on its own.
    }
  }

  /// Bakes the mask into [rawPhoto] using the most recently seen transform
  /// (the first tracked face, if any). Returns [rawPhoto] unchanged if no
  /// face was being tracked at capture time.
  Future<XFile> bakeIntoPhoto(XFile rawPhoto) async {
    final path = widget.maskAssetPath;
    if (path == null || _transforms.isEmpty) return rawPhoto;
    return bakeFaceMaskIntoPhoto(
      photo: rawPhoto,
      maskAssetPath: path,
      transform: _transforms.first,
      analysisImageSize: _analysisImageSize,
      mirrored: _mirroredForPhoto,
      anchor: anchorForPreset(path),
    );
  }

  /// Whether the analysis coordinates need flipping to match what's on
  /// screen. ONE definition, read by both the painter and the bake — they
  /// each used to decide for themselves, and only one of them was updated.
  ///
  /// Not mirrored on iOS: the plugin hands over an already-portrait
  /// 720x1280 buffer (a raw front-sensor frame would be landscape
  /// 1280x720), so it has already applied the device transform and with it
  /// the front-camera mirror. Flipping again put the mask on the opposite
  /// side of centre from the face. Android's buffer really is the raw
  /// sensor frame, so it still needs the flip.
  bool get _mirrored =>
      !Platform.isIOS &&
      widget.controller.description.lensDirection ==
          CameraLensDirection.front;

  /// What the PAINTER uses: the platform rule, flipped again if the host
  /// mirrored the preview under us. Two flips cancel.
  bool get _mirroredForPreview =>
      widget.previewMirrored ? !_mirrored : _mirrored;

  /// The same question, asked of the CAPTURED PHOTO rather than the preview
  /// — and on the front camera the answer is the opposite one.
  ///
  /// takePicture() hands back what the sensor saw. The preview is the
  /// mirrored view of that, which is what makes a selfie camera feel like
  /// a mirror (face_reaction_capture's flipHorizontal exists for exactly
  /// this reason). So whichever of those two spaces the analysis buffer
  /// happens to agree with, the photo is always in the other one:
  ///
  ///   iOS front      analysis already mirrored  -> preview false, photo true
  ///   Android front  analysis is raw sensor     -> preview true,  photo false
  ///
  /// Baking with the preview's flag is what put the mask on the opposite
  /// side of the face in the saved image while tracking perfectly live.
  ///
  /// Rear lens is NOT inverted: nothing mirrors it, so preview and photo
  /// are both the plain sensor frame and both want false.
  bool get _mirroredForPhoto =>
      widget.controller.description.lensDirection == CameraLensDirection.front
          ? !_mirrored
          : _mirrored;

  @override
  void dispose() {
    if (_streaming) {
      widget.controller.stopImageStream().catchError((_) {});
    }
    _detector?.close();
    _maskImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: FaceMaskPainter(
          mask: _maskImage,
          transforms: _transforms,
          analysisImageSize: _analysisImageSize,
          mirrored: _mirroredForPreview,
          // Places the mask by its own eyes — see FaceMaskAnchor.
          anchor: anchorForPreset(widget.maskAssetPath),
        ),
      ),
    );
  }
}
