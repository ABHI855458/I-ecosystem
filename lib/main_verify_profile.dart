import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/supabase_config.dart' show SupabaseConfig, supabase;
import 'core/theme.dart';
import 'features/composer/composer_screen.dart';
import 'features/profile_v2/my_profile_screen.dart';
import 'features/profile_v2/profile_posts_list.dart';
import 'features/profile_v2/profile_v2_icons.dart';
import 'features/profile_v2/profile_v2_menus.dart';
import 'features/profile_v2/profile_v2_sections.dart';
import 'features/profile_v2/profile_v2_tokens.dart';
import 'screens/feed/single_post_detail_screen.dart';
import 'services/demo_content.dart';
import 'services/feed_service.dart';
import 'services/post_service.dart';

// ---------------------------------------------------------------------------
// Second isolated verification entry point, sibling to lib/main_verify.dart
// (owned by the concurrent `profile-posts-real-data` session — untouched
// here). Its own main(), its own MaterialApp, its own `home:`, its own
// --dart-define (VSCREEN, not SCREENSHOT_MODE) so the two harnesses can
// never collide or misread each other's define. Run only against the
// `claude-verify` simulator, never F3ABA043 (the other session's device).
//
// Exists to answer one question the code-read Step-1 report couldn't:
// do the five profile/post-interaction items the report found "already
// implemented" actually render and behave correctly at runtime. Nothing
// here is production code — delete this file when verification is done.
// ---------------------------------------------------------------------------

const _screen = String.fromEnvironment('VSCREEN', defaultValue: 'profile');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF16151A),
    ),
  );

  debugPrint('[PVERIFY] VSCREEN define = $_screen');

  await dotenv.load(fileName: '.env', isOptional: true);
  await SupabaseConfig.initialize();
  DemoContent.seedIfNeeded();

  runApp(const _VerifyApp());
}

class _VerifyApp extends StatelessWidget {
  const _VerifyApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I (profile verify)',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const _VerifyRoot(),
    );
  }
}

class _VerifyRoot extends StatefulWidget {
  const _VerifyRoot();

  @override
  State<_VerifyRoot> createState() => _VerifyRootState();
}

class _VerifyRootState extends State<_VerifyRoot> {
  Widget? _resolved;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      switch (_screen) {
        case 'fab':
          // Same MyProfileScreen the 'profile' case mounts, but with the
          // creation FAB pre-opened — simulator taps don't work here, so
          // the menu is constructed already `open: true` rather than
          // relying on a tap to open it.
          _resolved = const _FabOpenHarness();
        case 'raw_query':
          // Diagnostic only — bypasses FeedService's fail-closed-to-empty
          // catch to see the RAW error (if any) an unauthenticated client
          // gets querying `posts` directly, since fetchEveryoneFeed()
          // returned 0 rows with no way to tell "genuinely empty" from
          // "permission denied, swallowed".
          try {
            final rows = await supabase.from('posts').select('id, visibility, deleted_at').limit(5);
            debugPrint('[PVERIFY] raw_query rows=${rows.length} sample=$rows');
          } catch (e) {
            debugPrint('[PVERIFY] raw_query ERROR: $e');
          }
          _resolved = const Scaffold(body: Center(child: Text('see log', style: TextStyle(color: Colors.white))));
        case 'posts':
          // Mounts the real, shared PostsList (features/profile_v2/
          // profile_posts_list.dart) directly, sidestepping MyProfileScreen
          // entirely — this simulator has no signed-in session (see the
          // 'profile' case), so MyProfileScreen's OWN Posts tab is always
          // empty here. PostsList doesn't care whose posts they are, so
          // real public 'everyone' posts (no auth required to read, per
          // posts_select in schema.sql) drive it instead, giving genuine
          // DesignSoloCard/EveryonePostCard rendering — Ping, RealMoji, the
          // comment-count row — exactly as items 1/3/4 need to be seen.
          final everyone = await FeedService.instance.fetchEveryoneFeed(limit: 6);
          debugPrint('[PVERIFY] posts: fetchEveryoneFeed returned ${everyone.length} rows');
          _resolved = _PostsHarness(items: everyone);
        case 'nophoto':
          // Group-2 item C: a caption-only post (no photoUrl, no photos)
          // used to lose Ping/RealMoji/the reactions pill/the comment card
          // entirely, since DesignSoloCard gated all of them on `hasPhoto`.
          // Synthetic FeedItem rather than hoping a real everyone-feed post
          // happens to lack a photo. Fake ids are fine here — reaction/
          // comment loads fail closed (caught, logged) on a non-UUID id,
          // same as every other demo-post id in this app.
          _resolved = _PostsHarness(items: [
            FeedItem(
              postId: 'pverify-nophoto-1',
              type: 'single',
              userId: 'pverify-user',
              username: 'test_user',
              caption: 'Caption-only post — no photo. Ping, RealMoji, '
                  'reactions and the comment thread should still render.',
              createdAt: DateTime.now(),
            ),
          ]);
        case 'detail':
          final everyone = await FeedService.instance.fetchEveryoneFeed(limit: 6);
          if (everyone.isEmpty) {
            _resolved = const Center(
              child: Text('[PVERIFY] fetchEveryoneFeed() returned no rows — '
                  'nothing to open a detail screen for.',
                  style: TextStyle(color: Colors.white)),
            );
          } else {
            final item = everyone.first;
            debugPrint('[PVERIFY] detail: using postId=${item.postId} '
                'type=${item.type} groupName=${item.groupName}');
            _resolved = SinglePostDetailScreen(item: item);
          }
        case 'composer':
          // Jumps straight to the send/confirm phase (skips the camera
          // capture UI, which needs a real camera the simulator doesn't
          // have) — this is where the destination pill row lives. Personal
          // (Everyone) posts and the 'composer_locked'/lockToPersonalPost
          // verification case that used to sit here were both removed along
          // with the feature — see composer_screen.dart's own history.
          _resolved = const ComposerScreen(testPhase: ComposerPhase.confirm);
        case 'delete_trace':
          _resolved = const _DeleteTraceHarness();
        case 'profile':
        default:
          _resolved = const MyProfileScreen();
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('[PVERIFY] error: $_error',
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_resolved == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _resolved!;
  }
}

/// Mounts the real, shared [PostsList] (the exact widget MyProfileScreen's
/// own Posts tab uses at my_profile_screen.dart:1577-1587) with a real
/// `leading` AddTile and a delete overlay on the first card pre-opened
/// (`open: true`, since simulator taps don't land here) — mirrors
/// my_profile_screen.dart's own `_postOptions`/`_postMenuPanel` shape
/// without importing its private members.
class _PostsHarness extends StatefulWidget {
  const _PostsHarness({required this.items});

