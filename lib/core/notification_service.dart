import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../services/current_user_service.dart';
import 'supabase_config.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'daily_channel';
  static const _channelName = 'Daily Notifications';
  static const _channelDesc = 'Daily streak, activity, and moment reminders';

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

  Future<void> scheduleDailyNotifications() async {
    await _plugin.cancelAll();

    final hasPostedToday = await _checkIfPostedToday();
    if (!hasPostedToday) {
      await _schedule(id: 1, title: 'Your streak is alive! 🔥', body: 'Post today to keep your streak going', hour: 9, minute: 0);
    }

    await _schedule(id: 2, title: 'Lunch hour is live! 🍽️', body: '47 people in CSE community right now', hour: 12, minute: 0);
    await _schedule(id: 3, title: 'Daily moment? 📸', body: "What's happening in your circle right now?", hour: 20, minute: 0);
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    final now = DateTime.now();
    var targetLocal = DateTime(now.year, now.month, now.day, hour, minute);
    if (!targetLocal.isAfter(now)) {
      targetLocal = targetLocal.add(const Duration(days: 1));
    }
    final tzScheduled = tz.TZDateTime.from(targetLocal.toUtc(), tz.UTC);

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzScheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  Future<void> cancelStreakNotification() async {
    await _plugin.cancel(id: 1);
  }

  Future<bool> _checkIfPostedToday() async {
    return false;
  }

  /// Upserts a push token into `device_tokens` so the server-side
  /// notification system (supabase/functions/, see
  /// supabase/functions/README.md) can reach this device for PING
  /// RECEIVED, PING REPLIED, PROFILE VIEW, and REACTION/COMMENT pushes.
  ///
  /// Not called anywhere yet — this app has no remote-push plugin wired in
  /// (only flutter_local_notifications, which is on-device only and can't
  /// produce a token). Once a push plugin is added and yields a real
  /// platform token, call this from wherever that plugin's
  /// onTokenRefresh/getToken result lands.
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
  }
}
