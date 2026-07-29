import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants.dart';
import '../../../core/glass.dart';
import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../services/reaction_service.dart';
import '../../../widgets/reaction_picker_popup.dart';
import 'post_card_shared.dart';
import 'reaction_row.dart';

// ---------------------------------------------------------------------------
// PhotoPostCard — the image-dominant post card, used whenever a post has a
// photo. Built to POST_CARD_SPEC.md (project root) — anonymous posts only.
// Top to bottom:
//   1. Text block: the ghost prompt question (semi-bold, emphasized) and
//      the poster's caption (regular, dimmer) — ABOVE the image, not
//      overlapping it. Left-padded to match the image's left edge.
//   2. The image itself: rounded corners, inset with a gap on the left
//      (not edge-to-edge), full opacity — no dimming/scrim over it. Things
//      that sit on/into its corners:
//      a. The anon persona icon (tier-glow ring, never the real profile
//         photo, never a real name) DIPPED into the image's top-left
//         corner — a circular notch is cut out of the image itself near
//         that corner (centered slightly right and down from the
//         mathematical corner point, not on top of it — the image's own
//         rounding already recedes from that exact point, so centering
//         there put most of the icon over the background instead of the
//         photo). A background-colored disc, slightly larger than the
//         icon and with its own soft shadow, sits in that notch behind the
//         icon — that's what makes it read as embedded/dipped rather than
//         a flat overlap: a clean ring of separation on every side, not
//         the icon's edge sitting flush against the photo.
//      a2. ADD YOUR REACTION — a small reaction-entry badge tucked at the
//         persona icon's own bottom-right edge (see _ReactionEntryBadge).
//         This is the single, dedicated entry point into the BeReal-style
//         reaction flow: tapping it opens the front-camera selfie capture
//         (openFaceCapture) when [allowFaceReactions] is true (Friends/
//         Everyone), or the emoji-only picker (toggleEmojiPicker) when
//         it's false (Anonymous) — same corner, branching purely on that
//         flag. It sits at the avatar's edge rather than the opposite
//         top-right corner because that corner already belongs to the
//         branch tag (below) — the avatar's own bottom-right quadrant is
//         the only unclaimed spot in the top-left identity cluster, and
//         keeps this new affordance visually grouped with "who this is"
//         rather than orphaned elsewhere on the card. Once the viewer has
//         reacted, the badge itself swaps from an idle icon to a tiny
//         thumbnail of THEIR reaction (selfie or emoji) — the corner is
//         both the entry point and the "you reacted" indicator, so there's
//         no separate place on the card showing the viewer's own reaction.
//         (Because it fully supersedes the old long-press-the-heart path,
//         PhotoPostCard no longer wires face capture into the heart's
//         long-press — TopActionIcons still supports that callback
//         generically for TextPostCard, but this card passes null.)
//      b. The branch/department tag (e.g. "CSE"), a plain small pill in
//         the image's top-right corner.
//      c. Reaction (heart) + ping, bottom-right, sitting on their own
//         small WHITE rounded backing tab (not floating directly on the
//         photo) — the tab's outer corner matches the image's own corner
//         radius so it reads as part of the image's corner, not a chip
//         dropped on top.
//   3. Below the image, two DISTINCT frosted-glass surfaces (not merged
//      into one block), stacked vertically:
//      a. SEE OTHERS' REACTIONS — ReactionRow: a horizontally-scrollable,
//         swipeable row of OTHER people's BeReal-style face-reaction
//         thumbnails (only for feeds where allowFaceReactions is true —
//         never on the Anonymous feed, which is emoji-only). The viewer's
//         own reaction is filtered out here since it's already shown on
//         the corner badge above. Hidden entirely (no empty glass box)
//         when there's nothing to show.
//      b. Comments — "View all N comments", in its own glass surface
//         directly below.
//
// No real name, no real profile photo, no timestamp, no song/audio bar —
// anywhere on this card, ever.
// ---------------------------------------------------------------------------

