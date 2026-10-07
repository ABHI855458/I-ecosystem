import 'package:flutter/material.dart';

import '../profile_v2/profile_v2_tokens.dart';
import 'highlight_models.dart';
import 'polaroid_cover.dart';

// ---------------------------------------------------------------------------
// The pile — ONE stack of polaroids at the right end of the Friends feed's
// top section. Not a tray of circles: a single object showing the newest
// friend's cover and how many are new.
//
// It says what it is. The first version was a dimmed polaroid over the
// word "Wall", which read as a disabled, unexplained thing ("this here
// isn't clear", 2026-10-07). Now: a HIGHLIGHTS heading that mirrors the
// heading on the left, a photo that is never dimmed, and a "3 new" badge
// on the pile itself when there is something to watch.
//
// Two taps, two things (2026-10-07: "if clicked on photo it shall be
// seen"): the CARD opens the photo on it; the HEADING opens the Wall.
// ---------------------------------------------------------------------------

class PolaroidPile extends StatelessWidget {
  const PolaroidPile({
    super.key,
    required this.top,
    required this.newCount,
    required this.onTap,
    required this.onOpenWall,
    this.loading = false,
    this.width = 74,
  });

  /// The Wall hasn't answered yet: a blank sheet on top, rather than the
  /// "+" that means there is nothing on it.
  final bool loading;

  /// The polaroid shown on top: the newest unseen one, or (nothing new) the
  /// most recent one. Null when there is nothing on the Wall yet.
  final Highlight? top;
  final int newCount;

  /// The card was tapped: play what is on it.
  final VoidCallback onTap;

  /// The heading was tapped: the whole Wall.
  final VoidCallback onOpenWall;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width;
    // A square window here (the photo is still shown whole inside it): the
    // pile has to stay one fixed size or the feed's top section would jump.
    final h = polaroidHeightFor(w);
    final fresh = newCount > 0;
    final headingColor = fresh ? PV2.accent : PV2.inkMember;

    Widget sheet(double angle, Offset offset, double alpha) => Positioned(
      left: 13 + offset.dx,
      top: 8 + offset.dy,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFF3A3A40),
              const Color(0xFFF4F1EA),
              alpha,
            ),
            borderRadius: BorderRadius.circular(w * 0.03),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          key: const ValueKey('polaroid-pile-heading'),
          behavior: HitTestBehavior.opaque,
          onTap: onOpenWall,
          child: Padding(
            // A taller touch target than the small caps alone.
            padding: const EdgeInsets.only(left: 12, bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'HIGHLIGHTS',
                  style: PV2.caps(
                    size: 11.5,
                    tracking: 0.14,
                    color: headingColor,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: headingColor,
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          key: const ValueKey('polaroid-pile'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: w + 26,
            height: h + 16,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Two sheets peeking out behind: it reads as a pile even
                // when only one polaroid exists.
                sheet(0.14, const Offset(5, 1), 0.62),
                sheet(-0.11, const Offset(-5, 2), 0.82),
                Positioned(
                  left: 13,
                  top: 6,
                  child: top == null
                      ? (loading
                            ? Transform.rotate(
                                angle: 0.03,
                                child: Container(
                                  width: w,
                                  height: h,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF4F1EA),
                                    borderRadius: BorderRadius.circular(
                                      w * 0.03,
                                    ),
                                  ),
                                ),
                              )
                            : PolaroidAddTile(
                                width: w,
                                label: '',
                                onTap: onTap,
                              ))
                      : PolaroidCover(
                          width: w,
                          title: top!.title,
                          imageUrl: top!.coverUrl,
                          isVideo: top!.coverIsVideo,
                          tilt: 0.03,
                          isNew: fresh,
                        ),
                ),
                if (fresh)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: -4,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: PV2.accentButton,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          '$newCount new',
                          maxLines: 1,
                          style: PV2.body(
                            size: 10.5,
                            weight: FontWeight.w800,
                            color: PV2.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
