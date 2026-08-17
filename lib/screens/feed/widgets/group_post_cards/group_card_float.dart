import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'group_card_shared.dart';

// ---------------------------------------------------------------------------
// GroupCardFloat — collage banner with up to 3 floating rotated member
// tiles over the group's real memory photo. Matches
// design_handoff_group_post_cards/README.md §1 (radii/positions/rotation),
// minus the comment/reaction footer and fire-streak meta (not real data).
// Degrades gracefully with fewer members: shows however many real tiles
// exist (0-3), never fabricates a placeholder member.
// ---------------------------------------------------------------------------

class GroupCardFloat extends StatelessWidget {
  const GroupCardFloat({super.key, required this.data});
  final GroupCardData data;

  static const _tiles = [
    (top: 16.0, left: 16.0, right: null, bottom: null, w: 96.0, h: 120.0, deg: -4.0),
    (top: 74.0, left: null, right: 16.0, bottom: null, w: 88.0, h: 110.0, deg: 5.0),
    (top: null, left: 24.0, right: null, bottom: 16.0, w: 88.0, h: 110.0, deg: -6.0),
  ];

  @override
  Widget build(BuildContext context) {
    final members = data.members.take(3).toList();
    return GroupCardShell(
      data: data,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 400,
          child: Stack(
            children: [
              Positioned.fill(
                child: CachedNetworkImage(imageUrl: data.mainPhotoUrl, fit: BoxFit.cover),
              ),
              for (var i = 0; i < members.length; i++)
                Positioned(
                  top: _tiles[i].top,
                  left: _tiles[i].left,
                  right: _tiles[i].right,
                  bottom: _tiles[i].bottom,
                  child: Transform.rotate(
                    angle: _tiles[i].deg * math.pi / 180,
                    child: Container(
                      width: _tiles[i].w,
                      height: _tiles[i].h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
                        boxShadow: const [
                          BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 30, offset: Offset(0, 12)),
                        ],
                      ),
                      child: GroupCardMemberTile(member: members[i]),
                    ),
                  ),
                ),
              Positioned(
                bottom: 16,
                right: 16,
                child: const GroupCardIconButtons(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
