import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;

import '../core/push_messaging_service.dart';
import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'post_author_pin_service.dart';
import 'reaction_service.dart';
import 'reaction_preset_service.dart';
import 'storage_service.dart';

class SupabaseService {
  SupabaseService._();

  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final response = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return response;
    } catch (_) {
      return null;
    }
  }

  static Future<void> signOut() async {
    // Local scope: clears this device's session immediately instead of
    // first making an un-timed network call to revoke it server-side — on
    // a slow connection that call is what made "Log Out" hang. It also only
    // signs out THIS phone, leaving the account's other devices signed in.
    await supabase.auth.signOut(scope: SignOutScope.local);
  }

  /// The one place every per-session cache gets cleared on logout. Single
  /// source of truth so a newly-added cache (like PostAuthorPinService,
  /// missing from here until now — profile_screen.dart's old _confirmLogout
  /// called signOut()/CurrentUserService.reset()/ReactionPresetService.reset()
  /// directly and had drifted out of sync with what actually needs
  /// resetting) can't be forgotten by a second call site again.
  static Future<void> signOutAndResetCaches() async {
    // Must run before signOut() — it needs the still-active session to
    // resolve the user id and delete this device's token, otherwise a
    // signed-out phone keeps receiving the previous account's pushes.
    // Hard cap on the push cleanup: logging out must never wait on it. At
    // worst this device keeps one stale token, which the dispatcher's
    // dedupe/failure sweep clears — far better than a Log Out button that
    // appears to do nothing.
    await PushMessagingService.instance.unregister().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    await signOut();
    CurrentUserService.instance.reset();
    ReactionPresetService.instance.reset();
    PostAuthorPinService.instance.reset();
    // Holds other people's reactor selfies keyed by user id — must not
    // survive into the next account's session. See ReactionService.
    ReactionService.instance.resetSelfieCache();
    // Signed storage URLs outlive the session that minted them (1h TTL),
    // so without this the next account on this device could keep loading
    // the previous account's private Us-album and ping photos until they
    // expired. See StorageService.clearSignedUrlCache.
    StorageService.clearSignedUrlCache();
  }
}
