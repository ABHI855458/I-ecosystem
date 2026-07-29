import '../core/supabase_config.dart';

/// Resolves the signed-in auth user's row in the app's own `users` table.
///
/// STOPGAP: nothing in the current sign-in flow (features/auth/*) inserts a
/// `users` row after a successful auth. Every write path elsewhere in this
/// app that touches "the current user" (memory_service.dart,
/// reaction_service.dart) sidesteps this by using the raw Supabase auth UID
/// directly as the FK value — but `posts.user_id`, `comments.user_id`, and
/// the new `buckets`/`bucket_contributions` tables all FK to `users.id`,
/// a separate app-level UUID, not `auth.users.id`. Without this, the
/// Private tab and Buckets have no valid id to write or filter by.
///
/// This lazily creates a `users` row on first use with placeholder
/// name/anon_name values (no bio/avatar flow is run). It is not a
/// replacement for real onboarding — once this app has a proper post-signup
/// provisioning step, this class should be deleted in favor of that.
class CurrentUserService {
  CurrentUserService._();
  static final instance = CurrentUserService._();

  String? _cachedUserId;

  /// Returns the current user's `users.id`, creating that row on first use
  /// if it doesn't exist yet. Throws StateError if nobody is signed in —
  /// only call this from authenticated screens.
  Future<String> resolveId() async {
    final cached = _cachedUserId;
    if (cached != null) return cached;

    final authUser = supabase.auth.currentUser;
    if (authUser == null) {
      throw StateError(
          'CurrentUserService.resolveId() called with no signed-in user');
    }

    final existing = await supabase
        .from('users')
        .select('id')
        .eq('auth_id', authUser.id)
        .maybeSingle();
    if (existing != null) {
      final id = existing['id'] as String;
      _cachedUserId = id;
      return id;
    }

    // Placeholder values only — real name/handle collection happens in
    // profile editing, not here. anon_name uses the full auth UID (not a
    // truncated slice) so it can't collide with another lazily-created row.
    final email = authUser.email ?? '${authUser.id}@placeholder.local';
    final inserted = await supabase
        .from('users')
        .insert({
          'auth_id': authUser.id,
          'email': email,
          'name': email.split('@').first,
          'anon_name': 'user_${authUser.id}',
        })
        .select('id')
        .single();

    final id = inserted['id'] as String;
    _cachedUserId = id;
    return id;
  }

  /// Clears the cached id — call on sign-out so a subsequent sign-in (as a
  /// different user) doesn't reuse a stale id.
  void reset() => _cachedUserId = null;
}
