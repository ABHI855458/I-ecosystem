import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'shared/nav_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants.dart';
import 'core/notification_service.dart';
import 'core/push_messaging_service.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/community/community_screen.dart';
import 'features/composer/composer_screen.dart';
import 'features/composer/photo_collage_builder.dart';
import 'features/groups/design_preview/group_profile_direction_picker.dart';
import 'features/groups/moments/locked_replies_screen.dart';
import 'features/home/anon_feed_v2/anon_feed_screen.dart';
import 'features/home/anonymous_tab.dart';
import 'screens/feed/everyone_feed_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/ping/ping_reveal_screen.dart';
import 'features/ping/ping_feed_models.dart';
import 'features/ping/ping_feed_rows.dart';
import 'features/ping/ping_group_wall.dart';
import 'features/ping/ping_prompt_sheet.dart';
import 'features/ping/ping_reply_detail_screen.dart';
import 'features/ping/ping_screen.dart'
    show PingScreen, buildPingRepliesFeedScreen, showPingChoiceSheet;
import 'features/profile_v2/my_profile_screen.dart';
import 'screens/onboarding/onboarding_circles_screen.dart';
import 'features/profile_v2/pinned_section.dart';
import 'features/profile_v2/profile_v2_create_flows.dart';
import 'features/profile_v2/profile_v2_data.dart';
import 'features/profile_v2/their_profile_screen.dart';
import 'main_shell.dart';
import 'screens/feed/widgets/design_solo_card.dart';
import 'screens/feed/widgets/instagram_post_preview.dart';
import 'services/current_user_service.dart';
import 'services/group_service.dart';
import 'services/notification_feed_service.dart';
import 'services/ping_service.dart';
import 'services/post_author_pin_service.dart';
import 'screens/reactions/realmoji_library_screen.dart';
import 'services/profile_lookup_service.dart';
import 'services/reaction_preset_service.dart' show ReactionPresetCategory;

/// The root navigator, exposed so background work that outlives the screen
/// that started it (a post uploading after its composer closed) can still
/// surface an error to the user.
final appNavigatorKey = GlobalKey<NavigatorState>();

// Set to 0 for normal app. Edit this for the shared simulator session as
// before — it still works unchanged, since it's only the FALLBACK below.
const _screenshotModeDefault = 0;

