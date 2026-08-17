import 'package:flutter/material.dart';

import '../../../../services/feed_service.dart';
import '../../../../services/group_service.dart';
import 'group_card_float.dart';
import 'group_card_mosaic.dart';
import 'group_card_shared.dart';
import 'group_card_stack.dart';
import 'group_card_strip.dart';

// ---------------------------------------------------------------------------
// GroupPostCard — the Everyone feed's entry point for a GROUP FeedItem
// (item.groupName != null, the same real group_posts/groups/group_members
// pathway EveryonePostCard's own groupName param already reads from — see
// FeedItem.groupId/groupName and FeedService.fetchGroupFeed). Loads the
// group's real member roster + recent real posts, then renders one of the
// 4 collage layouts (Float/Mosaic/Stack/Strip) — see
// design_handoff_group_post_cards/README.md for the visual spec each one
// matches.
//
// Variant choice is deterministic per POST (hashed from postId), not
// re-rolled on every rebuild, and not per-group — different posts from the
// same group can land on different layouts, which is the point (the design
// doc's own stated goal: "a feed of cards doesn't feel repetitive").
//
// No fabricated data anywhere downstream of this: no fire/streak counts, no
// location, no comment/reaction footer — group_posts has no schema backing
// any of those (see this app's earlier real-data-only rule for group
// screens). Each variant degrades gracefully with sparse data (fewer real
// members/posts) rather than needing this picker to pre-check sufficiency.
// ---------------------------------------------------------------------------

class GroupPostCard extends StatefulWidget {
  const GroupPostCard({super.key, required this.item});
  final FeedItem item;

  @override
  State<GroupPostCard> createState() => _GroupPostCardState();
}

class _GroupPostCardState extends State<GroupPostCard> {
  late final Future<GroupCardData?> _future = _load();

  Future<GroupCardData?> _load() async {
    final groupId = widget.item.groupId;
    final photoUrl = widget.item.photoUrl;
    if (groupId == null || photoUrl == null || photoUrl.isEmpty) return null;

    final results = await Future.wait([
      GroupService.instance.fetchMembers(groupId),
      GroupService.instance.fetchPosts(groupId),
    ]);
    final memberRows = results[0];
    final postRows = results[1];

    final members = memberRows.map((r) {
      final u = r['users'] as Map?;
      return GroupCardMember(
        id: r['user_id'] as String? ?? '',
        name: (u?['name'] as String?) ?? 'Member',
        avatarUrl: u?['profile_photo_url'] as String?,
      );
    }).toList();

    var posts = postRows
        .map((r) => GroupCardPost(
              id: r['id'] as String? ?? '',
              photoUrl: r['photo_url'] as String? ?? '',
              userId: r['user_id'] as String? ?? '',
              caption: r['caption'] as String?,
              createdAt: r['created_at'] != null ? DateTime.tryParse(r['created_at'] as String) : null,
            ))
        .where((p) => p.photoUrl.isNotEmpty)
        .toList();

    // Rotate so THIS feed item's own post is first — Stack should open on
    // the post that actually made this card appear in the feed, not
    // whatever the group's single newest post happens to be.
    final idx = posts.indexWhere((p) => p.id == widget.item.postId);
    if (idx > 0) {
      posts = [...posts.sublist(idx), ...posts.sublist(0, idx)];
    } else if (idx == -1) {
      posts = [
        GroupCardPost(
          id: widget.item.postId,
          photoUrl: photoUrl,
          userId: widget.item.userId,
          caption: widget.item.caption,
          createdAt: widget.item.createdAt,
        ),
        ...posts,
      ];
    }

    return GroupCardData(
      groupId: groupId,
      groupName: widget.item.groupName ?? 'Group',
      members: members,
      posts: posts,
      mainPhotoUrl: photoUrl,
      mainCaption: widget.item.caption,
      mainCreatedAt: widget.item.createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GroupCardData?>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const GroupCardSkeleton();
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        switch (widget.item.postId.hashCode.abs() % 4) {
          case 0:
            return GroupCardFloat(data: data);
          case 1:
            return GroupCardMosaic(data: data);
          case 2:
            return GroupCardStack(data: data);
          default:
            return GroupCardStrip(data: data);
        }
      },
    );
  }
}
