import '../core/constants.dart';
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

  /// Whether the resolved user has completed onboarding (AuthGate's
  /// post-sign-in routing signal — see supabase/schema.sql's
  /// `users.onboarding_completed`). Cached alongside the id from the same
  /// resolveId() round trip, so checking it costs nothing extra.
  bool? _cachedOnboardingComplete;

  /// Returns the current user's `users.id`, creating that row on first use
  /// if it doesn't exist yet. Throws StateError if nobody is signed in —
  /// only call this from authenticated screens.
  Future<String> resolveId() async {
    final cached = _cachedUserId;
    if (cached != null) return cached;

    // TEMPORARY: see DebugFlags.bypassAuthForUIWork. No real session exists
    // while bypassed, so hand back a clearly-fake id rather than throwing —
    // it has no real `users` row, so reads scoped to it come back empty and
    // writes will fail FK constraints. Expected; this is for viewing UI, not
    // exercising write paths.
    if (DebugFlags.bypassAuthForUIWork && supabase.auth.currentUser == null) {
      const dummyId = '00000000-0000-0000-0000-000000000000';
      _cachedUserId = dummyId;
      _cachedOnboardingComplete = true;
      return dummyId;
    }

    final authUser = supabase.auth.currentUser;
    if (authUser == null) {
      throw StateError(
          'CurrentUserService.resolveId() called with no signed-in user');
    }

    final existing = await supabase
        .from('users')
        .select('id, onboarding_completed')
        .eq('auth_id', authUser.id)
        .maybeSingle();
    if (existing != null) {
      final id = existing['id'] as String;
      _cachedUserId = id;
      _cachedOnboardingComplete = existing['onboarding_completed'] as bool? ?? false;
      return id;
    }

    // Placeholder values only — real name/handle collection happens in
    // OnboardingScreen, not here. anon_name uses the full auth UID (not a
    // truncated slice) so it can't collide with another lazily-created row.
    // onboarding_completed defaults to false at the DB layer (schema.sql) —
    // this is exactly what routes a freshly-created row into onboarding.
    final email = authUser.email ?? '${authUser.id}@placeholder.local';
    final inserted = await supabase
        .from('users')
        .insert({
          'auth_id': authUser.id,
          'email': email,
          'name': email.split('@').first,
          'anon_name': 'user_${authUser.id}',
        })
        .select('id, onboarding_completed')
        .single();

    final id = inserted['id'] as String;
    _cachedUserId = id;
    _cachedOnboardingComplete = inserted['onboarding_completed'] as bool? ?? false;
    return id;
  }

  /// Resolves the user (creating the row on first-ever call, same as
  /// resolveId) and returns whether they've completed onboarding —
  /// AuthGate's routing decision between OnboardingScreen and the home feed.
  Future<bool> isOnboardingComplete() async {
    if (_cachedOnboardingComplete != null) return _cachedOnboardingComplete!;
    await resolveId();
    return _cachedOnboardingComplete ?? false;
  }

  bool? _cachedHasCommunity;

  /// AuthGate's SelectClubsScreen gate — re-queries community_members live
  /// every time this cache is empty (i.e. every fresh app process), NOT a
  /// persisted "seen it" flag. Skipping without joining anything means a
  /// user still has 0 rows here, so the screen shows again next login —
  /// intentional, matches the spec's literal skip condition.
  Future<bool> hasJoinedAnyCommunity() async {
    if (_cachedHasCommunity != null) return _cachedHasCommunity!;
    final id = await resolveId();
    final rows = await supabase
        .from('community_members')
        .select('community_id')
        .eq('user_id', id)
        .limit(1);
    _cachedHasCommunity = (rows as List).isNotEmpty;
    return _cachedHasCommunity!;
  }

  /// OnboardingScreen calls this once, on completion — never automatic.
  Future<void> markOnboardingComplete() async {
    final id = await resolveId();
    await supabase.from('users').update({'onboarding_completed': true}).eq('id', id);
    _cachedOnboardingComplete = true;
  }

  /// Clears the cached id/onboarding state — call on sign-out so a
  /// subsequent sign-in (as a different user) doesn't reuse stale state.
  void reset() {
    _cachedUserId = null;
    _cachedOnboardingComplete = null;
    _cachedHasCommunity = null;
  }
}
