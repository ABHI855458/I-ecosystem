import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// PostCard — the Friends/Everyone feed's SINGLE-PERSON post card. Dark
// themed, per the pixel-exact build spec: dual-camera photo (back large +
// front inset, tap-to-swap / drag-to-corner), on-photo react disc (the only
// on-photo action), collapsed/expanded reaction row, comments link +
// preview. Presentational only — no network calls. Real reaction/comment
// data is wired in by PersonalPostCard (personal_post_card.dart), which
// owns ReactionService state the same way EveryonePostCard does for group
// posts. GROUP posts never use this widget — they keep EveryonePostCard's
// existing "Posted by {group} · {user}" treatment.
// ---------------------------------------------------------------------------

class PostCardReaction {
  const PostCardReaction({
    required this.id,
    required this.handle,
    required this.photo,
    required this.emoji,
  });

  final String id;
  final String handle;
  final String? photo;
  final String emoji;
}

class PostCardComment {
  const PostCardComment({required this.id, required this.handle, required this.body});

  final String id;
  final String handle;
  final String body;
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.handle,
    this.place,
    this.avatar,
    this.backPhoto,
    this.frontPhoto,
    this.reactions = const [],
    this.reactionCount = 0,
    this.comments = const [],
    this.commentCount = 0,
    this.reacted = false,
    this.onReact,
    this.onOpenComments,
    this.onOpenAllReactions,
    this.onPickReactionEmoji,
    this.logo,
    this.locked = false,
    this.loading = false,
    this.showReactDisc = true,
    this.showBuiltInEngagement = true,
    this.headerTrailing,
  });

  final String handle;
  final String? place;

  /// Null falls back to a plain person glyph — same convention
  /// EveryonePostCard's own avatarUrl uses.
  final String? avatar;
  final String? backPhoto;
  final String? frontPhoto;
  final List<PostCardReaction> reactions;
  final int reactionCount;
  final List<PostCardComment> comments;
  final int commentCount;
  final bool reacted;
  final VoidCallback? onReact;
  final VoidCallback? onOpenComments;

  /// "See all" tile in the expanded scroller.
  final VoidCallback? onOpenAllReactions;

  /// Long-press emoji picker selection — additive, not in the original
  /// prop list, since the picker needs somewhere to send a non-default
  /// emoji. Falls back to [onReact] when null.
  final ValueChanged<String>? onPickReactionEmoji;

  final String? logo;
  final bool locked;
  final bool loading;

  /// False when the caller overlays its own reaction entry point instead
  /// (PersonalPostCard, wiring PostReactionCorner/RealmojiTray — the same
  /// mechanism PhotoPostCard/EveryonePostCard use — over this card rather
  /// than using the built-in tap-to-like/long-press-to-pick disc below).
  final bool showReactDisc;

  /// False when the caller renders its own reaction-summary pill + comment
  /// card externally instead (PersonalPostCard, using the shared
  /// PostReactionsPill/PostCommentCard from post_card_shared.dart, per
  /// design-refs/design_handoff_post_card_feed 2). Skips the built-in
  /// below-photo reaction row and comment link/preview so this card is just
  /// header + media — the caller overlays/appends everything else itself.
  final bool showBuiltInEngagement;

  /// Rendered at the right edge of the header row, replacing the default
  /// "···" dots — the Live-presence pill (LivePresencePill,
  /// post_card_shared.dart) in the redesigned card. Null keeps the old dots.
  final Widget? headerTrailing;

  // §2: media corner radius 26dp.
  static const double kMediaRadius = 26;
  static const Color kAccent = Color(0xFFFF6F5E);
  static const Color kText = Color(0xFFF5F5F7);
  static const Color kMediaPlaceholder = Color(0xFF17171B);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _frontIsLarge = false;
  _Corner _insetCorner = _Corner.topLeft;
  bool _expandedReactions = false;

  final _reactDiscLink = LayerLink();
  OverlayEntry? _pickerEntry;

  @override
  void dispose() {
    _pickerEntry?.remove();
    super.dispose();
  }

  void _swapLens() => setState(() => _frontIsLarge = !_frontIsLarge);

  void _snapToNearestCorner(Offset localPosition, Size mediaSize) {
    final isRight = localPosition.dx > mediaSize.width / 2;
    final isBottom = localPosition.dy > mediaSize.height / 2;
    setState(() {
      _insetCorner = isRight
          ? (isBottom ? _Corner.bottomRight : _Corner.topRight)
          : (isBottom ? _Corner.bottomLeft : _Corner.topLeft);
    });
  }

  Offset _insetOffset(Size mediaSize) {
    const w = 108.0, h = 144.0, inset = 11.0;
    switch (_insetCorner) {
      case _Corner.topLeft:
        return const Offset(inset, inset);
      case _Corner.topRight:
        return Offset(mediaSize.width - w - inset, inset);
      case _Corner.bottomLeft:
        return Offset(inset, mediaSize.height - h - inset);
      case _Corner.bottomRight:
        return Offset(mediaSize.width - w - inset, mediaSize.height - h - inset);
    }
  }

  void _showReactPicker() {
    if (_pickerEntry != null) return;
    final overlay = Overlay.of(context);
    _pickerEntry = OverlayEntry(
      builder: (_) => _ReactPickerOverlay(
        link: _reactDiscLink,
        onDismiss: _hideReactPicker,
        onPick: (emoji) {
          _hideReactPicker();
          if (widget.onPickReactionEmoji != null) {
            widget.onPickReactionEmoji!(emoji);
          } else {
            widget.onReact?.call();
          }
        },
      ),
    );
    overlay.insert(_pickerEntry!);
  }

  void _hideReactPicker() {
    _pickerEntry?.remove();
    _pickerEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const _LoadingCard();

    final children = <Widget>[
      _AuthorRow(handle: widget.handle, place: widget.place, avatar: widget.avatar, trailing: widget.headerTrailing),
      widget.locked
          ? const _LockedMedia()
          : _Media(
              backPhoto: widget.backPhoto,
              frontPhoto: widget.frontPhoto,
              frontIsLarge: _frontIsLarge,
              insetOffsetFor: _insetOffset,
              onSwapLens: _swapLens,
              onDragEnd: _snapToNearestCorner,
              reacted: widget.reacted,
              onReactTap: widget.onReact,
              onReactLongPress: _showReactPicker,
              reactDiscLink: _reactDiscLink,
              logo: widget.logo,
              showReactDisc: widget.showReactDisc,
            ),
    ];

    if (!widget.locked && widget.showBuiltInEngagement) {
      children.add(
        _expandedReactions
            ? _ReactionScroller(
                reactions: widget.reactions,
                reactionCount: widget.reactionCount,
                onCollapse: () => setState(() => _expandedReactions = false),
                onSeeAll: widget.onOpenAllReactions,
              )
            : _ReactionRowCollapsed(
                reactions: widget.reactions,
                reactionCount: widget.reactionCount,
                onExpand: () => setState(() => _expandedReactions = true),
              ),
      );

      // Comments link is a standing affordance (like EveryonePostCard's own
      // "Add a comment…" row), not conditional on commentCount>0 — hiding it
      // at zero made the whole comment/reaction section read as entirely
      // missing whenever a post's real engagement data hadn't loaded yet.
      children.add(_CommentsLink(commentCount: widget.commentCount, onTap: widget.onOpenComments));
      if (widget.comments.isNotEmpty) {
        children.add(_CommentPreview(comments: widget.comments.take(3).toList()));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _withGaps(children, 10),
    );
  }
}

