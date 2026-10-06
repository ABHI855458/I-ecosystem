import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../shared/camera_pinch_zoom.dart';
import 'package:google_fonts/google_fonts.dart';

import '../face_filter/face_mask_overlay.dart';
import '../face_filter/face_mask_presets.dart' show kFaceMaskPresetC;
import 'capture_widgets.dart';

// ---------------------------------------------------------------------------
// The app's camera capture UI.
//
// Lifted verbatim out of composer_screen.dart, where every one of these
// widgets was private. The ping reply camera had grown its OWN look-alike
// chrome — a second shutter row, a second mode toggle, a second mask pill,
// a second flip button — which then drifted from this one on both layout
// and behaviour, and drifted again every time only one of the two was
// fixed. Explicit instruction: "whatever the camera design we have for the
// task bar's camera, copy the same thing — dual/single, camera flip and
// album — and wire it to the ping section".
//
// So there is now exactly one capture UI, used by the composer and by
// PingCameraScreen. Neither owns it; both pass callbacks into it.
// ---------------------------------------------------------------------------

/// Which leg of a dual capture is next: the back shot, then the front one.
enum DualStep { back, front }

/// The full-bleed camera card: viewfinder, mask overlay, capture flash,
/// scrim, dual/single switch, face-mask pill, and the shutter row (close,
/// shutter, flip, gallery).
///
/// Stateless on purpose — every piece of state lives in the host screen, so
/// the composer and the ping camera can drive it from whatever their own
/// flows need.
class CaptureCard extends StatelessWidget {
  const CaptureCard({
    super.key,
    required this.controller,
    required this.cameraReady,
    required this.cameraError,
    required this.usingRear,
    required this.swapping,
    required this.onCapture,
    this.onStartVideo,
    this.onStopVideo,
    required this.onGallery,
    required this.onSwap,
    required this.onClose,
    required this.dualCameraEnabled,
    required this.onToggleDualCamera,
    required this.flashKey,
    required this.maskFilterOn,
    required this.onToggleMaskFilter,
    required this.maskOverlayKey,
    this.onScanQr,
    this.dualStep = DualStep.back,
    this.frontCapturing = false,
    this.frontCaptureError,
    this.onUseBackPhotoOnly,
    this.borderRadius = 48,
    this.hint,
    this.allowFlipInDual = false,
    this.allowDualToggle = true,
  });

  final CameraController? controller;
  final bool cameraReady;
  final String? cameraError;
  final bool usingRear;
  final bool swapping;
  final VoidCallback onCapture;

  /// Hold-to-record video (PlainShutterButton's own doc). Null keeps the
  /// shutter tap-only, which is every camera except the ping reply one.
  final Future<bool> Function()? onStartVideo;
  final VoidCallback? onStopVideo;
  /// Non-null only for the GROUP camera (explicit request, 2026-10-03:
  /// "include the duo qr scanner and group qr scanner in the group's camera
  /// only"). Opens the one scanner that detects BOTH kinds of code and does
  /// the right thing for each — see qr_scanner_screen.dart.
  final VoidCallback? onScanQr;

  final VoidCallback onGallery;
  final VoidCallback onSwap;
  final VoidCallback onClose;
  final bool dualCameraEnabled;
  final VoidCallback onToggleDualCamera;
  final GlobalKey<CaptureFlashOverlayState> flashKey;

  /// Only meaningful on the front lens — the mask anchors on detected eyes,
  /// so the pill hides itself on the rear camera.
  final bool maskFilterOn;
  final VoidCallback onToggleMaskFilter;
  final GlobalKey<FaceMaskOverlayState> maskOverlayKey;

  /// Dual-capture progress. Defaults suit a host that drives dual manually
  /// (the ping camera waits for a second shutter tap rather than firing the
  /// front shot itself), so only the composer passes these.
  final DualStep dualStep;
  final bool frontCapturing;
  final String? frontCaptureError;
  final VoidCallback? onUseBackPhotoOnly;

  /// The composer floats this card inside a rounded sheet; the ping camera
  /// fills a bottom sheet whose top corners are already clipped by its own
  /// container.
  final double borderRadius;

  /// Optional one-line caption under the mode switch — the ping camera uses
  /// it for "now the front one — tap again" mid-dual.
  final String? hint;

  /// Whether the flip control stays available while dual mode is armed but
  /// not yet started.
  ///
  /// False (the composer) — dual there always runs back→front
  /// automatically, so there is no lens to choose and a flip would fight
  /// its own sequencing. True (the ping camera) — dual there takes the
  /// framed lens FIRST and waits for a second tap, so which lens you start
  /// on is a real choice. Either way the flip disappears once a pair is
  /// mid-flight.
  final bool allowFlipInDual;

  /// False hides the Single/Dual switch entirely (explicit request: Dip
  /// posts allow only a single-camera photo, no back+front pair). The
  /// composer is the only caller that ever passes false — the ping camera
  /// keeps the default.
  final bool allowDualToggle;

  bool get _inFrontStep => dualCameraEnabled && dualStep == DualStep.front;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraViewfinder(controller: controller, error: cameraError),

          // Shares `controller` — no second CameraController/camera
          // session. Any front-camera preview, single-shot OR the front leg
          // of a dual capture (dual's second shot IS a selfie).
          if (maskFilterOn &&
              !usingRear &&
              controller != null &&
              controller!.value.isInitialized)
            Positioned.fill(
              child: FaceMaskOverlay(
                key: maskOverlayKey,
                controller: controller!,
                maskAssetPath: kFaceMaskPresetC,
              ),
            ),

          Positioned.fill(child: CaptureFlashOverlay(key: flashKey)),

