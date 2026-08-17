import 'dart:ui';

import 'package:flutter/material.dart';

import '../features/notifications/notifications_screen.dart';

// ---------------------------------------------------------------------------
// GlassNotifCard — right-side frosted glass notification tile
// ---------------------------------------------------------------------------

class GlassNotifCard extends StatelessWidget {
  const GlassNotifCard({
    super.key,
    required this.notif,
    required this.onDismiss,
  });

  final AppNotif notif;
  final VoidCallback onDismiss;

  double _calcWidth(String text) {
    final len = text.length;
    if (len < 22) return 200;
    if (len < 36) return 260;
    if (len < 52) return 310;
    return 350;
  }

  @override
  Widget build(BuildContext context) {
    final isHigh = notif.isHighPriority;
    final w = _calcWidth(notif.title);

    return GestureDetector(
      // Tap-to-navigate — reuses NotifState.navigateTo's existing
      // type->destination dispatch (already wired for NotifBanner, the top
      // banner) so this glass toast opens the same relevant post/profile
      // instead of only ever being swipe-dismissible.
      onTap: () {
        onDismiss();
        notifState.navigateTo(notif);
      },
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 150) onDismiss();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isHigh) ...[
                  Container(
                    width: 3,
                    height: 36,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notif.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (notif.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          notif.body,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.65),
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GlassNotifOverlay — drop this inside any Stack to get the right-side layer
// ---------------------------------------------------------------------------

class GlassNotifOverlay extends StatefulWidget {
  const GlassNotifOverlay({super.key, required this.bottomOffset});
  final double bottomOffset;

  @override
  State<GlassNotifOverlay> createState() => _GlassNotifOverlayState();
}

class _GlassNotifOverlayState extends State<GlassNotifOverlay> {
  @override
  void initState() {
    super.initState();
    notifState.addListener(_rebuild);
  }

  @override
  void dispose() {
    notifState.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: widget.bottomOffset,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 240),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.6, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          )),
          child: child,
        ),
        child: notifState.glassVisible
            ? GlassNotifCard(
                key: ValueKey(notifState.glassNotif!.id),
                notif: notifState.glassNotif!,
                onDismiss: notifState.dismissGlass,
              )
            : const SizedBox.shrink(key: ValueKey('glass_none')),
      ),
    );
  }
}
