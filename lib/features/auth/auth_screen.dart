import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/password_policy.dart';
import '../../core/supabase_config.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';

// ---------------------------------------------------------------------------
// AuthScreen — email + password. Signup used to be gated to
// @rvce.edu.in/@rvu.edu.in (AppStrings.allowedEmailDomains); that's gone
// (2026-09-29) — enforce_college_email_domain()'s own on/off switch
// (app_config.require_college_email_domain) is now off, so ANY email can
// sign up and receive its OTP the normal way. AppStrings.allowedEmailDomains
// is kept only as a record of what the flag used to require, and is no
// longer read here.
// Two explicit modes (Log in / Create account), not one ambiguous button:
// Supabase deliberately makes signUp() on an already-registered, confirmed
// email return a success-shaped response rather than an error, to prevent
// account-existence enumeration — so there is no truthful way to tell the
// user "that account already exists" before they try. Both modes therefore
// land on the same next screen when there's nothing else to distinguish
// (Create account always continues to the OTP confirm screen), and Log in's
// failure copy is deliberately generic (never says which of email/password
// was wrong, or whether the account exists at all).
// ---------------------------------------------------------------------------

enum _AuthMode { login, signup }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _isLoading = false;
  String? _error;

  /// Starts hidden, same as every password field — a small eye button
  /// flips it (explicit request: "how in apps they keep use a special
  /// case... give eye to view it as well", i.e. the Instagram-style
  /// show/hide toggle). Login isn't policy-checked (an existing weaker
  /// password must still work), only this visibility flag applies there.
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    // The @rvce.edu.in/@rvu.edu.in gate is gone (user request 2026-09-29:
    // "remove the compulsory of rvce mail ... for normal mail the otp is
    // sent") — enforce_college_email_domain()'s own on/off switch
    // (app_config.require_college_email_domain) is now off server-side
    // (20260929070000_allow_any_email_domain.sql), so any email can sign up.
    // This screen never re-implements that check itself, on purpose: the
    // trigger is the one source of truth, and a client-side copy of it
    // would silently drift out of sync the next time that flag changes.

    // Only a NEW password is policy-checked — an already-registered
    // account's existing (possibly weaker, pre-policy) password must still
    // be able to log in.
    if (_mode == _AuthMode.signup) {
      final issue = PasswordPolicy.describe(password);
      if (issue != null) {
        setState(() => _error = issue);
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_mode == _AuthMode.login) {
        await SupabaseConfig.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        // AuthGate's onAuthStateChange listener swaps the root content the
        // moment this session lands — nothing further to do here.
      } else {
        final res = await SupabaseConfig.client.auth.signUp(email: email, password: password);
        // Normally signUp() returns no session — email confirmation is
        // required first, and OtpScreen is how the user provides that code.
        // If a session comes back immediately instead, the project's Auth →
        // Providers → Email → "Confirm email" setting is off (or some other
        // config auto-confirms new users): no confirmation email was ever
        // sent, so pushing OtpScreen here would strand the user on a screen
        // that can never receive a code — and AuthGate's listener has
        // already swapped its root to Onboarding underneath it, which is
        // exactly the "back button reveals the wrong screen" confusion this
        // guards against. Skip straight to letting AuthGate route instead.
        if (res.session != null) {
          debugPrint(
            '[AuthScreen._continue] signUp($email) returned a session with no '
            'confirmation step — Auth → Providers → Email → "Confirm email" is '
            'likely OFF in Supabase; OTP is not actually being enforced.',
          );
        } else if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OtpScreen(email: email, purpose: OtpPurpose.confirmSignup),
            ),
          );
        }
      }
    } on AuthException catch (e, st) {
      debugPrint(
        '[AuthScreen._continue] ${_mode.name}($email) failed: '
        'code=${e.code} status=${e.statusCode} message=${e.message}\n$st',
      );
      if (mounted) setState(() => _error = _authErrorMessage(e));
    } catch (e, st) {
      debugPrint('[AuthScreen._continue] ${_mode.name}($email) failed: $e\n$st');
      if (mounted) {
        // A dead network is not a credentials problem, and telling someone
        // their password is wrong when their phone simply can't reach the
        // server sends them re-typing a password that was never the issue.
        final offline = e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('ClientException');
        setState(
          () => _error = offline
              ? "Can't reach the server — check your connection and try again."
              : 'Something went wrong. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Maps a GoTrue failure to something the person can actually act on.
  ///
  /// The banned case matters specifically: deleting your account
  /// (Settings → Delete Account) soft-deletes the row AND permanently bans
  /// the auth user (supabase/functions/delete-account sets a 100-year
  /// ban_duration), so a later sign-in with correct credentials fails
  /// forever. Reporting that as "wrong email or password" sent people
  /// re-typing a password that was never wrong — the exact confusion this
  /// was reported as ("the account already exists but won't log in").
  ///
  /// This does NOT weaken enumeration protection: GoTrue only returns
  /// `user_banned` once the credentials have already validated, so it can
  /// only ever be seen by someone who already knows the password.
  String _authErrorMessage(AuthException e) {
    final code = (e.code ?? '').toLowerCase();
    final message = e.message.toLowerCase();

    if (code == 'user_banned' || message.contains('banned')) {
      return 'This account was deleted and can no longer be used to sign in. '
          'Create a new account to continue.';
    }
    if (code == 'email_not_confirmed' || message.contains('not confirmed')) {
      return 'Confirm your email first — check your inbox for the code.';
    }
    if (code == 'over_request_rate_limit' || message.contains('rate limit')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (_mode == _AuthMode.signup) {
      if (code == 'user_already_exists' || message.contains('already registered')) {
        return 'That email already has an account — use Log in instead.';
      }
      return 'Something went wrong. Try again.';
    }
    // Deliberately generic — doesn't distinguish "wrong password" from
    // "no such account", which is exactly what enumeration protection
    // means to hide.
    return "Wrong email or password, or this account doesn't exist yet — "
        'try Create account instead.';
  }

  @override
  Widget build(BuildContext context) {
    final isSignup = _mode == _AuthMode.signup;
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.vertical,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  const _Wordmark(),
                  const SizedBox(height: 16),
                  Text(
                    'Your campus, in one place.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(flex: 2),
                  _ModeSwitch(
                    mode: _mode,
                    onChanged: (m) => setState(() {
                      _mode = m;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      filled: true,
                      hintText: 'Email address',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: [
                      isSignup ? AutofillHints.newPassword : AutofillHints.password,
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _continue(),
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      hintText: 'Password',
                      // Instagram-style reveal toggle (explicit request):
                      // typing a password blind, with no way to check what
                      // was actually typed before submitting.
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  if (isSignup) ...[
                    const SizedBox(height: 6),
                    Text(
                      'At least ${PasswordPolicy.minLength} characters, with a '
                      'letter, a number and a special character.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  if (!isSignup) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                        child: Text(
                          'Forgot password?',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.errorRed,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _continue,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : Text(isSignup ? 'Create account' : 'Log in'),
                    ),
                  ),
                  const Spacer(flex: 3),
                  // Footer brand line, like Instagram's "from Meta".
                  const _PoweredBy(),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(context, _AuthMode.login, 'Log in')),
          Expanded(child: _segment(context, _AuthMode.signup, 'Create account')),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _AuthMode value, String label) {
    final selected = mode == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(value);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          // AppStrings.appName, not a literal — so the brand has one source.
          AppStrings.appName,
          style: GoogleFonts.plusJakartaSans(
            // 52, not the single letter's 72: the wordmark is four glyphs
            // ("Pals", formerly "Cliq" — same length, so this holds) and at
            // 72 it ran nearly edge to edge on a small phone.
            fontSize: 52,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            color: AppColors.textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 28,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}


/// "powered by i" — the footer brand line on the login / sign-up screen.
class _PoweredBy extends StatelessWidget {
  const _PoweredBy();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'powered by',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [Color(0xFF29D3E8), Color(0xFF37C9E6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Text(
                'i',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0B0B0D),
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
