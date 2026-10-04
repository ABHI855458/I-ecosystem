import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'screens/feed/widgets/face_reaction_capture.dart' show prewarmRealmojiCamera;
import 'shared/slight_swipe_settle.dart';

import 'shared/nav_guard.dart';
import 'package:flutter/services.dart';
import 'core/constants.dart';
import 'core/push_messaging_service.dart';
import 'features/composer/composer_screen.dart';
import 'features/community/community_screen.dart';
import 'features/profile_v2/duo_post_audience_sheet.dart';
import 'features/ping/ping_realmoji.dart' show showPingRealmojiReactors;
import 'services/ping_realmoji_service.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/ping/ping_screen.dart';
import 'features/ping/ping_page.dart'
    show groupWallAnswerRequest, pingFocusRequest, pingTabActive, prefetchPingData;
import 'features/profile_v2/my_profile_screen.dart';
import 'features/profile_v2/group_profile_v2_screen.dart' show GroupProfileV2Screen;
import 'features/profile_v2/requests_section.dart' show requestsOpenRequest;
import 'shared/glass_notif_card.dart';
import 'main.dart' show appNavigatorKey;
import 'core/glass.dart' show showGlassToast;
import 'screens/feed/single_post_detail_screen.dart';
import 'services/feed_service.dart';
import 'services/ping_prompt_service.dart';
import 'shared/score_tier.dart';
import 'shared/tab_bar_icons.dart';
import 'core/ui/immersive_chrome.dart';

// Bottom tab bar geometry — the tab bar's own, unchanged position. Used
// on EVERY tab (Home/Ping/Community/Profile — see the AnimatedPositioned
// below, which wraps the single IndexedStack all four tabs share), never
// anon-specific. Do not derive these FROM anything else (the peek strip
// derives from these, not the other way around — see anonymous_tab.dart).
const double kTabBarHeight = 56.0;
const double kTabBarBottomOffset = 24.0;
const double kTabBarBottomOffsetCompact = 16.0;

// Extra lift applied ONLY to the bar's own position below (not to
// kTabBarBottomOffset itself, which the Anonymous feed's peek strip, the
// ping FAB, and the notification overlay all also read) — opens a gap
// between the bar and the peek strip's top edge without moving or
// resizing anything else.
const double kTabBarExtraLift = 10.0;

