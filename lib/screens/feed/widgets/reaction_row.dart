import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants.dart';
import '../../../core/glass.dart';
import '../../../services/reaction_service.dart';

// ---------------------------------------------------------------------------
// ReactionRow — horizontally-scrollable row of OTHER PEOPLE's reactions,
// below the image. Two constructors, matching the two shapes the app's two
// feed types produce (see PostCard_SPEC.md + PhotoPostCard's allowFaceReactions
// branch) — deliberately NOT one constructor with nullable params for both
// shapes, so it's structurally impossible to (for example) hand the
// Anonymous path a face-photo thumbnail or an identity-reveal callback:
//
//   • ReactionRow.facePhotos — Friends/Everyone feeds. BeReal-style circular
//     selfie thumbnails, each with a small emoji badge overlaid bottom-right
//     (RealMoji style). Optionally tappable (onReactionTap) to reveal who a
//     reaction is from — this is the ONLY constructor that ever exposes a
//     tap handler, because identity reveal must never be reachable from the
//     Anonymous path.
//   • ReactionRow.emojiOnly — the Anonymous feed. Plain emoji chips, no
//     photos, ever. Not tappable — there is no callback parameter to wire
//     one up with, so a caller can't accidentally reveal identity here even
//     by mistake.
//
// The viewer's own reaction is not part of either list (PhotoPostCard
// filters it out before passing [reactions] in) — that one is shown on the
// post itself, via the reaction-entry badge tucked at the persona icon's
// edge.
//
// Pure display: takes the already-fetched list, fetches nothing itself
// (identity resolution, when used, is the caller's job — see
// PhotoPostCard's onReactionTap wiring). CachedNetworkImage gives disk+
// memory caching for free (already the caching mechanism used everywhere
// else in this codebase — avatars, memory photos, feed images), which is
// what keeps this from janking feed scroll on re-render: repeat scrolls hit
// cache, not the network.
//
// Wrapped in a GlassBox (frosted, blurred) — its own distinct surface,
// sitting above the (also glass, separately boxed) comment row below it
// rather than merged into one shared block. RepaintBoundary isolates the
// backdrop blur from the rest of the card's rebuilds (emoji-picker toggles,
// upload spinners, etc.) so those setState calls don't force BackdropFilter
// to redo its blur pass — that's what keeps this cheap enough not to jank
// feed scroll.
// ---------------------------------------------------------------------------

enum _ReactionRowMode { facePhotos, emojiOnly }

class ReactionRow extends StatelessWidget {
  const ReactionRow.facePhotos({
    super.key,
    required List<FaceReaction> reactions,
    this.isLoading = false,
    this.thumbSize = 30,
    this.onReactionTap,
  })  : _mode = _ReactionRowMode.facePhotos,
        _faceReactions = reactions,
        _emojiEntries = const [];

  const ReactionRow.emojiOnly({
    super.key,
    required List<EmojiReactionEntry> reactions,
    this.isLoading = false,
    this.thumbSize = 30,
  })  : _mode = _ReactionRowMode.emojiOnly,
        _emojiEntries = reactions,
        _faceReactions = const [],
        onReactionTap = null;

  final _ReactionRowMode _mode;
  final List<FaceReaction> _faceReactions;
  final List<EmojiReactionEntry> _emojiEntries;
  final bool isLoading;
  final double thumbSize;

  /// Friends/Everyone only (facePhotos mode). Never present on
  /// ReactionRow.emojiOnly — the Anonymous feed must never reveal who's
  /// behind a reaction, tap or otherwise.
  final void Function(FaceReaction reaction)? onReactionTap;

  bool get _isEmpty =>
      _mode == _ReactionRowMode.facePhotos ? _faceReactions.isEmpty : _emojiEntries.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return RepaintBoundary(
        child: GlassBox(
          borderRadius: 16,
          blur: 16,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: _ShimmerRow(thumbSize: thumbSize),
        ),
      );
    }
    // Empty state: no glass box at all — nothing to hold, so no surface to
    // show. The comment row below renders on its own regardless.
    if (_isEmpty) return const SizedBox.shrink();

    final itemCount =
        _mode == _ReactionRowMode.facePhotos ? _faceReactions.length : _emojiEntries.length;

    return RepaintBoundary(
      child: GlassBox(
        borderRadius: 16,
        blur: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SizedBox(
          height: thumbSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) => _mode == _ReactionRowMode.facePhotos
                ? _FaceReactionThumb(
                    reaction: _faceReactions[i],
                    size: thumbSize,
                    onTap: onReactionTap == null ? null : () => onReactionTap!(_faceReactions[i]),
                  )
                : _EmojiChip(entry: _emojiEntries[i], size: thumbSize),
          ),
        ),
      ),
    );
  }
}

class _FaceReactionThumb extends StatelessWidget {
  const _FaceReactionThumb({required this.reaction, required this.size, this.onTap});
  final FaceReaction reaction;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.42;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: reaction.photoUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: AppColors.cardSurface,
                  width: size,
                  height: size,
                ),
                errorWidget: (_, _, _) => Container(
                  width: size,
                  height: size,
                  color: AppColors.cardSurface,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: size * 0.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
                child: Text(
                  reaction.emoji,
                  style: TextStyle(fontSize: badgeSize * 0.62),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anonymous feed's reaction chip — a plain emoji in a circular glass-toned
// badge, deliberately styled to echo _FaceReactionThumb's circular footprint
// (same [size], same row rhythm) without ever carrying a photo. No
// GestureDetector, no onTap — nothing here to wire an identity reveal onto
// even by mistake.
// ---------------------------------------------------------------------------

class _EmojiChip extends StatelessWidget {
  const _EmojiChip({required this.entry, required this.size});
  final EmojiReactionEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.cardSurface,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(entry.emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow({required this.thumbSize});
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thumbSize,
      child: Shimmer.fromColors(
        baseColor: AppColors.cardSurface,
        highlightColor: AppColors.cardSurface.withValues(alpha: 0.4),
        child: Row(
          children: List.generate(
            3,
            (i) => Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
              child: Container(
                width: thumbSize,
                height: thumbSize,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