Widget _avatarPhoto(String? url) {
  if (url == null || url.isEmpty) return Container(color: PostCard.kMediaPlaceholder);
  return CachedNetworkImage(
              memCacheWidth: 1080,
    imageUrl: url,
    fit: BoxFit.cover,
    errorWidget: (_, _, _) => Container(color: PostCard.kMediaPlaceholder),
  );
}

List<Widget> _withGaps(List<Widget> children, double gap) {
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) out.add(SizedBox(height: gap));
    out.add(children[i]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// 1. Author row
// ---------------------------------------------------------------------------

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.handle, required this.place, required this.avatar, this.trailing});

  final String handle;
  final String? place;
  final String? avatar;
  final Widget? trailing;

  static const double _kAvatarSize = 42;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // §2 header padding: 12 top / 14 side / 11 bottom.
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
      child: Row(
        children: [
          ClipOval(
            child: Container(
              width: _kAvatarSize,
              height: _kAvatarSize,
              color: Colors.black,
              child: avatar == null
                  ? const Icon(Icons.person, size: 22, color: Color(0xFF5A5A60))
                  : CachedNetworkImage(
              memCacheWidth: 1080,
                      imageUrl: avatar!,
                      width: _kAvatarSize,
                      height: _kAvatarSize,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const Icon(Icons.person, size: 22, color: Color(0xFF5A5A60)),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // §4: username is the one Nunito display use — 700/15.5dp.
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.015 * 15.5,
                    color: PostCard.kText,
                  ),
                ),
                // §4: date line is Inter 500/12.5dp @ .5 alpha, NOT Nunito —
                // was wrongly sharing the username's display font.
                if (place != null && place!.isNotEmpty)
                  Text(
                    place!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFF5F5F7).withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                    child: Container(
                      width: 3.5,
                      height: 3.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF5F5F7).withValues(alpha: 0.45),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Media — dual-camera photo, front inset, action rail
// ---------------------------------------------------------------------------

class _Media extends StatelessWidget {
  const _Media({
    required this.backPhoto,
    required this.frontPhoto,
    required this.frontIsLarge,
    required this.insetOffsetFor,
    required this.onSwapLens,
    required this.onDragEnd,
    required this.reacted,
    required this.onReactTap,
    required this.onReactLongPress,
    required this.reactDiscLink,
    required this.logo,
    required this.showReactDisc,
  });

  final String? backPhoto;
  final String? frontPhoto;
  final bool frontIsLarge;
  final Offset Function(Size) insetOffsetFor;
  final VoidCallback onSwapLens;
  final void Function(Offset localPosition, Size mediaSize) onDragEnd;
  final bool reacted;
  final VoidCallback? onReactTap;
  final VoidCallback onReactLongPress;
  final LayerLink reactDiscLink;
  final String? logo;
  final bool showReactDisc;

  @override
  Widget build(BuildContext context) {
    final largeUrl = frontIsLarge ? frontPhoto : backPhoto;
    final insetUrl = frontIsLarge ? backPhoto : frontPhoto;

    return Padding(
      // Feed.dc.html: photo margin 0 12px (was 8) — isolated from the
      // draggable inset's own positioning (real _Media state only), which
      // is computed relative to this box's size via insetOffsetFor(), not
      // hardcoded against this padding value. Applied uniformly to the
      // locked/loading placeholder states too so they stay the same size
      // as the real photo.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PostCard.kMediaRadius),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final insetOffset = insetOffsetFor(size);
              return Stack(
                fit: StackFit.expand,
                children: [
                  _photo(largeUrl),
                  Positioned(
                    left: insetOffset.dx,
                    top: insetOffset.dy,
                    child: GestureDetector(
                      onTap: onSwapLens,
                      onPanEnd: (details) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final local = box.globalToLocal(details.globalPosition);
                        onDragEnd(local, size);
                      },
                      child: Container(
                        width: 108,
                        height: 144,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: _photo(insetUrl),
                        ),
                      ),
                    ),
                  ),
                  // _LogoPlate (the "c." app-branding watermark) removed —
                  // it sat in this exact bottom-right corner, colliding
                  // with PersonalPostCard's own reaction cluster overlay
                  // there, and no caller ever actually passes a real
                  // `logo` image (grepped — always null), so it only ever
                  // rendered its literal "c." text fallback. Not part of
                  // this spec; explicit removal request.
                  if (showReactDisc)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: CompositedTransformTarget(
                        link: reactDiscLink,
                        child: _ReactDisc(
                          reacted: reacted,
                          onTap: onReactTap,
                          onLongPress: onReactLongPress,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _photo(String? url) {
    if (url == null || url.isEmpty) return Container(color: PostCard.kMediaPlaceholder);
    return Container(
      color: PostCard.kMediaPlaceholder,
      child: CachedNetworkImage(
              memCacheWidth: 1080,
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, _, _) => Container(color: PostCard.kMediaPlaceholder),
      ),
    );
  }
}

// Unreferenced since the card header stopped drawing a logo plate. Kept
// rather than deleted, same convention as the rest of this file.
// ignore: unused_element
class _LogoPlate extends StatelessWidget {
  const _LogoPlate({required this.logo});
  final String? logo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      alignment: Alignment.center,
      child: logo != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
              memCacheWidth: 120,imageUrl: logo!, width: 40, height: 40, fit: BoxFit.cover),
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'c',
                    style: GoogleFonts.nunito(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.05 * 19,
                      color: const Color(0xFF111111),
                    ),
                  ),
                  TextSpan(
                    text: '.',
                    style: GoogleFonts.nunito(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.05 * 19,
                      color: PostCard.kAccent,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ReactDisc extends StatelessWidget {
  const _ReactDisc({required this.reacted, required this.onTap, required this.onLongPress});

  final bool reacted;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          alignment: Alignment.center,
          child: reacted
              ? const Icon(Icons.favorite, size: 19, color: PostCard.kAccent)
              : const SizedBox(width: 20, height: 20, child: CustomPaint(painter: _SmileyPainter())),
        ),
      ),
    );
  }
}

/// Eyes + smile curve only, no outer ring. Path math taken directly from the
/// spec's SVG: two r=1.35 dots at (8.6,9.4)/(15.4,9.4), mouth
/// "M7.6 14.4a5.6 5.6 0 0 0 8.8 0" reproduced via Path.arcToPoint (Flutter's
/// arc param order/semantics mirror SVG's A command 1:1).
class _SmileyPainter extends CustomPainter {
  const _SmileyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = const Color(0xFF111111);

    canvas.drawCircle(const Offset(8.6, 9.4), 1.35, fill);
    canvas.drawCircle(const Offset(15.4, 9.4), 1.35, fill);

    final mouth = Path()
      ..moveTo(7.6, 14.4)
      ..arcToPoint(const Offset(16.4, 14.4), radius: const Radius.circular(5.6), clockwise: false);
    canvas.drawPath(mouth, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 3. Reaction row (collapsed)
// ---------------------------------------------------------------------------

class _ReactionRowCollapsed extends StatelessWidget {
  const _ReactionRowCollapsed({required this.reactions, required this.reactionCount, required this.onExpand});

  final List<PostCardReaction> reactions;
  final int reactionCount;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    // Standing affordance, not conditional on reactionCount>0 — same
    // reasoning as _CommentsLink below: hiding it at zero made the row read
    // as entirely missing whenever real reaction data hadn't loaded yet.
    final shown = reactions.take(3).toList();

    return GestureDetector(
      onTap: onExpand,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(
          children: [
            if (shown.isNotEmpty)
              SizedBox(
                width: 26 + (shown.length - 1) * 16.0,
                height: 26,
                child: Stack(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * 16.0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: ClipOval(child: _avatarPhoto(shown[i].photo)),
                        ),
                      ),
                  ],
                ),
              ),
            SizedBox(width: shown.isEmpty ? 0 : 9),
            Text(
              '+$reactionCount',
              style: GoogleFonts.nunito(fontSize: 14.5, fontWeight: FontWeight.w800, color: PostCard.kText),
            ),
            const SizedBox(width: 9),
            Text(
              'reactions',
              style: GoogleFonts.nunito(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF5F5F7).withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 9),
            Icon(Icons.keyboard_arrow_down, size: 15, color: const Color(0xFFF5F5F7).withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Reaction scroller (expanded)
// ---------------------------------------------------------------------------

class _ReactionScroller extends StatelessWidget {
  const _ReactionScroller({
    required this.reactions,
    required this.reactionCount,
    required this.onCollapse,
    required this.onSeeAll,
  });

  final List<PostCardReaction> reactions;
  final int reactionCount;
  final VoidCallback onCollapse;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final shown = reactions.take(5).toList();
    final remainder = reactionCount - shown.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          padding: const EdgeInsets.only(top: 13, bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.12), blurRadius: 0, spreadRadius: 0.5)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: onCollapse,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 11),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'REACTIONS · $reactionCount',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: const Color(0xFFF5F5F7).withValues(alpha: 0.5),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_up, size: 15, color: const Color(0xFFF5F5F7).withValues(alpha: 0.5)),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 44 + 6 + 14,
                child: ScrollConfiguration(
                  behavior: const _NoScrollbarBehavior(),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) const SizedBox(width: 13),
                        _ReactionTile(reaction: shown[i]),
                      ],
                      if (remainder > 0) ...[
                        if (shown.isNotEmpty) const SizedBox(width: 13),
                        _SeeAllTile(remainder: remainder, onTap: onSeeAll),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class _ReactionTile extends StatelessWidget {
  const _ReactionTile({required this.reaction});
  final PostCardReaction reaction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: ClipOval(child: _avatarPhoto(reaction.photo)),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0E0E11).withValues(alpha: 0.8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                        ),
                        child: Text(reaction.emoji, style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reaction.handle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunito(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFF5F5F7).withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeeAllTile extends StatelessWidget {
  const _SeeAllTile({required this.remainder, required this.onTap});
  final int remainder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                '+$remainder',
                style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w800, color: PostCard.kText),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'See all',
              style: GoogleFonts.nunito(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF5F5F7).withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Comments link
// ---------------------------------------------------------------------------

class _CommentsLink extends StatelessWidget {
  const _CommentsLink({required this.commentCount, required this.onTap});
  final int commentCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = commentCount <= 0
        ? 'Add a comment…'
        : commentCount == 1
            ? 'View 1 comment'
            : 'View all $commentCount comments';
    final dim = const Color(0xFFF5F5F7).withValues(alpha: 0.55);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
        child: Row(
          children: [
            SizedBox(width: 19, height: 19, child: CustomPaint(painter: _SpeechBubblePainter(color: dim))),
            const SizedBox(width: 9),
            Text(label, style: GoogleFonts.nunito(fontSize: 14.5, fontWeight: FontWeight.w700, color: dim)),
          ],
        ),
      ),
    );
  }
}

class _SpeechBubblePainter extends CustomPainter {
  const _SpeechBubblePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(1, 1.5, 17, 12.5), const Radius.circular(4.5));
    final path = Path()..addRRect(body);

    final tail = Path()
      ..moveTo(6, 14)
      ..lineTo(5, 18)
      ..lineTo(9.5, 14);
    path.addPath(tail, Offset.zero);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpeechBubblePainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// 6. Comment preview
// ---------------------------------------------------------------------------

class _CommentPreview extends StatelessWidget {
  const _CommentPreview({required this.comments});
  final List<PostCardComment> comments;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _withGaps(
          [
            for (final c in comments)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: c.handle,
                      style: GoogleFonts.nunito(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                        letterSpacing: -0.01 * 14.5,
                        color: PostCard.kText,
                      ),
                    ),
                    TextSpan(
                      text: ' ${c.body}',
                      style: GoogleFonts.nunito(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                        letterSpacing: -0.01 * 14.5,
                        color: const Color(0xFFF5F5F7).withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Locked state
// ---------------------------------------------------------------------------

class _LockedMedia extends StatelessWidget {
  const _LockedMedia();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Feed.dc.html: photo margin 0 12px (was 8) — isolated from the
      // draggable inset's own positioning (real _Media state only), which
      // is computed relative to this box's size via insetOffsetFor(), not
      // hardcoded against this padding value. Applied uniformly to the
      // locked/loading placeholder states too so they stay the same size
      // as the real photo.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PostCard.kMediaRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFF2A2A32), PostCard.kMediaPlaceholder],
                  ),
                ),
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 22, color: PostCard.kText),
                      const SizedBox(height: 10),
                      Text(
                        'Post to unlock',
                        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: PostCard.kText),
                      ),
                    ],
                  ),
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
// Loading state
// ---------------------------------------------------------------------------

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final block = Colors.white.withValues(alpha: 0.07);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, color: block)),
              const SizedBox(width: 10),
              Container(width: 90, height: 12, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: block)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          // Feed.dc.html: photo margin 0 12px (was 8) — isolated from the
      // draggable inset's own positioning (real _Media state only), which
      // is computed relative to this box's size via insetOffsetFor(), not
      // hardcoded against this padding value. Applied uniformly to the
      // locked/loading placeholder states too so they stay the same size
      // as the real photo.
      padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(PostCard.kMediaRadius), color: block),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reacting state — long-press picker
// ---------------------------------------------------------------------------

const _kReactionEmojis = ['❤️', '😂', '😮', '😢', '🔥'];

class _ReactPickerOverlay extends StatelessWidget {
  const _ReactPickerOverlay({required this.link, required this.onDismiss, required this.onPick});

  final LayerLink link;
  final VoidCallback onDismiss;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(onTap: onDismiss, behavior: HitTestBehavior.translucent),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -10),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final emoji in _kReactionEmojis) ...[
                    GestureDetector(
                      onTap: () => onPick(emoji),
                      child: Text(emoji, style: const TextStyle(fontSize: 15)),
                    ),
                    const SizedBox(height: 7),
                  ],
                  GestureDetector(
                    onTap: () => onPick('📷'),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: PostCard.kAccent),
                      alignment: Alignment.center,
                      child: const Icon(Icons.camera_alt_rounded, size: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