// Pulls the bar closer to the physical bottom edge on every non-Anon page
// (Friends/Home's own Everyone sub-page, Ping, Community, Profile) — those
// pages sit flush at bottomPad today (Instagram-style, no lift), which read
// as sitting a touch high. Anon is untouched: its floating position is
// already tuned against the peek strip's own static reservation (see
// kTabBarExtraLift above) and isn't part of this ask. Clamped to 0 so
// devices with bottomPad == 0 (no home indicator) never push the bar
// past the physical screen edge.
const double _tabBarLowerOffset = 10.0;

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.debugInitialHomeTab, this.debugInitialIndex});

  /// Debug-only passthrough to the Home tab's own HomeScreen.debugInitialTab
  /// — lets a debug route land on Friends (or Anon) inside the REAL shell
  /// (tab bar, notifications, etc. all present) instead of a bare
  /// Scaffold(body: HomeScreen(...)) that skips this widget (and therefore
  /// the floating tab bar) entirely. Null everywhere except that one debug
  /// call site.
  final int? debugInitialHomeTab;

  /// Debug-only — lands MainShell's own bottom-nav on a given tab index
  /// (0=Home, 1=Ping, 2=Community, 3=Profile) instead of always Home. Null
  /// everywhere except debug screenshot call sites.
  final int? debugInitialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  late int _currentIndex = widget.debugInitialIndex ?? 0;

  // Physics-only mirror of _currentIndex — updated EXCLUSIVELY at gesture
  // settle (see _handleScrollNotification's horizontal branch), never
  // mid-drag like _currentIndex is (that one intentionally updates live,
  // via onPageChanged, for instant nav-highlight tracking). Swapping the
  // outer PageView's ScrollPhysics object mid-gesture disposes its active
  // drag recognizer out from under the still-down finger — gating physics
  // on a value that changes mid-drag (_currentIndex) was why backward
  // swiping off of Ping stopped dead the instant it crossed the midpoint
  // toward Home. Physics now only ever changes between gestures.
  late int _dragLockIndex = widget.debugInitialIndex ?? 0;

  bool _compact = false;
  bool _scrollHideEnabled = false;

  // Whether the Home tab's own Anonymous sub-page (vs its Everyone/Friends
  // sub-page — see HomeScreen's PageView) is currently active. Only the
  // Anonymous sub-page keeps the tab bar's original floating position; every
  // other page (Everyone/Friends, Ping, Community, Profile) uses the lower,
  // Instagram-style position instead — see _tabBarBottom in build().
  // Defaults false to match HomeScreen's own default (_tabIndex now starts
  // at 1, Friends — "first let there be friends feed then anon feed").
  bool _isHomeAnonActive = false;

  // True while the Anon feed's comments sheet is open (AnonFeedScreenV2 —
  // see its own onCommentsOpenChanged doc for why this can't just be a
  // z-order fix). The floating tab bar hides while true and reappears the
  // instant the sheet closes.
  bool _anonCommentsOpen = false;

  late final AnimationController _bannerCtrl;
  late final Animation<Offset> _bannerSlide;
  AppNotif? _lastBannerNotif;

  late final List<Widget> _screens;

  // Drives both tap-to-jump (animateToPage, called from _BottomNav) and
  // drag-to-swipe (native PageView physics) with one shared index — see
  // build()'s physics gating and onTabSelected below for why Home/Profile
  // are locked out of outer drag specifically.
  late final _pageCtrl = PageController(initialPage: widget.debugInitialIndex ?? 0);
  static const _pageCurve = Cubic(0.4, 0.14, 0.3, 1.0); // matches _BottomNav._curve
  static const _pageDuration = Duration(milliseconds: 380);

  StreamSubscription<Map<String, String>>? _pushTapSub;

  @override
  void initState() {
    super.initState();
    // Matches _currentIndex's own initial value — see pingTabActive's own
    // doc (ping_page.dart) for why PingScreen needs to know this at all:
    // it sits in _screens below and stays mounted for the app's lifetime
    // regardless of which page is scrolled into view.
    pingTabActive.value = _currentIndex == 1;
    // Load the Ping tab's data now, alongside the feed — not on first open.
    prefetchPingData();
    // +2 for the first open of the day. MainShell is the first thing that
    // mounts behind a real session (AuthGate routes here only once
    // onboarding and the community step are done), so this is the earliest
    // point where there is definitely a user to credit. Idempotent
    // server-side, so re-entering the shell can't pay twice.
    unawaited(ViewerScoreService.instance.recordDailyOpen());
    // Warm the ping-prompt lists so no ping sheet opens on a fallback list
    // and then swaps (the prompt-dropdown flicker).
    unawaited(PingPromptService.instance.prefetch());
    // Look up the device cameras once, now, so the first RealMoji capture
    // opens its preview straight away.
    prewarmRealmojiCamera();
    // Camera-first-on-launch was tried and reverted (explicit request:
    // land on the Friends feed instead) — MainShell just shows _screens[0]
    // (Home, Friends by default) with no auto-push.
    _screens = [
      HomeScreen(
        debugInitialTab: widget.debugInitialHomeTab,
        onOpenCamera: _openComposer,
        onAnonActiveChanged: (v) {
          if (v != _isHomeAnonActive) setState(() => _isHomeAnonActive = v);
        },
        onCommentsOpenChanged: (v) {
          if (v != _anonCommentsOpen) setState(() => _anonCommentsOpen = v);
        },
        // Continuous fixed-order swipe (Anon → Friends → Ping → …) — see
        // HomeScreen.onFriendsOverscrollUpdate/End's own doc. Home's own
        // inner PageView owns the Anon↔Friends drag; this live-mirrors the
        // outer Ping page in as the user drags past Friends, then commits
        // or springs back on release.
        onFriendsOverscrollUpdate: (over) {
          if (_currentIndex != 0) return;
          final vw = MediaQuery.sizeOf(context).width;
          _pageCtrl.jumpTo(over.clamp(0, vw));
        },
        onFriendsOverscrollEnd: () {
          if (_currentIndex != 0) return;
          final vw = MediaQuery.sizeOf(context).width;
          // 0.35 -> 0.14 of the viewport. Together with the un-damped
          // overscroll HomeScreen now reports, this is what makes the
          // Friends→Ping swipe commit on a normal flick rather than
          // demanding a long deliberate drag.
          final committed = _pageCtrl.offset > vw * 0.14;
          _pageCtrl.animateToPage(
            committed ? 1 : 0,
            duration: _pageDuration,
            curve: _pageCurve,
          );
        },
      ),
      const PingScreen(),
      const CommunityScreen(),
      // Profile v2 (see features/profile_v2/). The bottom nav is a floating
      // pill overlaid on the page rather than a layout sibling, so the screen
      // is told to reserve room for it — otherwise its last row of content
      // sits underneath the bar.
      //
      // NOTE: this drops the Community↔Profile overscroll bridge that the old
      // ProfileScreen implemented (the onBackToCommunityOverscroll* callbacks).
      // Swiping between the two tabs still works via the outer PageView; only
      // the drag-past-the-edge affordance is gone until v2 reimplements it.
      const MyProfileScreen(extraBottomInset: kTabBarHeight + 12),
    ];
    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bannerSlide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _bannerCtrl, curve: Curves.easeOutCubic));

    notifState.onGoHome = () => _jumpToTab(0);
    notifState.onGoPing = () => _jumpToTab(1);
    notifState.onGoCommunity = () => _jumpToTab(2);
    notifState.onGoProfile = () => _jumpToTab(3);
    notifState.onGoLeaderboard = () => _jumpToTab(3);
    notifState.onOpenPingNotif = _onOpenPingNotif;
    notifState.onOpenPost = _onOpenPost;
    notifState.onRouteNotif = _routeNotif;

    notifState.addListener(_onNotifChanged);
    groupWallAnswerRequest.addListener(_onGroupAnswerRequested);
    // Real, persisted notifications (reactions/pings/friend requests/branch
    // views) + the realtime subscription that keeps them live — see
    // NotifState.loadReal's own doc. Loaded at startup so the badge counts
    // in _BottomNav are correct even before the inbox is ever opened.
    notifState.loadReal();

    // A tray tap (background/terminated) never goes through
    // NotifState._tapNotif — that only fires for a tap inside the in-app
    // inbox list. This is the other half: routes a system-notification tap
    // to the same destinations, reusing navigateTo for dispatcher-sent
    // types (which carry notification_id) and falling back to the raw
    // `screen` key for the four direct-send functions that don't write
    // through notify-dispatch (notify-ping, notify-ping-reply,
    // notify-profile-view, prompt-rotation — see their own data payloads).
    _pushTapSub =
        PushMessagingService.instance.onNotificationTap.listen(_onPushTap);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _scrollHideEnabled = true);
      });
    });
  }

  @override
  void dispose() {
    notifState.removeListener(_onNotifChanged);
    groupWallAnswerRequest.removeListener(_onGroupAnswerRequested);
    _pushTapSub?.cancel();
    _bannerCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Sends a tapped notification to the exact place it's about, from the
  /// row's server payload. Returns false for the few cases the older
  /// per-type routing already handles precisely (ping reveal cards, the
  /// inbox rows that carry their own Accept / audience buttons).
  /// Closes anything pushed over the tabs (a group, a post, the inbox) so a
  /// notification's tab switch is actually visible — switching tabs under a
  /// pushed screen changed nothing the user could see.
  /// A group ping was just sent from anywhere — go to the Ping tab, where
  /// PingPage opens the camera for my answer and then shows the wall.
  void _onGroupAnswerRequested() {
    if (groupWallAnswerRequest.value == null) return;
    _popToShell();
    _jumpToTab(1);
  }

  void _popToShell() {
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  }

  /// Profile tab with the Requests panel open — where a Duo invite, group
  /// invite, Duo photo or new group post waits for the user's answer.
  void _openRequests() {
    _popToShell();
    _jumpToTab(3);
    requestsOpenRequest.value = true;
  }

  /// Notifications whose whole point is an answer from the user — all of
  /// which live in the profile's Requests panel. us_album_mutual is shared
  /// by "added a photo to your Duo" (needs MY approval, action=approve) and
  /// "approved your Duo photo" (just news), so only the former counts.
  static bool _isRequest(String? type, Map<String, dynamic> data) =>
      type == 'us_album_invite' ||
      type == 'group_invite' ||
      type == 'group_post' ||
      data['screen'] == 'group_invite' ||
      // action=share: a new group post waiting for MY audience. A
      // pinned_group_post_view also carries group_post_id but is just news.
      (data['screen'] == 'group' && data['action'] == 'share') ||
      (data['screen'] == 'us_album' && data['action'] == 'approve');

  bool _routeNotif(AppNotif n) {
    final d = n.data;
    String? str(String k) => d[k] is String ? d[k] as String : null;

    if (_isRequest(n.rawType, d)) {
      _openRequests();
      return true;
    }
    _popToShell();

    // A RealMoji on my reply / ping: show who reacted, with their selfies
    // — the "see those reactions" half (explicit request, 2026-10-03).
    if (n.rawType == 'ping_realmoji') {
      final replyId = str('ping_reply_id');
      final pingId = replyId == null ? str('ping_id') : null;
      if (replyId == null && pingId == null) return false;
      _jumpToTab(1);
      unawaited(() async {
        try {
          final rx = await PingRealmojiService.instance.fetchFor(
            replyIds: [?replyId],
            pingIds: [?pingId],
          );
          if (!mounted || rx.isEmpty) return;
          await showPingRealmojiReactors(context, rx);
        } catch (_) {}
      }());
      return true;
    }

    // Streak / level-progress rows carry no destination of their own —
    // streaks live on the Ping page. Rank rows used to open the community
    // scoreboard, which is hidden now, so they land there too.
    if (n.type == NotifType.milestone || n.type == NotifType.rank) {
      _jumpToTab(1);
      return true;
    }

    switch (str('screen')) {
      case 'post' || 'post_detail':
        final pid = n.postId ?? str('post_id');
        if (pid == null) return false;
        unawaited(_onOpenPost(pid));
        return true;
      case 'ping' || 'ping_reveal' || 'ping_camera':
        final pingId = n.pingId ?? str('ping_id');
        _jumpToTab(1);
        if (pingId != null) pingFocusRequest.value = pingId;
        return true;
      case 'group':
        final threadId = str('thread_id');
        final groupId = str('group_id');
        // Group pings / group streaks: the group wall on the Ping page.
        if (threadId != null) {
          _jumpToTab(1);
          pingFocusRequest.value = threadId;
          return true;
        }
        // A new group post asks you to pick your audience — that button
        // lives on the inbox row.
        if (str('group_post_id') != null && n.type != NotifType.engagement) {
          return false;
        }
        if (groupId == null) return false;
        appNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => GroupProfileV2Screen(groupId: groupId),
          ),
        );
        return true;
      case 'anon_feed':
        _jumpToTab(0);
        homeTabRequest.value = 1; // Anon is gone — Friends feed
        return true;
      case 'feed':
        _jumpToTab(0);
        homeTabRequest.value = 1;
        return true;
      // Never auto-open the camera from a notification (explicit request:
      // entering the app lands on the Friends feed).
      case 'composer':
        _jumpToTab(0);
        homeTabRequest.value = 1;
        return true;
      // A Duo post by my partner — "choose your audience and post".
      case 'duo_post':
        final duoPostId = str('post_id');
        if (duoPostId == null) return false;
        showDuoPostAudienceSheet(context, postId: duoPostId);
        return true;
      case 'community':
        _jumpToTab(2);
        return true;
      // Somebody messaged in a group chat — land on the chat itself.
      case 'group_chat':
        _jumpToTab(2);
        communityOpenGroupChat.value = str('group_id');
        return true;
      case 'profile' || 'us_album' || 'circles':
        _jumpToTab(3);
        return true;
      case 'moment':
        // Moments are hidden — the post itself if it still exists.
        final pid = n.postId ?? str('post_id');
        if (pid != null) {
          unawaited(_onOpenPost(pid));
        } else {
          _jumpToTab(0);
        }
        return true;
      case 'leaderboard':
        _jumpToTab(1);
        return true;
    }
    // No `screen` but a post attached (comment, older reaction rows).
    final pid = n.postId;
    if (pid != null && n.type == NotifType.engagement) {
      unawaited(_onOpenPost(pid));
      return true;
    }
    return false;
  }

  /// See _pushTapSub's own doc (initState) for why this exists separately
  /// from NotifState._tapNotif.
  Future<void> _onPushTap(Map<String, String> data) async {
    final notificationId = data['notification_id'];
    if (notificationId != null) {
      // Cold-start tap: the row notify-dispatch just sent this push for
      // may be newer than whatever NotifState loaded at startup.
      await notifState.loadReal();
      final rows = notifState.all.where((n) => n.id == notificationId);
      if (rows.isNotEmpty) {
        notifState.navigateTo(rows.first);
        return;
      }
      // Fall through to the screen-based routing below — a digest push
      // (data['screen'] == 'notifications') never carries notification_id
      // in the first place, and a row that's gone by the time the user
      // taps (rare) still deserves a real destination, not a silent tap.
    }

    if (_isRequest(data['type'], data)) {
      _openRequests();
      return;
    }
    _popToShell();
    switch (data['screen']) {
      // Every `screen` value the server can emit is handled here. The
      // server vocabulary is 15 strings (SQL notification rows + the five
      // direct-send edge functions); this switch previously covered 5 and
      // dropped the other 10 into `default`, i.e. the Home feed. That only
      // bit when a dispatcher-sent row couldn't be resolved locally (the
      // notification_id path above handles the normal case), but "tapped a
      // group push, landed on the feed" is exactly the silent-wrong-target
      // class worth closing outright.
      case 'ping_camera':
      case 'ping_reveal':
      case 'ping':
        _jumpToTab(1);
        final pingId = data['ping_id'];
        if (pingId != null) pingFocusRequest.value = pingId;
      case 'profile':
      case 'circles':
      case 'us_album':
        _jumpToTab(3);
      case 'duo_post':
        final duoPostId = data['post_id'];
        if (duoPostId is String) {
          showDuoPostAudienceSheet(context, postId: duoPostId);
        }
      case 'group_chat':
        _jumpToTab(2);
        final chatGroupId = data['group_id'];
        if (chatGroupId is String) communityOpenGroupChat.value = chatGroupId;
      case 'community':
      case 'group':
      case 'groups':
        _jumpToTab(2);
      // post_detail is notify-engagement's spelling, post is the SQL
      // producers' — same destination, two vocabularies. Both resolve to
      // the post itself when an id is present, and degrade to the feed
      // when it isn't, matching navigateTo's own post-family rule.
      case 'post':
      case 'post_detail':
      case 'moment':
        final postId = data['post_id'];
        if (postId != null) {
          unawaited(_onOpenPost(postId));
        } else {
          _jumpToTab(0);
        }
      // The wake-digest push ("N things happened while you were away")
      // is the one that lands here — its whole payload is the inbox.
      // A group-album invite too: its Accept / Decline live on the inbox
      // row (there's no group to open until it's accepted).
      case 'notifications':
        appNavigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        );
      case 'leaderboard':
        _jumpToTab(3);
      case 'feed':
        _jumpToTab(0);
        homeTabRequest.value = 1;
      // Prompts land straight on Dip, not whichever Home side was last open.
      case 'anon_feed':
        _jumpToTab(0);
        homeTabRequest.value = 1; // Anon is gone — Friends feed
      case 'composer':
        // prompt_rotation pushes used to open the camera straight away —
        // which is what "the camera opens when I enter the app" was. Land on
        // the Friends feed instead (Anon no longer exists).
        _jumpToTab(0);
        homeTabRequest.value = 1;
      default:
        _jumpToTab(0);
    }
  }

  void _onNotifChanged() {
    // BUG FIX (explicit report — "the 9+ and notifications aren't changing
    // at all, they are hardcoded"): the bottom nav's badge counts
    // (unreadHome/unreadPings/totalUnread) are read fresh in build(), but
    // this is the ONLY listener on notifState — so marking something read,
    // or a background realtime refresh that touches no banner, used to
    // never call setState at all (it only did inside the banner-visible
    // branch). The badges looked frozen because nothing was ever
    // rebuilding them outside of an unrelated tab-switch. Every
    // notifyListeners() from NotifState must refresh this shell now; the
    // banner show/hide animation below is an ADDITIONAL effect, not the
    // only reason to rebuild.
    if (mounted) setState(() {});
    if (notifState.bannerVisible) {
      _lastBannerNotif = notifState.bannerNotif;
      _bannerCtrl.forward(from: 0);
    } else {
      _bannerCtrl.reverse().then((_) {
        if (mounted) setState(() => _lastBannerNotif = null);
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    // _dragLockIndex sync — see its own doc. Checked before the
    // _scrollHideEnabled gate below since it must never miss a settle.
    // Nested horizontal scrollers (a post's photo carousel, the Group Wall
    // pager) bubble their notifications through here too. Only the tab
    // PageView itself (depth 0) speaks for the tabs; the rest must be
    // ignored or they re-run this shell's build mid-swipe.
    if (notification.metrics.axis == Axis.horizontal &&
        notification.depth != 0) {
      return false;
    }
    if (notification.metrics.axis == Axis.horizontal &&
        notification is ScrollEndNotification) {
      final settled = _pageCtrl.page?.round() ?? _currentIndex;
      if (settled != _dragLockIndex) {
        setState(() => _dragLockIndex = settled);
      }
    }

    if (!_scrollHideEnabled) return false;
    // Vertical feed scroll only. A horizontal swipe (the tab pager at
    // pixels = N * screenWidth, the Group Wall pager) used to flip the bar
    // to compact mid-swipe, rebuilding the whole shell under the finger —
    // the wall stuttered and settled half-way ("smudged").
    if (notification.metrics.axis != Axis.vertical) return false;
    // Compact state is a pure function of scroll offset — only setState
    // when the derived boolean actually flips, not on every scroll tick.
    final shouldCompact = notification.metrics.pixels > 40;
    if (shouldCompact != _compact) {
      setState(() => _compact = shouldCompact);
    }
    return false;
  }

  /// Used to push a mock PingViewSheet here — a name+colour overlay with
  /// no real ping id, no DB read, and camera buttons that were SnackBar
  /// stubs. Replaced with a real deep link: switch to the Ping tab (the
  /// only surface with a real ping, camera and group wall — see
  /// ping_page.dart) and hand it the tapped ping's id via [pingFocusRequest],
  /// a top-level ValueNotifier rather than a constructor param because
  /// PingScreen sits in the IndexedStack below and is built once at launch,
  /// with no rebuild to carry a new value through. [PingPage] consumes it
  /// and expands that ping's card once its data has loaded. `notif.pingId`
  /// is null for the local/ephemeral fire* nudges (no server row to parse
  /// an id from) — [pingFocusRequest] is simply left untouched then, and
  /// the tab switch alone matches the old sheet's own fallback.
  /// Entity-level deep link for a reaction/comment/moment notification —
  /// pushes the post itself, on top of whatever tab is currently showing,
  /// same as tapping that post from a feed or a profile grid would.
  ///
  /// Fetched fresh rather than reused from wherever the notification came
  /// from, because nothing about a notification row carries a full
  /// FeedItem — only a bare post_id (notifications.post_id). A null result
  /// means the post is gone (deleted; the FK is ON DELETE SET NULL) or the
  /// fetch failed, and the fallback is the feed tab plus a plain toast —
  /// never a silent no-op tap, and never a detail screen with nothing in
  /// it.
  Future<void> _onOpenPost(String postId) async {
    final item = await FeedService.instance.fetchPostById(postId);
    final nav = appNavigatorKey.currentState;
    if (item == null) {
      _jumpToTab(0);
      final ctx = nav?.overlay?.context;
      if (ctx != null && ctx.mounted) {
        showGlassToast(ctx, "That post isn't available anymore.");
      }
      return;
    }
    nav?.push(MaterialPageRoute<void>(
      builder: (_) => SinglePostDetailScreen(item: item),
    ));
  }

  void _onOpenPingNotif(AppNotif notif) {
    _jumpToTab(1);
    if (notif.pingId != null) {
      pingFocusRequest.value = notif.pingId;
    }
  }

  /// Every programmatic tab switch (notification taps, deep links) goes
  /// through here rather than a bare `setState(() => _currentIndex = i)` —
  /// BUG FIX (explicit report — "the tab bar suddenly disappears in
  /// Profile"): `immersiveChrome` is a screen-owned flag (Ping's reply-
  /// photo viewer is the one real setter today — see ping_page.dart's
  /// _openPhoto/_closePhoto) meant to hide the bar only for as long as
  /// that overlay is on screen. Every tab is kept alive in the PageView
  /// below (never disposed on switch), so jumping away mid-photo — via a
  /// notification tap, not just a swipe — skipped `_closePhoto()`
  /// entirely and left the flag stuck at `true` forever, hiding the bar on
  /// every screen after, Profile included. A tab switch is exactly the
  /// boundary past which no page's immersive claim should still apply.
  void _jumpToTab(int index) {
    immersiveChrome.value = false;
    pingTabActive.value = index == 1;
    setState(() => _currentIndex = index);
    // The tabs are a PageView now: setting _currentIndex alone only lit up
    // the nav icon and left the old page on screen — every notification
    // deep link "switched tabs" without moving.
    if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(index);
  }

  /// [answeringPrompt] is set only when the camera was opened from a prompt
  /// bar's Respond action — it becomes the anon post's peek-bar text (see
  /// openCameraRoute). [answeringCommunityId]/[answeringPromptId] travel
  /// alongside it so the resulting post is attributed to the community
  /// whose rotating prompt was answered. Plain camera taps pass nothing.
  void _openComposer([
    String? answeringPrompt,
    String? answeringCommunityId,
    String? answeringPromptId,
  ]) {
    // Guarded: the camera button is the one bottom-bar control that pushes
    // a route, and a fast double tap stacked two composers.
    NavGuard.push(context, openCameraRoute(
      isAnonymous: _isHomeAnonActive,
      answeringPrompt: answeringPrompt,
      answeringCommunityId: answeringCommunityId,
      answeringPromptId: answeringPromptId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final unreadHome = notifState.unreadHome;
    final unreadPings = notifState.unreadPings;
    final communityBadge = notifState.communityBadge;
    final totalUnread = notifState.totalUnread;

    // Anonymous keeps its original floating position (unchanged). Every
    // other page — Everyone/Friends, Ping, Community, Profile — sits flush
    // against the safe area instead, Instagram-style, with no extra
    // floating offset/lift.
    final showAnonTabBarPosition = _currentIndex == 0 && _isHomeAnonActive;
    // Anon tab always uses the plain (non-compact) offset — its peek strip
    // (AnonFeedScreenV2's own bottom Positioned) is anchored assuming this
    // exact fixed offset, not the compact one. _compact flips true whenever
    // ANY bubbled ScrollNotification.metrics.pixels exceeds 40, which
    // AnonFeedScreenV2's own vertical PageView triggers on the very first
    // swipe (page-2's pixel offset alone is already hundreds of px) — that
    // shrank the tab bar's offset by 8pt out from under the peek strip's
    // static reservation, closing the gap between them (reported as "no
    // space between task bar and peek prompt" after scrolling).
    final tabBarBottom = showAnonTabBarPosition
        ? bottomPad + kTabBarBottomOffset + kTabBarExtraLift
        : (bottomPad - _tabBarLowerOffset).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Tab content ──────────────────────────────────────────────
          // PageView, not IndexedStack — drives horizontal swipe between
          // tabs in bottom-nav order, synced with tap-to-jump below.
          // Outer drag is locked out only while sitting on Home (index 0,
          // whose OWN inner Anon↔Friends PageView needs the gesture instead
          // — see HomeScreen.onSwipePastFriends for how that still bridges
          // outward). Profile (index 3) used to be locked too, on the
          // rationale that its inner Posts/Moments/Groups/Tagged TabBarView
          // needed to stay independent — that TabBarView no longer exists
          // (MyProfileScreen/features/profile_v2 switches tabs via a plain
          // state enum, not a swipeable TabBarView; verified no PageView/
          // TabBarView/onHorizontalDrag anywhere in that screen), so the
          // lock had nothing left to protect and just made leaving Profile
          // by swipe (e.g. to Communities) silently do nothing. Ping/
          // Community/Profile (1/2/3) all have no inner horizontal gesture
          // now, so drag both ways.
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: PageView(
                controller: _pageCtrl,
                physics: _dragLockIndex == 0
                    ? const NeverScrollableScrollPhysics()
                    // Same eased physics the Home tab's inner pager uses,
                    // so Ping→Friends commits on a light swipe too — the
                    // other half of the reported "swiping left to right is
                    // difficult" between those two pages.
                    : const _EasyPageScrollPhysics(),
                onPageChanged: (i) => setState(() {
                  // See _jumpToTab's own doc — same leaked-immersive-flag
                  // fix, for the swipe/tap path rather than the
                  // notification-jump path.
                  immersiveChrome.value = false;
                  pingTabActive.value = i == 1;
                  _currentIndex = i;
                  _compact = false;
                }),
                children: _screens,
              ),
            ),
          ),

          // ── Anon score (top-right) — page-level entry point, shown on
          // the Ping/Community/Profile tabs only. On the Home tab it lives
          // INSIDE HomeScreen's own header instead (see _SlimHeader) — it
          // needs to collapse/reappear with that feed's own scroll-driven
          // chrome, which this MainShell-level overlay can't do since it
          // sits above HomeScreen and never sees its scroll position.
          //
          // The bell (notifications) icon and the '+' (reaction-preset-
          // manager) icon that used to sit alongside this — top-left and
          // top-right respectively — are REMOVED from here: both are now
          // Home-only (_SlimHeader's own copies), per explicit requirement
          // that neither appear on any other screen (Ping, Camera/
          // Composer, Community, Profile, Group Profile, Settings). No
          // layout adjustment needed beyond deleting them — these are
          // Positioned overlays in a Stack, not Row/Column siblings, so
          // removing them reserves no space to begin with; nothing shifts.
          // Suppressed on the Ping tab (index 1) — PingScreen now renders
          // its own header-level score display (see _PingHeader in
          // ping_screen.dart), so this floating badge would duplicate it.
          // Suppressed on the Community tab (index 2) for the same reason —
          // CommunityScreen's own header already shows a streak/rank badge
          // (see _CommunityHeader in community_screen.dart).
          // Suppressed on the Profile tab (index 3) for the same reason —
          // Profile v2 renders its own anon/ping score tiles, and this badge
          // landed on top of that screen's settings button. With every tab now
          // suppressed the badge never shows; it is left wired up rather than
          // deleted so re-enabling it on a future screen stays a one-line
          // change.
          if (_currentIndex != 0 &&
              _currentIndex != 1 &&
              _currentIndex != 2 &&
              _currentIndex != 3)
            Positioned(
              top: topPad + 8,
              right: 16,
              child: ValueListenableBuilder<int>(
                valueListenable: ViewerScoreService.instance.score,
                builder: (context, score, _) => _AnonScoreBadge(score: score),
              ),
            ),

          // ── Bottom nav — floating frosted-glass pill, centered ───────
          // Hidden entirely (opacity + slide-down + ignore-pointer) while
          // the Anon feed's comments sheet is open — that sheet is a Stack
          // child inside AnonFeedScreenV2's own tree, several layers below
          // this overlay, so it can never paint over the bar on its own;
          // this is the only way to keep it from floating on top of the
          // sheet. Reappears the instant _anonCommentsOpen flips back.
          // Split into a non-animated outer Positioned (tabBarBottom itself
          // — driven by _currentIndex/_isHomeAnonActive) and an inner
          // TweenAnimationBuilder that ONLY animates the comments-sheet dip
          // (-24). These used to be one value on a single AnimatedPositioned,
          // which meant EVERY change to tabBarBottom animated over the same
          // 340ms meant for the sheet dip — including the jump between
          // Anon's raised position and every other tab's flush-to-bottom
          // one. Swiping Anon<->Friends changes _isHomeAnonActive
          // gradually, in step with the drag, so the slide was masked;
          // landing on Home from Ping/Community/Profile changes
          // _currentIndex in one discrete frame, so the bar visibly
          // climbed up through the peek strip for that same 340ms instead
          // of already being in its raised position — reported live as
          // "tab bar overlapped over the peek prompt" specifically on that
          // return path. tabBarBottom itself now snaps instantly; only the
          // sheet-open dip still eases.
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarBottom,
            // `immersiveChrome` is raised by screens that must own the whole
            // display (the reply-photo viewer). Folded into the same
            // hide/ignore pair the anon-comments sheet already uses.
            child: ValueListenableBuilder<bool>(
              valueListenable: immersiveChrome,
              builder: (context, immersive, child) {
                // BUG FIX ("the task bar is also over the comment [box]"):
                // _anonCommentsOpen only covers the Anon feed's own comments
                // SHEET. A friends-feed comment field is a plain inline
                // TextField inside the card, not a sheet — nothing ever
                // told this bar about it, so typing a comment there left
                // the floating nav sitting on top of the keyboard the
                // whole time. Generalising to "is the keyboard actually up"
                // covers every inline comment field anywhere in the app,
                // present or future, with no per-screen wiring required —
                // and can't misfire, since the tab bar has no reason to be
                // visible while typing regardless of what opened the
                // keyboard.
                // Read from the platform View, NOT MediaQuery: this builder
                // sits inside MainShell's own Scaffold body, and a Scaffold
                // with resizeToAvoidBottomInset (the default) REMOVES
                // viewInsets.bottom from the MediaQuery it hands its body.
                // So the MediaQuery reading here was always 0 and the bar
                // never actually hid — reported again as the task bar
                // covering the ping reply composer. View.of comes straight
                // from the engine in physical pixels, untouched by any
                // Scaffold above or below.
                final keyboardOpen = View.of(context).viewInsets.bottom > 0;
                final hidden = _anonCommentsOpen || immersive || keyboardOpen;
                return IgnorePointer(
                  ignoring: hidden,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    opacity: hidden ? 0 : 1,
                    child: child,
                  ),
                );
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _anonCommentsOpen ? 24 : 0),
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 340),
                curve: const Cubic(0.4, 0.14, 0.3, 1.0),
                builder: (context, dip, child) => Transform.translate(
                  offset: Offset(0, dip),
                  child: child,
                ),
                child: Center(
                  child: _BottomNav(
                    currentIndex: _currentIndex,
                    compact: _compact,
                    unreadHome: unreadHome,
                    unreadPings: unreadPings,
                    communityBadge: communityBadge,
                    totalUnread: totalUnread,
                    onTabSelected: (i) {
                      HapticFeedback.lightImpact();
                      // Immediate, not just left to onPageChanged: tapping
                      // the ALREADY-active tab is a no-op for animateToPage
                      // (no page change fires), but should still reset
                      // compact, same as before this PageView migration.
                      setState(() => _compact = false);
                      _pageCtrl.animateToPage(
                        i,
                        duration: _pageDuration,
                        curve: _pageCurve,
                      );
                    },
                    onComposerOpen: _openComposer,
                  ),
                ),
              ),
            ),
          ),

          // ── Glass notification — right side, above bottom nav ────────
          GlassNotifOverlay(bottomOffset: tabBarBottom + kTabBarHeight + 12),

          // ── Notification banner — drops down from the top ────────────
          if (_lastBannerNotif != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SlideTransition(
                position: _bannerSlide,
                child: NotifBanner(
                  notif: _lastBannerNotif!,
                  onDismiss: notifState.dismissBanner,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating frosted-glass pill — 5 tabs (Home, Ping, Camera, Community,
// Profile). Camera is a fixed 44x44 circle, never part of the tab index —
// tapping it opens the composer, same as before.
// ---------------------------------------------------------------------------

List<double> _saturationMatrix(double s) {
  const lumR = 0.213, lumG = 0.715, lumB = 0.072;
  return <double>[
    lumR + (1 - lumR) * s,
    lumG - lumG * s,
    lumB - lumB * s,
    0,
    0,
    lumR - lumR * s,
    lumG + (1 - lumG) * s,
    lumB - lumB * s,
    0,
    0,
    lumR - lumR * s,
    lumG - lumG * s,
    lumB + (1 - lumB) * s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.compact,
    required this.unreadHome,
    required this.unreadPings,
    required this.communityBadge,
    required this.totalUnread,
    required this.onTabSelected,
    required this.onComposerOpen,
  });

  final int currentIndex;
  final bool compact;
  final int unreadHome;
  final int unreadPings;
  final bool communityBadge;
  final int totalUnread;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onComposerOpen;

  static const double _widthResting = 286.0;
  static const double _widthCompact = 246.0;
  static const double _heightResting = 56.0;
  static const double _heightCompact = 48.0;
  static const EdgeInsets _paddingResting = EdgeInsets.fromLTRB(8, 5, 8, 5);
  static const EdgeInsets _paddingCompact = EdgeInsets.fromLTRB(7, 4, 7, 4);
  static const double _iconSizeResting = 22.0;
  static const double _iconSizeCompact = 20.0;
  static const Curve _curve = Cubic(0.4, 0.14, 0.3, 1.0);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 340);
    final width = compact ? _widthCompact : _widthResting;
    final height = compact ? _heightCompact : _heightResting;
    final padding = compact ? _paddingCompact : _paddingResting;
    final iconSize = compact ? _iconSizeCompact : _iconSizeResting;
    const radius = 999.0;

    return AnimatedContainer(
      duration: duration,
      curve: _curve,
      width: width,
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.55),
            blurRadius: 44,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ColorFilter.matrix(_saturationMatrix(1.7)),
            inner: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          ),
          child: AnimatedContainer(
            duration: duration,
            curve: _curve,
            padding: padding,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(24, 22, 20, 0.55),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.10),
                width: 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.home,
                        isActive: currentIndex == 0,
                        iconSize: iconSize,
                        // No count on Home (explicit request, 2026-10-03:
                        // "no need of showing 9+ on home screen") — the
                        // feed is a place you browse, not a queue to clear.
                        // unreadHome is still computed and still drives the
                        // inbox's own count.
                        badge: 0,
                        onTap: () => onTabSelected(0),
                      ),
                    ),
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.ping,
                        isActive: currentIndex == 1,
                        iconSize: iconSize,
                        badge: unreadPings,
                        onTap: () => onTabSelected(1),
                      ),
                    ),
                    // Placeholder — preserves the camera's horizontal
                    // space in the flex layout; the real camera circle is
                    // rendered as an overlaid Stack child below so it can
                    // stay a true fixed 44x44 regardless of bar height.
                    const SizedBox(width: 44),
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.community,
                        isActive: currentIndex == 2,
                        iconSize: iconSize,
                        // No red dot on Community — explicit request.
                        // communityBadge stays plumbed through, unused.
                        onTap: () => onTabSelected(2),
                      ),
                    ),
                    Expanded(
                      child: _NavTab(
                        glyph: TabGlyph.profile,
                        isActive: currentIndex == 3,
                        iconSize: iconSize,
                        badge: totalUnread,
                        onTap: () => onTabSelected(3),
                      ),
                    ),
                  ],
                ),
                _CameraTab(iconSize: iconSize, onTap: onComposerOpen),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A single flex tab — Home / Ping / Community / Profile
