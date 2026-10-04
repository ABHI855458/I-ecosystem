import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import 'reset_password_screen.dart';

/// Institutional college mail (RVCE/RVU) routes this app's OTP to Spam/Junk
/// far more often than a personal Gmail address does — their mail filters
/// flag anything from a new automated sender. Reuses AppStrings.
/// allowedEmailDomains (the old signup-restriction list, unreferenced since
/// 20260929070000_allow_any_email_domain.sql let any domain sign up) as
/// exactly the "known institutional domain" list this needs.
bool _isInstitutionalEmail(String email) {
  final e = email.toLowerCase().trim();
  return AppStrings.allowedEmailDomains.any((d) => e.endsWith(d));
}

// ---------------------------------------------------------------------------
// OtpScreen — 6-digit code entry as six individually-focused boxes (not a
// single text field), auto-advancing on each digit and auto-submitting once
// all six are filled.
//
// Two purposes share this one screen (same code, same 6-box input, same
// resend/cooldown UX — no reason to fork it):
//  - confirmSignup: verifies a brand-new signUp()'s email. On success,
//    AuthGate's onAuthStateChange listener swaps the whole app root out from
//    under this screen automatically (login → onboarding/home) — this screen
//    just pops itself off the now-obsolete auth Navigator stack.
//  - recovery: verifies a resetPasswordForEmail() code. Success DOES create
//    a session too (so AuthGate's listener also fires), but landing the user
//    straight in the app mid-recovery would be wrong — this screen instead
//    pushes ResetPasswordScreen directly so they set the new password before
//    anything else happens.
// ---------------------------------------------------------------------------

