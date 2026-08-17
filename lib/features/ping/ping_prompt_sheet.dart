import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

enum PingContext { everyone, anonymous }

void showPingPromptSheet(
  BuildContext context, {
  required String targetName,
  required PingContext pingContext,
  VoidCallback? onSent,
  bool glass = false,
  double heightFraction = 0.88,
  bool roundedTopOnly = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PingPromptSheet(
      targetName: targetName,
      pingContext: pingContext,
      onSent: onSent,
      glass: glass,
      heightFraction: heightFraction,
      roundedTopOnly: roundedTopOnly,
    ),
  );
}

// ---------------------------------------------------------------------------
// Prompt data
// ---------------------------------------------------------------------------

class _Prompt {
  const _Prompt({required this.text, required this.cardColor});

  final String text;
  final Color cardColor;
}

const _everyonePrompts = [
  // Casual / Friendly
  _Prompt(text: "Hey, want to hang out? 👋", cardColor: Color(0xFF0F2A1E)),
  _Prompt(text: "Coffee sometime? ☕", cardColor: Color(0xFF2A1A0F)),
  _Prompt(text: "Let's catch up soon!", cardColor: Color(0xFF0F1A2A)),
  _Prompt(text: "Miss you! Where you been?", cardColor: Color(0xFF2A0F1A)),
  _Prompt(text: "Long time no see!", cardColor: Color(0xFF1A0F1E)),
  _Prompt(text: "What are you up to?", cardColor: Color(0xFF0F1A1E)),
  // Activity
  _Prompt(text: "Study session? 📚", cardColor: Color(0xFF0F1E2A)),
  _Prompt(text: "Gym buddy? 💪", cardColor: Color(0xFF1E0F2A)),
  _Prompt(text: "Lunch today? 🍕", cardColor: Color(0xFF2A1E0F)),
  _Prompt(text: "Movie this weekend? 🎬", cardColor: Color(0xFF0F182A)),
  _Prompt(text: "We should hang!", cardColor: Color(0xFF2A1A0F)),
  _Prompt(text: "You free this weekend?", cardColor: Color(0xFF1E2A0F)),
  // Reaction
  _Prompt(text: "That post was 🔥", cardColor: Color(0xFF2A0F0F)),
  _Prompt(text: "You're hilarious 😂", cardColor: Color(0xFF0F2A0F)),
  _Prompt(text: "Love your vibe ✨", cardColor: Color(0xFF1E0F2A)),
  _Prompt(text: "Great photos! 📸", cardColor: Color(0xFF0F1E2A)),
  _Prompt(text: "Same vibes honestly 🙌", cardColor: Color(0xFF1A2A1A)),
  _Prompt(text: "Saw your post, let's talk!", cardColor: Color(0xFF0F0F2A)),
  // Flirty
  _Prompt(text: "Caught my eye 👀", cardColor: Color(0xFF2A0F1E)),
  _Prompt(text: "We should talk more 😊", cardColor: Color(0xFF0F2A1E)),
  // More
  _Prompt(text: "Collab on something? 🎯", cardColor: Color(0xFF0F2A2A)),
  _Prompt(text: "You good? Checking in 🤍", cardColor: Color(0xFF2A1A2A)),
];

const _anonPrompts = [
  _Prompt(text: "I relate to this so much", cardColor: Color(0xFF0F0F1E)),
  _Prompt(
    text: "You're not alone in feeling this",
    cardColor: Color(0xFF0F1E0F),
  ),
  _Prompt(text: "This needed to be said", cardColor: Color(0xFF1E0F0F)),
  _Prompt(text: "Sending you good vibes 🌙", cardColor: Color(0xFF0F0F1E)),
  _Prompt(text: "We should talk (anon)", cardColor: Color(0xFF1E1E0F)),
  _Prompt(text: "Your words matter", cardColor: Color(0xFF0F1E1E)),
  _Prompt(text: "Same here, honestly", cardColor: Color(0xFF1E0F1E)),
  _Prompt(text: "Thank you for sharing this", cardColor: Color(0xFF0F1A0F)),
  _Prompt(text: "I see you 👁️", cardColor: Color(0xFF1A0F0F)),
  _Prompt(text: "This hit different", cardColor: Color(0xFF0F0F1A)),
  _Prompt(text: "Felt this in my chest", cardColor: Color(0xFF1A1A0F)),
  _Prompt(text: "You're braver than you think", cardColor: Color(0xFF0F1A1A)),
  _Prompt(text: "Me too, honestly", cardColor: Color(0xFF1A0F1A)),
  _Prompt(text: "Hope you're okay 🤍", cardColor: Color(0xFF0F0F1E)),
  _Prompt(text: "This is real. I feel it too", cardColor: Color(0xFF1E0F0F)),
];

// ---------------------------------------------------------------------------
// Sheet widget
// ---------------------------------------------------------------------------

class PingPromptSheet extends StatefulWidget {
  const PingPromptSheet({
    super.key,
    required this.targetName,
    required this.pingContext,
    this.onSent,
    this.glass = false,
    this.heightFraction = 0.88,
    this.roundedTopOnly = false,
  });

  final String targetName;
  final PingContext pingContext;
  final VoidCallback? onSent;

  /// Frosted/blurred sheet chrome (matches the Ping tab's own choice sheet)
  /// instead of the default opaque card surface. Everyone's ping button
  /// uses this; Anonymous keeps its original look.
  final bool glass;

  /// Fraction of screen height the sheet is capped at. Content beyond that
  /// scrolls inside the existing prompt-list ScrollView rather than
  /// overflowing. Default matches the original (near-full-height) sheet.
  final double heightFraction;

