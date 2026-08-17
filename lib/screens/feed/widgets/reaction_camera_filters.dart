import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Color-matrix filters for the reaction camera screen (design-refs/
// design_handoff_group_post_cards 2/README-camera.md's "Filters" table).
// Each named filter is a composition of CSS-style filter primitives
// (saturate/sepia/contrast/brightness/grayscale/hue-rotate), reimplemented
// as 4x5 affine color matrices — the same math the CSS Filter Effects spec
// uses, so the look matches the reference.html prototype. Applied live via
// ColorFiltered over CameraPreview AND baked into the captured JPEG via the
// `image` package (see ReactionFilter.apply) — the spec is explicit that a
// filter must affect both, not just a live overlay.
// ---------------------------------------------------------------------------

/// A 4x5 affine color matrix: 4x4 linear part + a 4-value translate, in
/// Flutter's ColorFilter.matrix 0-255 scale. Composition order matches CSS
/// `filter: a() b() c()` — a applies first, its output feeds b, etc.
class _Mat {
  const _Mat(this.m, this.t);
  final List<double> m; // 16, row-major 4x4
  final List<double> t; // 4

  static const _Mat identity = _Mat([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ], [0, 0, 0, 0]);

  /// this ∘ other — apply [other] first, then this.
  _Mat compose(_Mat other) {
    final m2 = List<double>.filled(16, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += m[r * 4 + k] * other.m[k * 4 + c];
        }
        m2[r * 4 + c] = sum;
      }
    }
    final t2 = List<double>.filled(4, 0);
    for (var r = 0; r < 4; r++) {
      var sum = t[r];
      for (var k = 0; k < 4; k++) {
        sum += m[r * 4 + k] * other.t[k];
      }
      t2[r] = sum;
    }
    return _Mat(m2, t2);
  }

  static _Mat lerp(_Mat a, _Mat b, double f) {
    final m2 = List<double>.generate(16, (i) => a.m[i] + (b.m[i] - a.m[i]) * f);
    final t2 = List<double>.generate(4, (i) => a.t[i] + (b.t[i] - a.t[i]) * f);
    return _Mat(m2, t2);
  }

  List<double> toFlutterMatrix() => [
        m[0], m[1], m[2], m[3], t[0],
        m[4], m[5], m[6], m[7], t[1],
        m[8], m[9], m[10], m[11], t[2],
        m[12], m[13], m[14], m[15], t[3],
      ];
}

_Mat _saturate(double s) => _Mat([
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0,
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0,
      0, 0, 0, 1,
    ], [0, 0, 0, 0]);

_Mat _sepia(double a) {
  const sepia = _Mat([
    0.393, 0.769, 0.189, 0,
    0.349, 0.686, 0.168, 0,
    0.272, 0.534, 0.131, 0,
    0, 0, 0, 1,
  ], [0, 0, 0, 0]);
  return _Mat.lerp(_Mat.identity, sepia, a);
}

_Mat _grayscale(double a) {
  const gray = _Mat([
    0.2126, 0.7152, 0.0722, 0,
    0.2126, 0.7152, 0.0722, 0,
    0.2126, 0.7152, 0.0722, 0,
    0, 0, 0, 1,
  ], [0, 0, 0, 0]);
  return _Mat.lerp(_Mat.identity, gray, a);
}

_Mat _contrast(double c) {
  final off = (0.5 - 0.5 * c) * 255;
  return _Mat([
    c, 0, 0, 0,
    0, c, 0, 0,
    0, 0, c, 0,
    0, 0, 0, 1,
  ], [off, off, off, 0]);
}

_Mat _brightness(double b) => _Mat([
      b, 0, 0, 0,
      0, b, 0, 0,
      0, 0, b, 0,
      0, 0, 0, 1,
    ], [0, 0, 0, 0]);

/// Luminance-preserving hue rotation (W3C Filter Effects spec's
/// feColorMatrix type="hueRotate" formula).
_Mat _hueRotate(double deg) {
  final a = deg * math.pi / 180;
  final cosA = math.cos(a);
  final sinA = math.sin(a);
  return _Mat([
    0.213 + cosA * 0.787 - sinA * 0.213,
    0.715 - cosA * 0.715 - sinA * 0.715,
    0.072 - cosA * 0.072 + sinA * 0.928,
    0,
    0.213 - cosA * 0.213 + sinA * 0.143,
    0.715 + cosA * 0.285 + sinA * 0.140,
    0.072 - cosA * 0.072 - sinA * 0.283,
    0,
    0.213 - cosA * 0.213 - sinA * 0.787,
    0.715 - cosA * 0.715 + sinA * 0.715,
    0.072 + cosA * 0.928 + sinA * 0.072,
    0,
    0, 0, 0, 1,
  ], [0, 0, 0, 0]);
}

class ReactionFilter {
  const ReactionFilter._(this.name, this._matrix, this.swatchGradient);

  final String name;
  final _Mat _matrix;

  /// Swatch gradient (160deg per spec) shown on the filter rail chip and
  /// baked into the fixed shutter's fill when this filter is centered.
  final List<Color> swatchGradient;

  List<double> get colorFilterMatrix => _matrix.toFlutterMatrix();

  /// Bakes this filter into a captured frame — same matrix as the live
  /// preview, per spec ("do not merely overlay it").
  img.Image apply(img.Image src) {
    if (identical(_matrix, _Mat.identity)) return src;
    final m = _matrix;
    final out = img.Image(width: src.width, height: src.height);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        final nr = (m.m[0] * r + m.m[1] * g + m.m[2] * b + m.t[0]).clamp(0, 255);
        final ng = (m.m[4] * r + m.m[5] * g + m.m[6] * b + m.t[1]).clamp(0, 255);
        final nb = (m.m[8] * r + m.m[9] * g + m.m[10] * b + m.t[2]).clamp(0, 255);
        out.setPixelRgba(x, y, nr.round(), ng.round(), nb.round(), p.a.toInt());
      }
    }
    return out;
  }

  static final none = ReactionFilter._('None', _Mat.identity, const [Color(0xFF2A2A32), Color(0xFF2A2A32)]);
  static final warm = ReactionFilter._(
    'Warm',
    _contrast(1.05).compose(_sepia(0.28)).compose(_saturate(1.3)),
    const [Color(0xFFFFC531), Color(0xFFFF6A3D)],
  );
  static final cool = ReactionFilter._(
    'Cool',
    _brightness(1.05).compose(_hueRotate(180)).compose(_saturate(1.15)),
    const [Color(0xFF35C8FF), Color(0xFF6366F1)],
  );
  static final mono = ReactionFilter._(
    'Mono',
    _contrast(1.15).compose(_grayscale(1)),
    const [Color(0xFFE5E5E8), Color(0xFF5C5C66)],
  );
  static final faded = ReactionFilter._(
    'Faded',
    _saturate(0.8).compose(_brightness(1.12)).compose(_contrast(0.85)),
    const [Color(0xFFD9C9B8), Color(0xFFA08F80)],
  );
  static final punch = ReactionFilter._(
    'Punch',
    _contrast(1.2).compose(_saturate(1.75)),
    const [Color(0xFFFF5FA2), Color(0xFF7C5CFF)],
  );
  static final night = ReactionFilter._(
    'Night',
    _hueRotate(-15).compose(_saturate(1.2)).compose(_brightness(0.85)),
    const [Color(0xFF1E3A8A), Color(0xFF0F172A)],
  );

  static final all = <ReactionFilter>[none, warm, cool, mono, faded, punch, night];
}