class PhotoPostCard extends StatefulWidget {
  const PhotoPostCard({
    super.key,
    required this.postId,
    required this.media,
    required this.allowFaceReactions,
    required this.pingContext,
    this.pingTargetName,
    this.pingGlass = true,
    this.personaPhotoUrl,
    this.posterScore,
    this.branch,
    this.promptQuestion,
    this.answerText,
    this.commentCount = 0,
    this.onCommentTap,
    this.cornerRadius = 24,
    this.imageCornerRadius = 18,
    this.isLoading = false,
    this.hasError = false,
  });

  /// Reactions are fetched/written keyed on this — must be stable and
  /// unique per post.
  final String postId;

  /// The actual photo/collage content (e.g. wrap SinglePostCard,
  /// MemoryFeedCard, or a raw image). Ignored while [isLoading] or
  /// [hasError] are true. PhotoPostCard is only ever built for posts that
  /// have a photo — route text-only posts to TextPostCard instead.
  final Widget media;

  /// True for Friends/Everyone feeds, false for the Anonymous feed. Face
  /// reactions (the corner entry badge's camera flow, and the BeReal-style
  /// row of others' reactions below the image) only ever engage when this
  /// is true — the Anonymous feed is emoji-only reactions throughout.
  final bool allowFaceReactions;

  /// Passed straight through to showPingPromptSheet — see
  /// ping_prompt_sheet.dart for what this changes (prompt copy, styling).
  final PingContext pingContext;

  /// Name shown inside the ping sheet itself (a separate flow this card
  /// doesn't render) — null falls back to 'someone'. Passing a real name
  /// here does not put a name on the card; the card still shows none.
  final String? pingTargetName;
  final bool pingGlass;

  /// The poster's anon persona photo — never the real profile photo. Null
  /// falls back to a plain silhouette glyph inside the glow ring.
  final String? personaPhotoUrl;

  /// Drives the persona icon's tier-glow ring color/intensity — the
  /// compact, prominent status signal, per spec.
  final int? posterScore;

  /// Department/branch tag (e.g. "CSE"), shown in the image's top-right
  /// corner.
  final String? branch;

  /// The ghost prompt this post is replying to — shown in the text block
  /// above the image. Null hides the whole text block.
  final String? promptQuestion;

  /// The poster's written caption for [promptQuestion], shown directly
  /// below it in a dimmer, ghosted weight. Ignored if [promptQuestion] is
  /// null.
  final String? answerText;

  final int commentCount;
  final VoidCallback? onCommentTap;

  final double cornerRadius;

  /// Corner radius of the inset image itself (distinct from [cornerRadius],
  /// the outer card) — per spec, ~16-20px.
  final double imageCornerRadius;

  /// Card-level (not reaction-level) loading/error — set by the caller when
  /// the post's own content isn't ready/failed. Reaction data has its own
  /// internal loading state independent of this.
  final bool isLoading;
  final bool hasError;

  @override
  State<PhotoPostCard> createState() => _PhotoPostCardState();
}

class _PhotoPostCardState extends State<PhotoPostCard> with PostReactions<PhotoPostCard> {
  static const double _kImageInsetLeft = 28;
  static const double _kImageInsetRight = 10;

  @override
  void initState() {
    super.initState();
    if (!widget.isLoading && !widget.hasError) loadReactionSummary(widget.postId);
  }

  @override
  void didUpdateWidget(PhotoPostCard old) {
    super.didUpdateWidget(old);
    final justBecameReady =
        (old.isLoading || old.hasError) && !widget.isLoading && !widget.hasError;
    if (justBecameReady || old.postId != widget.postId) loadReactionSummary(widget.postId);
  }

