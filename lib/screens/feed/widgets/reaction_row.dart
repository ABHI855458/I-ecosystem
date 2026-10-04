import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants.dart';
import '../../../core/glass.dart';
import '../../../services/reaction_service.dart';
import 'post_card_shared.dart' show LightSurfaceBox;

// ---------------------------------------------------------------------------
// ReactionRow — horizontally-scrollable OTHER PEOPLE's face-reaction
// thumbnails, each a circular selfie with a small emoji badge overlaid
// bottom-right (BeReal RealMoji style). The viewer's own reaction is not
// part of this list (PhotoPostCard filters it out before passing
// [reactions] in) — that one is shown on the post itself, via the
// reaction-entry badge tucked at the persona icon's edge.
//
// Pure display: takes the already-fetched list, fetches nothing itself.
// CachedNetworkImage gives disk+memory caching for free (already the
// caching mechanism used everywhere else in this codebase — avatars,
// memory photos, feed images), which is what keeps this from janking feed
// scroll on re-render: repeat scrolls hit cache, not the network.
//
// Wrapped in a GlassBox (frosted, blurred) — its own distinct surface,
// sitting above the (also glass, separately boxed) comment row below it
// rather than merged into one shared block. RepaintBoundary isolates the
// backdrop blur from the rest of the card's rebuilds (emoji-picker toggles,
// upload spinners, etc.) so those setState calls don't force BackdropFilter
// to redo its blur pass — that's what keeps this cheap enough not to jank
// feed scroll.
// ---------------------------------------------------------------------------

class ReactionRow extends StatelessWidget {
  const ReactionRow({
    super.key,
    required this.reactions,
    this.isLoading = false,
    this.thumbSize = 30,
    this.embedded = false,
  });

  final List<FaceReaction> reactions;
  final bool isLoading;
  final double thumbSize;

  /// True when the caller already provides the surrounding glass surface
  /// (e.g. sitting beside the comment row in one shared LightSurfaceBox/
  /// GlassBox) — skips this widget's own box/padding and returns just the
  /// scrollable thumbnail list, so the two don't nest one glass surface
  /// inside another.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      final shimmer = _ShimmerRow(thumbSize: thumbSize);
      if (embedded) return shimmer;
      return RepaintBoundary(
        child: GlassBox(
          borderRadius: 16,
          blur: 16,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: shimmer,
        ),
      );
    }
    // Empty state: no glass box at all — nothing to hold, so no surface to
    // show. The comment row beside it renders on its own regardless.
    if (reactions.isEmpty) return const SizedBox.shrink();

    final list = SizedBox(
      height: thumbSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: reactions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => _FaceReactionThumb(
          reaction: reactions[i],
          size: thumbSize,
        ),
      ),
    );
    if (embedded) return list;

    return RepaintBoundary(
      child: GlassBox(
        borderRadius: 16,
        blur: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: list,
      ),
    );
  }
}

class _FaceReactionThumb extends StatelessWidget {
  const _FaceReactionThumb({required this.reaction, required this.size});
  final FaceReaction reaction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.42;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: CachedNetworkImage(
              memCacheWidth: 1080,
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
    );
  }
}

// ---------------------------------------------------------------------------
// EmojiReactionRow — horizontally-scrollable summary of OTHER people's emoji
// reactions, one circular thumbnail per distinct emoji (with a small count
// badge once more than one person used it). Used instead of ReactionRow on
// feeds that are emoji-only — the Anonymous feed never shows face photos,
// per the anonymity rule, and ReactionSummary.emojiCounts is aggregated
// (not a per-user list like FaceReaction), so this can only show "what was
// reacted," not "who." The viewer's own emoji is excluded here (already
// shown on the reaction-entry badge) — see PhotoPostCard for how [entries]
// is derived from ReactionSummary.emojiCounts.
// ---------------------------------------------------------------------------

class EmojiReactionRow extends StatelessWidget {
  const EmojiReactionRow({
    super.key,
    required this.entries,
    this.isLoading = false,
    this.thumbSize = 30,
    this.embedded = false,
  });

  final List<MapEntry<String, int>> entries;
  final bool isLoading;
  final double thumbSize;

  /// See ReactionRow.embedded — same reasoning, skips this widget's own
  /// LightSurfaceBox when the caller already supplies one (e.g. the shared
  /// row beside comments).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    // Live only on emoji-only feeds (Anonymous today), which are
    // white-background — LightSurfaceBox (not GlassBox, which is
    // white-alpha + blur and would be invisible here) and a matching light
    // shimmer, unlike ReactionRow above which stays dark for a future
    // face-reaction feed.
    if (isLoading) {
      final shimmer = _LightShimmerRow(thumbSize: thumbSize);
      if (embedded) return shimmer;
      return RepaintBoundary(
        child: LightSurfaceBox(
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: shimmer,
        ),
      );
    }
    // Empty state: no surface at all, same as ReactionRow.
    if (entries.isEmpty) return const SizedBox.shrink();

    final list = SizedBox(
      height: thumbSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => _EmojiReactionThumb(
          emoji: entries[i].key,
          count: entries[i].value,
          size: thumbSize,
        ),
      ),
    );
    if (embedded) return list;

    return RepaintBoundary(
      child: LightSurfaceBox(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: list,
      ),
    );
  }
}

class _EmojiReactionThumb extends StatelessWidget {
  const _EmojiReactionThumb({required this.emoji, required this.count, required this.size});
  final String emoji;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.42;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Text(emoji, style: TextStyle(fontSize: size * 0.52)),
          ),
          if (count > 1)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    fontSize: badgeSize * 0.42,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LightShimmerRow extends StatelessWidget {
  const _LightShimmerRow({required this.thumbSize});
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thumbSize,
      // ClipRect + unbounded Row (not a fixed-count layout that can
      // overflow): the caller's own available width varies with however
      // much room is left after its other action-row controls, so this
      // placeholder needs to gracefully clip rather than assert an exact
      // width like the real (scrollable) ListView.separated content does.
      child: ClipRect(
        child: Shimmer.fromColors(
          baseColor: const Color(0xFFECECEC),
          highlightColor: const Color(0xFFF8F8F8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
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
        ),
      ),
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
      child: ClipRect(
        child: Shimmer.fromColors(
          baseColor: AppColors.cardSurface,
          highlightColor: AppColors.cardSurface.withValues(alpha: 0.4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
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
        ),
      ),
    );
  }
}
