import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../services/current_user_service.dart';
import 'notification_service.dart';
import 'supabase_config.dart';

/// Background/terminated-state message handler.
///
/// MUST be a top-level (or static) function — the Flutter engine spins up a
/// separate isolate to run it, so it cannot close over anything from the UI
/// isolate. Firebase has to be re-initialized inside that isolate.
///
/// Deliberately does no work beyond initialization: when the FCM payload
/// carries a `notification` block (which every send from
/// supabase/functions/_shared/fcm.ts does), Android and iOS render the
/// system tray entry themselves. Doing it again here would double it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Explicit options here too: this isolate has no native default app, and
  // on iOS it would otherwise depend on GoogleService-Info.plist being
  // readable from a background context.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

/// Remote push (FCM) — the delivery half of the notification system whose
/// server side lives in supabase/functions/.
///
/// Split from [NotificationService] on purpose: that class owns
/// flutter_local_notifications, which is on-device only (scheduled streak
/// reminders) and cannot produce a push token. This class owns the remote
/// path and reuses NotificationService.registerDeviceToken() to persist the
/// token it gets.
///
/// No analytics: firebase_core is initialized solely because
/// firebase_messaging requires it. firebase_analytics is not a dependency
/// and must not become one — see the note in pubspec.yaml.
class PushMessagingService {
  PushMessagingService._();
  static final instance = PushMessagingService._();

  // `late`, NOT a field initializer: FirebaseMessaging.instance calls
  // Firebase.app() internally, which THROWS SYNCHRONOUSLY if no default app
  // exists yet — see the getter's stack trace (Firebase.app →
  // MethodChannelFirebase.app → "[core/no-app] No Firebase App '[DEFAULT]'
  // has been created"). A field initializer runs at construction time, i.e.
  // the moment `PushMessagingService.instance` is first accessed — which in
  // main.dart is BEFORE init()'s own `await Firebase.initializeApp()` has
  // run. That ordering bug threw synchronously out of main(), which (being
  // unhandled) aborted main() before it reached runApp() — reproducing the
  // exact blank-screen symptom this class was written to fix, just for a
  // new reason. Assigned in init(), below, only after Firebase.initializeApp()
  // has actually succeeded.
  late final FirebaseMessaging _messaging;
  final _local = FlutterLocalNotificationsPlugin();

  /// Fires with a push's `data` payload when the user taps a notification —
  /// from the tray (background/terminated) or the foreground banner. The app
  /// wires this to navigation.
  final _taps = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onNotificationTap => _taps.stream;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<dynamic>? _authSub;
  bool _initialized = false;

  /// Android needs an explicit high-importance channel for heads-up banners;
  /// without one, FCM drops pushes into a silent default channel. Mirrors
  /// the id declared in AndroidManifest.xml's
  /// com.google.firebase.messaging.default_notification_channel_id.
  static const _channel = AndroidNotificationChannel(
    'push_channel',
    'Pings & Activity',
    description: 'Pings, replies, reactions, comments and invites',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Belt-and-suspenders alongside main()'s unawaited() call: a missing
      // GoogleService-Info.plist/google-services.json doesn't always fail
      // fast — on iOS in particular this has been observed to hang rather
      // than throw, waiting on native config that will never arrive. A
      // caller that DOES await this (this class's own contract, even if
      // main() no longer relies on it) must still get control back.
      // Options come from the generated firebase_options.dart (flutterfire
      // configure), NOT from the native google-services.json /
      // GoogleService-Info.plist. That is the actual fix for the
      // [core/not-initialized] this used to throw on every iOS launch: the
      // plist was missing, and a no-arg initializeApp() can only read
      // native config. Passing options makes init independent of those
      // files being present and correctly bundled.
      //
      // The 8s timeout and main()'s unawaited() call are both unchanged —
      // startup must never block on this.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      // A missing google-services.json / GoogleService-Info.plist must not
      // take the whole app down — the rest of the app works fine without
      // push, and this is exactly the state a fresh clone (or, right now,
      // this app's iOS side) is in.
      // Distinguish "no Firebase config on THIS platform" (expected, and
      // currently the iOS case — ios/Runner/GoogleService-Info.plist is not
      // in the repo) from a genuine failure. Both disable push, but only
      // one of them is a bug, and the previous message read as an
      // ordering/init-sequence problem when it never was: initializeApp()
      // is already awaited above, before any FirebaseMessaging use.
      final missingConfig = e.toString().contains('core/not-initialized') ||
          e.toString().contains('core/no-app');
      debugPrint(
        missingConfig
            ? 'PushMessagingService: no Firebase config for this platform '
                '(iOS needs ios/Runner/GoogleService-Info.plist). Push '
                'disabled; init order is fine. Detail: $e'
            : 'PushMessagingService: Firebase init failed, push disabled: $e',
      );
      return;
    }

