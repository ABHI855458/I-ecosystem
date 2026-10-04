import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../services/group_service.dart';
import 'group_member_picker_screen.dart';
import 'group_profile_cover_screen.dart';

// ---------------------------------------------------------------------------
// CreateGroupScreen — name + photo, then search/select people to add.
// Creator becomes the group's admin (GroupService.createGroup does the
// admin-role insert). On confirm: create the group, navigate to its new
// GroupProfileCoverScreen (1a) — same real landing screen group_circles_row
// pushes when opening an existing group.
// ---------------------------------------------------------------------------

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  File? _iconFile;
  final Map<String, Map<String, dynamic>> _members = {};
  bool _submitting = false;
  String? _error;

  /// Blurred Group Teaser feature. 'private' is the default — matching
  /// every group made before this existed, where the only way in was an
  /// existing member or admin adding you. 'public' is the new, explicit
  /// opt-in: any community member can join instantly and sees every post in
  /// full. A private group's posts still reach its community, first photo
  /// clear and the rest blurred (group_post_audience_feed.locked).
  String _visibility = 'private';

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (xFile == null || !mounted) return;
    setState(() => _iconFile = File(xFile.path));
  }

  Future<void> _openMemberPicker() async {
    HapticFeedback.lightImpact();
    final picked = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute<List<Map<String, dynamic>>>(
        fullscreenDialog: true,
        builder: (_) => GroupMemberPickerScreen(excludeIds: _members.keys.toSet()),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      for (final user in picked) {
        _members[user['id'] as String] = user;
      }
    });
  }

  void _removeMember(String userId) {
    HapticFeedback.selectionClick();
    setState(() => _members.remove(userId));
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give this group a name.');
      return;
    }
    // Explicit request: "set minimum criteria for making a group is 2
    // members." createGroup always adds the creator as an admin member, so
    // "2 members" means at least one OTHER person picked here — a group of
    // just yourself ("bakchodi crew · 1") had nobody to share it with.
    if (_members.isEmpty) {
      setState(() => _error = 'Add at least one other person to the group.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    HapticFeedback.lightImpact();

    try {
      final groupId = await GroupService.instance.createGroup(
        name: name,
        iconFile: _iconFile,
        memberUserIds: _members.keys.toList(),
        visibility: _visibility,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GroupProfileCoverScreen(groupId: groupId),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't create the group. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'New Group',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickIcon,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 86,
                              height: 86,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.cardSurface,
                                border: Border.all(color: AppColors.border),
                                image: _iconFile != null
                                    ? DecorationImage(image: FileImage(_iconFile!), fit: BoxFit.cover)
                                    : null,
                              ),
                              child: _iconFile == null
                                  ? const Icon(Icons.group_rounded, size: 32, color: AppColors.textMuted)
                                  : null,
                            ),
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.background, width: 1.5),
                                ),
                                child: const Icon(Icons.camera_alt, size: 13, color: AppColors.onPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'GROUP NAME',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      maxLength: 40,
                      style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'e.g. Fest Squad 🎉',
                        hintStyle: GoogleFonts.inter(color: AppColors.textMuted.withValues(alpha: 0.6)),
                        counterStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
                        filled: true,
                        fillColor: AppColors.cardSurface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.coral),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'MEMBERS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                            letterSpacing: 0.6,
                          ),
                        ),
                        GestureDetector(
                          onTap: _openMemberPicker,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_add_alt_1_rounded, size: 14, color: AppColors.coral),
                              const SizedBox(width: 4),
                              Text(
                                'Add people',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.coral),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_members.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: Text(
                            "Just you so far — you're the admin.",
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          for (final user in _members.values)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _MemberChipRow(
                                user: user,
                                onRemove: () => _removeMember(user['id'] as String),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 22),
                    Text(
                      // Joining is invite-only either way — this only
                      // decides who can SEE the group's posts.
                      'WHO SEES POSTS',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _VisibilityOption(
                            icon: Icons.public_rounded,
                            title: 'Public',
                            subtitle: 'Anyone who visits the group sees its posts. Joining is still invite-only',
                            selected: _visibility == 'public',
                            onTap: () => setState(() => _visibility = 'public'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _VisibilityOption(
                            icon: Icons.lock_outline_rounded,
                            title: 'Private',
                            subtitle: 'Only members see posts. Invite-only',
                            selected: _visibility == 'private',
                            onTap: () => setState(() => _visibility = 'private'),
                          ),
                        ),
                      ],
                    ),
                    if (_visibility == 'public')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          // Explicit spec requirement: post-time, the
                          // poster should know only the first photo is
                          // public before someone joins — surfacing the
                          // consequence here too, at the point where
                          // public/private is actually decided.
                          "Mark any single post Private when you post it and only members will see it.",
                          style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.errorRed),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 16),
              child: GestureDetector(
                onTap: _submitting ? null : _submit,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _submitting ? AppColors.coral.withValues(alpha: 0.5) : AppColors.coral,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Create Group',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.coral.withValues(alpha: 0.10) : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.coral : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: selected ? AppColors.coral : AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.coral : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textMuted, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberChipRow extends StatelessWidget {
  const _MemberChipRow({required this.user, required this.onRemove});
  final Map<String, dynamic> user;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] as String?)?.trim().isNotEmpty == true
        ? user['name'] as String
        : (user['anon_name'] as String? ?? 'someone');

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.background,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
