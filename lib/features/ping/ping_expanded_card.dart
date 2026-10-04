import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../core/constants.dart';
import 'ping_feed_models.dart';
import 'ping_reveal_screen.dart' show PingCameraScreen;
import 'ping_visual_kit.dart' show pingCyan, pingR4;

// ---------------------------------------------------------------------------
// PingExpandedCard — the in-place expand a To-Reply row (and a Group Wall
// "reply to unlock" tap) opens into (no navigation). One card: header +
// prompt/window, a dashed "add photo" square that opens the real half-screen
// dual camera (PingCameraScreen — the same one used app-wide for sending a
// ping, so both flows share one capture experience), and a text bar for
// text-only replies. No separate "captured" preview step — the camera sheet
// itself handles capture-and-send, matching how PingCameraScreen already
// works everywhere else it's used.
// ---------------------------------------------------------------------------

class PingExpandedCard extends StatefulWidget {
  const PingExpandedCard({
    super.key,
    required this.entry,
    required this.onClose,
    this.onPingBack,
  });

  final PingFeedEntry entry;
  final VoidCallback onClose;

  /// "Ping back" — an alternate to answering their prompt: skip the photo/
  /// text reply and instead open the same prompt-picker used to ping a
  /// friend from the "Ping Someone" strip, targeted at this person. Null
  /// hides the button (kept optional so other callers aren't forced to
  /// wire it before this ships everywhere PingExpandedCard is used).
  final VoidCallback? onPingBack;

  @override
  State<PingExpandedCard> createState() => _PingExpandedCardState();
}

class _PingExpandedCardState extends State<PingExpandedCard> {
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    final photo = await showModalBottomSheet<XFile?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PingCameraScreen(
        recipientName: widget.entry.renderedName,
      ),
    );
    if (photo == null || !mounted) return;
    setState(() {
      widget.entry.sentReplies.add(
        _textCtrl.text.trim().isEmpty ? '(photo)' : _textCtrl.text.trim(),
      );
      _textCtrl.clear();
    });
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      widget.entry.sentReplies.add(text);
      _textCtrl.clear();
    });
  }

  /// Drives the header status pill — just "open"/"closed", no duration
  /// (the duration now lives in [_windowSuffix]'s subtitle line instead).
  String _windowLabel() {
    final remaining = widget.entry.replyWindowRemaining;
    if (remaining == null) return '';
    return remaining == Duration.zero ? 'closed' : 'open';
  }

  /// " · {n}h left to reply" appended onto the "pinged you" subtitle.
  /// Empty once the window's closed or never started (matches the pill).
  String _windowSuffix() {
    final remaining = widget.entry.replyWindowRemaining;
    if (remaining == null || remaining == Duration.zero) return '';
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final left = h > 0 ? '${h}h' : '${m}m';
    return ' · $left left to reply';
  }

  @override
  Widget build(BuildContext context) {
    // Glass card — G4 gradient (160°, white(.09)→white(.045)) + backdrop
    // blur sigma 12, per COLORS_AND_SHAPES.md §1.8/§2.7. Shadow lives on
    // the outer Container (a clipped widget can't paint its own shadow).
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: pingR4(30, 12, 34, 16),
        boxShadow: [
          const BoxShadow(
            color: Color(0x73000000),
            blurRadius: 44,
            offset: Offset(0, 18),
          ),
          BoxShadow(color: pingCyan.withValues(alpha: 0.08), blurRadius: 32),
        ],
      ),
      child: ClipRRect(
        borderRadius: pingR4(30, 12, 34, 16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.09),
                  Colors.white.withValues(alpha: 0.045),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: avatar + name/subtitle on the left, status pill + close on the right.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.entry.avatarColor,
                      ),
                      child: Center(
                        child: Text(
                          widget.entry.displayName[0].toUpperCase(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.85),
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
                            widget.entry.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // "pinged you" + the countdown folded into one subtitle
                          // line, instead of a second standalone timer row.
                          Text(
                            'pinged you${_windowSuffix()}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(label: _windowLabel()),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  widget.entry.prompt,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.17,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 20),

                // "add photo" drop zone — solid (not dashed) 1.5px border, exact
                // reference dims (120×150, radius 18, "+" as a plain glyph in a
                // 46×46 ring, not an Icon). Tapping opens the real half-screen
                // dual camera (PingCameraScreen) directly. That sheet captures
                // and sends in one motion (it already shows its own "Sent!"
                // confirmation before popping), so there is no separate
                // captured/retake step here — this card just appends the sent
                // reply to the running list once the sheet reports success.
                GestureDetector(
                  onTap: _openCamera,
                  child: Container(
                    width: 120,
                    height: 150,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white.withValues(alpha: 0.03),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            '+',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w300,
                              fontSize: 22,
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          'add photo',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: 0.34),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (widget.onPingBack != null) ...[
                  GestureDetector(
                    onTap: widget.onPingBack,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Text(
                        'Ping back',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Text bar — sends a text-only reply (photo replies send via the
                // camera sheet above and use whatever's typed here as caption).
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: TextField(
                          controller: _textCtrl,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: 'say something…',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendText(),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _textCtrl.text.trim().isEmpty ? null : _sendText,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: _textCtrl.text.trim().isEmpty
                              ? Colors.white.withValues(alpha: 0.08)
                              : AppColors.neonCyan,
                          boxShadow: _textCtrl.text.trim().isEmpty
                              ? null
                              : [
                                  BoxShadow(
                                    color: AppColors.neonCyan.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 14,
                                  ),
                                ],
                        ),
                        child: Text(
                          'Send',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textCtrl.text.trim().isEmpty
                                ? Colors.white.withValues(alpha: 0.3)
                                : const Color(0xFF0A0A0D),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                if (widget.entry.sentReplies.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'unlimited within the window — send more anytime',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.entry.sentReplies.map(
                    (text) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: AppColors.neonCyan.withValues(alpha: 0.16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          Text(
                            'sent',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: AppColors.neonCyan.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill/badge with a dot indicator, replacing the old plain-text
/// "open 2h 59m" line. Renders nothing once [label] is empty (no active
/// window — e.g. an unrevealed To-Reply entry).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final open = label == 'open';
    final color = open ? pingCyan : Colors.white.withValues(alpha: 0.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
