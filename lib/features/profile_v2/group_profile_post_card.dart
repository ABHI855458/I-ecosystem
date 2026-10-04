import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/glass.dart';
import '../../screens/feed/widgets/post_card_shared.dart';
import '../../screens/feed/widgets/dual_photo_view.dart';
import '../../screens/feed/widgets/post_photo_carousel.dart';
import '../../screens/feed/widgets/group_post_cards/group_card_shared.dart'
    show groupCardClockTime, kGroupCardMonths, kGroupCardWeekdays;
import '../../services/post_author_pin_service.dart';
import '../../services/post_service.dart' show PostService, PostViewer;
import '../../services/post_size_prefs_service.dart';
import '../../services/reaction_service.dart';
import '../../shared/time_ago.dart';
import 'profile_v2_icons.dart';
import 'profile_v2_menus.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

/// One group post on a group's own profile page. View-only for reactions —
/// unlike the feed's DesignGroupCard, this screen does not let you Ping or
/// react with RealMoji. The bottom-left ReactionPreviewChip — the same one
/// the feed shows — opens the comments sheet (reactor strip on top) here,
/// since this is an already member-gated group profile where reactor
/// identity is allowed to show. Reacting itself still happens from the
/// main feed.
///
/// Tapping the card (outside the pill/delete-menu/reaction chip) opens a
/// separate read-only detail screen for the photo + full comment thread —
/// [onTap] is optional so a caller that doesn't pass one keeps today's
/// non-interactive card.
class GroupProfilePostCard extends StatefulWidget {
  const GroupProfilePostCard({
    super.key,
    required this.row,
    required this.groupName,
    required this.canDelete,
    required this.menuOpen,
    required this.onToggleMenu,
    required this.onDismissMenu,
    required this.onDelete,
    this.onTap,
    this.onShare,
    this.shareLabel,
    this.locked = false,
  });

  /// A private group's post shown to a non-member on the group profile —
  /// photo 1 clear, the rest blurred (the server already sends photo 1 in
  /// every slot; see group_profile_posts_for_viewer), and no reactor list.
  final bool locked;

  /// The raw group_posts row (+ joined `users`), same shape the old
  /// _realPostCard read from.
  final Map<String, dynamic> row;
  final String groupName;
  final bool canDelete;

  /// The screen still owns which post's delete-menu is open (only one at a
  /// time across the whole list), so that stays screen-level state passed
  /// down rather than moved in here.
  final bool menuOpen;
  final VoidCallback onToggleMenu;
  final VoidCallback onDismissMenu;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  /// Non-null for any member: sets THEIR OWN audience for this post
  /// (share_group_post replaces only rows they shared, never another
  /// member's).
  final VoidCallback? onShare;

  /// Menu label for [onShare]. Null = 'Share to my circles' (someone else's
  /// post); the author's own post passes 'Edit my audience'.
  final String? shareLabel;

  @override
  State<GroupProfilePostCard> createState() => _GroupProfilePostCardState();
}

class _GroupProfilePostCardState extends State<GroupProfilePostCard> {
  ReactionSummary _summary = const ReactionSummary.empty();
  List<LikeReactor> _reactors = const [];

  // Seen pill — a PROFILE surface, so this reads like DesignSoloCard's own
  // `viewerSeen: true` branch: who has EVER seen this post (a permanent
  // record), not who's live/present right now. touch()-ing presence here
  // would incorrectly mark the viewer as live-present just for opening
  // their own group's profile. Per-card groupId (keyed on this post's own
  // id) so the dropdown of one card in the list doesn't fight another's
  // outside-tap detection.
  List<PostViewer> _viewers = const [];
  bool _showLiveDropdown = false;

