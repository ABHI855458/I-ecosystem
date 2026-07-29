import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants.dart';
import '../../../core/glass.dart';
import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../services/current_user_service.dart';
import '../../../services/reaction_service.dart';
import '../../../shared/score_tier.dart';
import 'face_reaction_capture.dart';

// ---------------------------------------------------------------------------
// Shared building blocks for PhotoPostCard and TextPostCard
// (photo_post_card.dart / text_post_card.dart), per POST_CARD_SPEC.md. This
// file holds what's genuinely identical between the two card widgets: the
// reaction/ping state machine (PostReactions) and the small presentational
// pieces (PersonaPhoto, BranchTag, GhostPromptBlock, TopActionIcons,
// CommentRow, WordSafeText). Face-reaction thumbnails (BeReal-style) are
// NOT part of TopActionIcons anymore — per spec they're their own row below
// the image, using ReactionRow directly (see photo_post_card.dart).
// ---------------------------------------------------------------------------

/// Reaction + ping state, shared by both card widgets so the ~150 lines of
/// ReactionService/Supabase plumbing isn't duplicated across two State
/// classes. Mixed onto `State<T>`, so it already has `context`/`setState`/
/// `mounted` — callers only need to supply the postId (and ping details)
/// per call, since those live on the concrete widget, not the mixin.
mixin PostReactions<T extends StatefulWidget> on State<T> {
  ReactionSummary? summary;
  bool loadingSummary = false;
  bool showEmojiPicker = false;
  bool uploadingFaceReaction = false;

  Future<void> loadReactionSummary(String postId) async {
    setState(() => loadingSummary = true);
    try {
      final result = await ReactionService.instance.fetchSummary(postId);
      if (!mounted) return;
      setState(() {
        summary = result;
        loadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingSummary = false);
      // Reaction load failure isn't fatal to the card — it just shows the
      // bare add-reaction icon with no count, same as the empty state.
    }
  }

  Future<void> onEmojiSelected(String postId, String emoji) async {
    setState(() => showEmojiPicker = false);
    final previous = summary ?? const ReactionSummary.empty();
    final removing = previous.myEmoji == emoji;

    final counts = Map<String, int>.from(previous.emojiCounts);
    if (previous.myEmoji != null) {
      final prevCount = (counts[previous.myEmoji!] ?? 1) - 1;
      if (prevCount <= 0) {
        counts.remove(previous.myEmoji);
      } else {
        counts[previous.myEmoji!] = prevCount;
      }
    }
    if (!removing) counts[emoji] = (counts[emoji] ?? 0) + 1;

    // Mirror the same swap on the individual-entries list — this is what
    // the Anonymous chip row (ReactionRow.emojiOnly) actually renders from,
    // not the aggregate counts above.
    var myUserId = previous.myUserId;
    if (myUserId == null) {
      try {
        myUserId = await CurrentUserService.instance.resolveId();
      } catch (_) {
        // Shouldn't happen (you can't react without being signed in), but
        // fall through to a no-op entries list rather than throw here.
      }
    }
    final entries = previous.emojiReactions.where((e) => e.userId != myUserId).toList();
    if (!removing && myUserId != null) {
      entries.add(EmojiReactionEntry(userId: myUserId, emoji: emoji));
    }

    setState(() {
      summary = ReactionSummary(
        emojiCounts: counts,
        myEmoji: removing ? null : emoji,
        emojiReactions: entries,
        faceReactions: previous.faceReactions,
        myFaceReaction: previous.myFaceReaction,
        myUserId: myUserId,
      );
    });

    HapticFeedback.selectionClick();
    try {
      if (removing) {
        await ReactionService.instance.removeEmojiReaction(postId);
      } else {
        await ReactionService.instance.setEmojiReaction(postId: postId, emoji: emoji);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => summary = previous);
      showGlassToast(context, "Couldn't save your reaction.", isError: true);
    }
  }

  Future<void> openFaceCapture(String postId) async {
    HapticFeedback.selectionClick();
    final result = await showModalBottomSheet<FaceReactionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FaceReactionCapture(
        onFallbackToEmoji: () => setState(() => showEmojiPicker = true),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => uploadingFaceReaction = true);
    try {
      await ReactionService.instance.setFaceReaction(
        postId: postId,
        selfie: result.selfie,
        emoji: result.emoji,
      );
      await loadReactionSummary(postId); // photo_url comes from storage — needs a real reload, not an optimistic guess
    } catch (_) {
      if (!mounted) return;
      showGlassToast(context, "Couldn't upload your reaction.", isError: true);
    } finally {
      if (mounted) setState(() => uploadingFaceReaction = false);
    }
  }

  void toggleEmojiPicker() {
    HapticFeedback.selectionClick();
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  void openPing({required PingContext pingContext, String? targetName, bool glass = true}) {
    HapticFeedback.lightImpact();
    showPingPromptSheet(context, targetName: targetName ?? 'someone', pingContext: pingContext, glass: glass);
  }
}

// ---------------------------------------------------------------------------
// Persona icon — the anon persona photo (Profile > Anon persona photo),
// wrapped in the same ScoreGlowRing tier-glow treatment used everywhere
// else in the app as the compact score/tier signal. Never the real profile
// photo; a null url falls back to a plain silhouette glyph rather than
// initials, since initials can hint at a real name. Sits as a small badge
// in the card's top-left corner — not overlapping into a photo's rounded
// edge, just a simple corner marker.
// ---------------------------------------------------------------------------

class PersonaPhoto extends StatelessWidget {
  const PersonaPhoto({super.key, required this.photoUrl, required this.score});
  final String? photoUrl;
  final int score;

  static const double kSize = 30;

  @override
  Widget build(BuildContext context) {
    return ScoreGlowRing(
      score: score,
      size: kSize,
      borderWidth: 1.75,
      child: Container(
        color: AppColors.cardSurface,
        child: photoUrl == null
            ? const Center(
                child: Icon(Icons.theater_comedy_outlined, color: AppColors.textMuted, size: 15),
              )
            : CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const SizedBox.shrink(),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(Icons.theater_comedy_outlined, color: AppColors.textMuted, size: 15),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Branch/department tag — small ghosted pill (e.g. "CSE"), part of the
// identity row beside the persona icon.
// ---------------------------------------------------------------------------

class BranchTag extends StatelessWidget {
  const BranchTag({super.key, required this.branch});
  final String branch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        branch,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WordSafeText — like Text with maxLines + TextOverflow.ellipsis, except
// the truncation only ever falls on a word boundary. Flutter's built-in
// TextOverflow.ellipsis clips at the pixel/character level once the text
// no longer fits, which can (and does) cut mid-word. This lays the text out
// with a TextPainter at [maxWidth]; if it overflows [maxLines], it finds
// where the last visible line ends, backs up to the previous space (never
// a partial word), and appends "…" to that shorter, already-fitting
// prefix — rather than iteratively re-testing "words + ellipsis" candidates
// against maxLines (which can itself shift line-wrapping in ways that
// don't match the final rendered Text exactly).
// ---------------------------------------------------------------------------

class WordSafeText extends StatelessWidget {
  const WordSafeText(
    this.text, {
    super.key,
    required this.style,
    required this.maxLines,
    required this.maxWidth,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);

    if (!painter.didExceedMaxLines) {
      return Text(text, style: style);
    }

    // Locate the last visible character (bottom-right of the clipped,
    // maxLines-tall layout), then walk back to the previous space so the
    // cut never lands mid-word.
    final endPosition = painter.getPositionForOffset(Offset(maxWidth, painter.height - 1));
    var cutoff = endPosition.offset.clamp(0, text.length);
    while (cutoff > 0 && text[cutoff - 1] != ' ') {
      cutoff--;
    }
    final truncated = (cutoff > 0 ? text.substring(0, cutoff) : text.substring(0, endPosition.offset)).trimRight();

    return Text(truncated.isEmpty ? '…' : '$truncated…', style: style);
  }
}

// ---------------------------------------------------------------------------
// GhostPromptBlock — the ghost prompt question the poster was replying to,
// small and emphasized, with their written answer/caption directly below
// it in a dimmer, ghosted weight. Sits beside the persona icon on both
// cards. Deliberately no pulsing accent bar or IntrinsicHeight here (an
// earlier pass had one) — LayoutBuilder (used by WordSafeText's caller)
// cannot participate in intrinsic-dimension queries, and nesting one
// inside IntrinsicHeight corrupted Flutter's rendering pipeline outright.
// Keeping this plain avoids that hazard entirely.
// ---------------------------------------------------------------------------

class GhostPromptBlock extends StatelessWidget {
  const GhostPromptBlock({
    super.key,
    required this.question,
    this.answer,
    required this.maxWidth,
  });

  final String question;
  final String? answer;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final answerText = answer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WordSafeText(
          question,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.3,
          ),
          maxLines: 2,
          maxWidth: maxWidth,
        ),
        if (answerText != null && answerText.isNotEmpty) ...[
          const SizedBox(height: 3),
          WordSafeText(
            answerText,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.55),
              height: 1.3,
            ),
            maxLines: 4,
            maxWidth: maxWidth,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top action icons — reaction (heart) + ping ONLY, per spec. Comment lives
// in its own row (CommentRow) below; face-reaction thumbnails live in their
// own BeReal-style row below the image (see photo_post_card.dart) — neither
// is bundled into this cluster anymore. Thin outline icons, monochrome
// except the reacted heart (colored). [iconShadows] is for use over
// arbitrary photo content (PhotoPostCard overlays these directly on the
// image per spec, and the image itself must stay full-opacity/undimmed —
// no scrim — so legibility comes from a glyph drop-shadow instead of
// darkening the photo).
// ---------------------------------------------------------------------------

const Color kClusterGray = Color(0xFF8E8E93);
const double kClusterIconSize = 18;
const double kClusterGap = 14;

class TopActionIcons extends StatelessWidget {
  const TopActionIcons({
    super.key,
    required this.liked,
    required this.likeCount,
    required this.uploadingFaceReaction,
    required this.onReactionTap,
    required this.onReactionLongPress,
    required this.onPingTap,
    this.iconColor,
    this.iconShadows,
  });

  final bool liked;
  final int likeCount;
  final bool uploadingFaceReaction;
  final VoidCallback onReactionTap;
  final VoidCallback? onReactionLongPress;

  final VoidCallback onPingTap;

  /// Defaults to white-on-scrim (for use over media); pass kClusterGray
  /// explicitly when placing these over a plain card background instead.
  final Color? iconColor;

  /// Optional drop-shadow so the glyphs stay legible over bright photo
  /// content without needing to dim the image itself.
  final List<Shadow>? iconShadows;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? Colors.white.withValues(alpha: 0.90);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlainIconButton(icon: Icons.send_outlined, onTap: onPingTap, color: color, shadows: iconShadows),
        const SizedBox(width: kClusterGap),
        _HeartTapTarget(
          liked: liked,
          count: likeCount,
          uploading: uploadingFaceReaction,
          onTap: onReactionTap,
          onLongPress: onReactionLongPress,
          color: color,
          shadows: iconShadows,
        ),
      ],
    );
  }
}

class _HeartTapTarget extends StatelessWidget {
  const _HeartTapTarget({
    required this.liked,
    required this.count,
    required this.uploading,
    required this.onTap,
    required this.onLongPress,
    this.color = kClusterGray,
    this.shadows,
  });

  final bool liked;
  final int count;
  final bool uploading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: uploading
          ? SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: kClusterIconSize,
                  color: liked ? AppColors.errorRed : color,
                  shadows: shadows,
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: liked ? AppColors.errorRed : color,
                      shadows: shadows,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _PlainIconButton extends StatelessWidget {
  const _PlainIconButton({
    required this.icon,
    required this.onTap,
    this.color = kClusterGray,
    this.shadows,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(icon, size: kClusterIconSize, color: color, shadows: shadows),
    );
  }
}

// ---------------------------------------------------------------------------
// Comment row — its own row below the card's content (not overlaid).
// Instagram-style "View all N comments" summary chosen over a bare count
// badge: it doubles as the tap target into the existing comment sheet and
// reads cleaner than a raw number. No timestamp — this app dropped those
// from the design entirely.
// ---------------------------------------------------------------------------

class CommentRow extends StatelessWidget {
  const CommentRow({
    super.key,
    required this.commentCount,
    required this.onCommentTap,
  });

  final int commentCount;
  final VoidCallback? onCommentTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GestureDetector(
        onTap: onCommentTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mode_comment_outlined, size: 15, color: kClusterGray),
            const SizedBox(width: 6),
            Text(
              commentCount > 0 ? 'View all $commentCount comments' : 'Add a comment…',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: kClusterGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
