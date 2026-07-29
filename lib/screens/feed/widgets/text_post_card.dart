import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../services/reaction_service.dart';
import '../../../widgets/reaction_picker_popup.dart';
import 'post_card_shared.dart';

// ---------------------------------------------------------------------------
// TextPostCard — the compact card for posts with NO photo. Built to
// POST_CARD_SPEC.md (project root) — anonymous posts only. Mirrors
// PhotoPostCard's ordering minus the image:
//   1. Text block: the ghost prompt question (semi-bold, emphasized) and
//      the poster's caption (regular, dimmer), left-aligned.
//   2. Identity row: the anon persona icon (tier-glow ring) + branch tag.
//      No name, ever.
//   3. Reaction (heart) + ping — no image to overlay these on here, so
//      they sit in their own row at normal spacing.
//   4. "View all N comments".
//
// A text-only post is a ghost-prompt reply by construction, so
// [promptQuestion] is required (unlike PhotoPostCard, where it's optional).
// No face-reaction row here — this card is Anonymous-only (per spec, that
// feed is emoji-only reactions), and there's no photo for BeReal-style
// selfie reactions to attach to anyway.
//
// Split out from PhotoPostCard rather than being a conditional branch of
// one shared widget, because the two have fundamentally different
// proportions: PhotoPostCard fills whatever height its caller gives it (the
// photo IS the card); TextPostCard must size itself to its own content.
//
// That distinction is also why this is wrapped in Align: this card lives
// inside AnonymousTab's PageView, which hands each page TIGHT, full-page-
// height constraints. A Column can't refuse a tight height from its parent
// no matter what mainAxisSize says — its decorated background would
// stretch to fill the whole page even though the content only occupies the
// top of it. Align gives its child LOOSE constraints regardless of what
// constraints Align itself receives, so the actual decorated card sizes to
// its own content, and only the (transparent) leftover space below it in
// the page is empty.
// ---------------------------------------------------------------------------

class TextPostCard extends StatefulWidget {
  const TextPostCard({
    super.key,
    required this.postId,
    required this.allowFaceReactions,
    required this.pingContext,
    this.pingTargetName,
    this.pingGlass = true,
    this.personaPhotoUrl,
    this.posterScore,
    this.branch,
    required this.promptQuestion,
    this.answerText,
    this.commentCount = 0,
    this.onCommentTap,
    this.cornerRadius = 20,
  });

  /// Reactions are fetched/written keyed on this — must be stable and
  /// unique per post.
  final String postId;

  /// True for Friends/Everyone feeds, false for the Anonymous feed. In
  /// practice this card is Anonymous-only (Friends/Everyone posts always
  /// have a photo), but the param is kept for symmetry with PhotoPostCard.
  final bool allowFaceReactions;

  /// Passed straight through to showPingPromptSheet.
  final PingContext pingContext;
  final String? pingTargetName;
  final bool pingGlass;

  /// The poster's anon persona photo — never the real profile photo. Null
  /// falls back to a plain silhouette glyph inside the glow ring.
  final String? personaPhotoUrl;

  /// Drives the persona icon's tier-glow ring color/intensity.
  final int? posterScore;

  /// Department/branch tag (e.g. "CSE"), shown beside the persona icon.
  final String? branch;

  /// The ghost prompt this post is replying to — shown in the text block.
  final String promptQuestion;

  /// The poster's written caption, shown directly below the question in a
  /// dimmer, ghosted weight.
  final String? answerText;

  final int commentCount;
  final VoidCallback? onCommentTap;

  final double cornerRadius;

  @override
  State<TextPostCard> createState() => _TextPostCardState();
}

class _TextPostCardState extends State<TextPostCard> with PostReactions<TextPostCard> {
  @override
  void initState() {
    super.initState();
    loadReactionSummary(widget.postId);
  }

  @override
  void didUpdateWidget(TextPostCard old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId) loadReactionSummary(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();

    return Align(
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.cornerRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Text block — ghost prompt question + caption.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) => GhostPromptBlock(
                    question: widget.promptQuestion,
                    answer: widget.answerText,
                    maxWidth: constraints.maxWidth,
                  ),
                ),
              ),

              // 2. Identity row — persona icon (tier-glow ring) + branch
              // tag. No name, ever.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PersonaPhoto(
                      photoUrl: widget.personaPhotoUrl,
                      score: widget.posterScore ?? 0,
                    ),
                    if (widget.branch != null) ...[
                      const SizedBox(width: 8),
                      BranchTag(branch: widget.branch!),
                    ],
                  ],
                ),
              ),

              // 3. Reaction + ping — no image here, so just a normal row
              // below the identity row, not overlaid on anything.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TopActionIcons(
                        liked: reactions.myEmoji != null,
                        likeCount: reactions.totalEmojiCount,
                        uploadingFaceReaction: uploadingFaceReaction,
                        onReactionTap: toggleEmojiPicker,
                        onReactionLongPress:
                            widget.allowFaceReactions ? () => openFaceCapture(widget.postId) : null,
                        onPingTap: () => openPing(
                          pingContext: widget.pingContext,
                          targetName: widget.pingTargetName,
                          glass: widget.pingGlass,
                        ),
                        iconColor: kClusterGray,
                      ),
                    ),
                    if (showEmojiPicker)
                      Positioned(
                        right: 0, bottom: 34,
                        child: ReactionPickerPopup(
                          onSelect: (emoji) => onEmojiSelected(widget.postId, emoji),
                        ),
                      ),
                  ],
                ),
              ),

              // 4. Comments.
              CommentRow(
                commentCount: widget.commentCount,
                onCommentTap: widget.onCommentTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