// Compile-time override, e.g. `flutter run --dart-define=SCREENSHOT_MODE=3`.
// Lets an isolated verification run (its own simulator, its own `flutter
// run` process — see the two-tmux-session setup this pairs with) pin its
// debug-harness mode WITHOUT editing this file at all, so it can never be
// clobbered by — or clobber — the shared session's own edits to
// _screenshotModeDefault above. Falls back to that default when no define
// is passed, so the shared session's plain `flutter run` (no --dart-define)
// is byte-for-byte unaffected by this change.
const _screenshotMode = int.fromEnvironment(
  'SCREENSHOT_MODE',
  defaultValue: _screenshotModeDefault,
);
// 1=anon tab, 2=composer, 3=everyone tab
// 4=notifications, 5=text ping view, 6=photo ping view, 8=collage builder, 9=profile
// 10=camera dual-off, 11=anon post-select (post-capture), 12=everyone compose (Polaroid)
// 20=profile+search screen
// 13=everyone style picker, 14=everyone compose (Normal)
// 15=camera overlay on home feed
// 16=ping camera sheet (85%), 17=ping sent toast, 18=ping replies feed
// 21=ping everyone tab, 22=ping group tab, 23=ping anon tab
// 25=instagram-style post preview (heart/comment/send/smiley cluster)
// 32=OTP screen (6-box input, signup purpose), 33=onboarding screen (persona + name)
// 34=AuthScreen (login/signup mode switch), 35=ForgotPasswordScreen
// 36=ResetPasswordScreen, 37=OTP screen (recovery purpose)
// 40=group profile direction picker (1a/1b/1c mock comparison)
// 41=Candid-style dual-photo confirm preview (generated test back/front photos)
// 42=Moments locked-replies screen (5 mock replies, locked state)
// 900=Ping visual QA harness (unrevealed/viewed ReplyRow, GroupWallCard, reply detail)
// 60=Community board (ANNOUNCEMENTS tab), 61=Community board (STREAKS tab)
// 953=Onboarding "Build your circles" step (replaces friend requests), using my own communities
// 954=Pinned tab (eye sheet), 955=Pin picker sheet — pinning feature isolated verification
// 956=Whoami (read-only), 957=Whoami+auto-pin, 958=Whoami+auto-react — real-session E2E verification
// 970=RealMoji library, Anon scope (variant 1A grid) — isolated visual verification

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App-wide safety net (explicit request, 2026-10-04: "it shall not crash
  // out due to lack of storage or whatever reason"). Every error that no
  // screen caught itself — a failed write on a full disk, a dropped
  // connection mid-request, a bad row — is logged and absorbed here
  // instead of propagating:
  //   * framework errors (build/layout/paint) are reported, not rethrown;
  //   * uncaught async errors are marked handled (returning true), so the
  //     platform never treats them as fatal;
  //   * in release, a widget that fails to build renders as empty space
  //     rather than Flutter's grey error box.
  FlutterError.onError = (details) {
    if (kDebugMode) {
      FlutterError.presentError(details);
    } else {
      debugPrint('[FlutterError] ${details.exceptionAsString()}');
    }
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Uncaught] $error\n$stack');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (_) => const SizedBox.shrink();
  }
  // Bounded decoded-image memory: the feeds are photo-heavy, and an
  // unbounded cache is how low-RAM phones get killed.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20;

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF16151A),
    ),
  );

  // Every screen's text goes through GoogleFonts.<family>(...), which
  // fetches and caches that family's font file the FIRST time it's ever
  // called (later launches hit the on-disk cache and resolve instantly).
  // Nothing used to wait for that first fetch, so a fresh install painted
  // its very first frame in the system fallback font, then visibly swapped
  // to the real one mid-session as each family's fetch resolved — reported
  // as "the font suddenly changes" on the friends-feed Duo byline
  // (Nunito), but the same race exists for every family below on any
  // screen. Triggering + awaiting all of them here means the swap has
  // already happened before the first frame instead of on-screen.
  // Bounded, not a plain await: a stalled/offline first launch must still
  // reach runApp() (same discipline as the NotificationService guard
  // below) — worst case here is unchanged from before this fix, painting
  // in the fallback font until each fetch finishes in the background.
  final fontsPreload = GoogleFonts.pendingFonts([
    GoogleFonts.inter(),
    GoogleFonts.jetBrainsMono(),
    GoogleFonts.plusJakartaSans(),
    GoogleFonts.dmSans(),
    GoogleFonts.spaceGrotesk(),
    GoogleFonts.nunito(),
    GoogleFonts.archivo(),
    GoogleFonts.figtree(),
    GoogleFonts.ibmPlexMono(),
  ]).timeout(const Duration(seconds: 4), onTimeout: () => const []).catchError(
        (_) => const <void>[],
      );

  // isOptional: true — a fresh clone won't have real keys filled in yet
  // (.env ships with empty placeholder values, gitignored for real ones).
  await dotenv.load(fileName: '.env', isOptional: true);
  await SupabaseConfig.initialize();
  // Local read: lets a returning user skip AuthGate's network checks.
  await CurrentUserService.instance.warmFromDisk();
  // Awaited last so its (already in-flight, capped) wait only adds the
  // excess over whatever dotenv+Supabase init above already took.
  await fontsPreload;

  if (_screenshotMode == 0) {
    // Local notifications are best-effort too. Neither call may take the
    // app down: a platform permission refusal here used to escape main()
    // and stop runApp() from ever running (Android sat on the splash
    // screen). scheduleDailyNotifications() now swallows its own errors;
    // this guard covers init() and anything added later.
    // UNAWAITED, for the same reason PushMessagingService below is, and for
    // one more that is specific to this call: init() ends in
    // requestNotificationsPermission(), which puts a SYSTEM DIALOG on screen
    // and does not complete until the user answers it. Awaited here, that
    // sat between ensureInitialized() and runApp() — so on a first launch
    // the app showed nothing at all until the person found and tapped
    // "Allow", and a person who walked away left it blank indefinitely.
    // Measured cold start with it awaited: 17.6s on an API 37 emulator.
    //
    // Nothing here needs to finish before the first frame. The permission
    // only gates DISPLAY of a push that has not arrived yet, and the
    // plugin's onTap handler is only consulted once a notification exists to
    // be tapped. Both are ready long before either can matter.
    unawaited(() async {
      try {
        await NotificationService().init(
          onTap: (_) => appNavigatorKey.currentState?.popUntil((r) => r.isFirst),
        );
        await NotificationService().scheduleDailyNotifications();
      } catch (e) {
        debugPrint('NotificationService: init failed (non-fatal): $e');
      }
    }());

    // Remote push. Registers this device's FCM token into `device_tokens`
    // as soon as a session exists, which is what every notify-* Edge
    // Function looks up before it can send anything to this phone.
    // Fire-and-forget: this must NEVER block runApp(). Firebase init can
    // hang or throw for reasons outside this app's control, and an awaited
    // call here would leave the whole app on a blank white screen forever,
    // since runApp() below would never run. This stays unawaited even
    // though init() now passes explicit DefaultFirebaseOptions (so it no
    // longer depends on native google-services.json /
    // GoogleService-Info.plist being present) — the guarantee we want is
    // "startup cannot block on push", not "push usually works". See
    // push_messaging_service.dart's own 8s timeout for the matching
    // defense on the other side.
    unawaited(PushMessagingService.instance.init());
  }

  runApp(App(navigatorKey: appNavigatorKey));
}