  // How far the dip's center sits from the image's mathematical top-left
  // corner point (0,0). The image's own corner is ROUNDED (imageCornerRadius),
  // so the visible photo recedes away from (0,0) diagonally — centering the
  // dip exactly on (0,0) put most of the circle over the background instead
  // of the photo, reading as "floating off the image" rather than embedded
  // in it. Shifting the center toward the image's interior (mostly right,
  // a little down) moves it onto the actual rounded curve instead.
  static const double _kDipOffsetX = 10;
  static const double _kDipOffsetY = 3;

  // The notch (and the background disc behind the avatar, below) is cut
  // slightly LARGER than the persona icon itself, not an exact match. That
  // extra ring is what makes this read as embedded/dipped rather than a
  // flat overlap: it leaves a thin band of solid card-background color
  // (plus a soft shadow) between the photo's cut edge and the avatar's own
  // edge, on every side — a clean seam instead of the icon's edge sitting
  // directly against the photo.
  static const double _kDipRingGap = 4;

  // How far the reaction-entry badge's center sits from the persona icon's
  // own center, as a fraction of the persona icon's radius. 0.95 (just
  // inside the avatar's true edge) reads as "a badge clipped onto the
  // avatar's corner" — like a story-ring add button — rather than either
  // floating free of it (too high a ratio) or sitting dead-center on top
  // of it, obscuring the identity glyph entirely (too low a ratio).
  static const double _kEntryBadgeOffsetRatio = 0.95;
  static const double _kEntryBadgeSize = 22;

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();
    final hasPrompt = widget.promptQuestion != null;

    // Others' reactions only — the viewer's own face reaction is shown on
    // the corner entry badge instead, so it's excluded here to avoid
    // showing it twice.
    final otherFaceReactions = reactions.myFaceReaction == null
        ? reactions.faceReactions
        : reactions.faceReactions
            .where((r) => r.userId != reactions.myFaceReaction!.userId)
            .toList();
    final showFaceReactions = widget.allowFaceReactions &&
        (otherFaceReactions.isNotEmpty || (loadingSummary && summary == null));

    final personaRadius = PersonaPhoto.kSize / 2;
    final dipCenter = Offset(_kDipOffsetX, _kDipOffsetY);
    final dipRadius = personaRadius + _kDipRingGap;

