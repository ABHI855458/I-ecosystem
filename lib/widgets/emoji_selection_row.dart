import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_drawing/path_drawing.dart';

import '../core/constants.dart';

// ---------------------------------------------------------------------------
// EmojiSelectionRow — Step 1 of the reaction-preset creation flow: a
// horizontal scrollable row of curated emoji in dashed-circle slots, plus a
// trailing bolt "capture new" slot for an emoji outside that curated set.
// Renamed from the old EmojiGridPicker (a 6-column GridView) to match the
// spec's "horizontal scrollable row of emoji choices in outlined circles"
// requirement — same curated set (kPresetEmojiChoices, unchanged) and same
// pop-with-the-chosen-emoji convention, just a different layout.
//
// "Capture new" deliberately doesn't pull in a full unicode emoji-picker
// package (see kPresetEmojiChoices' own reasoning below) — it reveals a
// plain TextField, autofocused so the OS's own emoji keyboard can be
// switched to, and takes exactly one grapheme cluster via
// `text.characters.first` (the `characters` extension re-exported by
// package:flutter/material.dart — handles multi-codepoint emoji like ZWJ
// sequences and flags correctly, unlike raw String indexing).
// ---------------------------------------------------------------------------

const kPresetEmojiChoices = [
  '😀', '😂', '🥹', '😍', '😎', '🥳', '😭', '😡', '🤯', '🤔', '😴', '🤢',
  '🔥', '💀', '⭕', '👀', '❤️', '💯', '👍', '👎', '👏', '🙌', '🙏', '💪',
  '✨', '🎉', '😅', '😏', '🥲', '😤', '🤩', '🫡', '😬', '🫠', '🤪', '😇',
];

class EmojiSelectionRow extends StatefulWidget {
  const EmojiSelectionRow({super.key, this.title = 'Pick an emoji'});
  final String title;

  @override
  State<EmojiSelectionRow> createState() => _EmojiSelectionRowState();
}

class _EmojiSelectionRowState extends State<EmojiSelectionRow> {
  bool _capturing = false;
  final _captureController = TextEditingController();
  final _captureFocus = FocusNode();

  @override
  void dispose() {
    _captureController.dispose();
    _captureFocus.dispose();
    super.dispose();
  }

  void _select(String emoji) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(emoji);
  }

  void _startCapture() {
    HapticFeedback.selectionClick();
    setState(() => _capturing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureFocus.requestFocus();
    });
  }

  void _submitCapture() {
    final text = _captureController.text.trim();
    if (text.isEmpty) return;
    _select(text.characters.first);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_capturing) _buildCaptureField() else _buildRow(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRow() {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: kPresetEmojiChoices.length + 1,
        separatorBuilder: (context, i) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          if (i == kPresetEmojiChoices.length) {
            return _CaptureNewSlot(onTap: _startCapture);
          }
          final emoji = kPresetEmojiChoices[i];
          return _DashedEmojiSlot(emoji: emoji, onTap: () => _select(emoji));
        },
      ),
    );
  }

  Widget _buildCaptureField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _captureController,
              focusNode: _captureFocus,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26),
              maxLength: 8,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Type or paste an emoji',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                filled: true,
                fillColor: AppColors.cardSurface,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submitCapture(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _submitCapture,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.coral),
              child: const Icon(Icons.check_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedEmojiSlot extends StatelessWidget {
  const _DashedEmojiSlot({required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  static const double _size = 60;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: const _DashedCirclePainter(
          color: Color.fromRGBO(255, 255, 255, 0.28),
          dashWidth: 4,
          dashGap: 3,
        ),
        child: SizedBox(
          width: _size,
          height: _size,
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
        ),
      ),
    );
  }
}

class _CaptureNewSlot extends StatelessWidget {
  const _CaptureNewSlot({required this.onTap});
  final VoidCallback onTap;

  static const double _size = 60;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.coral.withValues(alpha: 0.18),
          border: Border.all(color: AppColors.coral.withValues(alpha: 0.6), width: 1.5),
        ),
        child: const Icon(Icons.bolt, color: Colors.white, size: 26),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashed circle stroke — built on path_drawing's dashPath/CircularIntervalList
// (already a pubspec dependency, already used by
// pixel_exact_post_card_clipper.dart) rather than hand-rolled
// PathMetric.computeMetrics() walking, which is what home_screen.dart's own
// _DashedBorderPainter uses for its (rectangular) dashed border. Simpler for
// a plain oval: dash the oval path directly.
// ---------------------------------------------------------------------------

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({
    required this.color,
    required this.dashWidth,
    required this.dashGap,
  });

  final Color color;
  final double dashWidth;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final circle = Path()..addOval(rect);
    final dashed = dashPath(
      circle,
      dashArray: CircularIntervalList<double>([dashWidth, dashGap]),
    );
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) =>
      old.color != color || old.dashWidth != dashWidth || old.dashGap != dashGap;
}
