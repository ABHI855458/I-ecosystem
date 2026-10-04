import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../features/composer/dual_photo_compositor.dart';

// ---------------------------------------------------------------------------
// DualPhotoView — an interactive dual photo in the feed.
//
// Explicit request: "the dual photo... make it like they can move around
// the other side photo in the feed to see what's behind as such". Every
// dual photo before this was flattened into one JPEG at post time
// (compositeDualPhotos), inset baked into the pixels — a static image has
// no "behind" to move anything to reveal.
//
// This renders the SAME layout that flattening used to bake in (same
// DualInsetGeometry ratios, same corner, same border) from two live layers
// instead, so a new dual post looks identical to an old one at rest — the
// difference only shows up once you touch it: drag the inset anywhere
// within the frame to see more of the background underneath.
//
// Deliberately NOT persisted: dragging and swapping are per-viewing,
// per-viewer things, reset the next time this widget mounts. How you are
// looking at someone's post is not an edit to it.
// ---------------------------------------------------------------------------

class DualPhotoView extends StatefulWidget {
  const DualPhotoView({
    super.key,
    required this.backgroundUrl,
    required this.insetUrl,
    this.insetOnRight = FriendsDualInsetGeometry.onRight,
    this.borderRadius = kFriendsPostRadius,
    this.aspectRatio = kFriendsPostAspect,
    this.fillParent = false,
    this.sizeMultiplier = 1.0,
  });

  final String backgroundUrl;
  final String insetUrl;
  final bool insetOnRight;
  final double borderRadius;

  /// Frame shape, driven by the viewer's post-size preset (see
  /// PostSizePrefsService). Defaults to the app's own tall frame. Ignored
  /// when [fillParent] is true.
  final double aspectRatio;

  /// Skips the AspectRatio+ClipRRect wrapper and fills whatever box the
  /// parent gives it instead — for a card that already owns its own size
  /// and clip shape (the anon feed's notched AnonCardFrameClipper, sized to
  /// a fixed design canvas, unlike the friends feed's plain rounded rect).
  /// The interaction (drag to peek, tap to swap) is identical either way.
  final bool fillParent;

  /// Grows the inset bubble (and its border/radius, both already ratios of
  /// its own width) beyond [FriendsDualInsetGeometry.bubbleWidthRatio]'s
  /// plain `w * ratio`. Explicit report: on the anon feed, the inset stayed
  /// its old size even after the post card itself was made taller — because
  /// the bubble's size is entirely WIDTH-derived (`w * bubbleWidthRatio`)
  /// and the anon card's design WIDTH never changed, only its height, this
  /// never picked up the growth on its own. Callers whose frame grew pass
  /// their own growth factor here so the inset grows with it instead of
  /// silently staying pinned to the old size.
  final double sizeMultiplier;

  @override
  State<DualPhotoView> createState() => _DualPhotoViewState();
}

class _DualPhotoViewState extends State<DualPhotoView> {
  /// Drag offset from the inset's resting position, in local pixels.
  /// Ephemeral — see class doc.
  Offset _drag = Offset.zero;

  /// Which photo is currently the BACKGROUND. Tapping the inset swaps them.
  ///
  /// Explicit request: "tapping on the other camera pic, the pic position
  /// shall interchange". Ephemeral like [_drag] — a swap is how YOU are
  /// looking at the post right now, not an edit to it, so it is never
  /// persisted and never shown to anyone else. Resets when the card
  /// remounts, same as the drag.
  bool _swapped = false;

  String get _backgroundUrl =>
      _swapped ? widget.insetUrl : widget.backgroundUrl;
  String get _insetUrl =>
      _swapped ? widget.backgroundUrl : widget.insetUrl;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            final bubbleW = w *
                FriendsDualInsetGeometry.bubbleWidthRatio *
                widget.sizeMultiplier;
            final bubbleH = bubbleW * FriendsDualInsetGeometry.aspectRatio;
            final margin = bubbleW * FriendsDualInsetGeometry.marginRatio;
            final topMargin = bubbleW * FriendsDualInsetGeometry.topMarginRatio;
            final restLeft = widget.insetOnRight
                ? (w - bubbleW - margin)
                : margin;
            const restTop = 0.0; // topMargin applied via offset below

            // Clamp so a drag can never pull the inset out of the frame.
            final left = (restLeft + _drag.dx).clamp(0.0, w - bubbleW);
            final top = (restTop + topMargin + _drag.dy)
                .clamp(0.0, h - bubbleH);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: _backgroundUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 1080,
                  ),
                ),
                Positioned(
                  left: left,
                  top: top,
                  width: bubbleW,
                  height: bubbleH,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() => _drag += details.delta);
                    },
                    // Releasing snaps back to the resting corner — "move
                    // around to see what's behind" is a peek, not a
                    // relayout; a drag that stuck wherever it was let go
                    // would make the frame look broken/misaligned to the
                    // next viewer scrolling past at rest.
                    onPanEnd: (_) => setState(() => _drag = Offset.zero),
                    // Tap swaps which photo is large. Distinct from the
                    // drag above: onTap only fires when the pointer didn't
                    // travel, so peeking behind the inset and swapping it
                    // don't compete for the same gesture.
                    onTap: () => setState(() => _swapped = !_swapped),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: FriendsDualInsetGeometry.backgroundColor,
                        borderRadius: BorderRadius.circular(
                          bubbleW * FriendsDualInsetGeometry.radiusRatio,
                        ),
                        border: Border.all(
                          color: FriendsDualInsetGeometry.borderColor,
                          width: FriendsDualInsetGeometry.borderWidth *
                              widget.sizeMultiplier,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          bubbleW * FriendsDualInsetGeometry.radiusRatio,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: _insetUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 360,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );

    if (widget.fillParent) return layout;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: layout,
      ),
    );
  }
}