    // Safe now — Firebase.initializeApp() above has actually completed.
    _messaging = FirebaseMessaging.instance;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Android 13+ and iOS both gate delivery behind a runtime prompt.
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Foreground: iOS suppresses the banner by default and hands the message
    // to the app instead. Ask the system to show it anyway so foreground
    // behaviour matches Android's.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_emitTap);

    // Cold start from a tray tap: the message that launched the app isn't
    // delivered through onMessageOpenedApp, only through this.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _emitTap(initial);

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((t) => _persist(t));

    // The token can only be stored once a `users` row exists, so registration
    // is driven off the auth session rather than app start — on a cold start
    // for a signed-in user this fires immediately with the restored session.
    _authSub = supabase.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        unawaited(syncToken());
      }
    });
    if (supabase.auth.currentSession != null) {
      unawaited(syncToken());
    }
  }

  /// Fetches the current FCM token and upserts it into `device_tokens`.
  /// Safe to call repeatedly — the upsert is keyed on (user_id, token).
  Future<void> syncToken() async {
    try {
      // On iOS the FCM token is only issued after APNs hands Firebase a
      // device token; getToken() throws until then rather than waiting.
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('PushMessagingService: no FCM token yet');
        return;
      }
      await _persist(token);
    } catch (e) {
      debugPrint('PushMessagingService: getToken failed: $e');
    }
  }

  Future<void> _persist(String token) async {
    try {
      await NotificationService().registerDeviceToken(
        token: token,
        platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
      debugPrint('PushMessagingService: registered token ${token.substring(0, 12)}…');
    } catch (e) {
      // Not signed in yet, or offline — onAuthStateChange/onTokenRefresh
      // will bring us back here.
      debugPrint('PushMessagingService: registerDeviceToken failed: $e');
    }
  }

  /// Removes this device's token so a signed-out phone stops receiving the
  /// previous account's pushes. Call before supabase.auth.signOut().
  Future<void> unregister() async {
    try {
      // Bounded: getToken() can hang indefinitely when Firebase/APNs never
      // came up (seen on iOS: "Firebase init failed ... TimeoutException"),
      // and logout awaits this — so "Log Out" looked like it did nothing.
      final token = await _messaging
          .getToken()
          .timeout(const Duration(seconds: 3));
      if (token == null) return;
      final userId = await CurrentUserService.instance.resolveId();
      await supabase
          .from('device_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', token)
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('PushMessagingService: unregister failed: $e');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    // 'major' pushes carry style: 'glow_shimmer' from
    // supabase/functions/_shared/notify.ts — the in-app notification list
    // uses it for the glow border; for the tray banner it just means
    // max importance.
    final isMajor = message.data['tier'] == 'major';
    await _local.show(
      id: message.hashCode,
      title: n.title ?? '',
      body: n.body ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: isMajor ? Importance.max : Importance.high,
          priority: isMajor ? Priority.max : Priority.high,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: message.data.isEmpty ? null : message.data.toString(),
    );
  }

  void _emitTap(RemoteMessage message) {
    _taps.add(message.data.map((k, v) => MapEntry(k, '$v')));
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _authSub?.cancel();
    await _taps.close();
  }
}
