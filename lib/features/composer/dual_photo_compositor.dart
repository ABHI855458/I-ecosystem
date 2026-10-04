import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

// ---------------------------------------------------------------------------
// Extracted from composer_screen.dart so PingCameraScreen can produce the
// exact same BeReal-style back+front composite as the main composer,
// instead of drifting into a second, differently-styled implementation.
// Nothing about the compositing logic itself changed in the move.
// ---------------------------------------------------------------------------

/// Shared BeReal-inset geometry — the SAME ratios drive both the main
/// composer's live confirm-screen preview (_CandidMediaPreview) and the
/// flattened upload ([compositeDualPhotos]). Every ratio below is relative
/// to [previewWidth] so the same numbers reproduce the preview's
/// proportions at any bubble size.
class DualInsetGeometry {
  const DualInsetGeometry._();

  /// Preview values (design px, at the on-screen preview's own scale).
  ///
  /// 112x158 -> 92x130: the bubble was reported as too big and awkward
  /// against the post. Same 1:1.41 proportion, ~18% smaller, which is what
  /// takes it from "a second photo competing with the first" to an inset.
  static const previewWidth = 92.0;
  static const previewHeight = 130.0;
  static const previewMargin = 14.0;

  /// TOP inset, separate from [previewMargin] (which is the side one).
  ///
  /// Back to a normal margin now that the bubble sits on the RIGHT (see
  /// [onRight]). It had been pushed down to 34 to clear the anon card's
  /// persona avatar, which is pinned over the photo's top-LEFT corner
  /// (_PersonaAvatar at `left: 37.09, top: -36.93` in the 375-wide card
  /// space) with a matching seat scalloped out of the frame path. Nothing
  /// occupies the top-right, so the bubble no longer has to dodge anything.
  static const previewTopMargin = 16.0;

  /// The bubble is pinned to the top-RIGHT corner.
  ///
  /// It used to be top-left — exactly where the anon card puts the poster's
  /// persona avatar — so the two fought over one corner and the selfie
  /// ended up part-covered no matter how the margins were tuned. Moving it
  /// across resolves that by construction rather than by clearance:
  /// "shift the front camera photo in the anon feed to the right side".
  static const onRight = true;

  /// A hairline, not the old 3px black slab — that read as a heavy frame
  /// welded onto the photo rather than an edge, and a pure black stroke
  /// vanished into dark frames entirely. Light and translucent so it
  /// separates the bubble from any photo behind it; depth comes from the
  /// drop shadow underneath instead.
  static const previewBorderWidth = 1.6;
  static const previewBorderColor = Color(0x8CFFFFFF);
  static const previewRadius = 18.0;

  /// Bubble width as a fraction of the BIG photo's width — unrelated to the
  /// preview's on-screen pixel size (that's a fraction of the phone's
  /// screen, not of the capture's resolution); kept at the app's existing
  /// design ratio.
  static const bubbleWidthRatio = 0.23;

  /// The rest scale off the bubble's own width, so they stay proportional
  /// to whatever bubbleWidthRatio produces.
  static const aspectRatio = previewHeight / previewWidth;
  static const marginRatio = previewMargin / previewWidth;
  static const topMarginRatio = previewTopMargin / previewWidth;
  static const borderRatio = previewBorderWidth / previewWidth;
  static const radiusRatio = previewRadius / previewWidth;
}

/// The FRIENDS-feed dual geometry, measured off the reference screenshot
/// rather than inherited from [DualInsetGeometry].
///
/// Separate from [DualInsetGeometry] on purpose: that one still drives the
/// anon/camera composer's flattened bake, which was deliberately settled on
/// its own corner and proportions (see [DualInsetGeometry.onRight]). A
/// friends post is a different surface with a different reference, so it
/// gets its own numbers instead of the two fighting over one set.
///
/// Base is the reference's own 121x161pt bubble inside a 402pt-wide frame;
/// every ratio below divides out of that so the same proportions reproduce
/// at any render width.
class FriendsDualInsetGeometry {
  const FriendsDualInsetGeometry._();

  static const baseWidth = 121.0;
  static const baseHeight = 161.0;
  static const baseMargin = 12.0;
  static const baseRadius = 9.0;

  /// Sits lower than the left margin, rather than tucked into the very
  /// corner. Explicit follow-up: "bring the dual camera photo little more
  /// down" — the inset used to share [baseMargin] on both axes, which put
  /// it hard against the top edge once the frame grew taller.
  static const baseTopMargin = 44.0;

  /// Painted BEHIND the inset photo. Explicit follow-up: "provide it with a
  /// black background" — a photo that doesn't fill the bubble (or is still
  /// loading) showed the background photo through it, which read as a
  /// glitch rather than a deliberate cutout.
  static const backgroundColor = Color(0xFF000000);

  /// The reference frame's own width — the denominator every ratio below
  /// divides out of, so [baseWidth] lands back on exactly 121 at this width
  /// rather than near it.
  static const baseFrameWidth = 402.0;

