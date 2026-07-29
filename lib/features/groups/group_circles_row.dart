import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../services/group_service.dart';
import 'create_group_screen.dart';
import 'group_profile_screen.dart';

// ---------------------------------------------------------------------------
// GroupCirclesRow — horizontal row of small circular group avatars below
// the profile picture (Story-bubble style), plus a "+" circle that launches
// CreateGroupScreen. Tapping a group circle opens its GroupProfileScreen.
// Own-profile only (mirrors _ProfileHeaderSection's placement).
// ---------------------------------------------------------------------------

class GroupCirclesRow extends StatefulWidget {
  const GroupCirclesRow({super.key});

  @override
  State<GroupCirclesRow> createState() => _GroupCirclesRowState();
}

class _GroupCirclesRowState extends State<GroupCirclesRow> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = GroupService.instance.fetchMyGroups();
  }

  // Block body, not `=> setState(() => _future = ...)`: an arrow closure
  // whose body is an assignment evaluates to the assigned value, so that
  // form makes the closure return the Future itself — which Flutter's
  // setState explicitly rejects at runtime ("setState() callback argument
  // returned a Future"). This fired every time the group flow returned from
  // CreateGroupScreen/GroupProfileScreen. A block body discards the
  // expression's value, so the closure is properly void.
  void _reload() => setState(() {
        _future = GroupService.instance.fetchMyGroups();
      });

  Future<void> _openCreateGroup() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const CreateGroupScreen()),
    );
    // Whether a group was created or the flow was cancelled, a reload is
    // cheap and keeps the row correct either way — no need to plumb a
    // return value through pushReplacement inside CreateGroupScreen.
    if (mounted) _reload();
  }

  void _openGroup(String groupId) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => GroupProfileScreen(groupId: groupId)),
    ).then((_) {
      if (mounted) _reload(); // picks up a rename/delete/leave that happened inside
    });
  }

  @override
  Widget build(BuildContext context) {
    // The "+" entry point must always be reachable — it's the only way into
    // group creation. It used to live inside the same FutureBuilder as the
    // groups list, so any fetchMyGroups() failure (e.g. no signed-in user —
    // see CurrentUserService's stopgap note) returned an early error+retry
    // widget that dropped "+" along with the list, making group creation
    // unreachable. Now "+" is unconditional and only the list portion after
    // it varies with fetch state.
    return SizedBox(
      height: 74,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _AddGroupCircle(onTap: _openCreateGroup),
          const SizedBox(width: 14),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              final isLoading = snap.connectionState == ConnectionState.waiting;

              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Couldn't load your groups.",
                        style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _reload,
                        child: Text(
                          'Retry',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.coral),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final groups = snap.data ?? [];

              if (isLoading) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      const _CircleShimmer(),
                      const SizedBox(width: 14),
                    ],
                  ],
                );
              }

              if (groups.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'No groups yet — start one.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                  ),
                );
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < groups.length; i++) ...[
                    _GroupCircle(group: groups[i], onTap: () => _openGroup(groups[i]['id'] as String)),
                    if (i != groups.length - 1) const SizedBox(width: 14),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AddGroupCircle extends StatelessWidget {
  const _AddGroupCircle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cardSurface,
                border: Border.all(color: AppColors.border, style: BorderStyle.solid),
              ),
              child: const Icon(Icons.add_rounded, color: AppColors.coral, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              'New',
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCircle extends StatelessWidget {
  const _GroupCircle({required this.group, required this.onTap});
  final Map<String, dynamic> group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? 'Group';
    final iconUrl = group['icon_url'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
              child: ClipOval(
                child: iconUrl == null
                    ? Container(
                        color: AppColors.cardSurface,
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: iconUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: AppColors.cardSurface),
                        errorWidget: (_, _, _) => Container(
                          color: AppColors.cardSurface,
                          child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 16),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleShimmer extends StatelessWidget {
  const _CircleShimmer();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.cardSurface),
          ),
        ],
      ),
    );
  }
}
