import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../services/reaction_preset_service.dart';
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
import '../../../shared/score_tier.dart';
import 'post_card_shared.dart';
import 'reaction_row.dart';
import 'reactor_cluster.dart';
import 'realmoji_reactor_stack.dart';

// ---------------------------------------------------------------------------
// EveryonePostCard — the Friends/Everyone feed post card. A SEPARATE widget
// from PhotoPostCard (screens/feed/widgets/photo_post_card.dart), the
// Anonymous feed's card. Plain, normal BeReal-style card — NO notch/dip/
// tray cutout (that traced-frame design is Anonymous-only; do not import
// AnonPostCardGeometry/AnonPostCardClipper/post_card_tray_icons here). This
// card shows the poster's REAL avatar and REAL name (no persona icon, no
// anonymity), per this feed's own rules.
//
// Anatomy, top to bottom:
//   1. Photo — plain rounded rectangle (widget.imageCornerRadius), full
//      width, cover fit, no white padding/shadow around it. Overlays inside
//      its clip bounds:
//      a. Author overlay (top-left) — real avatar (2px white ring) + real
//         name, white text with a drop shadow for legibility over the
//         photo.
//      b. Reaction corner (top-right) — plain PostReactionCorner, the
//         card's one reaction entry point (default "surface" chrome).
//      c. Counter pills (bottom-left) — like + comment count, dark glass
//         pills with a soft inset ring.
//      d. Reactor cluster (bottom-right) — the 3 most recent reactors'
//         faces.
//   2. Caption block — below the photo, on the card's own white
//      background: small real avatar, real name, caption body, then
//      hashtags in a muted color.
//
// Reaction data is real throughout (ReactionSummary via PostReactions,
// same mixin PhotoPostCard/TextPostCard use) — the "like" here is a single
// binary heart rather than that mixin's multi-emoji picker, implemented by
// always toggling one fixed emoji through the SAME onEmojiSelected path, so
// it gets real backend persistence and the mixin's existing optimistic
// count update for free instead of a parallel state machine. The recent-
// reactor cluster is a separate, purely-additive read (fetchRecentReactors)
// that doesn't affect the reaction summary's own correctness if it's ever
// slow or fails — it fails closed to an empty list, per
// ReactionService.fetchRecentReactors's own doc.
//
// No ping wiring on this card — that was a tray-only affordance tied to the
// (now removed) notch/dip design and was never part of this feed's spec.
// ---------------------------------------------------------------------------

class EveryonePostCard extends StatefulWidget {
  const EveryonePostCard({
    super.key,
    required this.postId,
    required this.media,
    required this.username,
    this.avatarUrl,
    this.caption,
    this.commentCount = 0,
    this.onCommentTap,
    this.cornerRadius = 34,
    this.imageCornerRadius = 24,
    this.imageAspectRatio = 372 / 303,
    this.isLoading = false,
    this.hasError = false,
    this.groupName,
    this.communityTag,
  });

  /// Reactions are fetched/written keyed on this — must be stable and
  /// unique per post.
  final String postId;

  /// The actual photo content (e.g. a CachedNetworkImage, SinglePostCard's
  /// background, or a MemoryFeedCard). Ignored while [isLoading] or
  /// [hasError] are true.
  final Widget media;

  /// The poster's REAL username — this feed shows real identity, unlike
  /// the Anonymous feed's persona-only PhotoPostCard.
  final String username;

  /// The poster's REAL profile photo. Null falls back to a plain person
  /// glyph.
  final String? avatarUrl;

  /// Raw caption text, hashtags and all — split into body + hashtags via
  /// [_parseCaption] at build time (see the caption block).
  final String? caption;

  final int commentCount;
  final VoidCallback? onCommentTap;

  /// Set only for GROUP posts — the group's display name (e.g. "CS Study
  /// Group"). Null for a regular individual post, which shows no group
  /// attribution and no community tag at all. When set, the caption
  /// block's identity line reads "Posted by {groupName} · {username}"
  /// instead of the plain username, with [communityTag] shown as a small
  /// pill beside it — see _CaptionBlock.
  final String? groupName;

  /// The community the group belongs to (e.g. "CSE"). Ignored when
  /// [groupName] is null. Distinct from the individual-post community tag
  /// that was removed from PhotoPostCard (item #4) — a group's community
  /// is structurally relevant to the group itself, unlike an anonymous
  /// individual post.
  final String? communityTag;

