import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../services/current_user_service.dart';
import '../../services/post_author_pin_service.dart';
import '../../services/supabase_service.dart';
import 'profile_screen.dart' show AnonPersonaPhotoPicker;

// ---------------------------------------------------------------------------
// SettingsScreen — reached from ProfileScreen's own header (gear icon, next
// to the existing logout icon — that icon is left in place rather than
// removed, so logout stays reachable in one tap; this screen is the second,
// fuller entry point that bundles it with everything else).
//
// Every section here talks to a real, already-existing table/RPC — nothing
// stubbed. Three settings from the original ask are deliberately NOT built,
// each with an explanation shown in-app instead of a fake control:
//   - Notification preferences: no preference-storage table exists.
//     notification_events is a service-role-only audit/idempotency log
//     (schema.sql), and device_tokens only stores push registration
//     tokens — neither has a per-category mute/toggle column.
//   - Pinned people list (view/unpin): pinned_people has RLS enabled with
//     NO client policies (schema.sql) — the only sanctioned entry points
//     are PostAuthorPinService's two RPCs, both keyed by post_id
//     (toggle_pin_post_author / is_post_author_pinned). There is no RPC to
//     list everyone a user has pinned, or to unpin by user_id directly —
//     that's a real backend gap, not a client oversight.
//   - Delete account: no existing service, and it's irreversible with wide
//     cascade blast radius (posts/comments/reactions/pings/groups/
//     communities.created_by, etc., with inconsistent ON DELETE rules) —
//     flagged rather than guessed at.
// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Settings',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: const [
          _EditProfileSection(),
          SizedBox(height: 28),
          _BlockedUsersSection(),
          SizedBox(height: 28),
          _UnsupportedSection(
            title: 'Notification preferences',
            explanation:
                'No backend support yet — there is a notification_events '
                'table, but it is a service-role-only audit/idempotency log, '
                'not a per-category preference store. device_tokens only '
                'holds push registration tokens. Adding real toggles needs a '
                'new preferences table first.',
          ),
          SizedBox(height: 28),
          _PinnedPeopleSection(),
          SizedBox(height: 20),
          _UnsupportedSection(
            title: 'Delete account',
            explanation:
                'Not built — this is irreversible and touches posts, '
                'comments, reactions, pings, groups, and communities.'
                'created_by with inconsistent ON DELETE rules across '
                'tables, plus the auth.users row itself (which the client '
                'JWT can\'t delete — needs a service-role Edge Function). '
                'Tell me to build it and I\'ll map the real cascade first.',
          ),
          SizedBox(height: 28),
          _AboutSection(),
          SizedBox(height: 28),
          _LogoutSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared section shell — every section below uses this for a consistent
// card look.
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: child,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit profile — real name + anon persona name, writing to users.name /
// users.anon_name. Validation duplicated from OnboardingScreen's own
// _validateName (onboarding_screen.dart) rather than shared — it's an
// 8-line pure function with two call sites in unrelated screens, not worth
// a cross-file abstraction for.
// ---------------------------------------------------------------------------

class _EditProfileSection extends StatefulWidget {
  const _EditProfileSection();

  @override
  State<_EditProfileSection> createState() => _EditProfileSectionState();
}

class _EditProfileSectionState extends State<_EditProfileSection> {
  final _nameController = TextEditingController();
  final _anonNameController = TextEditingController();
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
    _anonNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      final row = await supabase
          .from('users')
          .select('name, anon_name')
          .eq('id', id)
          .single();
      if (!mounted) return;
      _nameController.text = row['name'] as String? ?? '';
      _anonNameController.text = row['anon_name'] as String? ?? '';
    } catch (e, st) {
      debugPrint('[SettingsScreen._EditProfileSection._load] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't load your profile.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateName(String value, String label) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Add a $label to continue.';
    if (trimmed.length > 40) {
      return '$label is too long — keep it under 40 characters.';
    }
    return null;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final anonName = _anonNameController.text.trim();
    final firstError =
        _validateName(name, 'name') ?? _validateName(anonName, 'anonymous name');
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
        'anon_name': anonName,
      }).eq('id', id);
      if (mounted) setState(() => _success = 'Saved.');
    } catch (e, st) {
      debugPrint('[SettingsScreen._EditProfileSection._save] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't save — try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'PROFILE',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: const AnonPersonaPhotoPicker()),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'Anon persona photo — Anonymous feed only.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Real name', style: _labelStyle()),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
                  decoration: const InputDecoration(hintText: 'Your name'),
                ),
                const SizedBox(height: 16),
                Text('Anonymous name', style: _labelStyle()),
                const SizedBox(height: 6),
                TextField(
                  controller: _anonNameController,
                  style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
                  decoration: const InputDecoration(hintText: 'Shown only on the Anonymous feed'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.errorRed)),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 10),
                  Text(_success!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.accentTeal)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }

  TextStyle _labelStyle() => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      );
}

