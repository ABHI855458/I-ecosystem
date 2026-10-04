import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'profile_v2_tokens.dart';

// ---------------------------------------------------------------------------
// LockedPreview — "there is something here, and you can't see it yet."
//
// The alternative treatments are both worse. Hiding a section entirely makes
// a rich profile look empty, so a stranger has no reason to send a request.
// Showing the content defeats the point. This shows the SHAPE of what exists
// — how many posts, how many groups — over a blurred, non-interactive
// placeholder.
//
// IMPORTANT: this is a presentation layer, not a security boundary. The
// caller must not fetch the real content for a viewer who fails the check —
// see TheirProfileScreen._loadTheirPosts, which skips the fetch entirely
// rather than fetching and covering it up. Anything genuinely private
// (Us-album photos) is additionally refused by RLS.
// ---------------------------------------------------------------------------

class LockedPreview extends StatelessWidget {
  const LockedPreview({
    super.key,
    required this.label,
    this.count,
    this.height = 190,
    this.tiles = 3,
  });

  /// What is behind the blur, in the person's own words — "3 posts".
  final String label;

  /// Shown as a numeral when known. Null hides it, which is right when the
  /// count itself would leak something.
  final int? count;

  final double height;

  /// How many placeholder tiles to draw. Cosmetic only.
  final int tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The placeholder content. Deliberately abstract shapes rather
          // than a blurred copy of the real thing — there is no real thing
          // on this device to blur.
          Row(
            children: [
              for (var i = 0; i < tiles; i++) ...[
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.075 - i * 0.015),
                          Colors.white.withValues(alpha: 0.025),
                        ],
                      ),
                    ),
                  ),
                ),
                if (i != tiles - 1) const SizedBox(width: 10),
              ],
            ],
          ),

          // The blur itself. Sigma is high enough that no edge survives.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
              ),
            ),
          ),

          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 17,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  count == null ? label : '$count $label',
                  style: PV2.body(size: 13, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  'Add them to see',
                  style: PV2.body(size: 11.5, color: PV2.inkStamp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