  final List<FeedItem> items;

  @override
  State<_PostsHarness> createState() => _PostsHarnessState();
}

class _PostsHarnessState extends State<_PostsHarness> {
  // See _FabOpenHarnessState's note: PV2MenuAnchor needs a false->true
  // transition AFTER the anchor is laid out, not `open: true` from frame
  // one, or the overlay computes its position against an unlaid-out target.
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _menuOpen = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: PV2.pad, vertical: 24),
          child: PostsList(
            items: items,
            leading: AddTile(
              label: 'add post',
              icon: PV2Icons.plus(22, PV2.accent),
              radius: 20,
              onTap: () => debugPrint('[PVERIFY] tapped add post'),
            ),
            overlayBuilder: (item) => Positioned(
              top: 18,
              right: 18,
              child: PV2MenuAnchor(
                open: _menuOpen && items.isNotEmpty && item.postId == items.first.postId,
                onDismiss: () => setState(() => _menuOpen = false),
                offset: const Offset(0, 6),
                menu: PV2MenuPanel(
                  width: 134,
                  radius: 13,
                  padding: 4,
                  fill: PV2.menuFillLight,
                  border: PV2.menuBorderStrong,
                  children: [
                    PV2MenuItem(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete Post',
                      iconSize: 14,
                      fontSize: 12.5,
                      gap: 8,
                      radius: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      destructive: true,
                      onTap: () => debugPrint('[PVERIFY] tapped Delete Post'),
                    ),
                  ],
                ),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_horiz, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mounts the real PV2CreateFab pre-opened over a plain dark scaffold, so
/// the menu's exact option list can be screenshotted without a tap.
class _FabOpenHarness extends StatefulWidget {
  const _FabOpenHarness();

  @override
  State<_FabOpenHarness> createState() => _FabOpenHarnessState();
}

class _FabOpenHarnessState extends State<_FabOpenHarness> {
  // PV2MenuAnchor only pushes the overlay open on a false->true transition
  // seen in didUpdateWidget (profile_v2_menus.dart:85-93) — starting
  // already `open: true` on the very first frame means the anchor's
  // GlobalKey hasn't been laid out yet when the overlay computes its
  // position, so it renders pinned off-anchor. A real tap always causes a
  // genuine transition well after layout, so this mirrors that instead of
  // starting pre-opened.
  bool _open = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _open = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: Stack(
        children: [
          Positioned(
            right: 24,
            bottom: 120,
            child: PV2CreateFab(
              open: _open,
              onToggle: () => setState(() => _open = !_open),
              onAddMoment: () => debugPrint('[PVERIFY] tapped Add Moment'),
              onAddGroupPost: () => debugPrint('[PVERIFY] tapped Add Group Post'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Item 3 (optimistic delete) can't be screenshotted — it's a claim about
/// ordering, not appearance. This creates one throwaway personal post,
/// prints the pre/post counts around PostService.deletePost, and never
/// touches any pre-existing row.
class _DeleteTraceHarness extends StatefulWidget {
  const _DeleteTraceHarness();

  @override
  State<_DeleteTraceHarness> createState() => _DeleteTraceHarderState();
}

class _DeleteTraceHarderState extends State<_DeleteTraceHarness> {
  String _log = 'running…';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final lines = <String>[];
    try {
      final before = await FeedService.instance.fetchUserPosts();
      lines.add('before: ${before.length} posts');

      final userId = before.isNotEmpty
          ? before.first.userId
          : (await FeedService.instance.fetchUserPosts()).firstOrNullUserId();

      final post = LocalPost(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        userId: userId ?? '',
        username: 'pverify-throwaway',
        visibility: 'everyone',
        caption: '[PVERIFY throwaway — safe to ignore/delete]',
        photoPath: null,
        createdAt: DateTime.now(),
      );
      await PostService.instance.addPost(post);
      lines.add('created throwaway post ${post.id}');

      final mid = await FeedService.instance.fetchUserPosts();
      lines.add('after create: ${mid.length} posts');

      await PostService.instance.deletePost(post.id);
      lines.add('called PostService.deletePost(${post.id})');

      final after = await FeedService.instance.fetchUserPosts();
      lines.add('after delete: ${after.length} posts '
          '(should match "before" count: ${before.length})');
    } catch (e) {
      lines.add('ERROR: $e');
    }
    for (final l in lines) {
      debugPrint('[PVERIFY][delete_trace] $l');
    }
    if (mounted) setState(() => _log = lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_log, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ),
    );
  }
}

extension _FirstUserId on List<FeedItem> {
  String? firstOrNullUserId() => isEmpty ? null : first.userId;
}
