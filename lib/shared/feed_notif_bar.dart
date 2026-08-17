import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Shared feed notification toast — mounted once above the feed PageView
// (see HomeScreen), never inside a feed's own Stack. That's what guarantees
// it can never cover a post: it occupies real layout space between the
// header and the feed rather than floating on top of feed content.
// ---------------------------------------------------------------------------

/// Three-tier severity controls how long a toast stays up before
/// auto-dismissing.
enum FeedNotifSeverity { minor, standard, major }

extension FeedNotifSeverityX on FeedNotifSeverity {
  Duration get displayDuration => switch (this) {
        FeedNotifSeverity.minor => const Duration(milliseconds: 1000),
        FeedNotifSeverity.standard => const Duration(milliseconds: 2500),
        FeedNotifSeverity.major => const Duration(milliseconds: 3000),
      };
}

class _QueuedFeedNotif {
  const _QueuedFeedNotif(this.message, this.severity);
  final String message;
  final FeedNotifSeverity severity;
}

/// Owns the queue/show/dismiss/suppression state for feed toasts. One
/// instance lives in HomeScreen and is shared by every feed screen mounted
/// under it, so "queued while suppressed" behaves the same regardless of
/// which feed is currently active.
class FeedNotifController extends ChangeNotifier {
  final List<_QueuedFeedNotif> _queue = [];
  _QueuedFeedNotif? _current;
  int _key = 0;
  bool _suppressed = false;

  String? get currentMessage => _current?.message;
  FeedNotifSeverity? get currentSeverity => _current?.severity;
  int get currentKey => _key;
  bool get isShowing => _current != null;

  void push(String message, FeedNotifSeverity severity) {
    _queue.add(_QueuedFeedNotif(message, severity));
    _tryShowNext();
  }

  /// Suppresses new toasts from appearing — used while the daily prompt
  /// bar is in its "moment of relevance" (freshly expanded at the top of
  /// the Anonymous feed). Anything pushed while suppressed stays queued and
  /// is shown once suppression lifts.
  void setSuppressed(bool value) {
    if (_suppressed == value) return;
    _suppressed = value;
    if (!value) _tryShowNext();
  }

  void _tryShowNext() {
    if (_suppressed || _current != null || _queue.isEmpty) return;
    _current = _queue.removeAt(0);
    _key++;
    notifyListeners();
  }

  void dismissCurrent() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
    // Small gap between toasts, mirrors the old queue's feel rather than
    // snapping the next one in immediately.
    Future.delayed(const Duration(milliseconds: 300), _tryShowNext);
  }

  @override
  void dispose() {
    _queue.clear();
    super.dispose();
  }
}

/// Mount point for the toast — sits between the header and the feed
/// PageView (see HomeScreen.build). AnimatedSize grows/shrinks the slot so
/// the feed below reflows smoothly rather than the toast popping over it.
class FeedNotifHost extends StatelessWidget {
  const FeedNotifHost({super.key, required this.controller});
  final FeedNotifController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final message = controller.currentMessage;
        final severity = controller.currentSeverity;
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: message == null || severity == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: FeedNotifBar(
                    key: ValueKey('notif_${controller.currentKey}'),
                    message: message,
                    severity: severity,
                    onDismissed: controller.dismissCurrent,
                  ),
                ),
        );
      },
    );
  }
}

/// The toast card itself: slides + fades down into place, holds for
/// [severity]'s duration, then slides back out before calling
/// [onDismissed].
class FeedNotifBar extends StatefulWidget {
  const FeedNotifBar({
    super.key,
    required this.message,
    required this.severity,
    required this.onDismissed,
  });

  final String message;
  final FeedNotifSeverity severity;
  final VoidCallback onDismissed;

  @override
  State<FeedNotifBar> createState() => _FeedNotifBarState();
}

class _FeedNotifBarState extends State<FeedNotifBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;
  bool _dismissCalled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    // Drops in from just above its own slot rather than the old full
    // off-screen travel — it no longer needs to travel the whole screen
    // height since it now lives right at the top of the feed area.
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    Future.delayed(widget.severity.displayDuration, _dismiss);
  }

  void _dismiss() {
    if (_dismissCalled || !mounted) return;
    _dismissCalled = true;
    _ctrl.reverse().whenComplete(widget.onDismissed);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