  /// Pinned top-LEFT, matching the reference and the `insetOnRight: false`
  /// every friends post is already written with.
  static const onRight = false;

  /// Black, not [DualInsetGeometry]'s translucent white hairline. The
  /// reference's inset is separated by a hard dark edge — it reads as the
  /// dark app ground showing through a cutout rather than a stroke drawn on
  /// the photo, and the drop shadow below still carries the depth.
  static const borderWidth = 2.0;
  static const borderColor = Color(0xFF000000);

  /// 121/402 of the background photo's width.
  static const bubbleWidthRatio = baseWidth / baseFrameWidth;

  static const aspectRatio = baseHeight / baseWidth;
  static const marginRatio = baseMargin / baseWidth;
  static const topMarginRatio = baseTopMargin / baseWidth;
  static const radiusRatio = baseRadius / baseWidth;
}

/// The friends post frame: a tall 2:3 photo with softly rounded corners.
///
/// Was 3:4 at a 12pt top-only radius, matching a reference screenshot whose
/// photo ran edge to edge into a square-bottomed footer. Explicit follow-up:
/// "i have updated the posts length, so basically increase the size of the
/// widgets and round the edges as it was there before" — so the frame is
/// taller again (2:3 gives more height per unit width than 3:4) and the
/// corners are back to the app's own 26pt rounding, on all four sides.
const kFriendsPostAspect = 2 / 3;

/// Measured off the reference screenshot: the photo's corner arc is ~7.5%
/// of the frame's width, which at a 402pt-wide phone is ~30pt. Explicit
/// follow-up: "the curve of the edges... it looks sharp, same like the old
/// posts... the curved edges shall look beautiful like this".
///
/// BUMPED to 36 — explicit follow-up: "the posts edges aren't sufficiently
/// curved... before it looked awesome unlike now". Two real causes, not
/// just a bigger number: (1) the feed list wrapper now insets every card
/// from the phone's edges (see the ListView padding in
/// everyone_feed_screen.dart) rather than running it full-bleed, and an
/// inset card needs more radius for the same visual curve than a flush
/// one; (2) DesignGroupCard's photo was rounding at a separate, smaller
/// 20pt (see PostPhotoCarousel's own call site there) — now unified to
/// this same constant so personal and group posts read as one consistent
/// feed rather than two different corner treatments.
const kFriendsPostRadius = 36.0;

/// The ping / RealMoji buttons on a post's action rail. Scaled with the
/// taller frame — explicit request: "as the size of post has increased
/// accordingly increase the ping and real emoji button sizes as well".
///
/// BUMPED to 48 — follow-up explicit request to scale these again
/// relative to the post size, alongside the DP and reaction-viewer chip
/// (see _Avatar's default size and ReactionPreviewChip in
/// post_card_shared.dart).
///
/// TRIMMED 48 -> 42 — explicit follow-up that 48 read too large ("reduce
/// the size a little"). Still above the 34dp every other card (Everyone/
/// Group) uses for this same Ping+RealMoji pair, just less oversized.
const kPostRailButtonSize = 42.0;

/// Cover-crops [file] to [outputAspect] — the SAME crop a dual photo's
/// background gets inside [compositeDualPhotos] (see that function's own
/// doc on why: "the same aspect ratio every surface displays a post at").
///
/// A plain single-photo post never got this treatment before — it uploaded
/// at its raw native aspect (whatever the gallery pick or camera capture
/// happened to be) and left the feed's own BoxFit.cover to crop it at
/// DISPLAY time instead, uncropped in storage. That made a dual post and a
/// single post of the same subject frame differently in the feed — a dual
/// post's crop was already decided and consistent, a single post's crop
/// depended on whatever aspect ratio the source file happened to have.
/// Explicit request: "make the photo size and the dual camera side same...
/// keeping everything same" — this is what makes them the same.
Future<XFile> cropToAspect(XFile file, {double outputAspect = 4 / 5}) async {
  try {
    final bytes = await File(file.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    final src = _coverCropRect(
      img.width.toDouble(),
      img.height.toDouble(),
      outputAspect,
    );
    final w = src.width;
    final h = src.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, w, h), Paint());
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(w.toInt(), h.toInt());
    final pngData = await cropped.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();

    final dir = File(file.path).parent;
    final path =
        '${dir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(pngData!.buffer.asUint8List());
    return XFile(path);
  } catch (_) {
    return file;
  }
}

/// Shared cover-crop math — centre-crop the source rect down to
/// [outputAspect], cropping sides if the source is relatively wider, top/
/// bottom if relatively taller. Used by both [cropToAspect] and
/// [compositeDualPhotos]'s own background crop, so the two can never drift
/// apart on how a photo gets cropped.
Rect _coverCropRect(double srcW, double srcH, double outputAspect) {
  final srcAspect = srcW / srcH;
  if (srcAspect > outputAspect) {
    final cropW = srcH * outputAspect;
    return Rect.fromLTWH((srcW - cropW) / 2, 0, cropW, srcH);
  }
  final cropH = srcW / outputAspect;
  return Rect.fromLTWH(0, (srcH - cropH) / 2, srcW, cropH);
}