          // Bottom gradient scrim
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
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

          // Dual camera toggle — top-left, hidden once the front step is
          // underway (mid-sequence isn't a sensible time to change your
          // mind about it), and hidden entirely when allowDualToggle is
          // false (Dip: single photo only, no toggle to even find).
          if (!_inFrontStep && allowDualToggle)
            Positioned(
              top: 14,
              left: 14,
              child: CameraModeSwitch(
                dual: dualCameraEnabled,
                onTap: onToggleDualCamera,
              ),
            ),

          // Face mask pill — front lens only, there is no face to track on
          // the rear one.
          if (!usingRear)
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onToggleMaskFilter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: maskFilterOn
                          ? Colors.white.withValues(alpha: 0.9)
                          : const Color(0xFF0E0E16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.masks_rounded,
                          size: 16,
                          color: maskFilterOn
                              ? Colors.black
                              : Colors.white.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          // "Face" rather than "Mask": in dual mode this
                          // sits beside the DUAL control and a second thing
                          // labelled "mask" read as being about the camera
                          // rather than about the face.
                          'Face',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: maskFilterOn
                                ? Colors.black
                                : Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Mid-dual caption, e.g. "now the front one — tap again".
          if (hint != null)
            Positioned(
              top: 58,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    hint!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),

          // Front-capture-in-progress indicator
          if (_inFrontStep && frontCapturing)
            const Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
              ),
            ),

          // Front capture failed — retry (shutter stays live) or fall back
          // to the back photo alone.
          if (frontCaptureError != null)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      frontCaptureError!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    if (onUseBackPhotoOnly != null) ...[
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
                  ],
                ),
              ),
            ),

          // Shutter ring — close/gallery stay visible even when the camera
          // isn't ready, so a camera error still leaves a way out or a
          // fallback to the gallery.
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: cameraReady ? 1 : 0.55,
                  child: PlainShutterButton(
                    onCapture: onCapture,
                    onStartVideo: onStartVideo,
                    onStopVideo: onStopVideo,
                  ),
                ),
                Positioned(
                  left: 24,
                  child: SmallCircleBtn(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: onClose,
                    size: 44,
                    iconSize: 16,
                  ),
                ),
                Positioned(
                  right: 24,
                  child: SmallCircleBtn(
                    icon: Icons.photo_library_rounded,
                    onTap: onGallery,
                    size: 44,
                    iconSize: 19,
                  ),
                ),
                // Front/back flip, beside the shutter where a flip control
                // belongs. Hidden once a dual sequence is mid-flight, so
                // the lens can't change between the two halves — and, for
                // a host that sequences dual itself, hidden in dual mode
                // entirely (see [allowFlipInDual]).
                if (!_inFrontStep && (!dualCameraEnabled || allowFlipInDual))
                  Positioned(
                    right: 84,
                    child: FlipCameraButton(busy: swapping, onTap: onSwap),
                  ),
                // Scan a Duo / group QR, group camera only.
                if (onScanQr != null && !_inFrontStep)
                  Positioned(
                    left: 84,
                    child: SmallCircleBtn(
                      icon: Icons.qr_code_scanner_rounded,
                      onTap: onScanQr!,
                      size: 44,
                      iconSize: 19,
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

/// SINGLE | DUAL, as a segmented control.
///
/// Was a single chip reading "DUAL" that lit up when active — so the other
/// mode had no label at all, and the control gave no hint that tapping it
/// would change what the shutter does (one shot vs. a back-then-front
/// pair). A segment shows both modes and which one you are in.
class CameraModeSwitch extends StatelessWidget {
  const CameraModeSwitch({super.key, required this.dual, required this.onTap});

  final bool dual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Single" / "Dual" (explicit revert of an earlier "One cam" /
            // "Both cams" rewording) — still plain sentence-case text on a
            // readable font rather than the original monospaced, letter-
            // spaced SINGLE / DUAL, which read like a settings code.
            _seg('Single', Icons.photo_camera_rounded, !dual),
            _seg('Dual', Icons.switch_camera_rounded, dual),
          ],
        ),
      ),
    );
  }

  static const _accent = Color(0xFF29D3E8); // the app-wide cyan

  Widget _seg(String label, IconData icon, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? _accent : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: active
                ? const Color(0xFF0B0B0D)
                : Colors.white.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? const Color(0xFF0B0B0D)
                  : Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

/// The front/back flip, as a control in the shutter row.
///
/// Replaces a PiP-shaped box in the top-right corner that showed the lens
/// you would switch TO — it read as a picture-in-picture preview rather
/// than a button, sat nowhere near the shutter, and collided with the
/// dual-mode chrome.
class FlipCameraButton extends StatelessWidget {
  const FlipCameraButton({super.key, required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: busy
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                ),
              )
            : const Icon(
                Icons.cameraswitch_rounded,
                size: 21,
                color: Colors.white,
              ),
      ),
    );
  }
}

/// Full-bleed camera preview, with a plain non-crashing placeholder while
/// the controller is null or still initializing.
class CameraViewfinder extends StatelessWidget {
  const CameraViewfinder({super.key, required this.controller, this.error});

  final CameraController? controller;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      // Pinch to zoom (main camera + Ping camera both use this viewfinder).
      return CameraPinchZoom(
        controller: ctrl,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: ctrl.value.previewSize?.height ?? 1,
              height: ctrl.value.previewSize?.width ?? 1,
              child: CameraPreview(ctrl),
            ),
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

/// Small circle button (back, gallery, etc.).
class SmallCircleBtn extends StatelessWidget {
  const SmallCircleBtn({
    super.key,
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
        width: size,
        height: size,
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
