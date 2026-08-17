import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../main_shell.dart';
import '../../services/current_user_service.dart';
import '../../screens/onboarding/select_clubs_screen.dart';
import 'auth_screen.dart';
import 'onboarding_screen.dart';

// ---------------------------------------------------------------------------
// AuthGate — the app's actual root (see main.dart). Routes on
// supabase.auth.onAuthStateChange rather than a one-shot check, so sign-in,
// sign-out, and background token refresh are all handled through the same
// path: sign-in fires an event → this rebuilds → OTP/onboarding screens get
// swapped out for the home feed automatically, with no manual Navigator
// call needed from OtpScreen/OnboardingScreen themselves. A signOut() call
// from anywhere (only ever an explicit user action — see ProfileScreen)
// works the same way in reverse.
//
// Session persistence itself needs no code here — supabase_flutter defaults
// to SharedPreferencesLocalStorage when Supabase.initialize() isn't given an
// authOptions override (confirmed via source read; supabase_config.dart
// passes none), so supabase.auth.currentSession is already hydrated from
// disk by the time this widget's first build runs (SupabaseConfig.initialize
// is awaited in main() before runApp()) — that's what prevents any
// login-screen flash for an already-signed-in user; _initialSession below is
// read once, synchronously, not fetched.
// ---------------------------------------------------------------------------

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Session? _session = supabase.auth.currentSession;
  bool? _onboardingComplete;
  bool? _hasCommunity;

  @override
  void initState() {
    super.initState();
    supabase.auth.onAuthStateChange.listen(_onAuthStateChange);
    if (_session != null) _checkOnboarding();
  }

  void _onAuthStateChange(AuthState data) {
    if (!mounted) return;
    debugPrint(
      '[AuthGate._onAuthStateChange] event=${data.event} session=${data.session != null}',
    );
    final signedOut = data.session == null && _session != null;
    setState(() {
      _session = data.session;
      // Re-check on every fresh sign-in (a different account may have
      // signed in on the same device); clearing on sign-out just tidies
      // state, ProfileScreen's logout already calls reset() on the caches.
      _onboardingComplete = null;
      _hasCommunity = null;
    });
    if (signedOut) {
      CurrentUserService.instance.reset();
    } else if (data.session != null) {
      _checkOnboarding();
    }
  }

  Future<void> _checkOnboarding() async {
    debugPrint('[AuthGate._checkOnboarding] starting isOnboardingComplete()');
    try {
      final complete = await CurrentUserService.instance.isOnboardingComplete();
      debugPrint('[AuthGate._checkOnboarding] resolved: onboardingComplete=$complete');
      if (mounted) setState(() => _onboardingComplete = complete);
      if (complete) _checkCommunityStep();
    } catch (e, st) {
      debugPrint('[AuthGate._checkOnboarding] isOnboardingComplete failed: $e\n$st');
      // Fail open to the home feed rather than trapping a real signed-in
      // user behind a broken check — a transient network blip here
      // shouldn't be able to lock anyone out of the app.
      if (mounted) setState(() => _onboardingComplete = true);
      _checkCommunityStep();
    }
  }

  /// Only reached once onboarding (name/anon-name/photo) is confirmed
  /// complete — a brand-new user hits this via OnboardingScreen's own
  /// direct navigation into SelectClubsScreen instead (see that screen's
  /// _done()), not through this path; this path exists for RETURNING users
  /// who've never done the club-select step (pre-dates this feature, or
  /// skipped it last time — see hasJoinedAnyCommunity's own doc comment).
  Future<void> _checkCommunityStep() async {
    debugPrint('[AuthGate._checkCommunityStep] starting hasJoinedAnyCommunity()');
    try {
      final has = await CurrentUserService.instance.hasJoinedAnyCommunity();
      debugPrint('[AuthGate._checkCommunityStep] resolved: hasCommunity=$has');
      if (mounted) setState(() => _hasCommunity = has);
    } catch (e, st) {
      debugPrint('[AuthGate._checkCommunityStep] hasJoinedAnyCommunity failed: $e\n$st');
      // Fail open, same reasoning as onboarding's own catch above.
      if (mounted) setState(() => _hasCommunity = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // TEMPORARY: see DebugFlags.bypassAuthForUIWork.
    if (DebugFlags.bypassAuthForUIWork) return const MainShell();

    // TEMPORARY diagnostic — checking whether _session (this widget's own
    // cached copy, set from onAuthStateChange/initState) actually still
    // matches the SDK's live source of truth right now, live, not assumed.
    final live = supabase.auth.currentSession;
    debugPrint(
      '[AuthGate.build] LIVE currentSession: '
      'present=${live != null} '
      'userId=${live?.user.id} '
      'email=${live?.user.email} '
      'expiresAt=${live?.expiresAt != null ? DateTime.fromMillisecondsSinceEpoch(live!.expiresAt! * 1000) : null} '
      'expired=${live?.isExpired}',
    );

    final session = _session;
    if (session == null) {
      debugPrint('[AuthGate.build] no session -> AuthScreen');
      return const AuthScreen();
    }

    final complete = _onboardingComplete;
    if (complete == null) {
      debugPrint('[AuthGate.build] session present, onboarding unknown -> Splash');
      return const _SplashScreen();
    }
    if (!complete) {
      debugPrint('[AuthGate.build] onboarding incomplete -> OnboardingScreen');
      return const OnboardingScreen();
    }

    final hasCommunity = _hasCommunity;
    if (hasCommunity == null) {
      debugPrint('[AuthGate.build] onboarding complete, community-step unknown -> Splash');
      return const _SplashScreen();
    }
    if (!hasCommunity) {
      debugPrint('[AuthGate.build] no community membership -> SelectClubsScreen');
      return const SelectClubsScreen();
    }
    debugPrint('[AuthGate.build] onboarding + community step complete -> MainShell');
    return const MainShell();
  }
}

// ---------------------------------------------------------------------------
// _SplashScreen — shown only while a signed-in session's onboarding status
// is being resolved (a single query, see CurrentUserService.resolveId).
// Reuses AuthScreen's own wordmark styling so there's no visual seam between
// this and whatever screen it hands off to.
// ---------------------------------------------------------------------------

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'I',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 72,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