    final entryBadgeRadius = _kEntryBadgeSize / 2;
    final entryBadgeCenter = dipCenter +
        Offset(personaRadius * _kEntryBadgeOffsetRatio, personaRadius * _kEntryBadgeOffsetRatio);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.cornerRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Text block — ghost prompt question + caption, ABOVE the
            // image, left-padded to match the image's own left edge. Extra
            // bottom gap (>= the persona icon's dip radius) so the icon's
            // upward overlap into this row lands on empty background, not
            // on the caption text.
            if (hasPrompt)
              Padding(
                padding: const EdgeInsets.fromLTRB(_kImageInsetLeft, 14, 16, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) => GhostPromptBlock(
                    question: widget.promptQuestion!,
                    answer: widget.answerText,
                    maxWidth: constraints.maxWidth,
                  ),
                ),
              ),
            SizedBox(height: hasPrompt ? dipRadius - _kDipOffsetY + 4 : 14),

            // 2. The image, with the persona icon dipped into its top-left
            // corner, the reaction-entry badge tucked at the icon's edge,
            // the branch tag in its top-right corner, and the reaction/
            // ping icons on a white backing tab bottom-right.
            // clipBehavior: Clip.none on this outer Stack is what lets the
            // persona icon, the entry badge, and the emoji-picker popup
            // render outside the image's own box (up into the gap above,
            // and above the image respectively) without being cut off.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_kImageInsetLeft, 0, _kImageInsetRight, 0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipPath(
                      clipper: _TopLeftNotchClipper(
                        cornerRadius: widget.imageCornerRadius,
                        notchCenter: dipCenter,
                        notchRadius: dipRadius,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildMedia(),

                          if (widget.branch != null)
                            Positioned(
                              top: 10, right: 10,
                              child: BranchTag(branch: widget.branch!),
                            ),

                          // White rounded backing tab, bottom-right — its
                          // own bottom-right corner matches the image's
                          // corner radius exactly, so it reads as part of
                          // the image's corner rather than a chip dropped
                          // on top of the photo.
                          Positioned(
                            right: 0, bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(widget.imageCornerRadius),
                                  bottomRight: Radius.circular(widget.imageCornerRadius),
                                ),
                              ),
                              child: TopActionIcons(
                                liked: reactions.myEmoji != null,
                                likeCount: reactions.totalEmojiCount,
                                // Uploading state now lives solely on the
                                // reaction-entry badge (below) — the heart
                                // is a separate, unrelated "like" control
                                // and shouldn't freeze into a spinner while
                                // a face-reaction upload is in flight.
                                uploadingFaceReaction: false,
                                onReactionTap: toggleEmojiPicker,
                                // Face capture now has its own dedicated
                                // entry point (the corner badge) — no
                                // longer bundled into the heart's long
                                // press.
                                onReactionLongPress: null,
                                onPingTap: () => openPing(
                                  pingContext: widget.pingContext,
                                  targetName: widget.pingTargetName,
                                  glass: widget.pingGlass,
                                ),
                                iconColor: kClusterGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Backing disc — solid card-background color, slightly
                    // larger than the persona icon and centered on the same
                    // dip point, with its own soft shadow. This is what
                    // actually creates the "embedded" look: it leaves a
                    // clean ring of background (plus shadow depth) between
                    // the photo's cut edge and the icon's own edge, rather
                    // than the icon sitting flush against the photo.
                    Positioned(
                      left: dipCenter.dx - dipRadius,
                      top: dipCenter.dy - dipRadius,
                      child: Container(
                        width: dipRadius * 2,
                        height: dipRadius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.cardSurface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Persona icon — sits centered on the same dip point,
                    // on top of the backing disc above.
                    Positioned(
                      left: dipCenter.dx - personaRadius,
                      top: dipCenter.dy - personaRadius,
                      child: PersonaPhoto(
                        photoUrl: widget.personaPhotoUrl,
                        score: widget.posterScore ?? 0,
                      ),
                    ),

                    // Reaction-entry badge — tucked at the persona icon's
                    // bottom-right edge, on top of everything below it.
                    // The single entry point into the BeReal-style
                    // reaction flow; also doubles as the "you reacted"
                    // indicator once set.
                    Positioned(
                      left: entryBadgeCenter.dx - entryBadgeRadius,
                      top: entryBadgeCenter.dy - entryBadgeRadius,
                      child: _ReactionEntryBadge(
                        size: _kEntryBadgeSize,
                        allowFaceReactions: widget.allowFaceReactions,
                        myFaceReaction: reactions.myFaceReaction,
                        myEmoji: reactions.myEmoji,
                        uploading: uploadingFaceReaction,
                        onTap: () => widget.allowFaceReactions
                            ? openFaceCapture(widget.postId)
                            : toggleEmojiPicker(),
                      ),
                    ),

                    // Emoji picker opens upward from the icons it belongs
                    // to — floats above the image's own bounds.
                    if (showEmojiPicker)
                      Positioned(
                        right: 10, bottom: 44,
                        child: ReactionPickerPopup(
                          onSelect: (emoji) => onEmojiSelected(widget.postId, emoji),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 3. Below the image: two distinct glass surfaces — others'
            // face reactions (Friends/Everyone only — never on Anonymous),
            // then comments, stacked with a gap between them rather than
            // merged into one block.
            if (showFaceReactions)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: ReactionRow(
                  reactions: otherFaceReactions,
                  isLoading: loadingSummary && summary == null,
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, showFaceReactions ? 8 : 10, 16, 12),
              child: RepaintBoundary(
                child: GlassBox(
                  borderRadius: 16,
                  blur: 16,
                  child: CommentRow(
                    commentCount: widget.commentCount,
                    onCommentTap: widget.onCommentTap,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.hasError) {
      return Container(
        color: AppColors.cardSurface,
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 40),
        ),
      );
    }
    if (widget.isLoading) {
      return Shimmer.fromColors(
        baseColor: AppColors.cardSurface,
        highlightColor: AppColors.cardSurface.withValues(alpha: 0.5),
        child: Container(color: Colors.white),
      );
    }
    return widget.media;
  }
}

// ---------------------------------------------------------------------------
// Reaction-entry badge — the single, dedicated affordance for reacting to
// THIS post, BeReal-style. Sits tucked at the persona icon's bottom-right
// edge (see the placement rationale in the file-level doc comment above).
//
// Idle: a small glyph — camera for feeds that allow face reactions
// (Friends/Everyone), add-reaction for the Anonymous feed (emoji-only).
// Uploading: a small spinner, replacing the glyph while a captured selfie
// is being saved.
// Reacted: the glyph is replaced by a tiny thumbnail of the viewer's own
// reaction — their selfie (face reactions) or their emoji (Anonymous) —
// reusing the same circular-thumbnail language ReactionRow uses for
// everyone else's reactions below the image, just scaled down to fit a
// corner badge instead of a full row entry.
// ---------------------------------------------------------------------------

class _ReactionEntryBadge extends StatelessWidget {
  const _ReactionEntryBadge({
    required this.size,
    required this.allowFaceReactions,
    required this.myFaceReaction,
    required this.myEmoji,
    required this.uploading,
    required this.onTap,
  });

  final double size;
  final bool allowFaceReactions;
  final FaceReaction? myFaceReaction;
  final String? myEmoji;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardSurface,
          border: Border.all(color: AppColors.background, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 4,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: Center(child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    if (uploading) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white70),
      );
    }
    if (allowFaceReactions && myFaceReaction != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: myFaceReaction!.photoUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const Icon(Icons.face_retouching_natural, size: 11, color: Colors.white70),
        ),
      );
    }
    if (!allowFaceReactions && myEmoji != null) {
      return Text(myEmoji!, style: const TextStyle(fontSize: 11));
    }
    return Icon(
      allowFaceReactions ? Icons.camera_alt_rounded : Icons.add_reaction_outlined,
      size: 11,
      color: Colors.white70,
    );
  }
}

