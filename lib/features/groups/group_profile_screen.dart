import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../services/current_user_service.dart';
import '../../services/group_service.dart';
import '../../services/image_prep_service.dart';
import 'group_member_picker_screen.dart';

// ---------------------------------------------------------------------------
// GroupProfileScreen — reuses the personal profile's layout language
// (banner + circular icon overlapping it, member row, posts grid, camera
// FAB) but scoped to a group's shared album instead of a personal one, and
// with no Private/anonymous tab — nothing in a group is anonymous.
//
// Structurally closest existing precedent is BucketViewScreen (shared
// container + drop-a-photo FAB + grid), not ProfileScreen itself — that
// file's tabs/header are one 3900-line StatefulWidget tightly coupled to
// personal-profile-only state (streak, bio editor, level-up banner), not
// something a second screen can parameterize by groupId. This mirrors its
// *visual* structure (banner+circle, grid, FAB-driven capture using
// ImagePicker + ImagePrepService, same loading/empty/error shape) rather
// than importing/reusing it directly.
// ---------------------------------------------------------------------------

class GroupProfileScreen extends StatefulWidget {
  const GroupProfileScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  late Future<_GroupData> _future;
  bool _uploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_GroupData> _load() async {
    final group = await GroupService.instance.fetchGroup(widget.groupId);
    if (group == null) {
      throw StateError('Group not found or no longer visible');
    }
    final results = await Future.wait([
      GroupService.instance.fetchMembers(widget.groupId),
      GroupService.instance.fetchPosts(widget.groupId),
      GroupService.instance.myRole(widget.groupId),
      CurrentUserService.instance.resolveId(),
    ]);
    return _GroupData(
      group: group,
      members: results[0] as List<Map<String, dynamic>>,
      posts: results[1] as List<Map<String, dynamic>>,
      myRole: results[2] as String?,
      myUserId: results[3] as String,
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _addPhoto() async {
    HapticFeedback.lightImpact();
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 90,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't open the camera.");
      return;
    }
    if (picked == null || !mounted) return;

    setState(() {
      _uploading = true;
      _uploadError = null;
    });

    try {
      final prepared = await ImagePrepService.instance.prepareForStudio(picked.path);
      final fileToUpload = prepared ?? File(picked.path);
      await GroupService.instance.addPost(groupId: widget.groupId, photoFile: fileToUpload);
      if (!mounted) return;
      setState(() => _uploading = false);
      _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = "Couldn't add that photo. Try again.";
      });
    }
  }

  Future<void> _deletePost(String postId) async {
    HapticFeedback.lightImpact();
    try {
      await GroupService.instance.deletePost(postId);
      _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't delete that post.");
    }
  }

  void _showPostOptions(Map<String, dynamic> post, bool canDelete) {
    if (!canDelete) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text('Delete post', style: GoogleFonts.inter(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _deletePost(post['id'] as String);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openGroupSettings(_GroupData data) async {
    HapticFeedback.lightImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _GroupSettingsSheet(isAdmin: data.myRole == 'admin'),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'rename':
        await _renameGroup(data);
      case 'icon':
        await _changeIcon();
      case 'members':
        await _openMemberManagement(data);
      case 'add_members':
        await _addMembers(data);
      case 'delete':
        await _confirmDeleteGroup();
      case 'leave':
        await _confirmLeaveGroup();
    }
  }

  Future<void> _renameGroup(_GroupData data) async {
    final ctrl = TextEditingController(text: data.group['name'] as String? ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Rename group', style: GoogleFonts.inter(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          style: GoogleFonts.inter(color: AppColors.textPrimary),
          decoration: const InputDecoration(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    try {
      await GroupService.instance.updateGroupInfo(widget.groupId, name: newName);
      _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't rename the group.");
    }
  }

  Future<void> _changeIcon() async {
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (xFile == null || !mounted) return;
    try {
      await GroupService.instance.updateGroupInfo(widget.groupId, iconFile: File(xFile.path));
      _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't update the group icon.");
    }
  }

  Future<void> _addMembers(_GroupData data) async {
    final existingIds = data.members.map((m) => m['user_id'] as String).toSet();
    final picked = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute<List<Map<String, dynamic>>>(
        fullscreenDialog: true,
        builder: (_) => GroupMemberPickerScreen(excludeIds: existingIds),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      for (final user in picked) {
        await GroupService.instance.addMember(widget.groupId, user['id'] as String);
      }
      _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't add those members.");
    }
  }

  Future<void> _openMemberManagement(_GroupData data) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MemberManagementSheet(
        groupId: widget.groupId,
        members: data.members,
        isAdmin: data.myRole == 'admin',
        myUserId: data.myUserId,
        onChanged: _reload,
      ),
    );
  }

  Future<void> _confirmDeleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Delete this group?', style: GoogleFonts.inter(color: AppColors.textPrimary)),
        content: Text(
          'This removes the group and its shared album for everyone. This can\'t be undone.',
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await GroupService.instance.deleteGroup(widget.groupId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't delete the group.");
    }
  }

  Future<void> _confirmLeaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: Text('Leave this group?', style: GoogleFonts.inter(color: AppColors.textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await GroupService.instance.leaveGroup(widget.groupId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't leave the group.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: FutureBuilder<_GroupData>(
          future: _future,
          builder: (context, snap) {
            final isLoading = snap.connectionState == ConnectionState.waiting;
            if (isLoading) {
              return const Center(child: CircularProgressIndicator(color: AppColors.coral, strokeWidth: 2));
            }
            if (snap.hasError) {
              return _MessageState(
                icon: Icons.error_outline_rounded,
                message: "Couldn't load this group.",
                actionLabel: 'Retry',
                onAction: _reload,
              );
            }

            final data = snap.data!;
            return RefreshIndicator(
              color: AppColors.coral,
              backgroundColor: AppColors.cardSurface,
              onRefresh: () async => _reload(),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _GroupHeader(data: data, onSettings: () => _openGroupSettings(data))),
                  if (_uploadError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(_uploadError!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.errorRed)),
                      ),
                    ),
                  if (data.posts.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _MessageState(
                        icon: Icons.photo_camera_back_outlined,
                        message: 'No photos yet.\nBe the first to drop one in.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: 0.85,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final post = data.posts[i];
                            final canDelete = data.myRole == 'admin' || post['user_id'] == data.myUserId;
                            final photoUrl = post['photo_url'] as String?;
                            return GestureDetector(
                              onLongPress: () => _showPostOptions(post, canDelete),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: photoUrl == null
                                    ? Container(color: AppColors.cardSurface)
                                    : CachedNetworkImage(
                                        imageUrl: photoUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => Container(color: AppColors.cardSurface),
                                        errorWidget: (_, _, _) => Container(
                                          color: AppColors.cardSurface,
                                          child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 18),
                                        ),
                                      ),
                              ),
                            );
                          },
                          childCount: data.posts.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomPad),
        child: FloatingActionButton(
          onPressed: _uploading ? null : _addPhoto,
          backgroundColor: AppColors.coral,
          child: _uploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.add_a_photo_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — back button, banner + icon overlapping bottom-left (same overlap
// convention as ProfileScreen's _ProfileHeader), name, member count,
// member avatar row, admin-only settings gear.
// ---------------------------------------------------------------------------

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.data, required this.onSettings});
  final _GroupData data;
  final VoidCallback onSettings;

  static const _banners = <LinearGradient>[
    LinearGradient(colors: [Color(0xFF1A1040), Color(0xFF3B1E50), Color(0xFF6B2D5E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFF0D2B45), Color(0xFF1A4060), Color(0xFF0D3050)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFF1A2820), Color(0xFF2A4030), Color(0xFF1E4028)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFF2A1A10), Color(0xFF4A2A18), Color(0xFF3A1E10)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  ];

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final group = data.group;
    final name = group['name'] as String? ?? 'Group';
    final iconUrl = group['icon_url'] as String?;
    final banner = _banners[(group['id'] as String).hashCode.abs() % _banners.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              height: 130,
              decoration: BoxDecoration(gradient: banner),
            ),
            Positioned(
              top: topPad + 8,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: Colors.white),
                ),
              ),
            ),
            if (data.myRole == 'admin' || data.myRole == 'member')
              Positioned(
                top: topPad + 8,
                right: 12,
                child: GestureDetector(
                  onTap: onSettings,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                    child: const Icon(Icons.more_horiz_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              bottom: -36,
              left: 16,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cardSurface,
                  border: Border.all(color: AppColors.background, width: 3),
                  image: iconUrl != null ? DecorationImage(image: CachedNetworkImageProvider(iconUrl), fit: BoxFit.cover) : null,
                ),
                child: iconUrl == null ? const Icon(Icons.group_rounded, size: 30, color: AppColors.textMuted) : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 46),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                '${data.members.length} ${data.members.length == 1 ? 'member' : 'members'}',
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: data.members.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final m = data.members[i];
                    final user = m['users'] as Map?;
                    final photoUrl = user?['profile_photo_url'] as String?;
                    final memberName = user?['name'] as String? ?? '?';
                    final isAdmin = m['role'] == 'admin';
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: isAdmin ? AppColors.coral : AppColors.border, width: isAdmin ? 1.5 : 1),
                          ),
                          child: ClipOval(
                            child: photoUrl == null
                                ? Container(
                                    color: AppColors.cardSurface,
                                    child: Center(
                                      child: Text(
                                        memberName.isNotEmpty ? memberName[0].toUpperCase() : '?',
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                      ),
                                    ),
                                  )
                                : CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 16)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings sheet — admin sees the full set; a plain member only sees Leave.
