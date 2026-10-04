import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
import 'post_card_shared.dart';
import 'reaction_row.dart';

// ---------------------------------------------------------------------------
// TextPostCard — the compact card for posts with NO photo. Anonymous posts
// only. Mirrors PhotoPostCard's ordering minus the image:
//   1. Text block: the ghost prompt question (semi-bold, emphasized) and
//      the poster's caption (readable, high-contrast), left-aligned. No
//      focus-driven fade here (this card has no scroll-reveal focus value
//      wired up), so both render at full opacity always.
//   2. Identity row: just the anon persona icon (plain circle). No name, no
//      branch/community tag, ever.
//   3. Reaction + ping + comments, side by side, below everything else. No
//      per-post bell anywhere on this card — that's a single page-level
//      control now (MainShell). No pin control here either: pinning is a
//      named-person concept, and anonymous posts have no identity to pin —
//      see profile_screen.dart for pinning a Friends profile instead.
//
// A text-only post is a ghost-prompt reply by construction, so
// [promptQuestion] is required (unlike PhotoPostCard, where it's optional).
// No face-reaction row here — this card is Anonymous-only (that feed is
// emoji-only reactions), and there's no photo for BeReal-style selfie
// reactions to attach to anyway.
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
    this.onSentPrompt,
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
  /// have a photo), but it still drives the quick-react badge/heart the
  /// same way PhotoPostCard's does, for symmetry.
  final bool allowFaceReactions;

  /// Passed straight through to showPingPromptSheet.
  final PingContext pingContext;
  final String? pingTargetName;

  /// Forwarded straight to showPingPromptSheet — see PhotoPostCard's own
  /// doc on this field for why it's optional.
  final PingSendHandler? onSentPrompt;

  /// The poster's anon persona photo — never the real profile photo. Null
  /// falls back to a plain silhouette glyph.
  final String? personaPhotoUrl;

  /// Kept on the API for a possible future compact status signal.
  final int? posterScore;

  /// Department/branch (e.g. "CSE") — kept on the API but no longer
  /// rendered anywhere on this card (individual anonymous posts never show
  /// a community tag).
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

class _TextPostCardState extends State<TextPostCard>
    with PostReactions<TextPostCard> {
  @override
  void initState() {
    super.initState();
    loadReactionSummary(widget.postId);
    unawaited(loadMyRealmojiReaction(widget.postId));
  }

  @override
  void didUpdateWidget(TextPostCard old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId) {
      loadReactionSummary(widget.postId);
      unawaited(loadMyRealmojiReaction(widget.postId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();

    // Others' emoji reactions only — the viewer's own is shown on the
    // PostReactionCorner entry button instead, same reasoning
    // PhotoPostCard's own computation uses (see that file's build method).
    final otherEmojiEntries = <MapEntry<String, int>>[];
    reactions.emojiCounts.forEach((emoji, count) {
      final othersCount = reactions.myEmoji == emoji ? count - 1 : count;
      if (othersCount > 0) otherEmojiEntries.add(MapEntry(emoji, othersCount));
    });
    otherEmojiEntries.sort((a, b) => b.value.compareTo(a.value));
    final showReactionsRow =
        otherEmojiEntries.isNotEmpty || (loadingSummary && summary == null);

    return Align(
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.cornerRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0. Top corner controls — removed. This card is Anonymous-
              // only (allowFaceReactions is always false here), and
              // PostTopControlsRow now renders nothing in that case (no
              // per-post bell anymore — that's page-level only, see
              // MainShell — and no reaction-library corner on this feed
              // either), so the row was always empty; the wrapping Padding
              // is gone too rather than reserving blank top space for it.

              // 1. Text block — ghost prompt question + caption.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) => GhostPromptBlock(
                    question: widget.promptQuestion,
                    answer: widget.answerText,
                    maxWidth: constraints.maxWidth,
                  ),
                ),
              ),

              // 2. Identity row — just the persona icon (plain circle). No
              // name, no branch/community tag, ever.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: PersonaPhoto(
                  photoUrl: widget.personaPhotoUrl,
                  score: widget.posterScore ?? 0,
                ),
              ),

              // 3. Reaction + ping + comments, side by side — same
              // "adjacent, not stacked" rule PhotoPostCard's own
              // _ReactionsAndCommentsRow follows. This card is Anonymous-
              // only in practice, so there's no face-reaction branch here —
              // just the feed's reaction entry point (PostReactionCorner,
              // same preset-tray widget Friends/Everyone uses, just
              // instantiated with allowFaceReactions: false), ping, plus
              // others' emoji reactions.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: _TextReactionsAndCommentsRow(
                  showReactionsRow: showReactionsRow,
                  otherEmojiEntries: otherEmojiEntries,
                  reactionsLoading: loadingSummary && summary == null,
                  myEmoji: myRealmojiReaction?.glyph,
                  uploadingReaction: uploadingFaceReaction,
                  showReactionTray: showPresetTray,
                  onReactionTap: openReactionTray,
                  onReactionClose: closePresetTray,
                  onReactionSelect: (preset) =>
                      selectPreset(widget.postId, preset),
                  onReactionAddNew: () => openAddPresetFlow(
                    widget.postId,
                    allowFaceReactions: false,
                  ),
                  onReactionCaptureRealmoji: (type) => captureRealmojiAndReact(
                    widget.postId,
                    ReactionPresetCategory.anonymous,
                    type,
                  ),
                  onPingTap: () => openPing(
                    pingContext: widget.pingContext,
                    targetName: widget.pingTargetName,
                    onSentPrompt: widget.onSentPrompt,
                  ),
                  commentCount: widget.commentCount,
                  onCommentTap: widget.onCommentTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TextReactionsAndCommentsRow — TextPostCard's version of PhotoPostCard's
