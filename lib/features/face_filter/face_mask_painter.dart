import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'face_mask_presets.dart';
import 'face_mask_transform.dart';

// ---------------------------------------------------------------------------
// Paints the mask image on top of the live preview, transformed per-face.
// Draws nothing when [transforms] is empty (no face detected) — the caller
// is responsible for not crashing on that case by simply not populating the
// list, which this painter treats as a no-op paint.
// ---------------------------------------------------------------------------

class FaceMaskPainter extends CustomPainter {
  const FaceMaskPainter({
    required this.mask,
    required this.transforms,
    required this.analysisImageSize,
    this.mirrored = false,
    this.anchor,
  });

  /// The decoded mask asset. Null while it's still loading — paints nothing.
  final ui.Image? mask;

  /// One transform per face currently being masked (empty = no face).
  final List<FaceMaskTransform> transforms;

  /// The dimensions of the image space the transforms' coordinates were
  /// computed in (the ML Kit analysis frame), used to map into this
  /// painter's own canvas size.
  final Size analysisImageSize;

  /// True when the preview under this painter is horizontally MIRRORED —
  /// i.e. the front camera, which both iOS and Android preview as a mirror
  /// so it behaves like looking into one.
  ///
  /// ML Kit reports landmarks in the RAW sensor frame, which is not
  /// mirrored. Drawing those coordinates straight onto a mirrored preview
  /// puts the mask on the wrong side of the screen and makes it travel the
  /// wrong way as the head moves — which reads exactly as "it doesn't stick
  /// to the face, it's just an image". Flipping x (and the rotation with
  /// it) puts the mask back on the face.
  final bool mirrored;

  /// Where the artwork's own eyes sit inside the image. When present the
  /// mask is placed BY ITS EYES — the artwork's eye midpoint is put on the
  /// detected eye midpoint and scaled so the two eye spans match. Null
  /// falls back to the old centre-on-eyes placement.
  final FaceMaskAnchor? anchor;

  @override
  void paint(Canvas canvas, Size size) {
    final maskImage = mask;
    if (maskImage == null || transforms.isEmpty) return;

    final maskAspect = maskImage.width / maskImage.height;
    final srcRect = Rect.fromLTWH(
      0,
      0,
      maskImage.width.toDouble(),
      maskImage.height.toDouble(),
    );

    for (final t in transforms) {
      // All the geometry — cover-mapping, mirroring, eye anchoring, sizing —
      // lives in computeMaskPlacement, shared with the capture bake so the
      // preview and the saved photo can never disagree again.
      final p = computeMaskPlacement(
        transform: t,
        analysisImageSize: analysisImageSize,
        targetSize: size,
        maskAspect: maskAspect,
        mirrored: mirrored,
        anchor: anchor,
      );
      if (p == null) continue;

      canvas.save();
      canvas.translate(p.center.dx, p.center.dy);
      canvas.rotate(p.rotation);
      canvas.drawImageRect(
        maskImage,
        srcRect,
        Rect.fromCenter(center: Offset.zero, width: p.width, height: p.height),
        Paint()
          // High, not medium: the artwork's edges are feathered, and a
          // cheaper filter visibly stair-steps that gradient when the mask
          // is scaled up onto a close face.
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant FaceMaskPainter oldDelegate) {
    return oldDelegate.mask != mask ||
        oldDelegate.transforms != transforms ||
        oldDelegate.analysisImageSize != analysisImageSize ||
        oldDelegate.mirrored != mirrored ||
        oldDelegate.anchor != anchor;
  }
}
