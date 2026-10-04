import 'package:flutter/material.dart';
import '../../core/feature_flags.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../main_shell.dart';
import '../../services/current_user_service.dart';
import '../../screens/onboarding/onboarding_duo_screen.dart';
import '../../screens/onboarding/select_clubs_screen.dart';
import '../../services/us_album_service.dart';
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
  bool? _hasDuos;

  @override
  void initState() {
    super.initState();
    supabase.auth.onAuthStateChange.listen(_onAuthStateChange);
    if (_session != null) {
      // Remembered on-device from the last launch — no splash, no network.
      _onboardingComplete = CurrentUserService.instance.knownOnboardingComplete;
      _hasCommunity = CurrentUserService.instance.knownHasCommunity;
      _checkOnboarding();
    }
  }

  void _onAuthStateChange(AuthState data) {
    if (!mounted) return;
    debugPrint(
      '[AuthGate._onAuthStateChange] event=${data.event} session=${data.session != null}',
    );
    final signedOut = data.session == null && _session != null;
    // Same account (e.g. the startup initialSession / token refresh): keep
    // the gates we already know instead of flashing the splash again.
    final sameUser = data.session != null &&
        data.session!.user.id == _session?.user.id;
    if (sameUser) {
      _session = data.session;
      return;
    }
    setState(() {
      _session = data.session;
      // Re-check on every fresh sign-in (a different account may have
      // signed in on the same device); clearing on sign-out just tidies
      // state, ProfileScreen's logout already calls reset() on the caches.
      _onboardingComplete = null;
      _hasCommunity = null;
      _hasDuos = null;
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
      // Fast onboarding ignores the Duo gate (see build), so don't spend a
      // network round trip (or two) on it before the feed can show.
      if (has && !kFastOnboarding) _checkDuoStep();
    } catch (e, st) {
      debugPrint('[AuthGate._checkCommunityStep] hasJoinedAnyCommunity failed: $e\n$st');
      // Fail open, same reasoning as onboarding's own catch above.
      if (mounted) setState(() => _hasCommunity = true);
      _checkDuoStep();
    }
  }

  /// Mandatory Duo step for users who already finished onboarding before it
  /// existed (or left the app mid-step): fewer than [kMinOnboardingDuos]
  /// Duo requests sent → OnboardingDuoScreen before the feed.
  Future<void> _checkDuoStep() async {
    try {
      final partners = await DuoService.instance.fetchDuoPartnerIds();
      debugPrint('[AuthGate._checkDuoStep] duo partners=${partners.length}');
      var met = partners.length >= kMinOnboardingDuos;
      if (!met) {
        // Same capped requirement the Duo screen shows: never demand more
        // Duos than there are people in your clubs to send them to, or an
        // early / small-club user gets bounced back to a screen they can't
        // finish, on every login.
        final candidates = await loadDuoCandidates(null);
        final unsent =
            candidates.where((p) => !partners.contains(p['id'])).length;
        met = partners.length >=
            onboardingDuosRequired(
              sentCount: partners.length,
              availableUnsent: unsent,
            );
      }
      if (mounted) setState(() => _hasDuos = met);
    } catch (e, st) {
      debugPrint('[AuthGate._checkDuoStep] failed: $e\n$st');
      // Fail open, same reasoning as onboarding's own catch above.
      if (mounted) setState(() => _hasDuos = true);
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
    final hasDuos = kFastOnboarding ? true : _hasDuos;
    if (hasDuos == null) return const _SplashScreen();
    if (!hasDuos) {
      debugPrint('[AuthGate.build] fewer than $kMinOnboardingDuos duos -> OnboardingDuoScreen');
      return const OnboardingDuoScreen();
    }
    debugPrint('[AuthGate.build] onboarding + community + duo steps complete -> MainShell');
    return const MainShell();
  }
}

// ---------------------------------------------------------------------------
// _SplashScreen — shown only while a signed-in session's onboarding status
// is being resolved (a single query, see CurrentUserService.resolveId).
// Reuses AuthScreen's own wordmark styling so there's no visual seam between
// this and whatever screen it hands off to.
// ---------------------------------------------------------------------------

/// The launch screen, shown while [AuthGate] is still resolving whether
/// there's a session.
///
/// BUG FIX / explicit request: "this shall have the name Cliq and app logo
/// as such, in good font." This used to render a bare "I" letterform with
/// no icon at all — the one showcase surface that's supposed to carry the
/// app's public brand (see AppStrings.appName's own doc: home screen icon
/// + login page + this) still showed the project's internal single-letter
/// placeholder. Now mirrors AuthScreen's own `_Wordmark` (same font, same
/// accent underline) with the real app icon above it, rather than
/// inventing a second, different treatment for the same brand.
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
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/brand/logo.png',
                width: 84,
                height: 84,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              AppStrings.appName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                color: AppColors.textPrimary,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 9),
            Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
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
