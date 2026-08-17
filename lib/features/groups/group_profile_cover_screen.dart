import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../services/current_user_service.dart';
import '../../services/group_service.dart';
import '../../services/image_prep_service.dart';
import '../../shared/time_ago.dart';
import 'design_preview/widgets/avatar.dart';
import 'design_preview/widgets/frosted_icon_button.dart';
import 'group_member_picker_screen.dart';
import 'group_profile_screen.dart';
import 'group_roster_screen.dart';

// ---------------------------------------------------------------------------
// GroupProfileCoverScreen — "Cover" direction (1a) from the group-profile
// design handoff, this time wired to real data and made the production
// landing screen for "tap into a group" (see group_circles_row.dart and
// create_group_screen.dart). Two real drill-downs live inside it:
//   - the stats bar opens the existing GroupProfileScreen (1b — untouched,
//     still owns the Today-strip/calendar/camera-CTA flow and the full
//     settings sheet, so this screen's own settings affordances route there
//     too rather than duplicating that sheet)
//   - the Members tab opens GroupRosterScreen (1c, new, real data)
//
// Two things the 1a spec calls for have no backing column and are dropped
// rather than faked, same discipline as GroupProfileScreen's own header
// comment: no bio field exists on `groups`, so the bio line is omitted; the
// "on time %" stat has no cadence/deadline concept in the schema, so the
// stats bar is 2 cells (dips, streak) not 3. The grid's "mini selfie chip"
// badge is also dropped — group_posts has no front-camera field to back it.
// ---------------------------------------------------------------------------

class GroupProfileCoverScreen extends StatefulWidget {
  const GroupProfileCoverScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupProfileCoverScreen> createState() => _GroupProfileCoverScreenState();
}

enum _Tab { dips, recaps }

class _GroupProfileCoverScreenState extends State<GroupProfileCoverScreen> {
  late Future<_CoverData> _future;
  _Tab _tab = _Tab.dips;
  bool _uploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CoverData> _load() async {
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
    return _CoverData(
      group: group,
      members: results[0] as List<Map<String, dynamic>>,
      posts: results[1] as List<Map<String, dynamic>>,
      myRole: results[2] as String?,
      myUserId: results[3] as String,
    );
  }

  // NOT `setState(() => _future = _load())` — an assignment expression
  // evaluates to the assigned value, so that arrow body returns the
  // Future _load() produces, and setState() throws at runtime ("setState()
  // callback argument returned a Future") the instant this fires — it did,
  // every time _reload() ran (after adding a photo, adding members, or
  // returning from the roster/streak-detail screens). A block body's bare
  // statement returns nothing, which is what setState actually needs.
  void _reload() => setState(() {
        _future = _load();
      });

  /// Same camera-capture flow GroupProfileScreen's sticky CTA uses.
  Future<void> _addPhoto() async {
    HapticFeedback.lightImpact();
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 90);
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

