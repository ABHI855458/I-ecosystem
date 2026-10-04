import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_mask_presets.dart';
import 'landmark_smoother.dart';

// ---------------------------------------------------------------------------
// Pure math: smoothed landmark points -> where/how big/how rotated to draw
// the mask. No Flutter widget or camera code in here — kept separately
// testable and reusable.
// ---------------------------------------------------------------------------

/// Mask width as a multiple of inter-eye distance. Tunable.
const kMaskWidthToEyeDistanceRatio = 2.2;

/// How far the head extends beyond ML Kit's face box.
///
/// The detector's box is the FACE — roughly brow to chin, ear to ear. A
/// head is wider (ears, hair at the sides) and much taller (forehead and
/// hair above, jaw below). These multipliers are deliberately generous:
/// under-covering leaks identity, over-covering just paints more black.
const kHeadWidthToBoxWidth = 1.62;
const kHeadHeightToBoxHeight = 2.05;

/// How far ABOVE the face box's centre the head's centre sits, as a
/// fraction of box height. Hair and forehead add far more above the eyes
/// than the jaw adds below, so the concealed region is not centred on the
/// face box.
const kHeadCenterRiseToBoxHeight = 0.22;

/// Secondary vertical-fit check: expected mask width as a fraction of the
/// face bounding-box height (typical face proportions). The two width
/// estimates (eye-distance-based and bbox-based) are averaged, so a face
/// that's mostly missing its eye detection but has a solid bounding box
/// still gets a roughly-right scale, and vice versa. Tunable.
const kBoxHeightToMaskWidthRatio = 0.78;

class FaceMaskTransform {
  const FaceMaskTransform({
    required this.center,
    required this.rotation,
    required this.width,
    required this.eyeDistance,
    required this.headCenter,
    required this.headWidth,
    required this.headHeight,
  });

  /// Where the mask's own visual center should land, in the same
  /// coordinate space as the input landmarks (i.e. the analysis image's
  /// pixel space — the caller maps this into widget/canvas space).
  final Offset center;

  /// Rotation to apply, in radians, matching the angle between the eyes.
  final double rotation;

  /// Mask draw width, in the same coordinate space as [center]. Height is
  /// derived by the painter from the mask asset's own aspect ratio.
  ///
  /// Only used when the artwork has no measured anchor. With one, the
  /// painter derives width from [eyeDistance] instead, which is exact
  /// rather than tuned.
  final double width;

  /// The detected inter-eye distance, in the same space as [center]. With a
  /// FaceMaskAnchor this is what scales the artwork: draw width =
  /// eyeDistance / anchor.eyeSpanRatio makes the artwork's own eyes land on
  /// the real ones at any face size or distance from the camera.
  final double eyeDistance;

  /// The WHOLE HEAD to conceal — hair, forehead, ears and jaw included, not
  /// just ML Kit's face box (which runs roughly brow to chin and leaves
  /// hair and the top of the head exposed).
  ///
  /// The requirement here is absolute: "face shall not be seen at all, no
  /// hair, fully covered, zero identity reveal". Eye-anchored placement
  /// alone can't promise that — it sizes the artwork to the eyes and says
  /// nothing about what's left showing around it. These three describe the
  /// region that must end up opaque.
  final Offset headCenter;
  final double headWidth;
  final double headHeight;
}

/// Computes the mask placement from one frame's smoothed landmarks.
/// Returns null only if eye distance collapses to ~0 (degenerate detection)
/// so callers can simply skip drawing that frame.
FaceMaskTransform? computeFaceMaskTransform(
  SmoothedFace face, {
  double widthRatio = kMaskWidthToEyeDistanceRatio,
}) {
  final eyeDelta = face.rightEye - face.leftEye;
  final eyeDistance = eyeDelta.distance;
  if (eyeDistance < 1) return null;

  final widthFromEyes = eyeDistance * widthRatio;
  final widthFromBox = face.boxHeight * kBoxHeightToMaskWidthRatio;
  final width = (widthFromEyes + widthFromBox) / 2;

  // The head region to conceal, extrapolated from the face box.
  final headWidth = face.boxWidth * kHeadWidthToBoxWidth;
  final headHeight = face.boxHeight * kHeadHeightToBoxHeight;
  final headCenter = Offset(
    face.boxCenter.dx,
    face.boxCenter.dy - face.boxHeight * kHeadCenterRiseToBoxHeight,
  );

  return FaceMaskTransform(
    center: face.eyeMidpoint,
    rotation: math.atan2(eyeDelta.dy, eyeDelta.dx),
    width: width,
    eyeDistance: eyeDistance,
    headCenter: headCenter,
    headWidth: headWidth,
    headHeight: headHeight,
  );
}

