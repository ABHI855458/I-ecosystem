import '../core/supabase_config.dart';

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
}