  Future<void> _addMembers(_CoverData data) async {
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

  /// The stats bar's real drill-down: GroupProfileScreen (1b) already owns
  /// the Today-strip/calendar/full settings sheet — pushed here rather than
  /// rebuilt, per the confirmed navigation decision.
  void _openStreakDetail() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GroupProfileScreen(groupId: widget.groupId)),
    ).then((_) {
      if (mounted) _reload();
    });
  }

  void _openRoster() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GroupRosterScreen(groupId: widget.groupId)),
    ).then((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _deletePost(String postId, _CoverData data) async {
    try {
      await GroupService.instance.deletePost(postId);
      _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadError = "Couldn't delete that post.");
    }
  }

  void _openDipDetail(Map<String, dynamic> post, _CoverData data) {
    final canDelete = data.myRole == 'admin' || post['user_id'] == data.myUserId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _DipDetailScreen(
          post: post,
          canDelete: canDelete,
          onDelete: () => _deletePost(post['id'] as String, data),
        ),
      ),
    );
  }

  /// Consecutive local-calendar days, counting backward from today, with at
  /// least one group post — a one-day grace (streak survives if yesterday
  /// has a post even when today doesn't yet) before it reads as broken.
  static int _computeStreak(List<Map<String, dynamic>> posts) {
    final days = <DateTime>{};
    for (final p in posts) {
      final raw = p['created_at'] as String?;
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt == null) continue;
      days.add(DateTime(dt.year, dt.month, dt.day));
    }
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<_CoverData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _CoverSkeleton();
          }
          if (snap.hasError) {
            return _ErrorBody(onRetry: _reload, onBack: () => Navigator.of(context).pop());
          }

          final data = snap.data!;

          if (data.posts.isEmpty) {
            return _EmptyCoverState(
              group: data.group,
              onBack: () => Navigator.of(context).pop(),
              onOverflow: _openStreakDetail,
              uploading: _uploading,
              onPost: _uploading ? null : _addPhoto,
            );
          }

          final width = MediaQuery.of(context).size.width;
          final columns = width >= 600 ? 4 : 3;
          final streak = _computeStreak(data.posts);

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CoverCollage(
                  posts: data.posts,
                  onBack: () => Navigator.of(context).pop(),
                  onOverflow: _openStreakDetail,
                ),
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.group['name'] as String? ?? 'Group',
                          style: GoogleFonts.spaceGrotesk(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Colors.white),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Started ${_startedLabel(data.group['created_at'] as String?)} · Private group',
                          style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.45)),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _openRoster,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              AvatarStack(
                                ids: data.members.take(4).map((m) => m['user_id'] as String? ?? '').toList(),
                                labels: data.members.take(4).map((m) => (m['users'] as Map?)?['name'] as String? ?? '?').toList(),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${data.members.length} ${data.members.length == 1 ? 'member' : 'members'}',
                                style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: _openStreakDetail,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                _StatCell(value: '${data.posts.length}', label: 'dips', showDivider: true),
                                _StatCell(value: '$streak', label: 'day streak', showDivider: false),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _uploading ? null : _addPhoto,
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                  child: _uploading
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                      : Text('Post a dip', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _SquareIconButton(icon: Icons.person_add_alt_1_rounded, onTap: () => _addMembers(data)),
                            const SizedBox(width: 10),
                            _SquareIconButton(icon: Icons.settings_outlined, onTap: _openStreakDetail),
                          ],
                        ),
                        if (_uploadError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_uploadError!, style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFFFF6F61))),
                          ),
                        const SizedBox(height: 22),
                        _Tabs(
                          active: _tab,
                          onChangeDips: () => setState(() => _tab = _Tab.dips),
                          onTapMembers: _openRoster,
                          onChangeRecaps: () => setState(() => _tab = _Tab.recaps),
                        ),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: _tab == _Tab.dips
                      ? _DipGrid(posts: data.posts, columns: columns, onTap: (p) => _openDipDetail(p, data))
                      : const _PlaceholderTabBody(text: 'Recaps are coming soon.'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _startedLabel(String? createdAtRaw) {
    final dt = createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw)?.toLocal();
    if (dt == null) return '—';
    return DateFormat('MMM yyyy').format(dt);
  }
}

class _CoverData {
  const _CoverData({required this.group, required this.members, required this.posts, required this.myRole, required this.myUserId});
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> posts;
  final String? myRole;
  final String myUserId;
}

// ---------------------------------------------------------------------------
// Cover collage — real photos from the group's most recent posts fill the
// 3 cells (newest = the large left cell); falls back to the original
// gradient placeholders for any cell beyond how many real posts exist.
// ---------------------------------------------------------------------------

class _CoverCollage extends StatelessWidget {
  const _CoverCollage({required this.posts, required this.onBack, required this.onOverflow});
  final List<Map<String, dynamic>> posts;
  final VoidCallback onBack;
  final VoidCallback onOverflow;

  static const _fallbackGradients = <List<Color>>[
    [Color(0xFF1A1A2E), Color(0xFF0F3460)],
    [Color(0xFF2D1B69), Color(0xFF4A2C8A)],
    [Color(0xFF0D3B2E), Color(0xFF1A6B4A)],
  ];