enum OtpPurpose { confirmSignup, recovery }

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.email,
    this.purpose = OtpPurpose.confirmSignup,
  });

  final String email;
  final OtpPurpose purpose;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _codeKey = GlobalKey<_OtpCodeInputState>();
  bool _isLoading = false;
  bool _showSpamHint = false;
  String? _error;
  Timer? _hintTimer;

  Timer? _cooldownTimer;
  int _cooldownSeconds = 30;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showSpamHint = true);
    });
    // A code was already sent by AuthScreen right before this screen opened
    // — start the cooldown immediately rather than only after the user taps
    // resend once, so "resend" can never fire faster than the code itself.
    _startCooldown();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _cooldownSeconds = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Future<void> _verify(String otp) async {
    if (otp.length != 6) return;
    debugPrint('[OtpScreen._verify] submitting code (len=${otp.length}) for ${widget.email}');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await SupabaseConfig.client.auth.verifyOTP(
        email: widget.email,
        token: otp,
        type: widget.purpose == OtpPurpose.recovery
            ? OtpType.recovery
            : OtpType.signup,
      );
      debugPrint(
        '[OtpScreen._verify] verifyOTP returned — session=${res.session != null} user=${res.user?.id}',
      );
      if (!mounted || res.session == null) return;
      if (widget.purpose == OtpPurpose.recovery) {
        // A recovery verifyOTP also creates a session, which would make
        // AuthGate's listener drop the user straight into the app mid
        // password-reset — push the actual reset screen instead of relying
        // on that swap, same as confirmSignup does below.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ResetPasswordScreen(email: widget.email),
          ),
        );
      } else {
        // AuthGate's auth-state listener swaps the root content to
        // MainShell/OnboardingScreen once the session lands, but that root
        // swap doesn't touch this screen's own pushed route — pop it off
        // explicitly so the swapped-in content is actually visible.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e, st) {
      debugPrint('[OtpScreen._verify] verifyOTP(${widget.email}) failed: $e\n$st');
      if (mounted) {
        setState(() => _error = 'Invalid or expired code. Please try again.');
        _codeKey.currentState?.clear();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldownSeconds > 0) return;
    try {
      if (widget.purpose == OtpPurpose.recovery) {
        await SupabaseConfig.client.auth.resetPasswordForEmail(widget.email);
      } else {
        // resend(), not signInWithOtp() — this is a signup confirmation
        // code, and resend() doesn't need the password threaded back in
        // here just to re-issue it.
        await SupabaseConfig.client.auth.resend(
          type: OtpType.signup,
          email: widget.email,
        );
      }
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Code resent to ${widget.email}')),
        );
      }
    } catch (e, st) {
      debugPrint('[OtpScreen._resend] resend(${widget.email}) failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't resend the code. Try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'Check your email',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Enter the 6-digit code sent to\n${widget.email}',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.textMuted,
                  height: 1.6,
                ),
              ),
              // Institutional mail (RVCE/RVU) shown right away, not gated
              // behind the 10s timer below — their filters near-certainly
              // route this to Spam/Junk, it isn't a "maybe it's just slow"
              // guess the way the generic hint is for everyone else.
              if (_isInstitutionalEmail(widget.email)) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'College mail (RVCE/RVU) often sends this straight to '
                    'Spam or Junk — check there if it doesn’t show up '
                    'in a minute.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ] else if (_showSpamHint) ...[
                const SizedBox(height: 12),
                Text(
                  'Check your spam folder — code may take up to 2 minutes',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              _OtpCodeInput(
                key: _codeKey,
                enabled: !_isLoading,
                onCompleted: _verify,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.errorRed,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: _cooldownSeconds > 0 ? null : _resend,
                  child: Text(
                    _cooldownSeconds > 0 ? 'Resend code in ${_cooldownSeconds}s' : 'Resend code?',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: _cooldownSeconds > 0
                          ? AppColors.textMuted.withValues(alpha: 0.5)
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _OtpCodeInput — six individually-focused single-digit boxes. Owns its own
// controllers/focus nodes (uncontrolled from the parent's perspective) —
// the parent only hears about it via onCompleted(code) once all six are
// filled, and can force a reset (wrong code) via the exposed clear() method
// through a GlobalKey<_OtpCodeInputState>.
// ---------------------------------------------------------------------------

class _OtpCodeInput extends StatefulWidget {
  const _OtpCodeInput({
    super.key,
    required this.onCompleted,
    required this.enabled,
  });

  final ValueChanged<String> onCompleted;
  final bool enabled;

  @override
  State<_OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<_OtpCodeInput> {
  static const _length = 6;
  final _controllers = List.generate(_length, (_) => TextEditingController());
  final _focusNodes = List.generate(_length, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() {});
  }

  void _onChanged(int index, String value) {
    // Paste/autofill can drop the whole code into whichever box currently
    // has focus (iOS's one-time-code suggestion targets a single field) —
    // detect that and fan it out across the remaining boxes instead of
    // just keeping the first digit and dropping the rest.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length > _length) {
        debugPrint(
          '[_OtpCodeInput] pasted code has ${digits.length} digits but only '
          '$_length boxes exist — truncating to "${digits.substring(0, _length)}". '
          'If Supabase is issuing longer codes, this box count needs to change.',
        );
      }
      for (var i = 0; i < _length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final lastFilled = digits.length.clamp(0, _length) - 1;
      if (lastFilled >= 0 && lastFilled < _length - 1) {
        _focusNodes[lastFilled + 1].requestFocus();
      } else {
        _focusNodes[_length - 1].requestFocus();
      }
      _maybeComplete();
      return;
    }

    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _maybeComplete();
  }

  void _maybeComplete() {
    final code = _controllers.map((c) => c.text).join();
    setState(() {});
    if (code.length == _length) {
      debugPrint('[_OtpCodeInput] all $_length boxes filled — submitting "$code"');
      FocusScope.of(context).unfocus();
      widget.onCompleted(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < _length; i++)
          SizedBox(
            width: 44,
            height: 56,
            child: Focus(
              onKeyEvent: (node, event) => _handleKey(i, event),
              child: TextField(
                controller: _controllers[i],
                focusNode: _focusNodes[i],
                enabled: widget.enabled,
                autofocus: i == 0,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                textInputAction: i == _length - 1 ? TextInputAction.done : TextInputAction.next,
                autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: AppColors.cardSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                onChanged: (v) => _onChanged(i, v),
              ),
            ),
          ),
      ],
    );
  }
}