// ---------------------------------------------------------------------------
// Blocked users — direct against the real `blocks` table (blocker_id,
// blocked_id, created_at). Confirmed live via the actual Supabase schema
// dump earlier tonight; NOT documented in supabase/schema.sql (doc drift —
// same drift risk this session already found once elsewhere), so its RLS
// policy is unknown/unverified. Unblock issues a real delete and surfaces
// whatever error comes back rather than assuming it's allowed.
// ---------------------------------------------------------------------------

class _BlockedUsersSection extends StatefulWidget {
  const _BlockedUsersSection();

  @override
  State<_BlockedUsersSection> createState() => _BlockedUsersSectionState();
}

class _BlockedUsersSectionState extends State<_BlockedUsersSection> {
  List<Map<String, dynamic>>? _blocked;
  String? _error;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final blockRows = await supabase
          .from('blocks')
          .select('blocked_id, created_at')
          .eq('blocker_id', myId)
          .order('created_at', ascending: false) as List;

      final blockedIds = blockRows.map((r) => r['blocked_id'] as String).toList();
      final byId = <String, Map<String, dynamic>>{};
      if (blockedIds.isNotEmpty) {
        final users = await supabase
            .from('users')
            .select('id, name, profile_photo_url')
            .inFilter('id', blockedIds) as List;
        for (final u in users) {
          byId[u['id'] as String] = u as Map<String, dynamic>;
        }
      }

      final merged = blockRows.map((r) {
        final id = r['blocked_id'] as String;
        return {
          'blocked_id': id,
          'name': byId[id]?['name'] as String? ?? 'Unknown user',
          'profile_photo_url': byId[id]?['profile_photo_url'] as String?,
        };
      }).toList();