/// Composites [back] and [front] into one flattened image for upload —
/// whichever of the two is NOT [frontIsBig] is the full-bleed background,
/// the other is the rounded, bordered inset bubble pinned to the top-left
/// corner (matching design-refs/camera feature's fixed PiP position — no
/// drag-to-corner), using the exact same radius/border/margin ratios as
/// _CandidMediaPreview via [DualInsetGeometry] so the posted photo matches
/// whatever the caller last arranged (composer's confirm screen lets the
/// user flip big/small before sending; PingCameraScreen has no such step
/// and always passes `frontIsBig: false`).
Future<XFile> compositeDualPhotos(
  XFile back,
  XFile front, {
  required bool frontIsBig,
  double outputAspect = 4 / 5,
}) async {
  try {
    final bigFile = frontIsBig ? front : back;
    final smallFile = frontIsBig ? back : front;
    final bigBytes = await File(bigFile.path).readAsBytes();
    final smallBytes = await File(smallFile.path).readAsBytes();

    final bigCodec = await ui.instantiateImageCodec(bigBytes);
    final smallCodec = await ui.instantiateImageCodec(smallBytes);
    final bigImg = (await bigCodec.getNextFrame()).image;
    final smallImg = (await smallCodec.getNextFrame()).image;

    // Flatten to the SAME aspect ratio every surface displays a post at
    // (PhotoPostCard.imageAspectRatio / the composer preview, both 4:5),
    // cover-cropping the big photo here rather than leaving a 3:4 or 9:16
    // capture to be centre-cropped again at render time. That second crop
    // is what was eating the front-camera bubble: it sits in the top-left
    // corner, which is exactly the band a centre-crop of a taller-than-4:5
    // photo throws away. Compositing at the display ratio makes what the
    // person confirms the thing that actually gets shown.
    final bigSrc = _coverCropRect(
      bigImg.width.toDouble(),
      bigImg.height.toDouble(),
      outputAspect,
    );
    final w = bigSrc.width;
    final h = bigSrc.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(bigImg, bigSrc, Rect.fromLTWH(0, 0, w, h), Paint());

    final bubbleW = w * DualInsetGeometry.bubbleWidthRatio;
    // Fixed aspect ratio, matching the preview's own 112x158 box — NOT the
    // small photo's own aspect ratio (that was the old bug: it let the
    // bubble's shape drift from what the preview showed).
    final bubbleH = bubbleW * DualInsetGeometry.aspectRatio;
    final margin = bubbleW * DualInsetGeometry.marginRatio;
    final borderWidth = bubbleW * DualInsetGeometry.borderRatio;
    final left = DualInsetGeometry.onRight ? (w - bubbleW - margin) : margin;
    final top = bubbleW * DualInsetGeometry.topMarginRatio;
    final bubbleRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, bubbleW, bubbleH),
      Radius.circular(bubbleW * DualInsetGeometry.radiusRatio),
    );

    canvas.drawRRect(
      bubbleRRect.shift(const Offset(0, 3)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
    );

    // Cover-crop the small photo into the bubble's fixed aspect ratio —
    // matching Image.fit: cover in the live preview (_CandidMediaPreview's
    // _photo()) — rather than stretching the whole source image into a
    // differently-shaped box, which is what a full-source drawImageRect
    // into a fixed-aspect target would otherwise do.
    final smallW = smallImg.width.toDouble();
    final smallH = smallImg.height.toDouble();
    final srcAspect = smallW / smallH;
    final dstAspect = bubbleW / bubbleH;
    late final Rect srcRect;
    if (srcAspect > dstAspect) {
      // Source is relatively wider than the bubble — crop its sides.
      final cropW = smallH * dstAspect;
      srcRect = Rect.fromLTWH((smallW - cropW) / 2, 0, cropW, smallH);
    } else {
      // Source is relatively taller — crop top/bottom.
      final cropH = smallW / dstAspect;
      srcRect = Rect.fromLTWH(0, (smallH - cropH) / 2, smallW, cropH);
    }

    canvas.save();
    canvas.clipRRect(bubbleRRect);
    canvas.drawImageRect(
      smallImg,
      srcRect,
      Rect.fromLTWH(left, top, bubbleW, bubbleH),
      Paint(),
    );
    canvas.restore();

    canvas.drawRRect(
      bubbleRRect,
      Paint()
        ..color = DualInsetGeometry.previewBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    final picture = recorder.endRecording();
    final composite = await picture.toImage(w.toInt(), h.toInt());
    final pngData = await composite.toByteData(format: ui.ImageByteFormat.png);

    bigImg.dispose();
    smallImg.dispose();

    final dir = File(back.path).parent;
    final path =
        '${dir.path}/dual_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(pngData!.buffer.asUint8List());
    return XFile(path);
  } catch (_) {
    return back;
  }
}