// ---------------------------------------------------------------------------

class _NavTab extends StatefulWidget {
  const _NavTab({
    required this.glyph,
    required this.isActive,
    required this.iconSize,
    required this.onTap,
    this.badge = 0,
    this.hasDot = false,
  });

  final TabGlyph glyph;
  final bool isActive;
  final double iconSize;
  final VoidCallback onTap;
  final int badge;
  final bool hasDot;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _pressed = false;

  static const _pressDuration = Duration(milliseconds: 220);
  static const _activeColor = Colors.white;
  static const _restingColor = Color.fromRGBO(255, 255, 255, 0.45);
  static const _activeBg = Color.fromRGBO(255, 255, 255, 0.13);

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Ping always stays outline — it never fills, even when active.
    final fillable = widget.glyph != TabGlyph.ping;
    final color = widget.isActive ? _activeColor : _restingColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: _pressDuration,
        curve: Curves.ease,
        child: AnimatedContainer(
          duration: _pressDuration,
          curve: Curves.ease,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isActive ? _activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: widget.iconSize,
                  end: widget.iconSize,
                ),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 340),
                curve: const Cubic(0.4, 0.14, 0.3, 1.0),
                builder: (context, size, _) => TabBarIcon(
                  glyph: widget.glyph,
                  size: size,
                  color: color,
                  filled: fillable && widget.isActive,
                ),
              ),
              if (widget.badge > 0)
                Positioned(
                  right: -8,
                  top: -6,
                  child: _NavBadge(count: widget.badge),
                ),
              if (widget.hasDot && widget.badge == 0)
                Positioned(
                  right: -5,
                  top: -4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3B30),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera tab — fixed 44x44 circle, level with the other tabs, own glass