class App extends StatelessWidget {
  const App({super.key, this.navigatorKey});
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      // App-wide guard: a double tap can never open the same thing twice
      // (see TapLockNavigatorObserver).
      navigatorObservers: [TapLockNavigatorObserver()],
      builder: (context, child) =>
          TapLockScope(child: child ?? const SizedBox.shrink()),
      home: _screenshotMode == 0 ? const AuthGate() : const ScreenshotRoot(),
    );
  }
}

/// Public (not `_ScreenshotRoot`) specifically so lib/main_verify.dart — a
/// separate entry point, its own MaterialApp, never touching this file's
/// own `home:` — can reuse this switch instead of duplicating it. The
/// _screenshotMode constant above is still what drives it either way,
/// dart-defines are compile-time-global regardless of which file's main()
/// actually runs.
class ScreenshotRoot extends StatefulWidget {
  const ScreenshotRoot({super.key});

  @override
  State<ScreenshotRoot> createState() => ScreenshotRootState();
}

class ScreenshotRootState extends State<ScreenshotRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
  }

  void _showOverlay() {
    switch (_screenshotMode) {
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const ComposerScreen(),
          ),
        );
      case 10:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const ComposerScreen(),
          ),
        );
      case 11:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const ComposerScreen(
              testPhase: ComposerPhase.confirm,
              testAnonymous: true,
            ),
          ),
        );
      case 12:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) =>
                const ComposerScreen(testPhase: ComposerPhase.confirm),
          ),
        );
      case 13:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) =>
                const ComposerScreen(testPhase: ComposerPhase.confirm),
          ),
        );
      case 14:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) =>
                const ComposerScreen(testPhase: ComposerPhase.confirm),
          ),
        );
      case 5:
      case 6:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PingScreen(initialTab: 1),
          ),
        );
      case 7:
        break; // highlight scroll removed
      case 15:
        Navigator.of(context).push(openCameraRoute());
      case 16:
        showModalBottomSheet<PingCapture?>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const PingCameraScreen(
            recipientName: 'alex_xyz',
          ),
        );
      case 18:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => buildPingRepliesFeedScreen(
              senderName: 'alex_xyz',
              replies: const [
                Color(0xFF3A2050),
                Color(0xFF204060),
                Color(0xFF503020),
              ],
            ),
          ),
        );
      case 24:
        showPingChoiceSheet(context);
      case 901:
        final viewed = seedPingFeed().firstWhere((e) => e.id == 'r1');
        showFullScreenReplyPhoto(context, viewed, onPingBack: () {});
      case 902:
        showPingPromptSheet(
          context,
          targetName: 'theo_b',
          pingContext: PingContext.everyone,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold wrapper — several modes return a screen that is normally
    // mounted INSIDE MainShell/HomeScreen (both of which supply their own
    // Scaffold) and so has none of its own. Rendered bare as `home:`, those
    // screens have no Material ancestor, and any TextField beneath them
    // (e.g. PostCommentCard's comment composer) throws "No Material widget
    // found" and paints a red error box over the card. That's a harness
    // artifact, never reachable in the real app — this makes the harness
    // match the real ancestry instead of faking a fix in the widgets.
    //
    // Modes that already return their own Scaffold/MainShell are unharmed:
    // a nested Scaffold is legal and the inner one wins for layout.
    return Scaffold(backgroundColor: AppColors.background, body: _screen());
  }

  Widget _screen() {
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
      case 51:
      case 901:
      case 902:
        return const MainShell();
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
      case 900:
        return _PingVisualQaHarness();
      case 32:
        return const OtpScreen(email: 'test@rvce.edu.in');
      case 33:
        return const OnboardingScreen();
      case 34:
        return const AuthScreen();
      case 35:
        return const ForgotPasswordScreen();
      case 36:
        return const ResetPasswordScreen(email: 'test@rvce.edu.in');
      case 37:
        return const OtpScreen(
          email: 'test@rvce.edu.in',
          purpose: OtpPurpose.recovery,
        );
      case 40:
        return const GroupProfileDirectionPicker();
      case 41:
        return const _DualPhotoTestHarness();
      case 50:
        return const AnonFeedScreenV2();
      case 55:
        return const MainShell(debugInitialHomeTab: 0);
      case 60:
        return const CommunityScreen();
      case 61:
        return const CommunityScreen(debugShowStreaks: true);
      case 62:
        return const MainShell(debugInitialIndex: 2);
      case 63:
        // Exercises the same fetch-and-render path a real Friends-feed
        // avatar tap goes through (features/profile_v2/profile_navigation.
        // dart's openProfile) against a REAL users row, without needing an
        // actual tap gesture — verifies real data renders correctly into
        // TheirProfileScreen. Not a substitute for confirming the
        // GestureDetector itself receives a real touch; that part is
        // standard GestureDetector(behavior: HitTestBehavior.opaque) usage,
        // verified by reading, not by this harness.
        return const _TheirProfileRealDataHarness();
      case 64:
        // MyProfileScreen with real "My Duos" data — same harness
        // philosophy as mode 63, just the self-profile side of Phase 3.
        return const MyProfileScreen();
      case 65:
        // One real multi-photo post, with the poster-only Reactions
        // section shown (item #1 — replaces the old public reactions
        // dropdown this harness used to force open), so the carousel
        // (dots/counter) AND the new section's placement can both be
        // inspected in a single static screenshot. Real ids/URLs — this
        // post is seeded with 3 photo_urls and a real reaction row.
        return const SingleChildScrollView(
          child: DesignSoloCard(
            postId: '078367f9-032e-4e9c-924e-602cc06863ff',
            username: 'abhishek sd patel',
            userId: '5658d3a5-9d46-4e71-ae43-596ae6ba42c9',
            caption: 'Multi-photo + reactions section harness',
            photoUrl:
                'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/078367f9-032e-4e9c-924e-602cc06863ff.jpg',
            photoUrls: [
              'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/078367f9-032e-4e9c-924e-602cc06863ff.jpg',
              'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/a26de289-1ef6-44f2-baad-8b0f6f36977a.jpg',
              'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/a23db915-246a-4dce-ae9a-2877fa55d159.jpg',
            ],
            showReactionsViewer: true,
            showActionRail: false,
          ),
        );
      case 55:
        return const MainShell(debugInitialHomeTab: 0);
      case 60:
        return const CommunityScreen();
      case 61:
        return const CommunityScreen(debugShowStreaks: true);
      case 62:
        return const MainShell(debugInitialIndex: 2);
      case 63:
        // Exercises the same fetch-and-render path a real Friends-feed
        // avatar tap goes through (features/profile_v2/profile_navigation.
        // dart's openProfile) against a REAL users row, without needing an
        // actual tap gesture — verifies real data renders correctly into
        // TheirProfileScreen. Not a substitute for confirming the
        // GestureDetector itself receives a real touch; that part is
        // standard GestureDetector(behavior: HitTestBehavior.opaque) usage,
        // verified by reading, not by this harness.
        return const _TheirProfileRealDataHarness();
      case 64:
        // MyProfileScreen with real "My Duos" data — same harness
        // philosophy as mode 63, just the self-profile side of Phase 3.
        return const MyProfileScreen();
      case 65:
        // One real multi-photo post, with the poster-only Reactions
        // section shown (item #1 — replaces the old public reactions
        // dropdown this harness used to force open), so the carousel
        // (dots/counter) AND the new section's placement can both be
        // inspected in a single static screenshot. Real ids/URLs — this
        // post is seeded with 3 photo_urls and a real reaction row.
        return const SingleChildScrollView(
          child: DesignSoloCard(
            postId: '078367f9-032e-4e9c-924e-602cc06863ff',
            username: 'abhishek sd patel',
            userId: '5658d3a5-9d46-4e71-ae43-596ae6ba42c9',
            caption: 'Multi-photo + reactions section harness',
            photoUrl:
                'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/078367f9-032e-4e9c-924e-602cc06863ff.jpg',
            photoUrls: [
              'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/078367f9-032e-4e9c-924e-602cc06863ff.jpg',
              'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/a26de289-1ef6-44f2-baad-8b0f6f36977a.jpg',
              'https://uehqazxnodndutjvxemq.supabase.co/storage/v1/object/public/posts/everyone/5658d3a5-9d46-4e71-ae43-596ae6ba42c9/a23db915-246a-4dce-ae9a-2877fa55d159.jpg',
            ],
            showReactionsViewer: true,
            showActionRail: false,
          ),
        );
      case 42:
        return LockedRepliesScreen(
          momentId: 'test-moment-1',
          title: 'Quad Golden Hour',
          replies: List.generate(
            5,
            (i) => MomentReply(
              name: ['mira.j', 'theo_b', 'devon_r', 'priya_n', 'alex_k'][i],
              emoji: ['🔥', '😍', '💯', '🥹', '😂'][i],
              photoUrl: 'https://picsum.photos/seed/moment-reply-$i/480/680',
            ),
          ),
        );
      // 950-952=Profile v2 create flows (Add Moment / Create Group / Group
      // Post) — real Supabase wiring, added alongside profile_v2/
      // profile_v2_create_flows.dart for isolated-simulator verification.
      case 950:
        return const AddMomentScreen();
      case 951:
        return const CreateGroupScreen();
      case 952:
        return const GroupPostScreen();
      case 953:
        return const OnboardingCirclesScreen(communityIds: []);
      // 954=Pinned tab (eye sheet, Phase 1 pinning verification)
      // 955=Pin picker sheet (search + pin/unpin)
      case 954:
        return const Scaffold(
          backgroundColor: Color(0xFF08080A),
          body: SafeArea(child: Padding(padding: EdgeInsets.all(16), child: PinnedSection())),
        );
      case 955:
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: PinPickerSheet(),
        );
      // 956=Whoami (read-only) — prints signed-in email/users.id/auth_id +
      // current pins + latest notifications, for real-session verification.
      // 957=same, then auto-pins 'abisheksdpatel' for real. 958=same, then
      // auto-reacts to another user's real post for real (fires
      // notify_reaction for THAT post's author, not this session).
      // 970=RealMoji library in the Anon scope — the variant-1A grid, on a
      // real session so the saved/unsaved states are the real ones.
      case 970:
        return const RealmojiLibraryScreen(
          feedScope: ReactionPresetCategory.anonymous,
        );
      case 956:
        return const _WhoamiHarness(autoAction: _WhoamiAction.none);
      case 957:
        return const _WhoamiHarness(autoAction: _WhoamiAction.pin);
      case 958:
        return const _WhoamiHarness(autoAction: _WhoamiAction.react);
      // 961=probes live groups + membership + RPC existence (send_group_ping,
      // ping_post_author, send_ping) via deliberately-invalid calls, writing
      // nothing real. 962=sends a REAL group ping to a group id passed via
      // GROUP_PING_TARGET (--dart-define), prompt fixed to 'plan verify'.
      // 963=sends a REAL anon ping to a post id passed via ANON_PING_POST_ID.
      case 961:
        return const _WhoamiHarness(autoAction: _WhoamiAction.probe);
      case 962:
        return const _WhoamiHarness(autoAction: _WhoamiAction.groupPing);
      case 963:
        return const _WhoamiHarness(autoAction: _WhoamiAction.anonPing);
      default:
        return const MainShell();
    }
  }
}