/// Extracts the raw (unsmoothed) points this frame's detection needs, or
/// null if the face is missing an eye (both eyes are required to compute a
/// scale/rotation at all).
class RawFacePoints {
  const RawFacePoints({
    required this.leftEye,
    required this.rightEye,
    required this.noseBase,
    required this.boxCenter,
    required this.boxWidth,
    required this.boxHeight,
  });

  final Offset leftEye;
  final Offset rightEye;
  final Offset? noseBase;
  final Offset boxCenter;
  final double boxWidth;
  final double boxHeight;

  static RawFacePoints? fromFace(Face face) {
    final left = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final right = face.landmarks[FaceLandmarkType.rightEye]?.position;
    if (left == null || right == null) return null;
    final nose = face.landmarks[FaceLandmarkType.noseBase]?.position;
    return RawFacePoints(
      leftEye: Offset(left.x.toDouble(), left.y.toDouble()),
      rightEye: Offset(right.x.toDouble(), right.y.toDouble()),
      noseBase: nose == null
          ? null
          : Offset(nose.x.toDouble(), nose.y.toDouble()),
      boxCenter: face.boundingBox.center,
      boxWidth: face.boundingBox.width,
      boxHeight: face.boundingBox.height,
    );
  }
}


/// Where the mask artwork actually gets drawn, in some target space.
///
/// THE single source of truth for that, used by both the live overlay
/// (FaceMaskPainter) and the capture bake (bakeFaceMaskIntoPhoto). Those two
/// were separate implementations, and the bake silently missed every fix the
/// overlay received — the eye anchor, the iOS mirror, the eye-based sizing —
/// so the preview tracked the face correctly while the saved photo put the
/// mask somewhere else entirely. Reported exactly that way: "the filter is
/// fitting good but the image after clicking is showing somewhere else".
class MaskPlacement {
  const MaskPlacement({
    required this.center,
    required this.width,
    required this.height,
    required this.rotation,
  });

  /// Where the artwork's own CENTRE goes (already offset so its eyes land on
  /// the face's eyes — see [computeMaskPlacement]).
  final Offset center;
  final double width;
  final double height;
  final double rotation;
}

/// Maps one face's transform from analysis space into [targetSize].
///
/// [targetSize] is the preview canvas for the live overlay and the captured
/// photo's pixel size for the bake; the mapping is BoxFit.cover either way,
/// matching how the viewfinder scales its preview.
MaskPlacement? computeMaskPlacement({
  required FaceMaskTransform transform,
  required Size analysisImageSize,
  required Size targetSize,
  required double maskAspect,
  required bool mirrored,
  FaceMaskAnchor? anchor,
}) {
  if (analysisImageSize.width <= 0 || analysisImageSize.height <= 0) {
    return null;
  }

  final scale = math.max(
    targetSize.width / analysisImageSize.width,
    targetSize.height / analysisImageSize.height,
  );
  final dx = (targetSize.width - analysisImageSize.width * scale) / 2;
  final dy = (targetSize.height - analysisImageSize.height * scale) / 2;

  final srcX = mirrored
      ? analysisImageSize.width - transform.center.dx
      : transform.center.dx;
  // transform.center is the EYE MIDPOINT.
  final eyeMid = Offset(srcX * scale + dx, transform.center.dy * scale + dy);

  // Sized purely from the eyes: draw width = eyeDistance / eyeSpanRatio puts
  // the artwork's own lenses on the real ones, which for this mask works out
  // at about one face-width of body — the fitted look a worn mask has.
  final width = anchor != null
      ? (transform.eyeDistance / anchor.eyeSpanRatio) * scale
      : transform.width * scale;
  final height = width / maskAspect;

  // Head tilt reverses under a mirror: tilting right in the world reads as
  // tilting left on screen.
  final rotation = mirrored ? -transform.rotation : transform.rotation;

  // Offset so the ARTWORK's eye midpoint lands on eyeMid, rather than its
  // image centre — this mask's eyes sit at 0.4375 of its height, so centring
  // it would ride low on the face.
  final offsetX = anchor == null ? 0.0 : (0.5 - anchor.eyeMidX) * width;
  final offsetY = anchor == null ? 0.0 : (0.5 - anchor.eyeMidY) * height;
  final cos = math.cos(rotation);
  final sin = math.sin(rotation);

  return MaskPlacement(
    // Rotate the offset with the mask, so it stays correct at any head tilt.
    center: Offset(
      eyeMid.dx + offsetX * cos - offsetY * sin,
      eyeMid.dy + offsetX * sin + offsetY * cos,
    ),
    width: width,
    height: height,
    rotation: rotation,
  );
}