// ---------------------------------------------------------------------------
// Cuts a circular notch out of a rounded rect near its top-left corner, so
// the persona icon (and its background disc, in the widget above) appears
// embedded in the corner rather than floating on top of it. [notchCenter]
// is NOT locked to the box's mathematical (0,0) point — the box's own
// corner is already rounded, so the visible content recedes away from
// (0,0) diagonally, and a notch centered exactly there ends up mostly over
// whatever is behind the box rather than over the box's own content. See
// PhotoPostCard's _kDipOffsetX/_kDipOffsetY. Path.combine(difference, ...)
// does the boolean subtraction — this is the only way to get a true
// "bite taken out of the corner" look; simply drawing a circle on top of
// an unmodified rounded rect would just be a circle overlapping a
// rectangle, not a matched notch.
// ---------------------------------------------------------------------------

class _TopLeftNotchClipper extends CustomClipper<Path> {
  const _TopLeftNotchClipper({
    required this.cornerRadius,
    required this.notchCenter,
    required this.notchRadius,
  });
  final double cornerRadius;
  final Offset notchCenter;
  final double notchRadius;

  @override
  Path getClip(Size size) {
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cornerRadius)));
    final notch = Path()..addOval(Rect.fromCircle(center: notchCenter, radius: notchRadius));
    return Path.combine(PathOperation.difference, base, notch);
  }

  @override
  bool shouldReclip(covariant _TopLeftNotchClipper oldClipper) =>
      oldClipper.cornerRadius != cornerRadius ||
      oldClipper.notchCenter != notchCenter ||
      oldClipper.notchRadius != notchRadius;
}
