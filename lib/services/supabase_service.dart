import '../core/supabase_config.dart';
import 'current_user_service.dart';
import 'post_author_pin_service.dart';
import 'reaction_preset_service.dart';

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
    await supabase.auth.signOut();
  }

  /// The one place every per-session cache gets cleared on logout. Single
  /// source of truth so a newly-added cache (like PostAuthorPinService,
  /// missing from here until now — profile_screen.dart's old _confirmLogout
  /// called signOut()/CurrentUserService.reset()/ReactionPresetService.reset()
  /// directly and had drifted out of sync with what actually needs
  /// resetting) can't be forgotten by a second call site again.
  static Future<void> signOutAndResetCaches() async {
    await signOut();
    CurrentUserService.instance.reset();
    ReactionPresetService.instance.reset();
    PostAuthorPinService.instance.reset();
  }
}