// _ReactionsAndCommentsRow (not shared directly: that one's private to
// photo_post_card.dart, and this card never needs its face-reaction
// branch since it's Anonymous-only in practice).
// ---------------------------------------------------------------------------

class _TextReactionsAndCommentsRow extends StatelessWidget {
  const _TextReactionsAndCommentsRow({
    required this.showReactionsRow,
    required this.otherEmojiEntries,
    required this.reactionsLoading,
    required this.myEmoji,
    required this.uploadingReaction,
    required this.showReactionTray,
    required this.onReactionTap,
    required this.onReactionClose,
    required this.onReactionSelect,
    required this.onReactionAddNew,
    required this.onReactionCaptureRealmoji,
    required this.onPingTap,
    required this.commentCount,
    required this.onCommentTap,
  });

  final bool showReactionsRow;
  final List<MapEntry<String, int>> otherEmojiEntries;
  final bool reactionsLoading;
  final String? myEmoji;
  final bool uploadingReaction;
  final bool showReactionTray;
  final VoidCallback onReactionTap;
  final VoidCallback onReactionClose;
  final ValueChanged<ReactionPreset> onReactionSelect;
  final VoidCallback onReactionAddNew;
  final ValueChanged<RealmojiType> onReactionCaptureRealmoji;
  final VoidCallback onPingTap;
  final int commentCount;
  final VoidCallback? onCommentTap;

  static const double _kThumbSize = 28;

  @override
  Widget build(BuildContext context) {
    return LightSurfaceBox(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            PostReactionCorner(
              allowFaceReactions: false,
              myFaceReaction: null,
              myEmoji: myEmoji,
              uploading: uploadingReaction,
              onTap: onReactionTap,
              onClose: onReactionClose,
              showTray: showReactionTray,
              category: ReactionPresetCategory.anonymous,
              onSelect: onReactionSelect,
              onAddNew: onReactionAddNew,
              onCaptureRealmoji: onReactionCaptureRealmoji,
              size: _kThumbSize,
            ),
            const SizedBox(width: 8),
            PostPingButton(onTap: onPingTap, size: _kThumbSize),
            const SizedBox(width: 10),
            if (showReactionsRow) ...[
              Expanded(
                child: SizedBox(
                  height: _kThumbSize,
                  child: EmojiReactionRow(
                    entries: otherEmojiEntries,
                    isLoading: reactionsLoading,
                    thumbSize: _kThumbSize,
                    embedded: true,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ],
            GestureDetector(
              onTap: onCommentTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mode_comment_outlined,
                    size: 15,
                    color: kClusterGray,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    commentCount > 0
                        ? 'View all $commentCount comments'
                        : 'Add a comment…',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kClusterGray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