/// Screenshot-mode-only harness for mode 63: fetches the first real `users`
/// row and renders it through ProfileLookupService into TheirProfileScreen —
/// the exact same fetch-and-build path openProfile() uses for a real avatar
/// tap, just triggered directly instead of via a GestureDetector.
class _TheirProfileRealDataHarness extends StatelessWidget {
  const _TheirProfileRealDataHarness();

  Future<PersonProfile?> _load() async {
    final row = await Supabase.instance.client
        .from('users')
        .select('id')
        .limit(1)
        .maybeSingle();
    final id = row?['id'] as String?;
    if (id == null) return null;
    return ProfileLookupService.instance.fetchById(id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PersonProfile?>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final person = snapshot.data;
        if (person == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'No users row found',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        return TheirProfileScreen(person: person);
      },
    );
  }
}

/// Screenshot-mode-only harness for mode 900: stacks the Ping feature's
/// hatch-texture/gradient states (unviewed ReplyRow, GroupWallCard, the
/// full-screen reply photo viewer) that don't naturally sit above the fold
/// in the real scrollable page, so they can be visually spot-checked
/// without driving simulator scroll gestures. Not part of the shipped app
/// surface.
class _PingVisualQaHarness extends StatelessWidget {
  _PingVisualQaHarness();

