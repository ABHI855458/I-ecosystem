import 'package:flutter/material.dart';

import '../../core/supabase_config.dart';
import '../../services/current_user_service.dart';
import '../profile_v2/profile_v2_tokens.dart';
import 'settings_scaffold.dart';

// ---------------------------------------------------------------------------
// EditProfileScreen — real name + bio, writing to users.name / users.bio.
// Adapted from the working (but unreachable) form in
// lib/features/profile/settings_screen.dart's _EditProfileSection — same
// load/save shape and validation, ported to a standalone PV2 screen and
// extended to cover bio (that form only had name + anon_name; bio wasn't
// wired anywhere).
//
// Avatar is out of scope: StorageService.uploadAvatar() exists but nothing
// in this app currently writes the result to users.profile_photo_url — a
// separate feature.
// ---------------------------------------------------------------------------

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      final row = await supabase
          .from('users')
          .select('name, bio')
          .eq('id', id)
          .single();
      if (!mounted) return;
      _nameController.text = row['name'] as String? ?? '';
      _bioController.text = row['bio'] as String? ?? '';
    } catch (e, st) {
      debugPrint('[EditProfileScreen._load] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't load your profile.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validate(String name, String bio) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return 'Add a name to continue.';
    if (trimmedName.length > 40) return 'Name is too long — keep it under 40 characters.';
    if (bio.trim().length > 160) return 'Bio is too long — keep it under 160 characters.';
    return null;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();
    final firstError = _validate(name, bio);
    if (firstError != null) {
      setState(() {
        _error = firstError;
        _success = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final id = await CurrentUserService.instance.resolveId();
      await supabase.from('users').update({
        'name': name,
        'bio': bio,
      }).eq('id', id);
      if (mounted) setState(() => _success = 'Saved.');
    } catch (e, st) {
      debugPrint('[EditProfileScreen._save] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't save — try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Edit Profile',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: PV2.inkStamp),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsInputCard(
                  label: 'Name',
                  field: TextField(
                    controller: _nameController,
                    maxLines: 1,
                    cursorColor: PV2.accent,
                    style: PV2.body(size: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      hintText: 'Your name',
                      hintStyle: PV2.body(size: 15, color: PV2.inkStamp),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SettingsInputCard(
                  label: 'Bio',
                  field: TextField(
                    controller: _bioController,
                    maxLines: 4,
                    maxLength: 160,
                    cursorColor: PV2.accent,
                    style: PV2.body(size: 15, height: 1.4),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      counterStyle: PV2.body(size: 10, color: PV2.inkStamp),
                      hintText: 'A short bio',
                      hintStyle: PV2.body(size: 15, color: PV2.inkStamp, height: 1.4),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: PV2.body(size: 12.5, color: PV2.danger)),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Text(_success!, style: PV2.body(size: 12.5, color: PV2.accent)),
                ],
                const SizedBox(height: 18),
                SettingsCommitButton(
                  label: 'Save',
                  enabled: true,
                  loading: _saving,
                  onTap: _save,
                ),
              ],
            ),
    );
  }
}
