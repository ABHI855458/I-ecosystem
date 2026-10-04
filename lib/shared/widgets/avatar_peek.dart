import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Press-and-hold a profile or group DP to see it big — the Instagram
/// "peek": the photo pops up as a large circle in the middle of the screen
/// over a blurred backdrop, and goes away the moment the finger lifts.
///
/// Wraps [child] without changing how it looks or what a TAP does — only a
/// long-press is added, and only when there is a real photo to show
/// ([imageUrl] null/empty = plain child, no peek over a placeholder).
class AvatarPeek extends StatefulWidget {
  const AvatarPeek({
    super.key,
    required this.imageUrl,
    required this.child,
    this.placeholderBuilder,
  });

  final String? imageUrl;
  final Widget child;

  /// Big version of the no-photo avatar (e.g. an anon persona's shape
  /// glyph), drawn at [side]. When set, holding a photo-less avatar still
  /// peeks — showing this — instead of doing nothing.
  final Widget Function(double side)? placeholderBuilder;

  @override
  State<AvatarPeek> createState() => _AvatarPeekState();
}

class _AvatarPeekState extends State<AvatarPeek>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  // Lazy, and only disposed if it was ever built: touching it for the
  // first time inside dispose() looked up TickerMode on a deactivated
  // element ("Looking up a deactivated widget's ancestor is unsafe").
  AnimationController? _animOrNull;
  AnimationController get _anim => _animOrNull ??= AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 120),
  );

  bool get _hasPhoto => (widget.imageUrl ?? '').isNotEmpty;
  bool get _canPeek => _hasPhoto || widget.placeholderBuilder != null;

  void _show() {
    if (!_canPeek || _entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    HapticFeedback.mediumImpact();
    final url = widget.imageUrl;
    final placeholder = widget.placeholderBuilder;
    _entry = OverlayEntry(
      builder: (ctx) {
        final side = MediaQuery.sizeOf(ctx).width * 0.72;
        return IgnorePointer(
          child: FadeTransition(
            opacity: _anim,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(
                      CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
                    ),
                    child: Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: (url == null || url.isEmpty)
                            ? placeholder!(side)
                            : CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                memCacheWidth: 1080,
                                errorWidget: (_, _, _) =>
                                    placeholder?.call(side) ??
                                    const ColoredBox(color: Color(0xFF2E2E33)),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    _anim.forward(from: 0);
  }

  Future<void> _hide() async {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    await _anim.reverse();
    entry.remove();
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _animOrNull?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canPeek) return widget.child;
    return GestureDetector(
      onLongPressStart: (_) => _show(),
      onLongPressEnd: (_) => _hide(),
      onLongPressCancel: _hide,
      child: widget.child,
    );
  }
}
