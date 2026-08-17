import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// OtpScreen — 6-digit code entry as six individually-focused boxes (not a
// single text field), auto-advancing on each digit and auto-submitting once
// all six are filled. On a successful verifyOTP, this screen does NOT
// navigate anywhere itself — AuthGate (auth_gate.dart) holds a
// StreamBuilder on supabase.auth.onAuthStateChange, which fires the moment
// verifyOTP succeeds and swaps the whole app root (login → onboarding/home)
// out from under this screen automatically. This screen just pops itself
// off the (now-obsolete) auth Navigator stack once that's happened.
// ---------------------------------------------------------------------------

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.email});

  final String email;

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
        type: OtpType.email,
      );
      debugPrint(
        '[OtpScreen._verify] verifyOTP returned — session=${res.session != null} user=${res.user?.id}',
      );
      // AuthGate's auth-state listener swaps the root content to
      // MainShell/OnboardingScreen once the session lands, but that root
      // swap doesn't touch this screen's own pushed route — pop it off
      // explicitly so the swapped-in content is actually visible.
      if (mounted && res.session != null) {
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
      await SupabaseConfig.client.auth.signInWithOtp(
        email: widget.email,
        shouldCreateUser: true,
      );
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Code resent to ${widget.email}')),
        );
      }
    } catch (e, st) {
      debugPrint('[OtpScreen._resend] signInWithOtp(${widget.email}) failed: $e\n$st');
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
              if (_showSpamHint) ...[
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