  final _feed = seedPingFeed();

  @override
  Widget build(BuildContext context) {
    final unviewedReply = _feed.firstWhere((e) => e.id == 'r2');
    final viewed = _feed.firstWhere((e) => e.id == 'r1');
    final group = _feed.firstWhere((e) => e.id == 'g1');
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0D),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            ReplyRow(entry: unviewedReply, onTap: () {}),
            const SizedBox(height: 16),
            GroupWallCard(
              entry: group,
              onMemberRevealed: (_) {},
              onExpandToReply: () {},
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  showFullScreenReplyPhoto(context, viewed, onPingBack: () {}),
              child: const Text('Open full-screen reply photo'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => showPingPromptSheet(
                context,
                targetName: 'theo_b',
                pingContext: PingContext.everyone,
              ),
              child: const Text('Open prompt-picker sheet'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 500,
              child: PingReplyDetailScreen(entry: viewed, onPingBack: () {}),
            ),
          ],
        ),
      ),
    );
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
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = color,
    );
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

// ---------------------------------------------------------------------------
// _WhoamiHarness (mode 956) — real-session verification, no mock data. Shows
// who's actually signed in on this device, then exercises the real Phase 1
// (pinning) and Phase 4 (notifications) client paths against the live DB
// through the app's own authenticated Supabase client — the same call path
// a real tap would take, just triggered directly since taps can't be
// simulated on this simulator (see the app's own screenshot-workaround
// convention). Read-only aside from the explicit "Pin" / "React" buttons.
// ---------------------------------------------------------------------------

