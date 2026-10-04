import 'package:flutter/material.dart';

import '../notifications/notifications_screen.dart';
import 'profile_v2_sections.dart';
import 'profile_v2_tokens.dart';

// ---------------------------------------------------------------------------
// Notifications — lives on MyProfileScreen's BANNER, in the slot the anon
// feed's "viewed by" eye used to occupy (explicit swap request — eye moved
// to the feed page's own header, this moved here). Same ChromeButton +
// badge structure as its neighbor ViewedByBannerButton (see that file's own
// doc) — built specifically for this banner rather
// than reusing home_screen.dart's own _HeaderBellButton verbatim, which
// looked visually wrong here (different size, different fill, a dim icon
// color) next to these glass buttons.
// ---------------------------------------------------------------------------

class NotificationsBannerButton extends StatefulWidget {
  const NotificationsBannerButton({super.key});

  @override
  State<NotificationsBannerButton> createState() => _NotificationsBannerButtonState();
}

class _NotificationsBannerButtonState extends State<NotificationsBannerButton> {
  @override
  void initState() {
    super.initState();
    // Live badge, not a one-shot fetch like Viewed-by's own
    // _loadCount — notifState is a real global singleton already kept in
    // sync app-wide (see notifications_screen.dart), so listening to it
    // directly is both simpler and more correct than a separate fetch
    // that could drift from the app's actual unread state.
    notifState.addListener(_onNotifChanged);
  }

  @override
  void dispose() {
    notifState.removeListener(_onNotifChanged);
    super.dispose();
  }

  void _onNotifChanged() {
    if (mounted) setState(() {});
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = notifState.totalUnread;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChromeButton(
          icon: const Icon(Icons.notifications_outlined, size: 18, color: Colors.white),
          onTap: _open,
        ),
        if (unread > 0)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              decoration: BoxDecoration(
                color: PV2.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: PV2.page, width: 1.5),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: PV2.body(size: 9.5, weight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
