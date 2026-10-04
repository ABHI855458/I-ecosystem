import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0A0A0F);
  static const Color cardSurface = Color(0xFF0D0D15);
  static const Color primary = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFF000000);
  static const Color secondary = Color(0xFF999999);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF999999);
  static const Color border = Color(0x1AFFFFFF); // white @ 10%
  static const Color errorRed = Color(0xFFFF4444);
  static const Color coral = Color(0xFFE1306C); // Instagram pink — primary
  static const Color sage = Color(0xFF833AB4); // Instagram purple — secondary
  static const Color gold = Color(0xFFF77737); // Instagram orange/gold

  // Glass surface helpers
  static const Color glassSurface = Color(0x1AFFFFFF); // white @ 10%
  static const Color glassBorder = Color(0x26FFFFFF); // white @ 15%

  // V2 accent palette — cyan / magenta / purple
  static const Color neonCyan = Color(0xFF00FFFF);
  static const Color vibrantMagenta = Color(0xFFFF006E);
  static const Color electricPurple = Color(0xFF9D4EDD);

  // Anonymous feed accent — replaces the old glowing magenta ghost-prompt
  // bar (didn't read well on the feed's white background). A muted, deep
  // teal instead: calm and legible on white without competing with the
  // coral CTA color used elsewhere.
  static const Color accentTeal = Color(0xFF2A9D8F);

  // Instagram gradient
  static const LinearGradient instaGradient = LinearGradient(
    colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Full Instagram gradient (for legend tier / special elements)
  static const LinearGradient fullInstaGradient = LinearGradient(
    colors: [
      Color(0xFF405DE6),
      Color(0xFF833AB4),
      Color(0xFFE1306C),
      Color(0xFFF77737),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppStrings {
  AppStrings._();

  /// The name shown TO USERS — home-screen label and the login wordmark.
  ///
  /// Deliberately not the project's identity: the bundle id stays
  /// com.abhisheksdpatel.iapp, the repo stays "i", and the dashboard stays
  /// "RVCE — Institutional Dashboard". This is the public-facing brand only.
  static const String appName = 'Ping';

  /// The PUBLICLY HOSTED legal documents (Netlify). These URLs — not the
  /// in-app copy in legal_content.dart — are what the Play Console Data
  /// Safety form points at, and what the signup flow must link to, because
  /// a store listing needs a URL a reviewer can open without installing the
  /// app. legal_content.dart stays as the offline-readable mirror; if either
  /// changes, both change together.
  /// Extensionless on purpose — the consolidated site (palster-site/) serves
  /// these as clean URLs and 301s the old *.html paths onto them, so these
  /// keep working across the rebrand. These same URLs go in the Play Console
  /// Data Safety form; change them in one place only.
  static const String privacyPolicyUrl =
      'https://wonderful-dodol-de7931.netlify.app/privacy';
  static const String eulaUrl =
      'https://wonderful-dodol-de7931.netlify.app/eula';

  /// Play requires a publicly reachable account-deletion page, reachable
  /// WITHOUT installing the app — an in-app-only path does not satisfy the
  /// Data Safety form on its own.
  static const String deleteAccountUrl =
      'https://wonderful-dodol-de7931.netlify.app/delete-account';
  static const String supabaseUrl =
      'https://uehqazxnodndutjvxemq.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_Vj5_7tm1bwJEL2XjMWbGdw_I8PGv2eV';

  /// Email domains this campus-only app USED TO require for signup.
  /// Enforced server-side by enforce_college_email_domain() (a BEFORE
  /// INSERT trigger on auth.users, supabase/migrations/
  /// 20260907010000_branch_and_config.sql, extended to a second domain by
  /// 20260905020000_allow_rvu_email_domain) — that trigger is the actual
  /// gate and reads its on/off state from
  /// app_config.require_college_email_domain, which is now OFF (user
  /// request 2026-09-29, 20260929070000_allow_any_email_domain.sql): any
  /// email can sign up. This constant is unreferenced now — kept only as a
  /// record of what the flag used to require, in case it's ever turned
  /// back on.
  static const List<String> allowedEmailDomains = ['@rvce.edu.in', '@rvu.edu.in'];

  /// Exact addresses exempt from [allowedEmailDomains] — the Play Store
  /// review account, which cannot hold a college address but must be able to
  /// sign in for review.
  ///
  /// Deliberately NOT an entry in [allowedEmailDomains]: that list is matched
  /// with endsWith(), so an address there would also admit any longer address
  /// ending in the same string (evil + playstore-review@useiapp.online).
  /// Compared with == only.
  static const List<String> exactEmailAllowlist = [
    'playstore-review@useiapp.online',
  ];

  /// `users.username` bounds — single source of truth shared by
  /// OnboardingScreen's validator/TextField.maxLength and the
  /// users_username_format CHECK constraint in
  /// supabase/migrations/20260905000000_username_and_anon_slots.sql. 15 is
  /// sized to fit one line in the feed's tightest author byline (the solo
  /// card's live-presence pill leaves ~15 chars of room) without ellipsis.
  ///
  /// Max cut to 10 for NEW usernames (explicit request, 2026-10-02: keep a
  /// limit so the username fits the Ping page's DP row and the camera's
  /// send grid without "…"). Enforced server-side for new/changed usernames
  /// by 20261003000000_username_max_10.sql; existing longer ones are left
  /// alone and shrink-to-fit in those rows instead.
  static const int usernameMinLength = 3;
  static const int usernameMaxLength = 10;
}

/// TEMPORARY debug switches. See AuthGate.build() and
/// CurrentUserService.resolveId() for what each flag skips.
class DebugFlags {
  DebugFlags._();

  /// Skips the login/session gate entirely (goes straight to MainShell) and
  /// makes resolveId()-dependent features use a fake user id instead of
  /// throwing. For viewing/working on UI while real auth is blocked on
  /// something external (e.g. SMTP domain verification) — NOT a security
  /// control. Flip back to `false` before any real login testing or before
  /// shipping a build.
  ///
  /// Overridable via `--dart-define=BYPASS_AUTH_FOR_UI_WORK=true` — same
  /// isolated-verification pattern as main.dart's _screenshotMode, so a
  /// dedicated debug-simulator run can flip this on without hand-editing
  /// (and risking colliding with) this shared constant.
  static const bool bypassAuthForUIWork = bool.fromEnvironment(
    'BYPASS_AUTH_FOR_UI_WORK',
    defaultValue: false,
  );
}
