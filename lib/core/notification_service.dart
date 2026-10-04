import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../services/current_user_service.dart';
import 'supabase_config.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  // The 'daily_channel' constants that lived here went with the scheduled
  // reminders that used them — this class no longer posts a notification of
  // its own, it only initialises the plugin (so a tapped SERVER push can be
  // routed) and clears reminders left by older installs.

  Future<void> init({void Function(String? payload)? onTap}) async {
    tzdata.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Best-effort: a failure here must never stop the app from starting.
  /// See the androidScheduleMode note in [_schedule] for the specific
  /// exception that used to escape into main() and block runApp().
  Future<void> scheduleDailyNotifications() async {
    try {
      await _scheduleDailyNotifications();
    } catch (e) {
      debugPrint('NotificationService: daily schedule failed (non-fatal): $e');
    }
  }

  Future<void> _scheduleDailyNotifications() async {
    // The three hardcoded daily reminders that used to be scheduled here are
    // GONE, and this now only clears any that a previous install left behind.
    //
    // They were wrong on three separate counts:
    //
    //   1. FABRICATED DATA. The noon one read "47 people in CSE community
    //      right now" — a literal, on a timer, every day, to every user. The
    //      number was never queried, and "CSE community" is not even one of
    //      the six pilot communities. The 9am one announced "Your streak is
    //      alive!" gated on _checkIfPostedToday(), which is a stub that
    //      always returns false — so it fired at people with no streak at
    //      all. Both are exactly what the server rule "every number is real,
    //      omit the line rather than invent it" exists to prevent.
    //
    //   2. DUPLICATES. Each now has a real server-side counterpart that
    //      sends the true version: the 4-stage streak escalation
    //      (notify_streak_escalation), the break-time live count
    //      (notify_break_live_count, which sends NOTHING when fewer than two
    //      people are genuinely present), and the window-turnover prompt
    //      (notify_window_change). Leaving these scheduled meant a user got
    //      a fabricated local copy and an accurate server copy of the same
    //      idea, hours apart.
    //
    //   3. STARTUP COST. Scheduling them meant a cancelAll() plus three
    //      zoned-schedule platform calls on the critical path to the first
    //      frame.
    //
    // cancelAll() stays: an upgrading device still has the old ones sitting
    // in its alarm table, and nothing else would ever clear them.
    await _plugin.cancelAll();
  }

  Future<void> cancelStreakNotification() async {
    await _plugin.cancel(id: 1);
  }

  /// Upserts a push token into `device_tokens` so the server-side
  /// notification system (supabase/functions/, see
  /// supabase/functions/README.md) can reach this device for PING
  /// RECEIVED, PING REPLIED, PROFILE VIEW, and REACTION/COMMENT pushes.
  ///
  /// Called from [PushMessagingService]'s `onTokenRefresh` listener and on
  /// every auth-state change with a live session (see push_messaging_service
  /// .dart's `_persist()`/`syncToken()`) — this is the live remote-push path.
  Future<void> registerDeviceToken({
    required String token,
    required String platform, // 'ios' | 'android'
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    await supabase.from('device_tokens').upsert(
      {
        'user_id': userId,
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,token',
    );

    // BUG FIX (reported: "my friends were getting the same notification
    // several times"). The upsert above only ever prevents the SAME token
    // value from being duplicated — it does nothing about an OLDER token
    // for this exact device. FCM tokens rotate more often than assumed
    // (app updates, Play Services updates, a cleared cache), and every
    // rotation used to just add a new row alongside the old one, which
    // stayed in device_tokens indefinitely. The send side fans out to
    // EVERY row on file (see notify.ts's sendToUser / notify-dispatch),
    // so a device that had rotated a few times received every push once
    // per still-live old token. One real account had accumulated 6.
    //
    // A device only ever has one current token per platform, so deleting
    // every OTHER (user_id, platform) row right after registering this
    // one is safe — it can never remove a token that is still this same
    // device's current registration. It CAN remove a genuine second
    // device of the same platform (two Android phones on one account),
    // but that device re-registers its own token on its own next open,
    // same as any token naturally does — a brief, self-correcting gap
    // beats guaranteed duplicate pushes on every send.
    //
    // A failed delete here used to be swallowed with nothing but a
    // debugPrint, leaving the stale token live indefinitely (nothing else
    // retried it). One retry after a short backoff covers the common
    // transient case (offline, a momentary RLS/network hiccup); anything
    // that still fails falls to the recurring server-side
    // dedupe_device_tokens() sweep (every 15 min — see
    // 20260925010000_notify_dispatch_claim.sql) as the actual safety net.
    Future<void> deleteStaleTokens() => supabase
        .from('device_tokens')
        .delete()
        .eq('user_id', userId)
        .eq('platform', platform)
        .neq('token', token);
    try {
      await deleteStaleTokens();
    } catch (e) {
      debugPrint('[NotificationService.registerDeviceToken] stale-token cleanup failed, retrying once: $e');
      try {
        await Future<void>.delayed(const Duration(seconds: 2));
        await deleteStaleTokens();
      } catch (e2) {
        debugPrint('[NotificationService.registerDeviceToken] stale-token cleanup retry failed, '
            'leaving for the server-side dedupe sweep: $e2');
      }
    }
  }
}