  /// True for a compact bottom-sheet silhouette: only the top corners are
  /// rounded and the sheet sits flush against the screen edges (no floating
  /// side/bottom margin) — used by the Anonymous feed's notch ping icon.
  /// False keeps the original floating card look (rounded on all corners,
  /// inset margin on every side).
  final bool roundedTopOnly;

  @override
  State<PingPromptSheet> createState() => _PingPromptSheetState();
}

class _PingPromptSheetState extends State<PingPromptSheet>
    with SingleTickerProviderStateMixin {
  int? _selectedIndex;
  bool _editing = false;
  bool _sent = false;
  late final TextEditingController _editCtrl;
  late final AnimationController _sendCtrl;

  List<_Prompt> get _prompts => widget.pingContext == PingContext.everyone
      ? _everyonePrompts
      : _anonPrompts;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
    _sendCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    _sendCtrl.dispose();
    super.dispose();
  }

  void _selectPrompt(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _editing = false;
    });
  }

  void _startEdit() {
    if (_selectedIndex != null && _editCtrl.text.isEmpty) {
      _editCtrl.text = _prompts[_selectedIndex!].text;
    }
    setState(() => _editing = true);
  }

  bool get _canSend {
    if (_sent) return false;
    if (_editing) return _editCtrl.text.trim().isNotEmpty;
    return _selectedIndex != null;
  }

  void _send() {
    if (!_canSend) return;
    HapticFeedback.heavyImpact();
    setState(() => _sent = true);
    _sendCtrl.forward();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSent?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final maxH = MediaQuery.of(context).size.height * widget.heightFraction;
    final radius = widget.roundedTopOnly
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          )
        : BorderRadius.circular(24);

    final sheet = Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: widget.glass
          ? null
          : BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: radius,
              border: Border.all(color: AppColors.border),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.pingContext == PingContext.anonymous
                          ? AppColors.border
                          : AppColors.coral.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.pingContext == PingContext.anonymous
                          ? '?'
                          : widget.targetName[0].toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 18,
                        color: widget.pingContext == PingContext.anonymous
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.pingContext == PingContext.anonymous
                            ? 'Send an anonymous ping'
                            : 'Ping ${widget.targetName}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.pingContext == PingContext.anonymous
                            ? "They won't know it's you"
                            : 'Pick a prompt or write your own',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: AppColors.border),

          // Main content
          if (_sent)
            SizedBox(height: 260, child: _buildSentState())
          else
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prompt scroll
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.pingContext == PingContext.everyone
                                ? 'choose a prompt'
                                : 'anonymous prompts',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (int i = 0; i < _prompts.length; i++)
                                _PromptChip(
                                  prompt: _prompts[i],
                                  selected: _selectedIndex == i && !_editing,
                                  onTap: () => _selectPrompt(i),
                                ),
                              _WriteOwnChip(onTap: _startEdit),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Edit field
                  if (_editing)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.coral.withValues(alpha: 0.50),
                          ),
                        ),
                        child: TextField(
                          controller: _editCtrl,
                          autofocus: true,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: 'Write your message...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.textMuted,
                            ),
                          ),
                          maxLines: 3,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),

                  // Action bar
                  if (_selectedIndex != null || _editing) _buildActionBar(),

                  SizedBox(height: bottomPad + 8),
                ],
              ),
            ),
        ],
      ),
    );

    final outerPadding = widget.roundedTopOnly
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(8, 0, 8, 8);

    if (!widget.glass) {
      return Padding(padding: outerPadding, child: sheet);
    }

    return Padding(
      padding: outerPadding,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D12).withValues(alpha: 0.85),
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: sheet,
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final text = _editing
        ? _editCtrl.text
        : (_selectedIndex != null ? _prompts[_selectedIndex!].text : '');
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.coral.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Edit button
              GestureDetector(
                onTap: _startEdit,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '✏️ Edit',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Send button
              Expanded(
                child: GestureDetector(
                  onTap: _canSend ? _send : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: _canSend
                          ? const LinearGradient(
                              colors: [
                                Color(0xFF405DE6),
                                Color(0xFF833AB4),
                                Color(0xFFE1306C),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: _canSend ? null : AppColors.border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.send_rounded,
                            size: 14,
                            color: _canSend ? Colors.white : Colors.white38,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Send',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _canSend ? Colors.white : Colors.white38,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSentState() {
    return AnimatedBuilder(
      animation: _sendCtrl,
      builder: (context, _) {
        final v = _sendCtrl.value;
        final checkScale =
            0.5 + 0.5 * Curves.elasticOut.transform(math.min(v * 2.0, 1.0));
        final textOpacity = Curves.easeIn.transform(
          (v * 2.0 - 0.8).clamp(0.0, 1.0),
        );

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.scale(
              scale: checkScale,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.coral,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Opacity(
              opacity: textOpacity,
              child: Column(
                children: [
                  Text(
                    'Ping sent! 🎉',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.pingContext == PingContext.anonymous
                        ? 'Sent anonymously'
                        : 'Sent to ${widget.targetName}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Prompt chip
// ---------------------------------------------------------------------------

class _PromptChip extends StatefulWidget {
  const _PromptChip({
    required this.prompt,
    required this.selected,
    required this.onTap,
  });

  final _Prompt prompt;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PromptChip> createState() => _PromptChipState();
}

class _PromptChipState extends State<_PromptChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.coral.withValues(alpha: 0.18)
                : widget.prompt.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected
                  ? AppColors.coral.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.07),
              width: widget.selected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            widget.prompt.text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: widget.selected ? AppColors.coral : AppColors.textPrimary,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _WriteOwnChip extends StatelessWidget {
  const _WriteOwnChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.edit_outlined,
              size: 13,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              'Write your own...',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
