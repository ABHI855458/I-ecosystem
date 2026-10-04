import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../screens/onboarding/select_clubs_screen.dart';
import '../../services/anon_name_generator.dart';
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
  final _usernameController = TextEditingController();
  final _anonName1Controller = TextEditingController();
  File? _localPhoto;
  bool _uploadingPhoto = false;
  bool _photoError = false;
  bool _saving = false;
  String? _error;

  /// Self-reported DOB, asked once here. Play content-rating compliance: the
  /// target audience spans 16-17 and 18+, which requires a neutral age
  /// screen. Never displayed anywhere, never sent to another user — written
  /// through set_my_birth_date() (the column is REVOKEd from `authenticated`).
  DateTime? _birthDate;

  Timer? _usernameCheckDebounce;
  bool _checkingUsername = false;
  String? _usernameAvailabilityError;

  /// Anon names already offered/rejected this session — [_suggestAnonName]
  /// avoids repeating one, and [_shuffleAnonName] uses it too so the dice
  /// button never lands on the same suggestion twice in a row.
  final Set<String> _triedAnonNames = {};
  bool _suggestingAnonName = false;

  @override
  void initState() {
    super.initState();
    // No auto-filled guess here on purpose — the box starts empty so the
    // person types their own username rather than editing one we picked
    // for them from their email address.
    _usernameController.addListener(_onUsernameChanged);
    // The anon name field is the opposite: auto-filled from the start
    // (explicit request, 2026-09-29 — "no need to type... give different
    // names not same for everyone"), still a normal editable field.
    unawaited(_suggestAnonName());
  }

  /// Picks a random candidate and, if it's genuinely free, drops it into
  /// the field — unless the person has already started typing their own by
  /// the time this resolves (never overwrite real input). Retries against
  /// `users.anon_name`'s UNIQUE constraint the same way username's own
  /// availability check does, up to a handful of tries.
  Future<void> _suggestAnonName() async {
    if (!mounted || _anonName1Controller.text.trim().isNotEmpty) return;
    setState(() => _suggestingAnonName = true);
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        final candidate = AnonNameGenerator.generate(avoid: _triedAnonNames);
        _triedAnonNames.add(candidate);
        if (!mounted) return;
        try {
          final rows = await supabase
              .from('users')
              .select('id')
              .ilike('anon_name', candidate)
              .limit(1);
          if ((rows as List).isEmpty) {
            if (mounted && _anonName1Controller.text.trim().isEmpty) {
              setState(() => _anonName1Controller.text = candidate);
            }
            return;
          }
        } catch (e, st) {
          // Same "UX nicety, not the source of truth" rule as username's
          // own check — _done's save still catches a real UNIQUE-constraint
          // failure at write time. A failed probe here just means the
          // field stays empty for the user to fill in themselves.
          debugPrint('[OnboardingScreen._suggestAnonName] check failed: $e\n$st');
          return;
        }
      }
    } finally {
      if (mounted) setState(() => _suggestingAnonName = false);
    }
  }

  /// The dice button next to the field — a fresh suggestion on demand, even
  /// after the person edited or cleared the auto-filled one.
  Future<void> _shuffleAnonName() async {
    if (_suggestingAnonName) return;
    setState(() => _anonName1Controller.text = '');
    await _suggestAnonName();
  }

  @override
  void dispose() {
    _usernameCheckDebounce?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _usernameController.dispose();
    _anonName1Controller.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    _usernameCheckDebounce?.cancel();
    setState(() => _usernameAvailabilityError = null);
    final candidate = _usernameController.text.trim().toLowerCase();
    if (_validateUsername(candidate) != null) return;
    _usernameCheckDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _checkingUsername = true);
      try {
        final rows = await supabase
            .from('users')
            .select('id')
            // Exact match: usernames are stored lowercase (format CHECK), and
            // ilike treats "_" as a wildcard, so "ab_c" read as taken by "abxc".
            .eq('username', candidate)
            .isFilter('deleted_at', null)
            .limit(1);
        if (!mounted || _usernameController.text.trim().toLowerCase() != candidate) return;
        setState(() {
          _usernameAvailabilityError =
              (rows as List).isNotEmpty ? 'That username is taken.' : null;
        });
      } catch (e, st) {
        // Availability check is a UX nicety, not a source of truth — the DB
        // unique index in the username_and_anon_slots migration is what
        // actually enforces this, at save time (see _done's catch below).
        // A failed probe here should never block the user from trying.
        debugPrint('[OnboardingScreen._onUsernameChanged] availability check failed: $e\n$st');
      } finally {
        if (mounted) setState(() => _checkingUsername = false);
      }
    });
  }

  /// `users.username` must match users_username_format
  /// (supabase/migrations/20260905000000_username_and_anon_slots.sql):
  /// lowercase a-z0-9_, 3-15 chars. Uniqueness is checked separately (both
  /// live, via _onUsernameChanged, and authoritatively by the DB's unique
  /// index on save).
  String? _validateUsername(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return 'Pick a username to continue.';
    if (trimmed.length < AppStrings.usernameMinLength) {
      return 'Username must be at least ${AppStrings.usernameMinLength} characters.';
    }
    if (trimmed.length > AppStrings.usernameMaxLength) {
      return 'Username must be ${AppStrings.usernameMaxLength} characters or fewer.';
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(trimmed)) {
      return 'Only lowercase letters, numbers, and underscores.';
    }
    return null;
  }

  /// Validation for the anon-name field — non-empty after trimming and
  /// under a sane length ceiling. `users.anon_name` has no DB-level length
  /// constraint, so this is a UX guard only, not a substitute for one. No
  /// content policing beyond this — anonymity here comes from the app's
  /// structure (never joined to the real name/photo anywhere), not from
  /// vetting what the user types.
  String? _validateAnonName(String value, String label, {required bool required}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return required ? 'Add a $label to continue.' : null;
    }
    if (trimmed.length > 40) {
      return '$label is too long — keep it under 40 characters.';
    }
    return null;
  }

  /// The real age gate — previously the only check on [_birthDate] was
  /// "was something picked", which let a date implying any age at all
  /// (a 5-year-old, a date-of-birth typo landing in the future-adjacent
  /// past) through onboarding. 13 is the standard minimum this kind of
  /// gate uses industry-wide (the age COPPA-style obligations key off);
  /// enforced here for immediate UX feedback, and again server-side in
  /// set_my_birth_date() since a client check alone can always be
  /// bypassed by calling the RPC directly.
  String? _validateAge(DateTime? birthDate) {
    if (birthDate == null) return 'Add your date of birth.';
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final hadBirthdayThisYear = now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hadBirthdayThisYear) age -= 1;
    if (age < 13) {
      return 'You must be at least 13 years old to use this app.';
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

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Opens on a plausible student birth year rather than today, so the
      // picker isn't 18 years of scrolling away from any real answer.
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      // Can't even SELECT a date implying under-13 — the picker enforces
      // the same 13-year minimum _validateAge checks on submit, so the
      // earliest a person actually hits the error message is if they type
      // it via an OS date-entry field that ignores lastDate; the RPC below
      // is the real backstop either way.
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Your date of birth',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  Future<void> _done() async {
    final username = _usernameController.text.trim().toLowerCase();
    final anonName1 = _anonName1Controller.text.trim();

    // Username and anon name are required before onboarding can complete.
    // The real identity (username, real photo elsewhere) and anon persona
    // name are kept separate per POST_CARD_SPEC.md's "no real name anywhere
    // on the anon card, ever" rule; the persona photo above stays optional,
    // unchanged from before this field was added.
    final firstError = _validateUsername(username) ??
        _usernameAvailabilityError ??
        _validateAnonName(anonName1, 'anonymous name', required: true) ??
        _validateAge(_birthDate);
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
        // `name` is NOT NULL live and still read by several other screens
        // (feed_service.dart etc.) — mirroring the username into it avoids
        // touching every one of those call sites in this pass.
        'name': username,
        'username': username,
        'anon_name': anonName1,
        'active_anon_slot': 1,
      }).eq('id', id);
      // Separate RPC, not part of the update above: birth_date is column-level
      // REVOKEd from `authenticated`, so a direct write would be refused.
      await supabase.rpc<dynamic>(
        'set_my_birth_date',
        params: {'p_birth_date': _birthDate!.toIso8601String().substring(0, 10)},
      );
      await CurrentUserService.instance.markOnboardingComplete();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const SelectClubsScreen()),
        (route) => false,
      );
    } on PostgrestException catch (e, st) {
      debugPrint('[OnboardingScreen._done] save failed: ${e.code} ${e.message}\n$st');
      if (mounted) {
        // The auto-suggested anon name is availability-checked before it
        // ever reaches the field, but a genuine race (someone else takes
        // it in the gap) is still possible — attribute the 23505 to
        // whichever unique key it actually was (users_anon_name_key vs
        // users_username_lower_key), not always "username".
        setState(
          () => _error = e.code != '23505'
              ? "Couldn't save — try again."
              : e.message.contains('anon_name')
                  ? "That anonymous name's taken — try another."
                  : "That username's taken — try another.",
        );
      }
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
                'Username',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                maxLength: AppStrings.usernameMaxLength,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toLowerCase()),
                  ),
                ],
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  filled: true,
                  hintText: 'yourname',
                  counterText: '',
                  suffixIcon: _checkingUsername
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textMuted,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _usernameAvailabilityError ??
                    'Shown on every post — lowercase letters, numbers, underscores only.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _usernameAvailabilityError != null
                      ? AppColors.errorRed
                      : AppColors.textMuted,
                ),
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
                controller: _anonName1Controller,
                textInputAction: TextInputAction.next,
                style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  filled: true,
                  hintText: 'A name for the Anonymous feed',
                  // A fresh random suggestion on demand — the field already
                  // starts pre-filled with one; this is for "I don't like
                  // this one" without having to think one up by hand.
                  suffixIcon: _suggestingAnonName
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          color: AppColors.textMuted,
                          tooltip: 'Shuffle',
                          onPressed: _shuffleAnonName,
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Picked for you — never linked to your real name or photo, '
                'shown only on the Anonymous feed. Change it to anything you like.',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              Text(
                'Date of birth',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              // A real date, not an "are you 18?" checkbox: a yes/no
              // self-attestation is treated as a weak age gate. Asked once,
              // stored once, shown to nobody — see _birthDate's own doc.
              GestureDetector(
                onTap: _saving ? null : _pickBirthDate,
                behavior: HitTestBehavior.opaque,
                child: InputDecorator(
                  decoration: const InputDecoration(filled: true),
                  child: Text(
                    _birthDate == null
                        ? 'Tap to choose'
                        : '${_birthDate!.day.toString().padLeft(2, '0')}'
                          '/${_birthDate!.month.toString().padLeft(2, '0')}'
                          '/${_birthDate!.year}',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: _birthDate == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Only used to keep the app age-appropriate. Never shown on '
                'your profile or to anyone else.',
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
