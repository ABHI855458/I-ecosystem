import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// TextPingCard — how a WORDS-ONLY ping reply looks.
//
// A ping reply is normally a photo. Replying with just text was always
// possible (ping_replies.kind == 'text', body set, photo_url null) but had no
// design of its own: the viewer painted the same cyan/hatch placeholder it
// uses while a photo loads, then dropped the words in as a 13.5px caption
// pinned to the bottom edge. A three-word reply and a three-sentence one
// looked identical, and both looked like a photo that had failed to load.
//
// This is the treatment asked for instead: a black card with the words set
// IN it, and the type sized against the length of what was written — short
// replies land large and loud, long ones step down until they fit — so the
// card always reads as full rather than as a caption floating in a void.
// Used by every ping kind (personal, group, anon), which is why it lives in
// its own file rather than inside one screen's build method.
// ---------------------------------------------------------------------------

/// The longest a text reply can be.
///
/// 260 is where TextPingCard's own size tiers bottom out — past it every
/// reply renders at the same smallest size, so a longer one reads as a wall
/// of text rather than a statement. Explicit request: "in text reply
/// correctly format how many words can be typed".
const kPingReplyMaxChars = 260;

class TextPingCard extends StatelessWidget {
  const TextPingCard({
    super.key,
    required this.text,
    this.scale = 1.0,
    this.accent = const Color(0xFF29D3E8),
  });

  final String text;

  /// Multiplies every size, so the same card works both full-bleed in the
  /// reply viewer and shrunk inside a feed row.
  final double scale;

  /// Tints the quote mark and the hairline only — the ground stays black.
  final Color accent;

  /// Type size for a given length.
  ///
  /// Deliberately stepped rather than continuous: a smooth
  /// size-per-character curve makes two replies of similar length render at
  /// visibly different sizes for no reason a reader can perceive, whereas
  /// tiers keep everything in a band looking like a set. Thresholds are in
  /// characters because that is what actually drives how many lines the
  /// paragraph takes at these widths.
  static double sizeFor(String value) {
    final n = value.characters.length;
    if (n <= 20) return 42;
    if (n <= 45) return 34;
    if (n <= 90) return 27;
    if (n <= 160) return 22;
    if (n <= 260) return 18;
    return 15.5;
  }

  @override
  Widget build(BuildContext context) {
    final body = text.trim();
    final size = sizeFor(body) * scale;
    // Short, loud replies get centred like a statement; long ones read
    // better left-aligned as prose.
    final short = body.characters.length <= 90;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF08080A)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Barely-there wash so a pure-black card doesn't read as a
          // rendering failure on an OLED screen.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.05),
                  Colors.transparent,
                  Colors.black,
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 26 * scale,
              vertical: 30 * scale,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment:
                  short ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                // The decorative opening quote mark that used to sit here is
                // gone — explicit request: "remove the colons seen there in
                // text reply". The accent rule under the text still frames
                // it as a quote without punctuation floating above the
                // first line.
                // Scales down further if a very long reply still overruns
                // the card at the smallest tier, so text is never clipped.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment:
                        short ? Alignment.center : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 320 * scale),
                      child: Text(
                        body,
                        textAlign: short ? TextAlign.center : TextAlign.left,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: size,
                          height: 1.22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015 * size,
                          color: const Color(0xFFF4F4F5),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 14 * scale),
                Container(
                  width: 34 * scale,
                  height: 2 * scale,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
