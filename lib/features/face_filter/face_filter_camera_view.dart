import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'face_input_image_converter.dart';
import 'face_mask_overlay.dart';

/// Standalone, reusable front-camera view with a real-time face-tracked
/// mask overlay baked into the captured photo. Owns its own
/// [CameraController] end to end (init, stream, dispose) — swap masks by
/// changing [maskAssetPath], no detection code to touch.
///
/// This is NOT currently wired into any screen in the app — the real
/// integration point (the composer's Anon camera) embeds [FaceMaskOverlay]
/// directly on top of its OWN existing controller instead, to avoid ever
/// having two live CameraControllers open at once (see composer_screen.dart
/// _swapToDirection's comment on why that hangs on iOS). This widget is kept
/// for standalone use/testing and for wiring into a future screen later.
class FaceFilterCameraView extends StatefulWidget {
  const FaceFilterCameraView({
    super.key,
    required this.maskAssetPath,
    this.maskAllFaces = false,
    this.onCaptured,
  });

  /// Null = camera runs with no mask.
  final String? maskAssetPath;
  final bool maskAllFaces;
  final ValueChanged<XFile>? onCaptured;

  @override
  State<FaceFilterCameraView> createState() => _FaceFilterCameraViewState();
}

class _FaceFilterCameraViewState extends State<FaceFilterCameraView> {
  CameraController? _controller;
  String? _error;
  final _overlayKey = GlobalKey<FaceMaskOverlayState>();
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: kFaceMaskImageFormatGroup,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _controller = ctrl);
    } catch (_) {
      if (mounted) setState(() => _error = "Camera didn't start.");
    }
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final raw = await ctrl.takePicture();
      final baked =
          await _overlayKey.currentState?.bakeIntoPhoto(raw) ?? raw;
      widget.onCaptured?.call(baked);
    } catch (_) {
      // Swallow — shutter stays tappable for retry, matching the app's
      // existing capture screens' failure handling.
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (ctrl != null && ctrl.value.isInitialized) ...[
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: ctrl.value.previewSize?.height ?? 1,
                height: ctrl.value.previewSize?.width ?? 1,
                child: CameraPreview(ctrl),
              ),
            ),
          ),
          FaceMaskOverlay(
            key: _overlayKey,
            controller: ctrl,
            maskAssetPath: widget.maskAssetPath,
            maskAllFaces: widget.maskAllFaces,
          ),
        ] else if (_error != null)
          Center(
            child: Text(_error!, style: const TextStyle(color: Colors.white54)),
          ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _capture,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: _capturing ? 0.4 : 1),
                  border: Border.all(color: Colors.white24, width: 4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
