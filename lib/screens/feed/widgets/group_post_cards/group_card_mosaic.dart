import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'group_card_shared.dart';

// ---------------------------------------------------------------------------
// GroupCardMosaic — CSS-grid-style photo collage: real memory photo
// spanning both rows on the left, up to 2 real member tiles on the right.
// Matches design_handoff_group_post_cards/README.md §2, minus the location
// pill (no location field on group_posts — not real data) and the
// comment/reaction footer.
// ---------------------------------------------------------------------------

class GroupCardMosaic extends StatelessWidget {
  const GroupCardMosaic({super.key, required this.data});
  final GroupCardData data;

  @override
  Widget build(BuildContext context) {
    final members = data.members.take(3).toList();
    return GroupCardShell(
      data: data,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 360,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 115,
                    child: CachedNetworkImage(imageUrl: data.mainPhotoUrl, fit: BoxFit.cover),
                  ),
                  if (members.isNotEmpty) const SizedBox(width: 4),
                  if (members.isNotEmpty)
                    Expanded(
                      flex: 100,
                      child: members.length == 1
                          ? GroupCardMemberTile(member: members[0], radius: 0)
                          : Column(
                              children: [
                                Expanded(child: GroupCardMemberTile(member: members[0], radius: 0)),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: members.length == 2
                                      ? GroupCardMemberTile(member: members[1], radius: 0)
                                      : Row(
                                          children: [
                                            Expanded(child: GroupCardMemberTile(member: members[1], radius: 0)),
                                            const SizedBox(width: 4),
                                            Expanded(child: GroupCardMemberTile(member: members[2], radius: 0)),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
              Positioned(bottom: 12, right: 12, child: const GroupCardIconButtons()),
            ],
          ),
        ),
      ),
    );
  }
}