  String get _id => widget.row['id'] as String;
  String get _liveGroupId => 'groupprofile-live-$_id';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(PostService.instance.recordGroupPostView(_id));
    unawaited(_loadViewers());
    // A pin change re-fetches the seen list, so an open dropdown's PINNED
    // section updates immediately (PostAuthorPinService.changes).
    PostAuthorPinService.instance.changes.addListener(_onPinsChanged);
  }

  void _onPinsChanged() {
    if (mounted) unawaited(_loadViewers());
  }

  @override
  void dispose() {
    PostAuthorPinService.instance.changes.removeListener(_onPinsChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ReactionService.instance.fetchSummary(null, groupPostId: _id),
      ReactionService.instance.fetchRecentReactors(
        null,
        groupPostId: _id,
        limit: 8,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as ReactionSummary;
      _reactors = results[1] as List<LikeReactor>;
    });
  }

  Future<void> _loadViewers() async {
    final viewers = await PostService.instance.fetchGroupPostViewers(_id);
    if (!mounted) return;
    setState(() => _viewers = viewers);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final user = row['users'] as Map<String, dynamic>?;
    final name = (user?['name'] as String?) ?? 'member';
    final avatarUrl = user?['profile_photo_url'] as String?;
    final caption = row['caption'] as String?;
    final note = row['note'] as String?;
    final place = row['place'] as String?;
    final takenAt = DateTime.tryParse(row['taken_at'] as String? ?? '');
    // taken_at (when the memory actually happened) takes over the date
    // line when set — created_at (when it was posted) is the fallback,
    // same as every post without it.
    final createdAt =
        takenAt ?? DateTime.tryParse(row['created_at'] as String? ?? '');
    final photos = resolvePostPhotos(
      photoUrls: (row['photo_urls'] as List?)?.cast<String>(),
      singleUrl: row['photo_url'] as String?,
    );

    final card = GestureDetector(
      // deferToChild: same pattern PostsList._card uses for the personal-
      // post cards — the pill's/delete-menu's own GestureDetectors win the
      // gesture arena when a tap lands on them, so onTap only fires for the
      // rest of the card.
      behavior: HitTestBehavior.deferToChild,
      onTap: widget.onTap,
      child: NeuCard(
        radius: 24,
        clip: true,
        // Reverted to NeuCard's own default fill — explicit request to put
        // the group post card back to how it looked before today's
        // panelled redesign (kGroupCardBody + the two kGroupCardPanel
        // wells). The tokens themselves are left defined and still used by
        // design_group_card.dart, so only THIS card reverts.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header per the provided design: a calendar chip (day over
            // month) leading a bold title with the weekday + clock time
            // beneath it — replacing the old avatar + name + "3h" row.
            // The title is the post's own caption when it has one, so a
            // titled memory reads as an event rather than a photo dump;
            // the poster's identity moves to the footer strip below.
            // Reverted: this header used to be wrapped in its own lighter
            // kGroupCardPanel NeuWell (added today). Explicit request to
            // go back to the pre-today look, so it's a plain Padding + Row
            // on the card's own ground again.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 10),
              child: Row(
                  children: [
                    NeuWell(
                      width: 46,
                      height: 46,
                      radius: 14,
                      shadows: PV2.insetStd,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            createdAt == null
                                ? '--'
                                : createdAt.day.toString().padLeft(2, '0'),
                            style: PV2.display(size: 17, height: 1),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            createdAt == null
                                ? ''
                                : kGroupCardMonths[createdAt.month - 1],
                            style: PV2.caps(
                              size: 8,
                              tracking: 0.14,
                              color: PV2.inkCount,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (caption != null && caption.isNotEmpty)
                                ? caption
                                : '$name\u2019s post',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PV2.body(
                              size: 15.5,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            createdAt == null
                                ? formatRelativeTime(createdAt)
                                : '${kGroupCardWeekdays[createdAt.weekday - 1]} \u00b7 ${groupCardClockTime(createdAt)}',
                            style: PV2.body(size: 12, color: PV2.inkCount),
                          ),
                        ],
                      ),
                    ),
                    if (widget.canDelete || widget.onShare != null)
                      PV2MenuAnchor(
                        open: widget.menuOpen,
                        onDismiss: widget.onDismissMenu,
                        offset: const Offset(0, 6),
                        menu: PV2MenuPanel(
                          width: 150,
                          radius: 13,
                          padding: 4,
                          children: [
                            if (widget.onShare != null)
                              PV2MenuItem(
                                icon: widget.shareLabel == null
                                    ? Icons.ios_share_rounded
                                    : Icons.people_outline_rounded,
                                label: widget.shareLabel ?? 'Share to my circles',
                                iconSize: 14,
                                fontSize: 12.5,
                                gap: 8,
                                radius: 10,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                onTap: widget.onShare!,
                              ),
                            if (widget.canDelete)
                              PV2MenuItem(
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete post',
                                iconSize: 14,
                                fontSize: 12.5,
                                gap: 8,
                                radius: 10,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                destructive: true,
                                onTap: widget.onDelete,
                              ),
                          ],
                        ),
                        // A full 44pt opaque target: it used to be only the
                        // 15pt glyph itself (Padding doesn't hit-test), so a
                        // near miss fell through to the card and opened the
                        // post instead of the menu.
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onToggleMenu,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: PV2Icons.more(
                                20,
                                Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ),
            // Item #1: the public bottom-left "who reacted" pill/
            // dropdown is gone from the photo overlay (and its text-only-
            // post inline fallback) — replaced by the single
            // PostReactionsSection below the caption/note, visible to any
            // member viewing this (already member-gated) group profile.
            if (photos.isNotEmpty)
              Stack(
                children: [
                  // A dual group post renders the two live layers, same as
                  // the friends feed — otherwise the inset uploaded by the
                  // composer would be stored and never shown.
                  // Third aspect ratio this card was quietly using — the
                  // friends feed's DesignGroupCard reads the POST's own
                  // stored ratio now (its poster's compose-time choice,
                  // never a viewer setting), and this profile view stayed
                  // on its own hardcoded 4:5. Unified on the same row field.
                  if ((row['photo_url_secondary'] as String?)?.isNotEmpty ==
                          true &&
                      photos.isNotEmpty)
                    DualPhotoView(
                      backgroundUrl: photos.first,
                      insetUrl: row['photo_url_secondary'] as String,
                      insetOnRight: row['inset_on_right'] as bool? ?? false,
                      borderRadius: 0,
                      aspectRatio: parseStoredAspectRatio(
                        row['aspect_ratio'] as String?,
                      ),
                    )
                  else
                    PostPhotoCarousel(
                      photoUrls: photos,
                      aspectRatio: parseStoredAspectRatio(
                        row['aspect_ratio'] as String?,
                      ),
                      borderRadius: 0,
                      blurFromIndex: widget.locked ? 1 : null,
                    ),
                  // No seen pill over a group-profile photo. It used to sit
                  // top-right here, but a group profile is already
                  // member-gated and the pill only crowded the image —
                  // removed on request ("the seen pill is over the post in
                  // group profile, let it not be there").
                  //
                  // The same reaction chip the friends feed and personal
                  // profile use — tap opens the comments sheet (reactor
                  // strip on top), since this is already a member-gated
                  // group profile where identity is allowed to show.
                  Positioned(
                    left: 14,
                    bottom: 14,
                    child: ReactionPreviewChip(
                      // Faces as well as the count — explicit correction:
                      // "in profile it shall show the same real emoji
                      // reaction reacted, it shall not only show number 1
                      // but as well the image preview". Both feed cards
                      // already passed these; this one didn't, so a post
                      // reacted to with a RealMoji read as a bare "1".
                      count:
                          _summary.totalEmojiCount +
                          _summary.faceReactions.length,
                      faces: _summary.faceReactions,
                      // Plain emoji reactions too — faces alone is only the
                      // RealMoji half, so an emoji-only post still read as
                      // a bare "1". See ReactionPreviewChip.emojiCounts.
                      emojiCounts: _summary.emojiCounts,
                      onTap: widget.locked
                          ? () => showGlassToast(
                              context,
                              'Be a friend to see reactions on this post',
                            )
                          : () => showPostCommentsSheet(
                              context,
                              groupPostId: _id,
                              isGroup: true,
                              reactors: _reactors,
                              reactionCount: _summary.totalReactionCount,
                              onPosted: _load,
                            ),
                    ),
                  ),
                ],
              ),
            // Caption is the header's title now, so it is NOT repeated here.
            // The note (a separate column) still renders below the photo as
            // the post's body text when there is one.
            if (note != null && note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
                child: Text(
                  note,
                  style: PV2.body(size: 13, color: PV2.inkBio, height: 1.4),
                ),
              ),
            // The standalone "Reactions" section and the footer's reactor
            // faces are both gone — the chip on the photo above is the one
            // way to see reactions now, via the comments sheet it opens.
            // Footer strip per the provided design: place on the left,
            // poster identity on the right. Always shown — poster identity
            // no longer needs a reactor count to justify the row.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
              child: NeuWell(
                radius: 13,
                shadows: PV2.insetStd,
                // Reverted to NeuWell's default fill — see the card's own
                // revert note above.
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                width: double.infinity,
                child: Row(
                  children: [
                    // Poster identity moved here from the old header row.
                    ClipOval(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: avatarUrl == null
                            ? const ColoredBox(
                                color: PV2.recessed,
                                child: Icon(
                                  Icons.person,
                                  size: 11,
                                  color: Colors.white38,
                                ),
                              )
                            : CachedNetworkImage(
                                memCacheWidth: 1080,
                                imageUrl: avatarUrl,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (place != null && place.isNotEmpty) ...[
                      PV2Icons.place(13, Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.body(size: 12.5, weight: FontWeight.w600),
                        ),
                      ),
                    ] else
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.body(size: 12.5, weight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Seen pill sits in its own row above the card now — same treatment
    // the feed's group-name row gives DesignGroupCard, but SeenPill/
    // SeenDropdown instead of LivePresencePill/LivePresenceDropdown: a
    // profile is a "who's ever seen this" surface, not a "who's live right
    // now" one (that's the feed's job, with its own 3-hour presence
    // window — see DesignGroupCard).
    final pillRow = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: TapRegion(
          groupId: _liveGroupId,
          child: SeenPill(
            viewers: _viewers,
            // Faces only, matching the feed's group-post pill.
            avatarsOnly: true,
            onTap: () {
              setState(() => _showLiveDropdown = !_showLiveDropdown);
              if (_showLiveDropdown) unawaited(_loadViewers());
            },
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [pillRow, card],
        ),
        // Painted last (on top of the NeuCard below it) rather than nested
        // inside pillRow's own Stack — nesting it there would let the
        // card, painted after it in the same Column, cover it, the same
        // bug the feed's group-name-row pill hit.
        if (_showLiveDropdown)
          Positioned(
            top: 34,
            right: 18,
            child: TapRegion(
              groupId: _liveGroupId,
              onTapOutside: (_) => setState(() => _showLiveDropdown = false),
              child: SeenDropdown(viewers: _viewers),
            ),
          ),
      ],
    );
  }
}
