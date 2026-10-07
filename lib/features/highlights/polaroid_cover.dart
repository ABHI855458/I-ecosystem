import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../profile_v2/profile_v2_tokens.dart';

// ---------------------------------------------------------------------------
// The polaroid — the one shape every highlight is drawn as (profile row,
// the Wall, the feed pile, the editor's live preview).
//
// White paper frame, the photo, the name handwritten on the wide bottom
// strip, tilted a few degrees. A strip of coloured tape marks one the
// viewer hasn't opened yet; a watched one is dimmed. Never blurred — "new"
// is said by the tape, not by hiding the photo.
//
// THE PHOTO IS NEVER CROPPED (explicit report, 2026-10-07: "the photo which
// we upload from our album ... will be cut off ... how we see in our gallery
// like that only it shall appear"). The window takes the photo's own shape
// — a portrait photo makes a tall polaroid, a landscape one a wide window —
// and the photo is fitted whole inside it. Only the width is fixed.
// ---------------------------------------------------------------------------

const _kPaper = Color(0xFFF4F1EA);
const _kPaperInk = Color(0xFF26262B);
const _kPhotoWell = Color(0xFF1B1B1F);

/// The photo window keeps the photo's shape between these limits (width /
/// height). Past them the photo is still shown whole, with a little more
/// paper round it, rather than letting one very tall or very wide picture
/// make a polaroid that doesn't fit its row.
const kPolaroidMinAspect = 0.72;
const kPolaroidMaxAspect = 1.5;

/// A polaroid's height for a given width and photo shape (frame + photo
/// window + strip). [aspect] is the photo's width / height; 1 = square.
double polaroidHeightFor(double width, {double aspect = 1}) {
  final side = width * 0.07;
  final window = (width - side * 2) /
      aspect.clamp(kPolaroidMinAspect, kPolaroidMaxAspect);
  return side + window + width * 0.26;
}

/// The tallest a polaroid of [width] can be — what a row or grid cell
/// reserves so mixed shapes all fit.
double polaroidMaxHeightFor(double width) =>
    polaroidHeightFor(width, aspect: kPolaroidMinAspect);

/// A small, stable tilt for [seed] (a highlight id): between 1.5 and 4
/// degrees, left or right. Stable so a polaroid doesn't jump to a new angle
/// every rebuild.
double polaroidTiltFor(String seed) {
  final h = seed.hashCode & 0x7fffffff;
  final degrees = 1.5 + (h % 26) / 10; // 1.5 .. 4.0
  final sign = (h >> 5).isEven ? 1.0 : -1.0;
  return sign * degrees * math.pi / 180;
}

class PolaroidCover extends StatelessWidget {
  const PolaroidCover({
    super.key,
    required this.width,
    required this.title,
    this.imageUrl,
    this.localPath,
    this.aspect = 1,
    this.isVideo = false,
    this.tilt = 0,
    this.isNew = false,
    this.dimmed = false,
    this.heroTag,
    this.onTap,
    this.onLongPress,
  });

  final double width;
  final String title;
  final String? imageUrl;

  /// The photo's own shape (width / height). The window follows it, so the
  /// photo shows whole — see the note at the top of this file.
  final double aspect;

  /// A small play mark on the photo: this one is a video.
  final bool isVideo;

  /// A photo still on the phone (the editor's preview). Wins over
  /// [imageUrl].
  final String? localPath;

  /// Radians.
  final double tilt;

  /// Coloured tape across the top: not opened yet.
  final bool isNew;

  /// Already watched.
  final bool dimmed;

  final Object? heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final side = w * 0.07;
    final photo = w - side * 2;
    final photoHeight =
        photo / aspect.clamp(kPolaroidMinAspect, kPolaroidMaxAspect);

    // contain, never cover: the whole photo, as it looks in the gallery.
    Widget image;
    if (localPath != null) {
      image = Image.file(File(localPath!), fit: BoxFit.contain);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 160),
        placeholder: (_, _) => const ColoredBox(color: _kPhotoWell),
        errorWidget: (_, _, _) => const ColoredBox(color: _kPhotoWell),
      );
    } else {
      image = const ColoredBox(color: _kPhotoWell);
    }
    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }
    if (isVideo) {
      image = Stack(
        fit: StackFit.expand,
        children: [
          image,
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(w * 0.04),
              child: Container(
                width: w * 0.2,
                height: w * 0.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: w * 0.16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final paper = Container(
      width: w,
      height: polaroidHeightFor(w, aspect: aspect),
      decoration: BoxDecoration(
        color: _kPaper,
        borderRadius: BorderRadius.circular(w * 0.03),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: w * 0.12,
            offset: Offset(0, w * 0.05),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(height: side),
          SizedBox(
            width: photo,
            height: photoHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(w * 0.015),
              child: image,
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: side),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.caveat(
                    fontSize: w * 0.175,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: _kPaperInk,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Widget out = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Opacity(opacity: dimmed ? 0.5 : 1, child: paper),
        if (isNew)
          Positioned(
            top: -w * 0.055,
            child: Transform.rotate(
              angle: -0.09,
              child: Container(
                width: w * 0.44,
                height: w * 0.14,
                decoration: BoxDecoration(
                  color: PV2.accent.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(w * 0.015),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    if (tilt != 0) out = Transform.rotate(angle: tilt, child: out);
    if (onTap == null && onLongPress == null) return out;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: out,
    );
  }
}

/// The dashed empty polaroid — "+ New" on your profile, "Pin yours" on the
/// Wall. Same footprint as a [PolaroidCover] of the same width.
class PolaroidAddTile extends StatelessWidget {
  const PolaroidAddTile({
    super.key,
    required this.width,
    required this.label,
    required this.onTap,
    this.tilt = 0,
  });

  final double width;
  final String label;
  final VoidCallback onTap;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    Widget out = CustomPaint(
      painter: _DashedRRectPainter(
        color: Colors.white.withValues(alpha: 0.34),
        radius: width * 0.03,
      ),
      child: SizedBox(
        width: width,
        height: polaroidHeightFor(width),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_rounded,
              size: width * 0.34,
              color: PV2.accent,
            ),
            SizedBox(height: width * 0.04),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: width * 0.08),
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: PV2.body(
                  size: (width * 0.135).clamp(10.0, 14.0),
                  weight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (tilt != 0) out = Transform.rotate(angle: tilt, child: out);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: out,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}
