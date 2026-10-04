import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

// ---------------------------------------------------------------------------
// CameraImage -> InputImage. This is the standard, well-tested conversion
// used by ML Kit's own example apps. It requires the CameraController to
// have been created with `imageFormatGroup: ImageFormatGroup.nv21` on
// Android / `.bgra8888` on iOS (see kFaceMaskImageFormatGroup below) so the
// frame always arrives as a single plane — multi-plane YUV420 conversion is
// deliberately NOT handled here, since hand-rolling it is fragile across
// devices and unnecessary once the controller is asked for the right format
// up front.
// ---------------------------------------------------------------------------

/// Pass this as `imageFormatGroup:` to any CameraController whose stream
/// will be fed through [inputImageFromCameraImage].
ImageFormatGroup get kFaceMaskImageFormatGroup =>
    Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// The coordinate space ML Kit reports landmarks in, for this frame.
///
/// This is NOT always the buffer's own width/height, and it is NOT always
/// the swap of them — which is what the overlay used to assume
/// unconditionally (`Size(image.height, image.width)`).
///
/// Measured on a real iPhone: the camera plugin delivers an ALREADY-PORTRAIT
/// 720x1280 buffer, and ML Kit returns coordinates in that same 720x1280
/// space. Swapping it to 1280x720 put the eye midpoint at y = 1.05 of the
/// frame height — outside the image, which is impossible and is exactly why
/// the mask landed far from the face:
///
///   [FaceMask] buf 720x1280 analysis 1280x720 eyeMid 427,756 = frac 0.33,1.05
///
/// So: coordinates arrive in the frame AS ML KIT SEES IT AFTER ROTATION. A
/// 90/270 rotation swaps the axes, 0/180 does not. Deriving it from the same
/// rotation the InputImage was built with keeps the two in lockstep instead
/// of hardcoding an assumption that only held on one platform.
Size? analysisSizeFor(CameraImage image, CameraController controller) {
  final rotation = _rotationFor(controller);
  if (rotation == null) return null;
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  switch (rotation) {
    case InputImageRotation.rotation90deg:
    case InputImageRotation.rotation270deg:
      return Size(h, w);
    case InputImageRotation.rotation0deg:
    case InputImageRotation.rotation180deg:
      return Size(w, h);
  }
}

/// The rotation handed to ML Kit — shared by [inputImageFromCameraImage] and
/// [analysisSizeFor] so the image and the space its coordinates land in can
/// never disagree.
InputImageRotation? _rotationFor(CameraController controller) {
  final camera = controller.description;
  final sensorOrientation = camera.sensorOrientation;

  if (Platform.isIOS) {
    // Empirical, from the device log above: the plugin's iOS buffers are
    // already upright, and ML Kit returns coordinates in that same space.
    // Passing the sensor orientation (90) made the reported space and the
    // real one disagree.
    return InputImageRotation.rotation0deg;
  }
  var rotationCompensation = _orientations[controller.value.deviceOrientation];
  if (rotationCompensation == null) return null;
  if (camera.lensDirection == CameraLensDirection.front) {
    rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
  } else {
    rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
  }
  return InputImageRotationValue.fromRawValue(rotationCompensation);
}

InputImage? inputImageFromCameraImage(
  CameraImage image,
  CameraController controller,
) {
  final rotation = _rotationFor(controller);
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null ||
      (Platform.isAndroid && format != InputImageFormat.nv21) ||
      (Platform.isIOS && format != InputImageFormat.bgra8888)) {
    return null;
  }

  if (image.planes.length != 1) return null;
  final plane = image.planes.first;

  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}
