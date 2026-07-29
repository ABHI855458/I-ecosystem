import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Camera preferences — backed by shared_preferences, same pattern as
// StreakService (static helpers, string keys, SharedPreferences.getInstance()).
// ---------------------------------------------------------------------------

class CameraPrefsService {
  static const _kDualCameraEnabled = 'dual_camera_enabled';

  /// Defaults to off — dual capture is opt-in.
  static Future<bool> loadDualCameraEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDualCameraEnabled) ?? false;
  }

  static Future<void> setDualCameraEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDualCameraEnabled, value);
  }
}