// surface + feathered halo shadow. Icon always outline, always white.
// ---------------------------------------------------------------------------

class _CameraTab extends StatefulWidget {
  const _CameraTab({required this.iconSize, required this.onTap});

  final double iconSize;
  final VoidCallback onTap;

  @override
  State<_CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<_CameraTab> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.ease,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(18, 17, 16, 0.32),
                spreadRadius: 5,
              ),
              BoxShadow(
                color: Color.fromRGBO(18, 17, 16, 0.28),
                blurRadius: 14,
                spreadRadius: 8,
              ),
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.4),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.compose(
                outer: ColorFilter.matrix(_saturationMatrix(1.8)),
                inner: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color.fromRGBO(255, 255, 255, 0.18),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.2),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: widget.iconSize,
                        end: widget.iconSize,
                      ),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 340),
                      curve: const Cubic(0.4, 0.14, 0.3, 1.0),
                      builder: (context, size, _) => TabBarIcon(
                        glyph: TabGlyph.camera,
                        size: size,
                        color: Colors.white,
                        filled: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anon score badge — the viewing user's OWN score/tier, a compact dark
// glass pill matching the bell icon's own visual language. Deliberately
// lighter-weight than the per-post ScoreGlowRing treatment (see
// shared/score_tier.dart) — a full glow ring next to a 36px bell would
// overwhelm this small a header slot, so tier is communicated via the
// star glyph + number color instead.
// ---------------------------------------------------------------------------

class _AnonScoreBadge extends StatelessWidget {
  const _AnonScoreBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(score);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 14, color: info.color),
          const SizedBox(width: 5),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: info.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small red badge
// ---------------------------------------------------------------------------

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}


/// Page physics that commit a tab change on a short swipe.
///
/// [PageScrollPhysics] only turns the page past the halfway point, or on a
/// release velocity above its own tolerance — neither of which a brief,
/// gentle drag reaches, so the page sprang back and the swipe read as
/// ignored. Mirrors HomeScreen's own _SlightSwipePageScrollPhysics; the two
/// pagers are stacked, so they have to feel the same or the handoff between
/// them feels broken.
class _EasyPageScrollPhysics extends PageScrollPhysics
    with SlightSwipeSettle {
  const _EasyPageScrollPhysics({super.parent});

  @override
  _EasyPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _EasyPageScrollPhysics(parent: buildParent(ancestor));

  @override
  double get minFlingVelocity => 8; // default 50
  @override
  double get minFlingDistance => 2; // default 18

}
