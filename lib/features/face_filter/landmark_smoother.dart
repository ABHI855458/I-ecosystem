import 'dart:ui';

// ---------------------------------------------------------------------------
// Exponential moving average smoothing for face landmark positions —
// eliminates frame-to-frame jitter from noisy per-frame ML Kit detections
// before the smoothed points feed the transform math (see
// face_mask_transform.dart). One smoother instance tracks ONE face; the
// overlay keeps a pool of these when masking multiple faces at once.
// ---------------------------------------------------------------------------

class _EmaPoint {
  _EmaPoint(this.alpha);
  final double alpha;
  Offset? _value;

  Offset next(Offset raw) {
    final prev = _value;
    if (prev == null) {
      _value = raw;
    } else {
      _value = Offset(
        prev.dx + alpha * (raw.dx - prev.dx),
        prev.dy + alpha * (raw.dy - prev.dy),
      );
    }
    return _value!;
  }
}

class _EmaScalar {
  _EmaScalar(this.alpha);
  final double alpha;
  double? _value;

  double next(double raw) {
    final prev = _value;
    _value = prev == null ? raw : prev + alpha * (raw - prev);
    return _value!;
  }
}

/// Smooths one face's tracked points frame-to-frame. `alpha` is the EMA
/// weight given to each new raw sample — higher tracks faster but jitters
/// more, lower is steadier but laggier. 0.3–0.5 is the tunable sweet spot
/// asked for; 0.4 is the default here.
class FaceLandmarkSmoother {
  FaceLandmarkSmoother({this.alpha = 0.4})
    : _leftEye = _EmaPoint(alpha),
      _rightEye = _EmaPoint(alpha),
      _noseBase = _EmaPoint(alpha),
      _boxCenter = _EmaPoint(alpha),
      _boxWidth = _EmaScalar(alpha),
      _boxHeight = _EmaScalar(alpha);

  final double alpha;
  final _EmaPoint _leftEye;
  final _EmaPoint _rightEye;
  final _EmaPoint _noseBase;
  final _EmaPoint _boxCenter;
  final _EmaScalar _boxWidth;
  final _EmaScalar _boxHeight;

  /// Clears accumulated state — call when a face is lost so it doesn't come
  /// back smoothing in from a stale, minutes-old position.
  void reset() {
    _leftEye._value = null;
    _rightEye._value = null;
    _noseBase._value = null;
    _boxCenter._value = null;
    _boxWidth._value = null;
    _boxHeight._value = null;
  }

  /// Feeds one frame's raw landmark points through the smoother and returns
  /// the smoothed result. [noseBase] may be null (landmark not detected);
  /// the smoothed nose then simply tracks whatever was last seen, or the
  /// eye midpoint if nothing has ever been seen.
  SmoothedFace update({
    required Offset leftEye,
    required Offset rightEye,
    required Offset? noseBase,
    required Offset boxCenter,
    required double boxWidth,
    required double boxHeight,
  }) {
    final smoothedLeft = _leftEye.next(leftEye);
    final smoothedRight = _rightEye.next(rightEye);
    final eyeMid = Offset(
      (smoothedLeft.dx + smoothedRight.dx) / 2,
      (smoothedLeft.dy + smoothedRight.dy) / 2,
    );
    final smoothedNose = _noseBase.next(noseBase ?? eyeMid);
    final smoothedBoxHeight = _boxHeight.next(boxHeight);
    return SmoothedFace(
      leftEye: smoothedLeft,
      rightEye: smoothedRight,
      noseBase: smoothedNose,
      boxCenter: _boxCenter.next(boxCenter),
      boxWidth: _boxWidth.next(boxWidth),
      boxHeight: smoothedBoxHeight,
    );
  }
}

class SmoothedFace {
  const SmoothedFace({
    required this.leftEye,
    required this.rightEye,
    required this.noseBase,
    required this.boxCenter,
    required this.boxWidth,
    required this.boxHeight,
  });

  final Offset leftEye;
  final Offset rightEye;
  final Offset noseBase;

  /// The face bounding box, smoothed. Needed for COVERAGE: ML Kit's box is
  /// the face only (roughly brow to chin), so the head — hair, forehead,
  /// ears, jaw — has to be extrapolated from it. Eye landmarks alone can't
  /// tell you how far the head extends.
  final Offset boxCenter;
  final double boxWidth;
  final double boxHeight;

  Offset get eyeMidpoint =>
      Offset((leftEye.dx + rightEye.dx) / 2, (leftEye.dy + rightEye.dy) / 2);
}
