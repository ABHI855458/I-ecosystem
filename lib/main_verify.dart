import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'main.dart' show ScreenshotRoot;
import 'services/demo_content.dart';

// ---------------------------------------------------------------------------
// Separate verification entry point — `flutter run --target=lib/main_verify.
// dart`. Its own main(), its own MaterialApp, its own `home:`. Never reads
// or is affected by main.dart's own `home:` line (which the concurrent
// session uses for its own rapid iteration, e.g. `home: const PV2Verify(...)`
// — that's their tool, this is the isolated-simulator verification tool,
// and neither can clobber the other since they're different entry files
// compiled into different app builds). Reuses ScreenshotRoot (main.dart's
// debug-harness switch, made public specifically for this) rather than
// duplicating its 60+ case list — `_screenshotMode` there still resolves
// via `--dart-define=SCREENSHOT_MODE=<n>`, since dart-defines are
// compile-time-global regardless of which file's main() actually runs.
//
// Deliberately skips main.dart's notification-service init and
// screenshotMode==0-only branches — this entry point is never the real
// signed-in app, only ever a debug-harness screen, so there's no "real app"
// path to preserve here.
// ---------------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF16151A),
    ),
  );

  // TEMP diagnostic — confirms whether --dart-define reached this build.
  debugPrint('[VERIFY] SCREENSHOT_MODE define = '
      '${const int.fromEnvironment('SCREENSHOT_MODE', defaultValue: -999)}');
  debugPrint('[VERIFY] BYPASS_AUTH define = '
      '${const bool.fromEnvironment('BYPASS_AUTH_FOR_UI_WORK', defaultValue: false)}');

  await dotenv.load(fileName: '.env', isOptional: true);
  await SupabaseConfig.initialize();
  DemoContent.seedIfNeeded();

  runApp(const VerifyApp());
}

class VerifyApp extends StatelessWidget {
  const VerifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I (verify)',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const ScreenshotRoot(),
    );
  }
}
