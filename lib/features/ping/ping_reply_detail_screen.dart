import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import 'ping_feed_models.dart';
import 'ping_visual_kit.dart';

// ---------------------------------------------------------------------------
// Reply Detail / Comments — design doc "Additional Features" section.
// Slide-in overlay (not a route change) opened via a viewed Reply row's
// "View full reply" affordance. Hero photo + PiP inset, prompt/reply text,
// a flat comment thread, sticky bottom composer. No reactions row —
// deliberately removed per spec, comments are the only social affordance.
// ---------------------------------------------------------------------------

void showPingReplyDetail(
  BuildContext context,
  PingFeedEntry entry, {
  VoidCallback? onPingBack,
}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, anim, _) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: PingReplyDetailScreen(entry: entry, onPingBack: onPingBack),
      ),
    ),
  );
}

/// Opens the full-screen reply photo viewer (§ full-bleed photo, PiP inset,
/// Ping-back + reaction row) directly, without going through Reply Detail
/// first. Reply Detail's own hero-photo tap uses this too.
void showFullScreenReplyPhoto(
  BuildContext context,
  PingFeedEntry entry, {
  VoidCallback? onPingBack,
}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim, _) => FadeTransition(
        opacity: anim,
        child: _FullScreenReplyPhoto(entry: entry, onPingBack: onPingBack),
      ),
    ),
  );
}

class PingReplyDetailScreen extends StatefulWidget {
  const PingReplyDetailScreen({
    super.key,
    required this.entry,
    this.onPingBack,
  });
  final PingFeedEntry entry;

  /// Ping-back CTA is also reachable from the full-screen photo viewer
  /// (tap the hero photo) — same action as the row-level "Ping back?"
  /// banner, just reachable one tap deeper. Null hides the CTA everywhere
  /// in this screen (e.g. anonymous replies have no ping-back path).
  final VoidCallback? onPingBack;

  @override
  State<PingReplyDetailScreen> createState() => _PingReplyDetailScreenState();
}

class _PingReplyDetailScreenState extends State<PingReplyDetailScreen> {
  late final List<PingComment> _comments;
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _comments = List.of(widget.entry.comments);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _openFullScreenPhoto(BuildContext context) {
    HapticFeedback.selectionClick();
    showFullScreenReplyPhoto(
      context,
      widget.entry,
      onPingBack: widget.onPingBack,
    );
  }

  void _postComment() {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _comments.add(
        PingComment(author: 'you', timestamp: DateTime.now(), text: text),
      );
      _commentCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Scaffold(
      backgroundColor: pingGround,
      body: SafeArea(
        child: Column(
          children: [
            // Header — back chevron / name+time / balancing spacer.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          entry.renderedName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: entry.origin == PingOrigin.anonymous
                                ? pingClay.withValues(alpha: 0.85)
                                : Colors.white,
                          ),
                        ),
                        Text(
                          _relativeTime(
                            entry.viewedAt ?? entry.sentAt ?? DateTime.now(),
                          ),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 40, height: 40),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  GestureDetector(
                    onTap: () => _openFullScreenPhoto(context),
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 150,
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 50,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            ),
                            child: HatchedPhoto(
                              tint: entry.avatarColor,
                              radius: 20,
                            ),
                          ),
                          Positioned(
                            top: -10,
                            left: -10,
                            child: Container(
                              width: 54,
                              height: 68,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: HatchedPhoto(
                                tint: entry.avatarColor,
                                radius: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    're: ${entry.prompt}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  if (entry.replyText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.replyText!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 16),
                  for (final c in _comments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _CommentTile(comment: c),
                    ),
                  if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No comments yet',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Sticky composer.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: TextField(
                        controller: _commentCtrl,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add a comment…',
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
                        onSubmitted: (_) => _postComment(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _postComment,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.neonCyan,
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 18,
                        color: Color(0xFF0A0A0D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final PingComment comment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2A3040),
          ),
          child: Center(
            child: Text(
              comment.author.isNotEmpty ? comment.author[0].toUpperCase() : '?',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.author,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _relativeTime(comment.timestamp),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                comment.text,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Reply',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ---------------------------------------------------------------------------
// Full-screen photo viewer — opened by tapping the hero photo on the Reply
// Detail screen. Shows the photo edge-to-edge with the same PiP selfie
// inset, plus a bottom action row: Ping-back (same action/window rule as
// the row banner and the detail screen's own CTA) and a reaction toggle.
// Reactions are local-only demo state (a filled/outline heart), matching
// how every other bit of Ping state in this feature works — no backend.
// ---------------------------------------------------------------------------

class _FullScreenReplyPhoto extends StatefulWidget {
  const _FullScreenReplyPhoto({required this.entry, this.onPingBack});
  final PingFeedEntry entry;
  final VoidCallback? onPingBack;

  @override
  State<_FullScreenReplyPhoto> createState() => _FullScreenReplyPhotoState();
}

class _FullScreenReplyPhotoState extends State<_FullScreenReplyPhoto> {
  bool _reacted = false;

  void _toggleReaction() {
    HapticFeedback.mediumImpact();
    setState(() => _reacted = !_reacted);
  }

  void _pingBack() {
    widget.onPingBack?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final canPingBack = widget.onPingBack != null && entry.pingBackAvailable;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: HatchedPhoto(tint: entry.avatarColor, radius: 0),
                    ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        width: 76,
                        height: 96,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: HatchedPhoto(
                          tint: entry.avatarColor,
                          radius: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.42),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _toggleReaction,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.42),
                        border: Border.all(
                          color: _reacted
                              ? pingCyan.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Icon(
                        _reacted
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _reacted
                            ? pingCyan
                            : Colors.white.withValues(alpha: 0.75),
                        size: 22,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (canPingBack)
                    GestureDetector(
                      onTap: _pingBack,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: pingCtaGradient,
                          boxShadow: [
                            BoxShadow(
                              color: pingCyan.withValues(alpha: 0.34),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Text(
                          'Ping ${entry.renderedName}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0B0B0D),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
