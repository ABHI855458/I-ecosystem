import 'package:flutter/material.dart';

import '../ping/ping_hold_reveal.dart';

// ---------------------------------------------------------------------------
// BlurredActorLine — a notification title with the actor's NAME blurred
// until the recipient hold-reveals it, e.g.
//
//     [Priya] pinged you 👋
//      ^blurred, hold to sharpen
//
// Reuses HoldToRevealBlur (lib/features/ping/ping_hold_reveal.dart) rather
// than rolling a second blur treatment: that widget is already the single
// canonical hold-to-reveal in this app — it consolidated three hand-rolled
// copies once before, and a fourth divergent one here would undo that. Its
// blur sigma, conic progress ring, haptics and 1s hold duration all come
// along unchanged, so this reads as the same gesture the Ping rows use.
//
// WHY ONLY THE NAME IS BLURRED, not the whole row: the point of the row is
// still legible while masked — you can see that you were pinged, and when,
// and choose whether to look at who. Blurring the entire line would hide
// the thing that makes it worth revealing.
//
// The ring is sized down (26 vs the default 42) and its hint text is
// suppressed by the compact layout, because this sits inline in a 13px
// text run rather than over a photo tile.
// ---------------------------------------------------------------------------

class BlurredActorLine extends StatelessWidget {
  const BlurredActorLine({
    super.key,
    required this.actorName,
    required this.suffix,
    required this.revealed,
    required this.onRevealed,
    required this.style,
  });

  /// The name to mask. Callers must not pass null/empty — a notification
  /// with no resolvable actor has nothing to blur and should render its
  /// plain server title instead (see NotifRowTitle's own branch).
  final String actorName;

  /// Everything after the name, including the leading space —
  /// ' pinged you 👋' / ' replied to your ping 🔥'.
  final String suffix;

  final bool revealed;
  final VoidCallback onRevealed;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Text.rich + WidgetSpan so the masked name sits ON the text baseline
    // and wraps with the sentence, instead of being a separate Row that
    // would break the line badly on a long name.
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: HoldToRevealBlur(
              revealed: revealed,
              onRevealed: onRevealed,
              // 14, not 18 — the caption removal alone still left the ring
              // taller than the ~17.5px line box a 13px-font sentence
              // affords (height:1.35 in the caller's style), which
              // overflowed by a hair. 14 sits inside it with margin.
              ringSize: 14,
              dotOpacity: 0.75,
              // BUG FOUND ON DEVICE: with the hint caption on (the
              // default), this row overflowed by exactly the caption's own
              // height — "hold 1s to reveal" doesn't fit inside a single
              // text line. Ring-only here; PlaceholderAlignment.middle (not
              // .baseline) is what keeps an 18px ring centered against the
              // surrounding 13px text instead of sitting low against its
              // baseline.
              showHint: false,
              child: Text(actorName, style: style),
            ),
          ),
          TextSpan(text: suffix, style: style),
        ],
      ),
      style: style,
    );
  }
}
