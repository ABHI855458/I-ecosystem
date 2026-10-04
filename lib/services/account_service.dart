import 'package:flutter/foundation.dart';

import '../core/supabase_config.dart';
import 'supabase_service.dart';

// ---------------------------------------------------------------------------
// AccountService — invokes the `delete-account` Edge Function (supabase/
// functions/delete-account/index.ts), the one place that can soft-delete a
// user's content and ban their auth row (needs the service role — a client
// JWT can do neither). See that function's own header for why this is a
// soft-delete + ban rather than a hard delete of auth.users.
// ---------------------------------------------------------------------------

class AccountService {
  AccountService._();
  static final instance = AccountService._();

  /// Deletes (soft-deletes + bans) the signed-in account, then signs out
  /// and clears every per-session cache via the same path logout uses
  /// (SupabaseService.signOutAndResetCaches) — AuthGate's own auth-state
  /// listener takes it from there and swaps to AuthScreen, same as a normal
  /// logout.
  Future<void> deleteAccount() async {
    try {
      final res = await supabase.functions.invoke('delete-account');
      final data = res.data;
      if (data is! Map || data['ok'] != true) {
        throw StateError('delete-account returned: $data');
      }
    } catch (e, st) {
      debugPrint('[AccountService.deleteAccount] failed: $e\n$st');
      rethrow;
    }
    await SupabaseService.signOutAndResetCaches();
  }
}