      if (mounted) setState(() => _blocked = merged);
    } catch (e, st) {
      debugPrint('[SettingsScreen._BlockedUsersSection._load] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't load blocked users.");
    }
  }

  Future<void> _unblock(String blockedId) async {
    setState(() => _unblocking.add(blockedId));
    try {
      final myId = await CurrentUserService.instance.resolveId();
      await supabase
          .from('blocks')
          .delete()
          .eq('blocker_id', myId)
          .eq('blocked_id', blockedId);
      if (mounted) {
        setState(() => _blocked?.removeWhere((b) => b['blocked_id'] == blockedId));
      }
    } catch (e, st) {
      debugPrint('[SettingsScreen._BlockedUsersSection._unblock] failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't unblock — try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(blockedId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'BLOCKED USERS',
      child: _error != null
          ? Text(_error!, style: GoogleFonts.inter(fontSize: 13, color: AppColors.errorRed))
          : _blocked == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                    ),
                  ),
                )
              : _blocked!.isEmpty
                  ? Text(
                      "You haven't blocked anyone.",
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                    )
                  : Column(
                      children: [
                        for (final b in _blocked!)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.background,
                                  backgroundImage: b['profile_photo_url'] != null
                                      ? NetworkImage(b['profile_photo_url'] as String)
                                      : null,
                                  child: b['profile_photo_url'] == null
                                      ? const Icon(Icons.person, size: 16, color: AppColors.textMuted)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    b['name'] as String,
                                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _unblocking.contains(b['blocked_id'])
                                      ? null
                                      : () => _unblock(b['blocked_id'] as String),
                                  child: _unblocking.contains(b['blocked_id'])
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Unblock'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned people — real list/unpin via PostAuthorPinService.listPinned()/
// unpin(), backed by the new list_pinned_people()/unpin_person() RPCs
// (schema.sql) — pinned_people has RLS with no client policies, so those
// RPCs are the only entry point, same reasoning as toggle_pin_post_author.
// ---------------------------------------------------------------------------

class _PinnedPeopleSection extends StatefulWidget {
  const _PinnedPeopleSection();

  @override
  State<_PinnedPeopleSection> createState() => _PinnedPeopleSectionState();
}

class _PinnedPeopleSectionState extends State<_PinnedPeopleSection> {
  List<Map<String, dynamic>>? _pinned;
  String? _error;
  final Set<String> _unpinning = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final pinned = await PostAuthorPinService.instance.listPinned();
      if (mounted) setState(() => _pinned = pinned);
    } catch (e, st) {
      debugPrint('[SettingsScreen._PinnedPeopleSection._load] failed: $e\n$st');
      if (mounted) setState(() => _error = "Couldn't load pinned people.");
    }
  }

  Future<void> _unpin(String pinnedUserId) async {
    setState(() => _unpinning.add(pinnedUserId));
    try {
      await PostAuthorPinService.instance.unpin(pinnedUserId);
      if (mounted) {
        setState(() => _pinned?.removeWhere((p) => p['pinned_user_id'] == pinnedUserId));
      }
    } catch (e, st) {
      debugPrint('[SettingsScreen._PinnedPeopleSection._unpin] failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't unpin — try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _unpinning.remove(pinnedUserId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'PINNED PEOPLE',
      child: _error != null
          ? Text(_error!, style: GoogleFonts.inter(fontSize: 13, color: AppColors.errorRed))
          : _pinned == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                    ),
                  ),
                )
              : _pinned!.isEmpty
                  ? Text(
                      "You haven't pinned anyone.",
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                    )
                  : Column(
                      children: [
                        for (final p in _pinned!)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.background,
                                  backgroundImage: p['profile_photo_url'] != null
                                      ? NetworkImage(p['profile_photo_url'] as String)
                                      : null,
                                  child: p['profile_photo_url'] == null
                                      ? const Icon(Icons.person, size: 16, color: AppColors.textMuted)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p['name'] as String? ?? 'Unknown user',
                                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _unpinning.contains(p['pinned_user_id'])
                                      ? null
                                      : () => _unpin(p['pinned_user_id'] as String),
                                  child: _unpinning.contains(p['pinned_user_id'])
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Unpin'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}

// ---------------------------------------------------------------------------
// About — real app version/build number via package_info_plus (already a
// pubspec dependency, previously unused anywhere in the app).
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'ABOUT',
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final info = snapshot.data;
          return Text(
            info == null
                ? 'Loading…'
                : '${AppStrings.appName} v${info.version} (build ${info.buildNumber})',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unsupported-feature notice — used for the three settings deliberately not
// built (see SettingsScreen's own header comment for why each one).
// ---------------------------------------------------------------------------

class _UnsupportedSection extends StatelessWidget {
  const _UnsupportedSection({required this.title, required this.explanation});

  final String title;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title.toUpperCase(),
      child: Text(
        explanation,
        style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logout — same confirm-then-signOutAndResetCaches() path as ProfileScreen's
// own header icon (SupabaseService.signOutAndResetCaches). AuthGate's
// onAuthStateChange listener handles the actual navigation back to
// AuthScreen once the session clears; nothing here navigates manually.
// ---------------------------------------------------------------------------

class _LogoutSection extends StatefulWidget {
  const _LogoutSection();

  @override
  State<_LogoutSection> createState() => _LogoutSectionState();
}

class _LogoutSectionState extends State<_LogoutSection> {
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF16151A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log out?',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Log out',
                style: GoogleFonts.inter(color: AppColors.errorRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.signOutAndResetCaches();
      // SettingsScreen is always reached via Navigator.push (from
      // ProfileScreen's gear icon) — without this, AuthGate's root swap to
      // AuthScreen happens invisibly underneath this still-pushed screen.
      // Same fix as ProfileScreen's own _confirmLogout.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, st) {
      debugPrint('[SettingsScreen._LogoutSection._confirmLogout] failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't log out — try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _confirmLogout,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.errorRed),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          'Log out',
          style: GoogleFonts.inter(
            color: AppColors.errorRed,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
