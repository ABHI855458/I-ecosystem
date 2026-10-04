import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/password_policy.dart';
import '../../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// ResetPasswordScreen — last step of the forgot-password flow. Reached only
// after OtpScreen's recovery-purpose verifyOTP has already produced a live
// session (see OtpScreen._verify's OtpPurpose.recovery branch); this screen
// just sets a new password on that session via updateUser. It's also reused
// as the mandatory "set a password" step for the app's 6 pre-existing
// passwordless (OTP-only) accounts — same call, same screen, since both
// cases are "you have a session but no usable password yet".
//
// On success this pops back to the first route on the auth Navigator stack,
// same pattern OtpScreen already uses — AuthGate's onAuthStateChange
// listener has had a session the whole time this screen was up, so nothing
// further needs to happen here to land the user in the app.
// ---------------------------------------------------------------------------

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  /// Instagram-style reveal toggles (explicit request) — independent per
  /// field, since checking the new password doesn't mean you want the
  /// confirm field bare too.
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    final issue = PasswordPolicy.describe(password);
    if (issue != null) {
      setState(() => _error = issue);
      return;
    }
    if (password != confirm) {
      setState(() => _error = "Passwords don't match.");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await SupabaseConfig.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, st) {
      debugPrint('[ResetPasswordScreen._submit] updateUser failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't set your password. Try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                'Set a new password',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'For ${widget.email}',
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.textMuted),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  filled: true,
                  hintText: 'New password',
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
              const SizedBox(height: 6),
              Text(
                'At least ${PasswordPolicy.minLength} characters, with a '
                'letter, a number and a special character.',
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  filled: true,
                  hintText: 'Confirm new password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.errorRed),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('Save password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
