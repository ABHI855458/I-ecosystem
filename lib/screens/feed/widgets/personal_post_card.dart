import 'dart:async';

import 'package:flutter/material.dart';

import '../../../features/ping/ping_prompt_sheet.dart' show PingContext;
import '../../../services/presence_service.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
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
  List<LikeReactor> _reactors = const [];
  bool _showLiveDropdown = false;
  List<PresenceUser> _present = const [];

  // Closes the live dropdown when the enclosing feed scrolls — per explicit
  // request ("vanish... when scrolling"). Scrollable.of walks UP the tree
  // from this widget's own context to find the ancestor feed's Scrollable
  // (the ListView/PageView in everyone_feed_screen.dart), so this works
  // regardless of this card's position in that list — unlike a
  // NotificationListener, which would need to be an ANCESTOR of the
  // Scrollable to catch its notifications, not a descendant like this card.
  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    if (!widget.loading && !widget.locked) {
      loadReactionSummary(widget.postId);
      unawaited(_loadReactors());
      unawaited(PresenceService.instance.touch(postId: widget.postId));
      unawaited(_loadPresence());
    }
  }

  Future<void> _loadPresence() async {
    final entries = await PresenceService.instance.fetchPresence(postId: widget.postId);
    if (!mounted) return;
    setState(() => _present = entries.map(PresenceUser.fromEntry).toList());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (newPosition != _scrollPosition) {
      _scrollPosition?.removeListener(_onAncestorScroll);
      _scrollPosition = newPosition;
      _scrollPosition?.addListener(_onAncestorScroll);
    }
  }

  void _onAncestorScroll() {
    if (_showLiveDropdown) setState(() => _showLiveDropdown = false);
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

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onAncestorScroll);
    super.dispose();
  }

  Future<void> _loadReactors() async {
    final reactors = await ReactionService.instance.fetchRecentReactors(widget.postId, limit: 5);
    if (!mounted) return;
    setState(() => _reactors = reactors);
  }

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            PostCard(
              handle: widget.handle,
              place: widget.place,
              avatar: widget.avatar,
              backPhoto: widget.backPhoto,
              frontPhoto: widget.frontPhoto ?? widget.backPhoto,
              logo: widget.logo,
              locked: widget.locked,
              loading: widget.loading,
              showReactDisc: false,
              // Engagement (reactions pill/strip, comment card) now renders
              // externally below, via the shared post_card_shared.dart
              // widgets — same components GroupPostCard uses, per the
              // Everyone/Group interaction-parity design.
              showBuiltInEngagement: false,
              headerTrailing: (!widget.locked && !widget.loading)
                  ? LivePresencePill(
                      present: _present,
                      onTap: () {
                        setState(() => _showLiveDropdown = !_showLiveDropdown);
                        if (_showLiveDropdown) unawaited(_loadPresence());
                      },
                    )
                  : null,
            ),
            if (!widget.locked && !widget.loading) ...[
              // REVERTED to top:62 — see turn note: Feed.dc.html's top:12
              // is relative to the PHOTO's own position:relative div, but
              // this Stack wraps the whole PostCard (header + photo), so a
              // literal top:12 lands inside the header row instead,
              // covering the avatar/username entirely (confirmed via
              // screenshot). top:62 was a deliberate approximation of the
              // header's height for this different Stack structure, not a
              // bug — flagged back rather than guessing a replacement.
              if (_showLiveDropdown) ...[
                // Outside-tap dismiss barrier. NOT Positioned.fill — that
                // combined with a childless GestureDetector triggered a
                // real layout crash loop here (RenderOpacity/RenderStack/
                // RenderIgnorePointer "NEEDS-LAYOUT", confirmed by removing
                // it and watching the exception spam stop), almost
                // certainly colliding with SpotlightCard's own internal
                // Opacity/IgnorePointer wrappers one level up. Positioned
                // with explicit left/right/top/bottom: 0 sizes identically
                // to .fill but apparently doesn't trip the same interaction
                // — kept as a distinct, explicit box instead of the
                // convenience constructor.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => setState(() => _showLiveDropdown = false),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: 62,
                  right: 12,
                  child: LivePresenceDropdown(present: _present),
                ),
              ],
              // The floating reactions avatar-pill that used to sit here
              // (bottom-left, faces + count, tapping it toggled a strip)
              // is REMOVED — explicit request: "remove this thing and let
              // the existing below drop down is enough." The REACTED row
              // beneath the card (PostReactionsSection) already shows the
              // same faces and count, and expands to the full list, so this
              // was the same information twice, once floating over the
              // photo.

              // Ping + RealMoji now bottom-RIGHT, stacked VERTICALLY
              // (Column, gap 12) per Feed.dc.html's own "right action
              // rail" — was a horizontal Row pinned bottom-left.
              Positioned(
                right: 13,
                bottom: 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PostPingButton(onTap: () => openPing(pingContext: PingContext.everyone, targetName: widget.handle)),
                    const SizedBox(height: 22),
                    PostReactionCorner(
                      // §2: 34dp per spec — this widget's own default (26)
                      // stays untouched since the Anon feed's tray relies
                      // on it with no override of its own.
                      size: 34,
                      allowFaceReactions: true,
                      myFaceReaction: null,
                      myEmoji: myRealmojiReaction?.glyph,
                      uploading: uploadingFaceReaction,
                      onTap: openReactionTray,
                      onClose: closePresetTray,
                      showTray: showPresetTray,
                      category: ReactionPresetCategory.everyone,
                      onSelect: (preset) => selectPreset(widget.postId, preset),
                      onAddNew: () => openAddPresetFlow(widget.postId, allowFaceReactions: true),
                      onCaptureRealmoji: (type) => captureRealmojiAndReact(
                        widget.postId,
                        ReactionPresetCategory.everyone,
                        type,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (!widget.locked && !widget.loading)
          PostCommentCard(
            postId: widget.postId,
            reactors: _reactors,
            reactionCount: reactions.totalReactionCount,
          ),
      ],
    );
  }
}
