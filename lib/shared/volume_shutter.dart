import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

/// Volume buttons as a camera shutter (like the system camera app).
///
/// While a camera screen is open: the system volume HUD is hidden, the
/// volume is parked at 50% (so BOTH buttons always register — at 0% or 100%
/// one of them would produce no change to listen for), and any press fires
/// [onShutter]. [stop] puts the person's own volume and the HUD back.
class VolumeShutter {
  static const double _park = 0.5;

  double? _original;
  bool _resetting = false;
  bool _active = false;
  DateTime _lastFire = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start(VoidCallback onShutter) async {
    if (_active) return;
    _active = true;
    try {
      await FlutterVolumeController.updateShowSystemUI(false);
      _original = await FlutterVolumeController.getVolume();
      await _parkVolume();
      FlutterVolumeController.addListener(
        (v) {
          if (!_active || _resetting) return;
          if ((v - _park).abs() < 0.01) return;
          final now = DateTime.now();
          if (now.difference(_lastFire) > const Duration(milliseconds: 450)) {
            _lastFire = now;
            onShutter();
          }
          unawaited(_parkVolume());
        },
        emitOnStart: false,
      );
    } catch (e) {
      debugPrint('[VolumeShutter] unavailable: $e');
    }
  }

  Future<void> _parkVolume() async {
    _resetting = true;
    try {
      await FlutterVolumeController.setVolume(_park);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _resetting = false;
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    FlutterVolumeController.removeListener();
    try {
      final o = _original;
      if (o != null) await FlutterVolumeController.setVolume(o);
      await FlutterVolumeController.updateShowSystemUI(true);
    } catch (_) {}
  }
}
