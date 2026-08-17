import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/notification_service.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/composer/composer_screen.dart';
import 'features/composer/photo_collage_builder.dart';
import 'features/groups/design_preview/group_profile_direction_picker.dart';
import 'features/home/anonymous_tab.dart';
import 'screens/feed/everyone_feed_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/ping/ping_reveal_screen.dart';
import 'features/ping/ping_screen.dart' show PingScreen, buildPingRepliesFeedScreen, showPingChoiceSheet;
import 'features/ping/ping_view_sheet.dart';
import 'features/profile/profile_screen.dart'
    show ProfileScreen, pushProfileSearch;
import 'main_shell.dart';
import 'screens/feed/widgets/instagram_post_preview.dart';
import 'services/demo_content.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

// Set to 0 for normal app
const _screenshotMode = 0;
// 1=anon tab, 2=composer, 3=everyone tab
// 4=notifications, 5=text ping view, 6=photo ping view, 8=collage builder, 9=profile
// 10=camera dual-off, 11=anon post-select (post-capture), 12=everyone compose (Polaroid)
// 20=profile+search screen
// 13=everyone style picker, 14=everyone compose (Normal)
// 15=camera overlay on home feed
// 16=ping camera sheet (85%), 17=ping sent toast, 18=ping replies feed
// 21=ping everyone tab, 22=ping group tab, 23=ping anon tab
// 25=instagram-style post preview (heart/comment/send/smiley cluster)
// 32=OTP screen (6-box input), 33=onboarding screen (persona + name)
// 40=group profile direction picker (1a/1b/1c mock comparison)
// 41=Candid-style dual-photo confirm preview (generated test back/front photos)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF16151A),
    ),
  );

  // isOptional: true — a fresh clone won't have real DeepAR keys filled in
  // yet (.env ships with empty placeholder values, gitignored for real
  // ones), and DeepAR is not core to app boot; DeepArService.isConfigured
  // reflects the empty-key case for callers instead of crashing here.
  await dotenv.load(fileName: '.env', isOptional: true);
  await SupabaseConfig.initialize();
  DemoContent.seedIfNeeded();

  if (_screenshotMode == 0) {
    await NotificationService().init(
      onTap: (_) => _navigatorKey.currentState?.popUntil((r) => r.isFirst),
    );
    await NotificationService().scheduleDailyNotifications();
  }

  runApp(App(navigatorKey: _navigatorKey));
}

class App extends StatelessWidget {
  const App({super.key, this.navigatorKey});
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: _screenshotMode == 0
          ? const AuthGate()
          : const _ScreenshotRoot(),
    );
  }
}

class _ScreenshotRoot extends StatefulWidget {
  const _ScreenshotRoot();

  @override
  State<_ScreenshotRoot> createState() => _ScreenshotRootState();
}

class _ScreenshotRootState extends State<_ScreenshotRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
  }

  void _showOverlay() {
    switch (_screenshotMode) {
      case 2:
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const ComposerScreen(),
        ));
      case 10:
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const ComposerScreen(),
        ));
      case 11:
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const ComposerScreen(
            testPhase: ComposerPhase.confirm,
            testAnonymous: true,
          ),
        ));
      case 12:
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const ComposerScreen(
            testPhase: ComposerPhase.confirm,
          ),
        ));
      case 13:
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const ComposerScreen(
            testPhase: ComposerPhase.confirm,
          ),
        ));
      case 14:
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const ComposerScreen(
            testPhase: ComposerPhase.confirm,
          ),
        ));
      case 5:
        showPingViewSheet(
          context,
          senderName: 'alex_xyz',
          type: PingViewType.text,
          promptText: 'Show me your view 👀',
          avatarColor: const Color(0xFF1A3040),
        );
      case 6:
        showPingViewSheet(
          context,
          senderName: 'alex_xyz',
          type: PingViewType.photo,
          avatarColor: const Color(0xFF1A3040),
        );
      case 7:
        break; // highlight scroll removed
      case 15:
        Navigator.of(context).push(openCameraRoute());
      case 16:
        showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const PingCameraScreen(
            recipientName: 'alex_xyz',
            prompt: 'Show me your view 👀',
          ),
        );
      case 18:
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => buildPingRepliesFeedScreen(
            senderName: 'alex_xyz',
            replies: const [
              Color(0xFF3A2050),
              Color(0xFF204060),
              Color(0xFF503020),
            ],
          ),
        ));
      case 20:
        pushProfileSearch(context);
      case 24:
        showPingChoiceSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_screenshotMode) {
      case 1:
        return const AnonymousTab();
      case 2:
        return const ComposerScreen();
      case 3:
        return const EveryoneFeedScreen(chromeCollapsed: false);
      case 4:
        return const NotificationsScreen();
      case 7:
        return const EveryoneFeedScreen(chromeCollapsed: false);
      case 8:
        return const CollageBuilderScreen();
      case 9:
        return const ProfileScreen();
      case 10:
        return const ComposerScreen();
      case 11:
        return const ComposerScreen(
          testPhase: ComposerPhase.confirm,
          testAnonymous: true,
        );
      case 12:
        return const ComposerScreen(testPhase: ComposerPhase.confirm);
      case 13:
        return const ComposerScreen(testPhase: ComposerPhase.confirm);
      case 14:
        return const ComposerScreen(testPhase: ComposerPhase.confirm);
      case 15:
      case 16:
      case 18:
        return const MainShell();
      case 19:
      case 20:
        return const ProfileScreen();
      case 21:
        return const PingScreen(initialTab: 0);
      case 22:
        return const PingScreen(initialTab: 1);
      case 23:
        return const PingScreen(initialTab: 2);
      case 24:
        return const PingScreen(initialTab: 1);
      case 25:
        return const InstagramPostPreview();
      case 32:
        return const OtpScreen(email: 'test@rvce.edu.in');
      case 33:
        return const OnboardingScreen();
      case 40:
        return const GroupProfileDirectionPicker();
      case 41:
        return const _DualPhotoTestHarness();
      default:
        return const MainShell();
    }
  }
}

/// Screenshot-mode-only harness for mode 41: generates two solid-color
/// placeholder PNGs on disk (no real camera needed) and opens the composer
/// confirm screen with them preloaded as back/front, so
/// _CandidMediaPreview's dual-photo layout can be visually checked without
/// driving the simulator's camera.
class _DualPhotoTestHarness extends StatefulWidget {
  const _DualPhotoTestHarness();

  @override
  State<_DualPhotoTestHarness> createState() => _DualPhotoTestHarnessState();
}

class _DualPhotoTestHarnessState extends State<_DualPhotoTestHarness> {
  String? _backPath;
  String? _frontPath;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _writeSolidPng(String path, int w, int h, Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = color);
    final img = await recorder.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes((bytes as ByteData).buffer.asUint8List());
  }

  Future<void> _generate() async {
    final dir = await Directory.systemTemp.createTemp('candid_test_');
    final backPath = '${dir.path}/back.png';
    final frontPath = '${dir.path}/front.png';
    await _writeSolidPng(backPath, 900, 1200, const Color(0xFF2B6E8F));
    await _writeSolidPng(frontPath, 600, 800, const Color(0xFFB5533F));
    if (!mounted) return;
    setState(() {
      _backPath = backPath;
      _frontPath = frontPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_backPath == null || _frontPath == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ComposerScreen(
      testPhase: ComposerPhase.confirm,
      testBackPhotoPath: _backPath,
      testFrontPhotoPath: _frontPath,
    );
  }
}
