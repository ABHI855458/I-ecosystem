import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Camera preferences — backed by shared_preferences, same pattern as
// StreakService (static helpers, string keys, SharedPreferences.getInstance()).
// ---------------------------------------------------------------------------

class CameraPrefsService {
  static const _kDualCameraEnabled = 'dual_camera_enabled';

  /// Defaults to ON — dual capture (back, then front as a top-left PiP) is
  /// the app's default capture mode; the toggle in the capture card turns it
  /// off. Anyone who explicitly set it keeps their choice, since only the
  /// unset fallback changed.
  static Future<bool> loadDualCameraEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDualCameraEnabled) ?? true;
  }

  static Future<void> setDualCameraEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDualCameraEnabled, value);
  }
}