// ---------------------------------------------------------------------------

class _GroupSettingsSheet extends StatelessWidget {
  const _GroupSettingsSheet({required this.isAdmin});
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          if (isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
              title: Text('Rename group', style: GoogleFonts.inter(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: AppColors.textPrimary),
              title: Text('Change icon', style: GoogleFonts.inter(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'icon'),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.textPrimary),
              title: Text('Add members', style: GoogleFonts.inter(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'add_members'),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined, color: AppColors.textPrimary),
              title: Text('Manage members', style: GoogleFonts.inter(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'members'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text('Delete group', style: GoogleFonts.inter(color: Colors.redAccent)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.group_outlined, color: AppColors.textPrimary),
              title: Text('View members', style: GoogleFonts.inter(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'members'),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: Text('Leave group', style: GoogleFonts.inter(color: Colors.redAccent)),
              onTap: () => Navigator.pop(context, 'leave'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member management — admin can remove members; everyone can see roles.
// ---------------------------------------------------------------------------

class _MemberManagementSheet extends StatefulWidget {
  const _MemberManagementSheet({
    required this.groupId,
    required this.members,
    required this.isAdmin,
    required this.myUserId,
    required this.onChanged,
  });

  final String groupId;
  final List<Map<String, dynamic>> members;
  final bool isAdmin;
  final String myUserId;
  final VoidCallback onChanged;

  @override
  State<_MemberManagementSheet> createState() => _MemberManagementSheetState();
}

class _MemberManagementSheetState extends State<_MemberManagementSheet> {
  late List<Map<String, dynamic>> _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _members = List.of(widget.members);
  }

  Future<void> _remove(Map<String, dynamic> member) async {
    final userId = member['user_id'] as String;
    HapticFeedback.lightImpact();
    try {
      await GroupService.instance.removeMember(widget.groupId, userId);
      setState(() => _members.removeWhere((m) => m['user_id'] == userId));
      widget.onChanged();
    } catch (_) {
      setState(() => _error = "Couldn't remove that member.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Members', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.errorRed)),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _members.length,
                itemBuilder: (context, i) {
                  final m = _members[i];
                  final user = m['users'] as Map?;
                  final name = user?['name'] as String? ?? 'someone';
                  final isAdminRow = m['role'] == 'admin';
                  final isSelf = m['user_id'] == widget.myUserId;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.cardSurface,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isSelf ? '$name (you)' : name,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                        if (isAdminRow)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.coral.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Admin', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppColors.coral)),
                          )
                        else if (widget.isAdmin)
                          GestureDetector(
                            onTap: () => _remove(m),
                            child: const Icon(Icons.person_remove_outlined, size: 18, color: AppColors.errorRed),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _GroupData {
  const _GroupData({
    required this.group,
    required this.members,
    required this.posts,
    required this.myRole,
    required this.myUserId,
  });
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> posts;
  final String? myRole;
  final String myUserId;
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.icon, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textMuted, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    actionLabel!,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
