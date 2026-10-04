// ---------------------------------------------------------------------------
// PasswordPolicy — one rule set for every "set/change a password" screen
// (AuthScreen's signup, ResetPasswordScreen's forced/forgot-password flow).
//
// User request 2026-09-29: "set correct password restriction how in apps
// they keep use a special case" — Supabase Auth's own server-side minimum
// is 6 characters with no complexity rule at all, which is what let a
// password like "aaaaaa" through. This adds the same client-side shape most
// apps enforce (Instagram/Google-style): a minimum length plus at least one
// letter, one digit, and one special character. It's UX only — a clear
// error before the round trip — the same way AuthScreen's old email-domain
// check was UX in front of a real server-side gate; there is no
// corresponding server-side length/complexity trigger here because
// Supabase Auth has no hook for one, so this client check is what actually
// stops a weak password today.
// ---------------------------------------------------------------------------

class PasswordPolicy {
  const PasswordPolicy._();

  static const int minLength = 8;

  static final RegExp _letter = RegExp(r'[A-Za-z]');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _special = RegExp(r'[!@#$%^&*()_\-+=\[\]{};:,.<>/?|~`]');

  /// Null when [password] satisfies the policy; otherwise the one thing to
  /// fix, stated plainly (shown as-is in an error line under the field).
  static String? describe(String password) {
    if (password.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (!_letter.hasMatch(password)) {
      return 'Password must include a letter.';
    }
    if (!_digit.hasMatch(password)) {
      return 'Password must include a number.';
    }
    if (!_special.hasMatch(password)) {
      return 'Password must include a special character (like ! or @).';
    }
    return null;
  }

  static bool isValid(String password) => describe(password) == null;
}