enum _WhoamiAction { none, pin, react, probe, groupPing, anonPing }

class _WhoamiHarness extends StatefulWidget {
  const _WhoamiHarness({required this.autoAction});
  final _WhoamiAction autoAction;

  @override
  State<_WhoamiHarness> createState() => _WhoamiHarnessState();
}

class _WhoamiHarnessState extends State<_WhoamiHarness> {
  String _log = 'Loading…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  // No tap capability in the verification sandbox — everything this
  // harness does happens automatically on load, gated by the
  // screenshot-mode number (956/957/958) rather than a button.
  Future<void> _run() async {
    await _refresh();
    switch (widget.autoAction) {
      case _WhoamiAction.none:
        break;
      case _WhoamiAction.pin:
        await _pinAbisheksdpatel();
      case _WhoamiAction.react:
        await _reactToOthersPost();
      case _WhoamiAction.probe:
        await _probeGroupsAndPingRpcs();
      case _WhoamiAction.groupPing:
        await _sendRealGroupPing();
      case _WhoamiAction.anonPing:
        await _sendRealAnonPing();
    }
  }

  /// Read-only probe for the plan's Step 2.0: confirms (a) which groups I'm
  /// actually in and their real member lists (same calls _loadRealPingData
  /// makes, so a silent [] is visible here instead of just inferred from a
  /// missing chip), and (b) whether send_group_ping / send_ping /
  /// ping_post_author exist live, via calls engineered to fail on a KNOWN
  /// validation message (proving the RPC exists and ran) rather than on
  /// PGRST202/"Could not find the function" (proving it's missing). Writes
  /// nothing — every call below is chosen specifically to abort before any
  /// INSERT.
  Future<void> _probeGroupsAndPingRpcs() async {
    setState(() => _busy = true);
    final sb = Supabase.instance.client;
    final buf = StringBuffer('$_log\n\n--- groups + ping RPC probe ---\n');
    try {
      final groups = await GroupService.instance.fetchMyGroups();
      buf.writeln('my groups (${groups.length}):');
      for (final g in groups) {
        final id = g['id'] as String;
        final name = g['name'] as String? ?? '(unnamed)';
        try {
          final members = await GroupService.instance.fetchMembers(id);
          final names = members
              .map((m) => (m['users'] as Map?)?['name'] ?? m['user_id'])
              .join(', ');
          buf.writeln('  - $name ($id) — ${members.length} members: $names');
        } catch (e) {
          buf.writeln('  - $name ($id) — fetchMembers FAILED: $e');
        }
      }
    } catch (e) {
      buf.writeln('fetchMyGroups FAILED: $e');
    }

    Future<void> probeRpc(String label, String fn, Map<String, dynamic> params) async {
      try {
        await sb.rpc(fn, params: params);
        buf.writeln('$label: RPC returned with no error (unexpected for this probe input)');
      } catch (e) {
        final msg = e.toString();
        final missing = msg.contains('PGRST202') || msg.contains('Could not find the function');
        buf.writeln('$label: ${missing ? 'MISSING (function not found)' : 'EXISTS (validation error, as expected)'} — $msg');
      }
    }

    await probeRpc(
      'send_group_ping',
      'send_group_ping',
      {'p_group_id': '00000000-0000-0000-0000-000000000000', 'p_prompt': 'probe'},
    );
    try {
      final myId = await CurrentUserService.instance.resolveId();
      await probeRpc('send_ping', 'send_ping', {'p_receiver_id': myId, 'p_prompt': 'probe'});
    } catch (e) {
      buf.writeln('send_ping probe skipped, could not resolve my id: $e');
    }
    await probeRpc(
      'ping_post_author',
      'ping_post_author',
      {'p_post_id': '00000000-0000-0000-0000-000000000000', 'p_prompt': 'probe'},
    );

    if (mounted) setState(() => _log = buf.toString());
    if (mounted) setState(() => _busy = false);
  }

