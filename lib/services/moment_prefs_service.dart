import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Whether the current user has contributed a photo to a given Moment — same
// pattern as CameraPrefsService (static helpers, string keys,
// SharedPreferences.getInstance()). Drives LockedRepliesScreen's locked vs
// revealed state so a returning contributor lands straight in the revealed
// view instead of being re-blurred every time.
// ---------------------------------------------------------------------------

class MomentPrefsService {
  static String _key(String momentId) => 'moment_posted_$momentId';

  static Future<bool> loadHasPosted(String momentId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(momentId)) ?? false;
  }

  static Future<void> setHasPosted(String momentId, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(momentId), value);
  }
}