  Widget _cell(int index, {required BorderRadius radius}) {
    final photoUrl = index < posts.length ? posts[index]['photo_url'] as String? : null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: photoUrl == null
            ? LinearGradient(colors: _fallbackGradients[index % _fallbackGradients.length], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
      ),
      child: photoUrl == null ? null : CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 2), child: _cell(0, radius: BorderRadius.zero))),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 1), child: _cell(1, radius: BorderRadius.zero))),
                    Expanded(child: Padding(padding: const EdgeInsets.only(top: 1), child: _cell(2, radius: BorderRadius.zero))),
                  ],
                ),
              ),
            ],
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x8C000000), Colors.transparent, Color(0xD9000000)],
                stops: [0, 0.35, 1],
              ),
            ),
          ),
          Positioned(
            top: 52,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FrostedIconButton(onTap: onBack, child: const Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: Colors.white)),
                FrostedIconButton(
                  onTap: onOverflow,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      3,
                      (_) => Container(width: 3.5, height: 3.5, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, required this.showDivider});
  final String value;
  final String label;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: showDivider ? BoxDecoration(border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.07)))) : null,
        child: Column(
          children: [
            Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 2),
            Text(label, style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.4))),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.active, required this.onChangeDips, required this.onTapMembers, required this.onChangeRecaps});
  final _Tab active;
  final VoidCallback onChangeDips;
  final VoidCallback onTapMembers;
  final VoidCallback onChangeRecaps;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
      child: Row(
        children: [
          _TabItem(label: 'Dips', selected: active == _Tab.dips, onTap: onChangeDips),
          const SizedBox(width: 22),
          // Members isn't an in-place tab body — it's the real drill-down
          // into GroupRosterScreen, so it never reads as "selected" here.
          _TabItem(label: 'Members', selected: false, onTap: onTapMembers),
          const SizedBox(width: 22),
          _TabItem(label: 'Recaps', selected: active == _Tab.recaps, onTap: onChangeRecaps),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? Colors.white : Colors.transparent, width: 2))),
        child: Text(
          label,
          style: GoogleFonts.dmSans(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Colors.white : Colors.white.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

class _DipGrid extends StatelessWidget {
  const _DipGrid({required this.posts, required this.columns, required this.onTap});
  final List<Map<String, dynamic>> posts;
  final int columns;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: posts.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 4 / 5),
        itemBuilder: (context, i) {
          final post = posts[i];
          final photoUrl = post['photo_url'] as String?;
          return GestureDetector(
            onTap: () => onTap(post),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.white.withValues(alpha: 0.05)),
              child: photoUrl == null ? null : CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }
}

class _PlaceholderTabBody extends StatelessWidget {
  const _PlaceholderTabBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Center(child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.dmSans(fontSize: 13, color: Colors.white.withValues(alpha: 0.35)))),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — 0 group_posts, mirrors GroupProfileScreen's own.
// ---------------------------------------------------------------------------

class _EmptyCoverState extends StatelessWidget {
  const _EmptyCoverState({required this.group, required this.onBack, required this.onOverflow, required this.onPost, required this.uploading});
  final Map<String, dynamic> group;
  final VoidCallback onBack;
  final VoidCallback onOverflow;
  final VoidCallback? onPost;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? 'Group';
    final iconUrl = group['icon_url'] as String?;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(onTap: onBack, child: Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white.withValues(alpha: 0.7))),
                GestureDetector(onTap: onOverflow, child: Icon(Icons.more_horiz_rounded, size: 22, color: Colors.white.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Expanded(
            child: Center(
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
                      child: iconUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)) : null,
                    ),
                    const SizedBox(height: 16),
                    Text(name, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 10),
                    Text('No dips yet. Someone has to go first.', textAlign: TextAlign.center, style: GoogleFonts.dmSans(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.5), height: 1.5)),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverSkeleton extends StatelessWidget {
  const _CoverSkeleton();

  Widget _block({double? width, required double height, double radius = 8}) => Container(
        width: width,
        height: height,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(radius)),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block(height: 180, radius: 16),
            _block(width: 200, height: 24),
            _block(width: 140, height: 14),
            _block(height: 80, radius: 16),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry, required this.onBack});
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(alignment: Alignment.centerLeft, child: GestureDetector(onTap: onBack, child: Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: Colors.white.withValues(alpha: 0.7)))),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.white.withValues(alpha: 0.4), size: 32),
                  const SizedBox(height: 12),
                  Text("Couldn't load this group.", style: GoogleFonts.dmSans(color: Colors.white.withValues(alpha: 0.5))),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
                      child: Text('Retry', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal single-post detail — real photo, real author (via formatRelativeTime),
// real caption, delete if authorized. Deliberately not a full PageView across
// every post (that's GroupProfileScreen's _PostViewerOverlay, private to that
// file) — this is a single-item view for a single grid tap.
// ---------------------------------------------------------------------------

class _DipDetailScreen extends StatefulWidget {
  const _DipDetailScreen({required this.post, required this.canDelete, required this.onDelete});
  final Map<String, dynamic> post;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  State<_DipDetailScreen> createState() => _DipDetailScreenState();
}

class _DipDetailScreenState extends State<_DipDetailScreen> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.post['photo_url'] as String?;
    final caption = widget.post['caption'] as String?;
    final user = widget.post['users'] as Map?;
    final name = user?['name'] as String? ?? '';
    final createdAt = DateTime.tryParse(widget.post['created_at'] as String? ?? '')?.toLocal();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: photoUrl == null ? const SizedBox.shrink() : InteractiveViewer(child: CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.contain, width: double.infinity)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (name.isNotEmpty)
                              Text('$name · ${formatRelativeTime(createdAt, withAgo: true)}', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            if (caption != null && caption.isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 4), child: Text(caption, style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 13))),
                          ],
                        ),
                      ),
                      if (widget.canDelete)
                        GestureDetector(
                          onTap: _deleting
                              ? null
                              : () async {
                                  setState(() => _deleting = true);
                                  widget.onDelete();
                                  if (mounted) Navigator.of(context).pop();
                                },
                          child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withValues(alpha: _deleting ? 0.4 : 1), size: 20),
                        ),
                    ],
                  ),
                ),
              ],
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