  /// Sends a REAL group ping via PingService.sendGroupPing — the exact
  /// production call design_group_card.dart / ping_page.dart make. Target
  /// group id comes from --dart-define=GROUP_PING_TARGET so this file never
  /// needs a hardcoded id; if omitted, falls back to the first group
  /// fetchMyGroups() returns.
  Future<void> _sendRealGroupPing() async {
    setState(() => _busy = true);
    final buf = StringBuffer('$_log\n\n--- real group ping ---\n');
    const target = String.fromEnvironment('GROUP_PING_TARGET');
    try {
      var groupId = target;
      if (groupId.isEmpty) {
        final groups = await GroupService.instance.fetchMyGroups();
        if (groups.isEmpty) {
          buf.writeln('no GROUP_PING_TARGET define and no groups to fall back to');
          if (mounted) setState(() => _log = buf.toString());
          if (mounted) setState(() => _busy = false);
          return;
        }
        groupId = groups.first['id'] as String;
        buf.writeln('no GROUP_PING_TARGET define, falling back to first group: $groupId');
      }
      final count = await PingService.instance.sendGroupPing(groupId: groupId, prompt: 'plan verify');
      buf.writeln('sendGroupPing($groupId) OK — recipients=$count');
    } catch (e) {
      buf.writeln('sendGroupPing FAILED: $e');
    }
    if (mounted) setState(() => _log = buf.toString());
    if (mounted) setState(() => _busy = false);
  }

