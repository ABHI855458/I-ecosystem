import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppStrings.supabaseUrl,
      publishableKey: AppStrings.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

// Top-level convenience accessor for service layer.
SupabaseClient get supabase => Supabase.instance.client;
