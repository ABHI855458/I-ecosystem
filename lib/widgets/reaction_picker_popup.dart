import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Quick reaction picker — glass pill of emoji buttons, shown on long-press.
/// Same visual language (frosted glass, bounce-on-select) as the popup in
/// `anonymous_tab.dart`'s `_buildReactionPopup`, rebuilt as a standalone
/// widget so it isn't tied to that screen's per-post state.
const kQuickReactionEmojis = ['🔥', '💀', '❤️', '😂', '👀'];
const kQuickReactionColors = [
  Color(0xFFF77737),
  Color(0xFFDDDDDD),
  Color(0xFFE1306C),
  Color(0xFFF7B733),
  Color(0xFF405DE6),
];

class ReactionPickerPopup extends StatefulWidget {
  const ReactionPickerPopup({super.key, required this.onSelect});
  final ValueChanged<String> onSelect;

  @override
  State<ReactionPickerPopup> createState() => _ReactionPickerPopupState();
}

class _ReactionPickerPopupState extends State<ReactionPickerPopup> {
  int? _bouncing;

  void _tap(int idx) {
    HapticFeedback.mediumImpact();
    setState(() => _bouncing = idx);
    widget.onSelect(kQuickReactionEmojis[idx]);
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _bouncing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < kQuickReactionEmojis.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _button(i),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(int idx) {
    final bouncing = _bouncing == idx;
    return GestureDetector(
      onTap: () => _tap(idx),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: bouncing ? 1.4 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.elasticOut,
        // Fixed width/height + BoxShape.circle instead of symmetric padding
        // + borderRadius — that combination sized itself off the emoji
        // glyph's own (non-square) text metrics, so these never actually
        // came out as circles. Matches every other reaction chip in the
        // app (PresetAvatar, RealmojiTray's chips, etc.), all a plain fixed
        // circle.
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kQuickReactionColors[idx].withValues(alpha: 0.12),
          ),
          child: Text(kQuickReactionEmojis[idx], style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}
