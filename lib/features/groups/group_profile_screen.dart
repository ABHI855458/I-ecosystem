import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../services/current_user_service.dart';
import '../../services/group_service.dart';
import '../../services/image_prep_service.dart';
import 'group_member_picker_screen.dart';

// ---------------------------------------------------------------------------
// GroupProfileScreen — "Streak" direction (1b) from the group-profile design
// handoff (design-refs/design_handoff_group_profile), adapted to render only
// what's backed by real data. The full 1b spec's streak-hero card, "N
// haven't dipped today" row, reactions, comments, and Ping button all
// require schema this app doesn't have for group_posts (no cadence/streak
// tracking, no group_posts reactions/comments tables, and pings.group_id
// actually references `communities`, not `groups`) — rather than fabricate
// numbers, this build omits those pieces entirely and keeps: identity
// (group avatar/name/member count), a real "who's posted today" strip
// (computed client-side from group_posts.created_at), a real posts-by-day
// calendar for the current month, and a state-dependent sticky CTA that
// reuses the same camera-capture flow (_addPhoto) the old FAB used.
//
// Still uses ImagePicker + ImagePrepService for capture and GroupService for
// all data, same as before — only the visual layer changed.
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

  /// Latest today-local-date post per member, keyed by user_id — drives the
  /// Today strip. `data.posts` is already newest-first (GroupService.
  /// fetchPosts orders by created_at desc), so the first match per user is
  /// their latest. Uses device-local "today", not a group daily-reset
  /// boundary — no such concept exists in this schema.
  Map<String, Map<String, dynamic>> _postedTodayMap(List<Map<String, dynamic>> posts) {
    final now = DateTime.now();
    final map = <String, Map<String, dynamic>>{};
    for (final p in posts) {
      final createdRaw = p['created_at'] as String?;
      final userId = p['user_id'] as String?;
      if (createdRaw == null || userId == null) continue;
      final created = DateTime.tryParse(createdRaw)?.toLocal();
      if (created == null) continue;
      if (created.year == now.year && created.month == now.month && created.day == now.day) {
        map.putIfAbsent(userId, () => p);
      }
    }
    return map;
  }

  /// Minimal full-screen photo viewer — group_profile_screen.dart had no
  /// existing tap-to-view-detail affordance (the old grid only wired
  /// long-press for delete), so tapping a Today-strip tile or a calendar
  /// cell opens this in-file overlay rather than a new dedicated screen.
  /// Also carries the delete action the old grid's long-press used to
  /// expose (own post, or any post if admin) so that capability isn't lost.
  void _openPostViewer(List<Map<String, dynamic>> posts, _GroupData data) {
    if (posts.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PostViewerOverlay(
          posts: posts,
          canDelete: (post) => data.myRole == 'admin' || post['user_id'] == data.myUserId,
          onDelete: _deletePost,
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<_GroupData>(
        future: _future,
        builder: (context, snap) {
          final isLoading = snap.connectionState == ConnectionState.waiting;
          if (isLoading) {
            return const _GroupProfileSkeleton();
          }
          if (snap.hasError) {
            return SafeArea(
              child: Column(
                children: [
                  _NavRow(onBack: () => Navigator.of(context).pop(), onOverflow: null),
                  Expanded(
                    child: _MessageState(
                      icon: Icons.error_outline_rounded,
                      message: "Couldn't load this group.",
                      actionLabel: 'Retry',
                      onAction: _reload,
                    ),
                  ),
                ],
              ),
            );
          }

          final data = snap.data!;

          if (data.posts.isEmpty) {
            return SafeArea(
              child: Column(
                children: [
                  _NavRow(onBack: () => Navigator.of(context).pop(), onOverflow: () => _openGroupSettings(data)),
                  Expanded(
                    child: _EmptyGroupState(
                      group: data.group,
                      uploading: _uploading,
                      onPost: _uploading ? null : _addPhoto,
                    ),
                  ),
                ],
              ),
            );
          }

          final postedToday = _postedTodayMap(data.posts);
          final hasPostedToday = postedToday.containsKey(data.myUserId);

          return Stack(
            children: [
              RefreshIndicator(
                color: Colors.white,
                backgroundColor: const Color(0xFF111118),
                onRefresh: () async => _reload(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 96),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _NavRow(onBack: () => Navigator.of(context).pop(), onOverflow: () => _openGroupSettings(data)),
                          _IdentityBlock(group: data.group, memberCount: data.members.length),
                          const SizedBox(height: 24),
                          _TodayStrip(
                            members: data.members,
                            postedToday: postedToday,
                            onTapPost: (post) => _openPostViewer([post], data),
                          ),
                          const SizedBox(height: 26),
                          _CalendarSection(
                            posts: data.posts,
                            onTapDay: (dayPosts) => _openPostViewer(dayPosts, data),
                          ),
                          if (_uploadError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Text(
                                _uploadError!,
                                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.errorRed),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _StickyCta(
                hasPostedToday: hasPostedToday,
                uploading: _uploading,
                onPost: _uploading ? null : _addPhoto,
                onViewToday: () => _openPostViewer(postedToday.values.toList(), data),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nav row — back chevron + overflow dots, bare on black (per the design
// spec's 1b/1c note: only 1a's cover-photo overlay needs a frosted circle
// backing; 1b sits directly on the plain black page).
// ---------------------------------------------------------------------------

class _NavRow extends StatelessWidget {
  const _NavRow({required this.onBack, required this.onOverflow});
  final VoidCallback onBack;
  final VoidCallback? onOverflow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white.withValues(alpha: 0.7)),
          ),
          GestureDetector(
            onTap: onOverflow,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.more_horiz_rounded, size: 22, color: Colors.white.withValues(alpha: onOverflow == null ? 0 : 0.6)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Identity — centered squircle avatar (real icon_url if set, else a
// deterministic gradient + initial, same hashCode-based selection mechanism
// the old banner picker used), name, member count. No privacy column exists
// on `groups`, but RLS (groups_select) enforces every group is member-only
// with no public feed, so "private" is a true structural fact, not a
// fabricated one.
// ---------------------------------------------------------------------------

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.group, required this.memberCount});
  final Map<String, dynamic> group;
  final int memberCount;

  static const _gradients = <List<Color>>[
    [Color(0xFF667EEA), Color(0xFF764BA2)],
    [Color(0xFFF093FB), Color(0xFFF5576C)],
    [Color(0xFF4FACFE), Color(0xFF00F2FE)],
    [Color(0xFFF7971E), Color(0xFFFFD200)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
    [Color(0xFFFF9A56), Color(0xFFFF6F61)],
    [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
    [Color(0xFFC471F5), Color(0xFFFA71CD)],
  ];

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? 'Group';
    final iconUrl = group['icon_url'] as String?;
    final id = group['id'] as String? ?? name;
    final colors = _gradients[id.hashCode.abs() % _gradients.length];

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: iconUrl == null
                  ? LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              image: iconUrl != null
                  ? DecorationImage(image: CachedNetworkImageProvider(iconUrl), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: iconUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.spaceGrotesk(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
          ),
          const SizedBox(height: 5),
          Text(
            '$memberCount ${memberCount == 1 ? 'member' : 'members'} · private',
            style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today strip — one tile per member. Posted-today shows their latest
// today-local post; not-posted is a dashed placeholder, and only the FIRST
// not-posted slot gets the plus icon (a deliberate "read as the one CTA"
// detail from the spec — every other empty slot stays bare).
// ---------------------------------------------------------------------------

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.members, required this.postedToday, required this.onTapPost});
  final List<Map<String, dynamic>> members;
  final Map<String, Map<String, dynamic>> postedToday;
  final ValueChanged<Map<String, dynamic>> onTapPost;

  @override
  Widget build(BuildContext context) {
    var firstEmptyShown = false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TODAY',
            style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: Colors.white.withValues(alpha: 0.35)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final m = members[i];
                final userId = m['user_id'] as String?;
                final user = m['users'] as Map?;
                final name = user?['name'] as String? ?? '?';
                final post = userId == null ? null : postedToday[userId];
                final posted = post != null;

                Widget tile;
                if (posted) {
                  final photoUrl = post['photo_url'] as String?;
                  tile = GestureDetector(
                    onTap: () => onTapPost(post),
                    child: Container(
                      width: 68,
                      height: 86,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
                      ),
                      child: photoUrl == null ? null : CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover),
                    ),
                  );
                } else {
                  final showPlus = !firstEmptyShown;
                  firstEmptyShown = true;
                  tile = CustomPaint(
                    painter: _DashedRRectPainter(
                      color: Colors.white.withValues(alpha: 0.16),
                      radius: 14,
                      dashWidth: 4,
                      dashGap: 4,
                    ),
                    child: SizedBox(
                      width: 68,
                      height: 86,
                      child: showPlus
                          ? Center(child: Icon(Icons.add_rounded, size: 18, color: Colors.white.withValues(alpha: 0.3)))
                          : null,
                    ),
                  );
                }

                return SizedBox(
                  width: 68,
                  child: Column(
                    children: [
                      tile,
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.white.withValues(alpha: posted ? 0.6 : 0.3)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar — current month, one cell per day, filled with that day's first
// group post (any member) as a thumbnail. "N posts all-time" is the real
// count of `posts` (GroupService.fetchPosts has no limit, so this list
// already IS the group's complete post history, not a page of it).
// ---------------------------------------------------------------------------

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.posts, required this.onTapDay});
  final List<Map<String, dynamic>> posts;
  final ValueChanged<List<Map<String, dynamic>>> onTapDay;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final postsByDay = <int, List<Map<String, dynamic>>>{};
    for (final p in posts) {
      final createdRaw = p['created_at'] as String?;
      if (createdRaw == null) continue;
      final created = DateTime.tryParse(createdRaw)?.toLocal();
      if (created == null) continue;
      if (created.year == now.year && created.month == now.month) {
        postsByDay.putIfAbsent(created.day, () => []).add(p);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                DateFormat('MMMM').format(now).toUpperCase(),
                style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: Colors.white.withValues(alpha: 0.35)),
              ),
              Text(
                '${posts.length} posts all-time',
                style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.35)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: 1,
            ),
            itemCount: daysInMonth,
            itemBuilder: (context, i) {
              final day = i + 1;
              final dayPosts = postsByDay[day];
              final isToday = day == now.day;
              final isFuture = day > now.day;
              final photoUrl = (dayPosts != null && dayPosts.isNotEmpty) ? dayPosts.first['photo_url'] as String? : null;

              return GestureDetector(
                onTap: dayPosts == null ? null : () => onTapDay(dayPosts),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: photoUrl != null ? null : Colors.white.withValues(alpha: isFuture || isToday ? 0.03 : 0.05),
                    border: isToday ? Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5) : null,
                  ),
                  child: photoUrl == null ? null : CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky CTA — state-dependent per spec, minus the streak language (no
// streak surfaced anywhere in this build): "Post a dip" when the current
// user hasn't posted today, secondary "View today's posts" treatment when
// they have.
// ---------------------------------------------------------------------------

class _StickyCta extends StatelessWidget {
  const _StickyCta({
    required this.hasPostedToday,
    required this.uploading,
    required this.onPost,
    required this.onViewToday,
  });

  final bool hasPostedToday;
  final bool uploading;
  final VoidCallback? onPost;
  final VoidCallback onViewToday;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomPad),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xF2000000)],
            stops: [0, 0.4],
          ),
        ),
        child: GestureDetector(
          onTap: hasPostedToday ? onViewToday : onPost,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: hasPostedToday ? Colors.white.withValues(alpha: 0.09) : Colors.white,
            ),
            alignment: Alignment.center,
            child: uploading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: hasPostedToday ? Colors.white : Colors.black),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasPostedToday ? Icons.visibility_outlined : Icons.camera_alt_outlined,
                        size: 18,
                        color: hasPostedToday ? Colors.white : Colors.black,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasPostedToday ? "View today's posts" : 'Post a dip',
                        style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600, color: hasPostedToday ? Colors.white : Colors.black),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — 0 group_posts. Hides Today strip + calendar entirely (per
// spec) rather than rendering them with all-empty data.
// ---------------------------------------------------------------------------

class _EmptyGroupState extends StatelessWidget {
  const _EmptyGroupState({required this.group, required this.onPost, required this.uploading});
  final Map<String, dynamic> group;
  final VoidCallback? onPost;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? 'Group';
    final iconUrl = group['icon_url'] as String?;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: Colors.white.withValues(alpha: 0.07),
                image: iconUrl != null ? DecorationImage(image: CachedNetworkImageProvider(iconUrl), fit: BoxFit.cover) : null,
              ),
              alignment: Alignment.center,
              child: iconUrl == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(name, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 10),
            Text(
              'No dips yet. Someone has to go first.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.5), height: 1.5),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onPost,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white),
                child: uploading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text('Post a dip', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton — rgba(255,255,255,.05) blocks, no spinner, per spec.
// ---------------------------------------------------------------------------

class _GroupProfileSkeleton extends StatelessWidget {
  const _GroupProfileSkeleton();

  static Widget _block({double? width, required double height, double radius = 8}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(radius)),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white.withValues(alpha: 0.2)),
                Icon(Icons.more_horiz_rounded, size: 22, color: Colors.white.withValues(alpha: 0.2)),
              ],
            ),
            const SizedBox(height: 24),
            Center(child: _block(width: 76, height: 76, radius: 26)),
            const SizedBox(height: 14),
            Center(child: _block(width: 160, height: 22)),
            const SizedBox(height: 8),
            Center(child: _block(width: 100, height: 12)),
            const SizedBox(height: 28),
            _block(width: 60, height: 11),
            const SizedBox(height: 12),
            SizedBox(
              height: 86,
              child: Row(
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _block(width: 68, height: 86, radius: 14),
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

// ---------------------------------------------------------------------------
// Dashed rounded-rect border painter, scoped to this file — mirrors
// home_screen.dart's private _DashedBorderPainter (can't import a private
// class across files; small per-file painters are this codebase's existing
// convention, see emoji_selection_row.dart's _DashedCirclePainter).
// ---------------------------------------------------------------------------

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashGap,
  });

  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius || old.dashWidth != dashWidth || old.dashGap != dashGap;
}

// ---------------------------------------------------------------------------
// Full-screen post viewer — minimal, in-file. No tap-to-view-detail
// affordance existed anywhere in the old grid (only long-press-to-delete
// did), so this is new, but deliberately small rather than a new "detail
// screen": a plain PageView over the tapped post(s) with a close button and,
// where [canDelete] allows it, the delete action the old grid's long-press
// used to expose.
// ---------------------------------------------------------------------------

class _PostViewerOverlay extends StatefulWidget {
  const _PostViewerOverlay({required this.posts, required this.canDelete, required this.onDelete});

  final List<Map<String, dynamic>> posts;
  final bool Function(Map<String, dynamic> post) canDelete;
  final Future<void> Function(String postId) onDelete;

  @override
  State<_PostViewerOverlay> createState() => _PostViewerOverlayState();
}

class _PostViewerOverlayState extends State<_PostViewerOverlay> {
  bool _deleting = false;

  Future<void> _handleDelete(String postId) async {
    setState(() => _deleting = true);
    await widget.onDelete(postId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              itemCount: widget.posts.length,
              itemBuilder: (context, i) {
                final post = widget.posts[i];
                final photoUrl = post['photo_url'] as String?;
                final caption = post['caption'] as String?;
                final user = post['users'] as Map?;
                final name = user?['name'] as String? ?? '';
                return Column(
                  children: [
                    Expanded(
                      child: photoUrl == null
                          ? const SizedBox.shrink()
                          : InteractiveViewer(
                              child: CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.contain, width: double.infinity),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (name.isNotEmpty || (caption != null && caption.isNotEmpty))
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (name.isNotEmpty)
                                    Text(name, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                  if (caption != null && caption.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(caption, style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 13)),
                                    ),
                                ],
                              ),
                            ),
                          if (widget.canDelete(post))
                            GestureDetector(
                              onTap: _deleting ? null : () => _handleDelete(post['id'] as String),
                              child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withValues(alpha: _deleting ? 0.4 : 1), size: 20),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(
              top: 8,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
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
