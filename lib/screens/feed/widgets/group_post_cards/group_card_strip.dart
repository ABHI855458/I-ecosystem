import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants.dart';
import '../../../../features/groups/design_preview/widgets/dashed_rrect_painter.dart';
import 'group_card_shared.dart';

// ---------------------------------------------------------------------------
// GroupCardStrip — horizontal scroll of varying-height, bottom-aligned
// tiles: up to 2 real photos (the feed item's own + the group's next most
// recent distinct post, if one exists) + up to 2 real member tiles + a
// dashed "+N" tile for any members beyond that. Matches
// design_handoff_group_post_cards/README.md §4, minus the location pill
// (no real data) and comment/reaction footer.
// ---------------------------------------------------------------------------

class GroupCardStrip extends StatelessWidget {
  const GroupCardStrip({super.key, required this.data});
  final GroupCardData data;

  @override
  Widget build(BuildContext context) {
    final photos = data.posts.take(2).toList();
    final members = data.members.take(2).toList();
    final extraMembers = data.members.length - members.length;

    const heights = [200.0, 250.0, 170.0, 220.0];

    final tiles = <Widget>[
      for (var i = 0; i < photos.length; i++)
        _PhotoTile(url: photos[i].photoUrl, height: heights[i % heights.length]),
      for (var i = 0; i < members.length; i++)
        _MemberTile(member: members[i], height: heights[(photos.length + i) % heights.length]),
      if (extraMembers > 0) _MoreTile(count: extraMembers, height: 150),
    ];

    return GroupCardShell(
      data: data,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: tiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Align(alignment: Alignment.bottomCenter, child: tiles[i]),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              const GroupCardIconButtons(vertical: false, size: 40, flat: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url, required this.height});
  final String url;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 132,
        height: height,
        child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.height});
  final GroupCardMember member;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: height,
      child: GroupCardMemberTile(member: member, radius: 16, initialFontSize: 24),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.count, required this.height});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: height,
      child: CustomPaint(
        painter: DashedRRectPainter(color: Colors.white.withValues(alpha: 0.16), radius: 16),
        child: Center(
          child: Text(
            '+$count',
            style: GoogleFonts.ibmPlexMono(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