  /// Sends a REAL anon ping via PingService.pingPostAuthor — the exact
  /// production call _openPromptPicker in anon_feed_screen.dart makes.
  /// Target post id comes from --dart-define=ANON_PING_POST_ID.
  Future<void> _sendRealAnonPing() async {
    setState(() => _busy = true);
    final buf = StringBuffer('$_log\n\n--- real anon ping ---\n');
    const postId = String.fromEnvironment('ANON_PING_POST_ID');
    if (postId.isEmpty) {
      buf.writeln('no ANON_PING_POST_ID define passed, nothing to ping');
    } else {
      try {
        await PingService.instance.pingPostAuthor(postId: postId, prompt: 'anon verify');
        buf.writeln('pingPostAuthor($postId) OK');
      } catch (e) {
        buf.writeln('pingPostAuthor FAILED: $e');
      }
    }
    if (mounted) setState(() => _log = buf.toString());
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refresh() async {
    final sb = Supabase.instance.client;
    final buf = StringBuffer();
    final session = sb.auth.currentSession;
    buf.writeln('email: ${session?.user.email}');
    buf.writeln('auth_id: ${session?.user.id}');

    String? myUserId;
    try {
      final me = await sb.from('users').select('id, name').eq('auth_id', session?.user.id ?? '').maybeSingle();
      myUserId = me?['id'] as String?;
      buf.writeln('users.id: $myUserId (${me?['name']})');
    } catch (e) {
      buf.writeln('users lookup failed: $e');
    }

    try {
      final rows = await PostAuthorPinService.instance.listPinned();
      buf.writeln('\npinned (${rows.length}):');
      for (final r in rows) {
        buf.writeln('  - ${r['name']} (${r['pinned_user_id']}) at ${r['pinned_at']}');
      }
    } catch (e) {
      buf.writeln('\nlistPinned() failed: $e');
    }

    try {
      final notifs = await NotificationFeedService.instance.fetchPage(limit: 10);
      buf.writeln('\nnotifications (${notifs.length} latest):');
      for (final n in notifs) {
        buf.writeln('  - [${n.type}/${n.tier}] ${n.title} (read=${n.isRead}) ${n.createdAt}');
      }
    } catch (e) {
      buf.writeln('\nfetchPage() failed: $e');
    }

    if (mounted) setState(() => _log = buf.toString());
  }

  Future<void> _pinAbisheksdpatel() async {
    setState(() => _busy = true);
    final buf = StringBuffer('$_log\n\n--- pin attempt ---\n');
    try {
      final newCount = await PostAuthorPinService.instance.pinPerson('726dc111-4c83-4974-94ba-e700118d7a7d');
      buf.writeln('pinPerson OK, new count=$newCount');
    } catch (e) {
      buf.writeln('pinPerson FAILED: $e');
    }
    if (mounted) setState(() => _log = buf.toString());
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reactToOthersPost() async {
    setState(() => _busy = true);
    final sb = Supabase.instance.client;
    final buf = StringBuffer('$_log\n\n--- react attempt ---\n');
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final post = await sb
          .from('posts')
          .select('id, user_id')
          .neq('user_id', myId)
          .isFilter('deleted_at', null)
          .limit(1)
          .maybeSingle();
      if (post == null) {
        buf.writeln('no other-authored post found');
      } else {
        await sb.from('reactions').upsert({
          'post_id': post['id'],
          'user_id': myId,
          'type': 'emoji',
          'emoji': '🔥',
        }, onConflict: 'post_id,user_id,type');
        buf.writeln('reacted to post ${post['id']} (author ${post['user_id']}) — check THEIR inbox for the notification');
      }
    } catch (e) {
      buf.writeln('react FAILED: $e');
    }
    if (mounted) setState(() => _log = buf.toString());
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(_log, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
