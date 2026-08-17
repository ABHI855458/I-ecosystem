import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/reaction_service.dart';
import 'post_card.dart';
import 'post_card_shared.dart';

// ---------------------------------------------------------------------------
// PersonalPostCard — stateful adapter wiring real reaction data into the
// presentational PostCard (post_card.dart), the same way
// _EveryonePostCardState wires ReactionService into EveryonePostCard for
// group posts. Individual posts ONLY — everyone_feed_screen.dart picks this
// widget when item.groupName == null, EveryonePostCard otherwise.
//
// Two gaps in the current schema, both stubbed rather than faked:
//  - No separate front/selfie capture URL is persisted (composer.dart
//    composites back+front into one image at capture time) — frontPhoto
//    falls back to the same photoUrl as backPhoto until dual-camera storage
//    lands.
//  - No comments table/service exists yet (FeedItem.commentCount is already
//    hardcoded 0 for the same reason on EveryonePostCard) — comments stays
//    empty and commentCount passes through whatever the caller has.
// ---------------------------------------------------------------------------

class PersonalPostCard extends StatefulWidget {
  const PersonalPostCard({
    super.key,
    required this.postId,
    required this.handle,
    this.avatar,
    this.backPhoto,
    this.frontPhoto,
    this.place,
    this.comments = const [],
    this.commentCount = 0,
    this.onOpenComments,
    this.logo,
    this.locked = false,
    this.loading = false,
  });

  final String postId;
  final String handle;
  final String? avatar;
  final String? backPhoto;
  final String? frontPhoto;
  final String? place;
  final List<PostCardComment> comments;
  final int commentCount;
  final VoidCallback? onOpenComments;
  final String? logo;
  final bool locked;
  final bool loading;

  @override
  State<PersonalPostCard> createState() => _PersonalPostCardState();
}

class _PersonalPostCardState extends State<PersonalPostCard> with PostReactions<PersonalPostCard> {
  static const String _kReactEmoji = '❤️';

  List<LikeReactor> _reactors = const [];

  @override
  void initState() {
    super.initState();
    if (!widget.loading && !widget.locked) {
      loadReactionSummary(widget.postId);
      unawaited(_loadReactors());
    }
  }

  @override
  void didUpdateWidget(PersonalPostCard old) {
    super.didUpdateWidget(old);
    final justBecameReady = (old.loading || old.locked) && !widget.loading && !widget.locked;
    if (justBecameReady || old.postId != widget.postId) {
      loadReactionSummary(widget.postId);
      unawaited(_loadReactors());
    }
  }

  Future<void> _loadReactors() async {
    final reactors = await ReactionService.instance.fetchRecentReactors(widget.postId, limit: 5);
    if (!mounted) return;
    setState(() => _reactors = reactors);
  }

  Future<void> _react(String emoji) async {
    await onEmojiSelected(widget.postId, emoji);
    unawaited(_loadReactors());
  }

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();

    return PostCard(
      handle: widget.handle,
      place: widget.place,
      avatar: widget.avatar,
      backPhoto: widget.backPhoto,
      frontPhoto: widget.frontPhoto ?? widget.backPhoto,
      reactions: _reactors
          .map((r) => PostCardReaction(id: r.id, handle: r.name, photo: r.avatarUrl, emoji: r.emoji))
          .toList(),
      reactionCount: reactions.totalEmojiCount,
      comments: widget.comments,
      commentCount: widget.commentCount,
      reacted: reactions.myEmoji != null,
      onReact: () => _react(_kReactEmoji),
      onPickReactionEmoji: _react,
      onOpenComments: widget.onOpenComments,
      logo: widget.logo,
      locked: widget.locked,
      loading: widget.loading,
    );
  }
}