  /// Outer card radius — spec default 34px.
  final double cornerRadius;

  /// Inset image's own radius — spec default 24px.
  final double imageCornerRadius;

  /// width / height of the photo — spec's fixed 372:303.
  final double imageAspectRatio;

  /// Card-level (not reaction-level) loading/error — set by the caller when
  /// the post's own content isn't ready/failed. Reaction data has its own
  /// internal loading state independent of this.
  final bool isLoading;
  final bool hasError;

  @override
  State<EveryonePostCard> createState() => _EveryonePostCardState();
}

class _EveryonePostCardState extends State<EveryonePostCard> with PostReactions<EveryonePostCard> {
  static const String _kLikeEmoji = '❤️';

  List<LikeReactor> _reactors = const [];

  /// RealMoji reactor selfies for the bottom stack (realmoji_picker.dart /
  /// realmoji_reactor_stack.dart) — a separate system from the like-pill's
  /// `reactions` table above (post_realmoji_reactions), loaded independently
  /// so a failure here never blocks the existing like/comment UI.
  List<RealmojiReaction> _realmojiReactors = const [];

  /// Increment-only counter that retriggers the heart's pop animation (see
  /// _LikePill.didUpdateWidget) — bumped on every tap, including repeat
  /// likes/unlikes, so the pop replays every time rather than only on a
  /// false->true edge.
  int _popKey = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.isLoading && !widget.hasError) {
      loadReactionSummary(widget.postId);
      unawaited(_loadReactors());
      unawaited(_loadRealmojiReactors());
      unawaited(loadMyRealmojiReaction(widget.postId));
    }
  }

  @override
  void didUpdateWidget(EveryonePostCard old) {
    super.didUpdateWidget(old);
    final justBecameReady =
        (old.isLoading || old.hasError) && !widget.isLoading && !widget.hasError;
    if (justBecameReady || old.postId != widget.postId) {
      loadReactionSummary(widget.postId);
      unawaited(_loadReactors());
      unawaited(_loadRealmojiReactors());
      unawaited(loadMyRealmojiReaction(widget.postId));
    }
  }

  Future<void> _loadReactors() async {
    final reactors = await ReactionService.instance.fetchRecentReactors(widget.postId);
    if (!mounted) return;
    setState(() => _reactors = reactors);
  }

  Future<void> _loadRealmojiReactors() async {
    try {
      final reactors = await RealmojiService.instance.fetchReactors(widget.postId);
      if (!mounted) return;
      setState(() => _realmojiReactors = reactors);
    } catch (e, st) {
      debugPrint('[EveryonePostCard] fetchReactors(${widget.postId}) failed: $e\n$st');
    }
  }

  Future<void> _toggleLike() async {
    setState(() => _popKey++);
    // onEmojiSelected already updates `summary` optimistically (see
    // PostReactions in post_card_shared.dart) before the network call
    // resolves, and rolls back on failure — that's the spec's "count
    // increments optimistically" requirement, for free.
    await onEmojiSelected(widget.postId, _kLikeEmoji);
    // Best-effort refresh so a fresh like shows up in the reactor cluster
    // promptly. The pill's own count doesn't depend on this succeeding.
    unawaited(_loadReactors());
  }

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();
    final liked = reactions.myEmoji == _kLikeEmoji;
    final parsedCaption = _parseCaption(widget.caption);

    // Others' face reactions only — excludes the viewer's own, same
    // reasoning PhotoPostCard's own computation uses (their own reaction
    // already shows on the PostReactionCorner entry button above).
    final otherFaceReactions = reactions.myFaceReaction == null
        ? reactions.faceReactions
        : reactions.faceReactions
            .where((r) => r.userId != reactions.myFaceReaction!.userId)
            .toList();
    final showReactionsRow = otherFaceReactions.isNotEmpty ||
        (loadingSummary && summary == null);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Align(
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
                // Photo + all its overlays. Wrapped in Flexible + Center: this
                // card sits inside the Everyone feed's vertical PageView
                // (everyone_feed_screen.dart) via SpotlightCard, which hands
                // this Column a bounded-but-loose-min height for its pager
                // focus/blur/scale mechanic. A bare AspectRatio only knows the
                // card's WIDTH, so on a shorter effective page the sum of
                // image + caption block could exceed that bound with nothing
                // able to shrink — Flexible hands AspectRatio a real maxHeight
                // so it picks whichever dimension is more constraining instead
                // of overflowing.
                Flexible(
                  child: Center(
                    // Plain rounded rectangle, widget.imageCornerRadius —
                    // NOT the Anonymous feed's traced dip/tray frame.
                    // Normal BeReal-style Friends card: no notch, no tray
                    // cutout, nothing "applicable only in Anonymous" here.
                    // Still edge-to-edge (no white padding/shadow around
                    // it — that improvement stays).
                    child: AspectRatio(
                      aspectRatio: widget.imageAspectRatio,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(widget.imageCornerRadius),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildMedia(),

                            // Author overlay — real avatar (2px white
                            // ring) + real name, overlaid directly on the
                            // photo with a drop shadow for legibility, no
                            // special notch/geometry to line up with —
                            // this is the "normal" BeReal-style header.
                            Positioned(
                              top: 13,
                              left: 13,
                              child: Row(
                                children: [
                                  ScoreGlowRing(
                                    score: scoreForUser(widget.username),
                                    size: 34,
                                    borderWidth: 2,
                                    child: widget.avatarUrl == null
                                        ? _avatarFallback(34)
                                        : CachedNetworkImage(
                                            imageUrl: widget.avatarUrl!,
                                            width: 34,
                                            height: 34,
                                            fit: BoxFit.cover,
                                            placeholder: (_, _) => _avatarFallback(34),
                                            errorWidget: (_, _, _) => _avatarFallback(34),
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.username,
                                    style: GoogleFonts.figtree(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Reaction entry — plain top-right corner
                            // button (surface style, the default every
                            // other call site uses), not a tray cutout.
                            // This icon stays exactly where it already was
                            // (per explicit correction: no new icon
                            // anywhere on the post) — only its tray content
                            // is repointed, from the old
                            // ReactionPresetService-backed
                            // ReactionPresetTray to RealmojiTray
                            // (user_realmojis-backed). See
                            // PostReactions.selectPreset /
                            // captureRealmojiAndReact.
                            Positioned(
                              top: 13,
                              right: 13,
                              child: PostReactionCorner(
                                allowFaceReactions: true,
                                myFaceReaction: null,
                                myEmoji: myRealmojiReaction?.glyph,
                                uploading: uploadingFaceReaction,
                                onTap: openReactionTray,
                                showTray: showPresetTray,
                                category: ReactionPresetCategory.everyone,
                                onSelect: (preset) =>
                                    selectPreset(widget.postId, preset),
                                onAddNew: () => openAddPresetFlow(
                                  widget.postId,
                                  allowFaceReactions: true,
                                ),
                                onCaptureRealmoji: (type) => captureRealmojiAndReact(
                                  widget.postId,
                                  ReactionPresetCategory.everyone,
                                  type,
                                ),
                              ),
                            ),

                            Positioned(
                              left: 13,
                              bottom: 13,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _LikePill(
                                    liked: liked,
                                    count: reactions.totalEmojiCount,
                                    popKey: _popKey,
                                    onTap: _toggleLike,
                                  ),
                                  const SizedBox(width: 7),
                                  _CommentCountPill(
                                    count: widget.commentCount,
                                    onTap: widget.onCommentTap,
                                  ),
                                ],
                              ),
                            ),

                            Positioned(
                              right: 10,
                              bottom: 16,
                              child: ReactorCluster(
                                reactors: _reactors
                                    .map((r) => ReactorInfo(
                                          id: r.id,
                                          name: r.name,
                                          avatarUrl: r.avatarUrl,
                                        ))
                                    .toList(),
                                totalCount: reactions.totalEmojiCount,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                _CaptionBlock(
                  avatarUrl: widget.avatarUrl,
                  username: widget.username,
                  body: parsedCaption.body,
                  hashtags: parsedCaption.hashtags,
                  groupName: widget.groupName,
                  communityTag: widget.communityTag,
                ),

                // RealMoji reactor selfie stack (realmoji_service.dart /
                // realmoji_reactor_stack.dart) — entry point ('+') lives at
                // the top-right corner overlay above now, not here; this
                // row is purely the "who's reacted" display. Never renders
                // an empty slot — RealmojiReactorStack itself collapses to
                // nothing when there are no reactors, but the Padding
                // wrapping it would still cost 4px of dead space, so the
                // whole thing is gated here instead.
                if (_realmojiReactors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                    child: RealmojiReactorStack(reactors: _realmojiReactors),
                  ),

                // Others' face reactions, beside "View all N comments" —
                // same adjacency rule PhotoPostCard/TextPostCard's own
                // _ReactionsAndCommentsRow follows on the Anonymous feed.
                // The reaction ENTRY point stays in the top-right corner
                // above — this row is purely the "who reacted" display,
                // additive alongside the reactor-cluster/like-pill
                // overlaid on the photo itself.
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                  child: _FriendsReactionsAndCommentsRow(
                    showReactionsRow: showReactionsRow,
                    otherFaceReactions: otherFaceReactions,
                    reactionsLoading: loadingSummary && summary == null,
                    commentCount: widget.commentCount,
                    onCommentTap: widget.onCommentTap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.hasError) {
      return Container(
        color: const Color(0xFFF0F0F0),
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: Color(0xFF999999), size: 40),
        ),
      );
    }
    if (widget.isLoading) {
      return Shimmer.fromColors(
        baseColor: const Color(0xFFECECEC),
        highlightColor: const Color(0xFFF8F8F8),
        child: Container(color: Colors.white),
      );
    }
    return widget.media;
  }
}

// ---------------------------------------------------------------------------
// Caption parsing — splits raw caption text into body copy (hashtags
// stripped, whitespace collapsed) and the list of hashtags themselves, so
// the caption block can style them separately per spec.
// ---------------------------------------------------------------------------

class _ParsedCaption {
  const _ParsedCaption(this.body, this.hashtags);
  final String body;
  final List<String> hashtags;
}

_ParsedCaption _parseCaption(String? caption) {
  if (caption == null || caption.trim().isEmpty) {
    return const _ParsedCaption('', []);
  }
  final hashtags = RegExp(r'#(\w+)')
      .allMatches(caption)
      .map((m) => '#${m.group(1)}')
      .toList();
  final body = caption
      .replaceAll(RegExp(r'#\w+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return _ParsedCaption(body, hashtags);
}

Widget _avatarFallback(double size) => Container(
      color: const Color(0xFFEDEBE8),
      child: Icon(Icons.person, size: size * 0.55, color: const Color(0xFFA6A09B)),
    );

// ---------------------------------------------------------------------------
// Glass pill — shared container for the like/comment counters: dark glass,
// blurred, with a soft inset ring. Tokens straight from spec: bg
// rgba(28,24,22,.42), inset ring rgba(255,255,255,.22).
// ---------------------------------------------------------------------------

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 13, 7),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(28, 24, 22, 0.42),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: content);
  }
}

// ---------------------------------------------------------------------------
// Like pill — binary heart, not the multi-emoji picker. Tapping toggles
// fill between none/#f0322f and plays heartPop (scale 1 -> 1.35 -> 0.9 -> 1
// over 0.45s). Retriggered via popKey (see _EveryonePostCardState) rather
// than a key-remount trick — didUpdateWidget + AnimationController.forward
// (from: 0) is the direct Flutter equivalent and handles rapid repeat taps
// cleanly on its own.
// ---------------------------------------------------------------------------

class _LikePill extends StatefulWidget {
  const _LikePill({
    required this.liked,
    required this.count,
    required this.popKey,
    required this.onTap,
  });

  final bool liked;
  final int count;
  final int popKey;
  final VoidCallback onTap;

  @override
  State<_LikePill> createState() => _LikePillState();
}

class _LikePillState extends State<_LikePill> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.35, end: 0.9).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_ctrl);
  }

  @override
  void didUpdateWidget(_LikePill old) {
    super.didUpdateWidget(old);
    if (old.popKey != widget.popKey) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      onTap: widget.onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
            child: Icon(
              widget.liked ? Icons.favorite : Icons.favorite_border,
              size: 15,
              color: widget.liked ? const Color(0xFFF0322F) : Colors.white,
            ),
          ),
          if (widget.count > 0) ...[
            const SizedBox(width: 5),
            Text(
              '${widget.count}',
              style: GoogleFonts.figtree(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentCountPill extends StatelessWidget {
  const _CommentCountPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mode_comment_outlined, size: 15, color: Colors.white),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Text(
              '$count',
              style: GoogleFonts.figtree(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group community tag — small pill naming which community a GROUP post
// belongs to (e.g. "CSE"). Only ever shown on group posts (see
// _CaptionBlock's groupName check) — never on a regular individual post.
// ---------------------------------------------------------------------------

class _GroupCommunityTag extends StatelessWidget {
  const _GroupCommunityTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEEB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF6B6560),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Caption block — below the photo, on the card's own white background.
// ---------------------------------------------------------------------------

class _CaptionBlock extends StatelessWidget {
  const _CaptionBlock({
    required this.avatarUrl,
    required this.username,
    required this.body,
    required this.hashtags,
    this.groupName,
    this.communityTag,
  });

  final String? avatarUrl;
  final String username;
  final String body;
  final List<String> hashtags;
  final String? groupName;
  final String? communityTag;

  static const double _kAvatarSize = 30;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 15, 8, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: SizedBox(
              width: _kAvatarSize,
              height: _kAvatarSize,
              child: avatarUrl == null
                  ? _avatarFallback(_kAvatarSize)
                  : CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => _avatarFallback(_kAvatarSize),
                      errorWidget: (_, _, _) => _avatarFallback(_kAvatarSize),
                    ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groupName != null) ...[
                  // GROUP posts only — "Posted by {group} · {poster}" plus a
                  // small community tag, in place of the plain username line.
                  // Regular individual posts never show this (groupName is
                  // null) or any community tag at all — that distinction is
                  // deliberate, per item #4/#9: individual anonymous posts
                  // dropped their community tag, but a group's community is
                  // structurally relevant to the group itself.
                  Row(
                    children: [
                      if (communityTag != null) ...[
                        _GroupCommunityTag(label: communityTag!),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: GoogleFonts.figtree(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF8A8580),
                            ),
                            children: [
                              const TextSpan(text: 'Posted by '),
                              TextSpan(
                                text: groupName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF14110F),
                                ),
                              ),
                              TextSpan(text: ' · $username'),
                            ],
                          ),
                          // 2 lines, not 1 — a longer group name plus " ·
                          // {username}" can't always fit on one line, and
                          // truncating at 1 risked cutting off before the
                          // poster's own name ever appeared, which defeats
                          // the point of the attribution.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ] else
                  Text(
                    username,
                    style: GoogleFonts.figtree(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF14110F),
                    ),
                  ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: GoogleFonts.figtree(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                      height: 1.46,
                      color: const Color(0xFF46403C),
                    ),
                  ),
                ],
                if (hashtags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    hashtags.join(' '),
                    style: GoogleFonts.figtree(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFA6A09B),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _FriendsReactionsAndCommentsRow — others' face reactions beside "View all
// N comments", mirroring PhotoPostCard/TextPostCard's own
// _ReactionsAndCommentsRow on the Anonymous feed. No SimpleReactionCorner
// here — Friends/Everyone's reaction ENTRY point stays in the card's
// top-right corner (PostReactionCorner, unchanged); this row is purely the
// "who reacted" display, collapsing to comments-alone when empty.
// ---------------------------------------------------------------------------

class _FriendsReactionsAndCommentsRow extends StatelessWidget {
  const _FriendsReactionsAndCommentsRow({
    required this.showReactionsRow,
    required this.otherFaceReactions,
    required this.reactionsLoading,
    required this.commentCount,
    required this.onCommentTap,
  });

  final bool showReactionsRow;
  final List<FaceReaction> otherFaceReactions;
  final bool reactionsLoading;
  final int commentCount;
  final VoidCallback? onCommentTap;

  static const double _kThumbSize = 28;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showReactionsRow) ...[
          Expanded(
            child: SizedBox(
              height: _kThumbSize,
              child: ReactionRow(
                reactions: otherFaceReactions,
                isLoading: reactionsLoading,
                thumbSize: _kThumbSize,
                embedded: true,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFF14110F).withValues(alpha: 0.08),
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
                color: Color(0xFFA6A09B),
              ),
              const SizedBox(width: 6),
              Text(
                commentCount > 0
                    ? 'View all $commentCount comments'
                    : 'Add a comment…',
                style: GoogleFonts.figtree(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFA6A09B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
