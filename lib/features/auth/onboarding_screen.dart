import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../screens/onboarding/select_clubs_screen.dart';
import '../../services/anon_persona_service.dart';
import '../../services/current_user_service.dart';
import '../../services/storage_service.dart';

// ---------------------------------------------------------------------------
// OnboardingScreen — shown once, right after a brand-new sign-up (AuthGate
// routes here whenever CurrentUserService.isOnboardingComplete() is false —
// i.e. every freshly lazily-created `users` row, see schema.sql's
// onboarding_completed default). Two lightweight steps: confirm/edit the
// placeholder name CurrentUserService.resolveId() derived from the email,
// and optionally set an anon persona photo (never the real profile photo —
// same rule the rest of the app follows for anonymous-feed identity).
//
// Persona photo reuses the same StorageService/AnonPersonaService pair
// profile_screen.dart's own (private, not reusable from here)
// _AnonPersonaPhotoPicker uses — NOT that widget itself, a small dedicated
// one, wired to the real resolved user id instead of that widget's
// hardcoded 'user_abhishek' placeholder.
//
// "Done" persists both, marks onboarding complete, and replaces this
// screen with SelectClubsScreen directly (not MainShell — AuthGate's own
// _hasCommunity gate only re-evaluates on auth-state events, not on this
// screen's direct DB writes, so a brand-new user needs the hop chained
// here explicitly; SelectClubsScreen is what actually lands on MainShell).
// ---------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _anonNameController = TextEditingController();
  File? _localPhoto;
  bool _uploadingPhoto = false;
  bool _photoError = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final authUser = supabase.auth.currentUser;
    _nameController.text = authUser?.email?.split('@').first ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _anonNameController.dispose();
    super.dispose();
  }

  /// Shared validation for both name fields — non-empty after trimming and
  /// under a sane length ceiling. `users.name`/`users.anon_name` have no
  /// DB-level length constraint, so this is a UX guard only, not a
  /// substitute for one. No content policing on the anon name beyond this —
  /// anonymity here comes from the app's structure (never joined to the
  /// real name/photo anywhere), not from vetting what the user types.
  String? _validateName(String value, String label) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Add a $label to continue.';
    if (trimmed.length > 40) {
      return '$label is too long — keep it under 40 characters.';
    }
    return null;
  }

  Future<void> _pickPhoto() async {
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    final file = File(xFile.path);
    setState(() {
      _localPhoto = file;
      _uploadingPhoto = true;
      _photoError = false;
    });
    try {
      final userId = await CurrentUserService.instance.resolveId();
      final url = await StorageService.uploadPersonaPhoto(file: file, userId: userId);
      if (!mounted) return;
      if (url != null) {
        AnonPersonaService.instance.setPhoto(url);
      } else {
        setState(() => _photoError = true);
      }
    } catch (e, st) {
      debugPrint('[OnboardingScreen._pickPhoto] upload failed: $e\n$st');
      if (mounted) setState(() => _photoError = true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _done() async {
    final name = _nameController.text.trim();
    final anonName = _anonNameController.text.trim();

    // Both required before onboarding can complete — real name (Friends/
    // Everyone feed, real avatar) and anon persona name (Anonymous feed
    // only) are separate identities, per POST_CARD_SPEC.md's "no real name
    // anywhere on the anon card, ever" rule; the persona photo above stays
    // optional, unchanged from before this field was added.
    final firstError =
        _validateName(name, 'name') ?? _validateName(anonName, 'anonymous name');
    if (firstError != null) {
      setState(() => _error = firstError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await CurrentUserService.instance.resolveId();
      await supabase.from('users').update({
        'name': name,
        'anon_name': anonName,
      }).eq('id', id);
      await CurrentUserService.instance.markOnboardingComplete();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SelectClubsScreen()),
        (route) => false,
      );
    } catch (e, st) {
      debugPrint('[OnboardingScreen._done] save failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't save — try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
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
              const SizedBox(height: 24),
              Text(
                "You're in.",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set up your profile before you jump in.',
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 32),
              Center(child: _PersonaPhotoPicker(
                localPhoto: _localPhoto,
                uploading: _uploadingPhoto,
                hasError: _photoError,
                onTap: _pickPhoto,
              )),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Anon persona photo — shown on the Anonymous feed only, never your real photo. Optional.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Real name',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                decoration: const InputDecoration(hintText: 'Your name'),
              ),
              const SizedBox(height: 6),
              Text(
                'Shown on the Friends/Everyone feed with your real photo.',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              Text(
                'Anonymous name',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _anonNameController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _done(),
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                decoration: const InputDecoration(hintText: 'A name for the Anonymous feed'),
              ),
              const SizedBox(height: 6),
              Text(
                'Never linked to your real name or photo — shown only on the Anonymous feed.',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.errorRed),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _done,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('Get started'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonaPhotoPicker extends StatelessWidget {
  const _PersonaPhotoPicker({
    required this.localPhoto,
    required this.uploading,
    required this.hasError,
    required this.onTap,
  });

  final File? localPhoto;
  final bool uploading;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardSurface,
          border: Border.all(
            color: hasError ? AppColors.errorRed : AppColors.border,
          ),
        ),
        child: Center(child: _content()),
      ),
    );
  }

  Widget _content() {
    if (uploading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
      );
    }
    if (localPhoto != null) {
      return ClipOval(
        child: Image.file(localPhoto!, width: 92, height: 92, fit: BoxFit.cover),
      );
    }
    return const Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted, size: 26);
  }
}
