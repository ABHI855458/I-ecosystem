import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_video.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestEntry, BoxHitTestResult, RenderStack;
import 'package:flutter/services.dart';

import '../../../core/glass.dart' show showGlassToast;
import '../../../services/reaction_service.dart';
import '../../moderation/post_actions_menu.dart';
import '../../../features/ping/ping_prompt_sheet.dart'
    show showPingPromptSheet, PingContext;
import '../../../main_shell.dart' show kTabBarHeight, tabBarBottomFor;
import 'package:shimmer/shimmer.dart';

import '../../../screens/feed/widgets/face_reaction_capture.dart';
import '../../../screens/feed/widgets/realmoji_tray.dart' show RealmojiTray;
import '../../../services/comment_service.dart';
import '../../../services/content_moderation_service.dart';
import '../../../services/daily_prompt_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/ping_service.dart';
import '../../../services/post_service.dart';
import '../../../services/reaction_preset_service.dart'
    show ReactionPreset, ReactionPresetCategory, ReactionPresetCategoryWire;
import '../../../services/realmoji_service.dart';
import '../../../shared/time_ago.dart';
import '../../../shared/widgets/avatar_peek.dart';
import '../../../screens/feed/widgets/dual_photo_view.dart';
import 'anon_feed_icons.dart';
import 'anon_feed_models.dart';
import 'anon_feed_tokens.dart';
import 'anon_frame_clipper.dart';

// ---------------------------------------------------------------------------
// Post-card design-canvas size — the single source of truth for how tall
// one anon post card's frame is, shared between _AnonPostCard (which draws
// the frame) and the outer LayoutBuilder in _AnonSnapSection (which has to
// reserve exactly that much room for it). Both used to carry their own
// copy of "468.809" / a bare literal "704" respectively — fine as long as
// nobody ever changed one without the other, which is exactly what broke:
// explicit request to grow the card's length surfaced that the "704"s
// scattered through the layout math were never actually tied to
// _AnonPostCard's own _designH, just historically equal to it.
//
// _kAnonCardDesignH: 468.809 was the design spec's original figure (the
// asset was rendered as a strict 4:5 rectangle against `kCardDesignWidth`
// = 375.047). +10% here per explicit request ("increase the length of the
// post card") — width is deliberately left untouched, so the card is no
// longer 4:5, it's taller. AnonCardFrameClipper's corner radii and
// dip/tray notch already auto-scale off whatever height they're given
// (its own internal `s = sqrt(height/h1)`), so growing this one constant
// is what "increase... the dip and curve edges as such as we increase the
// length" asks for — no separate corner/notch tuning needed.
const double _kAnonCardDesignH = 468.809 * 1.10;
// The fixed zoom _AnonPostCard applies on top of the design canvas (see
// its own `_cardScale`) — unrelated to per-device `scale`, unchanged.
const double _kAnonCardZoom = 1.5;
// What used to be the bare literal "704" — the card's rendered height at
// zoom, before the outer per-device `scale` multiplies it again. Deriving
// it from the two constants above means a future height tweak can't
// desync the layout math (slackForCard, grownScale, the debug metrics
// line) from what the card actually renders at.
const double _kAnonCardOuterH = _kAnonCardDesignH * _kAnonCardZoom;

/// Height a page keeps clear at its bottom for the floating tab bar: the
/// bar's own bottom offset (MainShell's tabBarBottomFor), its height, and a
/// 12pt gap above it. Was `56 + safe-area + 12` on top of a separate
/// safe-area + 24 strip for the bottom peek prompt; with the prompt gone
/// and the bar lowered, the difference goes to the post card.
double _tabBarReserve(BuildContext context) =>
    tabBarBottomFor(MediaQuery.paddingOf(context).bottom) + kTabBarHeight + 12;

// ---------------------------------------------------------------------------
// AnonFeedScreenV2 — full implementation of the Anon feed spec (§3–§13).
// Per explicit confirmation: §9.2's floating tab bar is NOT built here —
// this screen's tab bar is MainShell's existing one; this file owns only
// the feed content, from the header through the peek panel, plus the 3
// overlay sheets (§10–§12).
//
// Mirrors §14.3's Component state shape directly: `_idx` (current page),
// `_open` (per-post popover key: 'viewers' | 'reactions', at most one post
// at a time), `_mode` (Anon/Friends toggle), `_commentsOpen`/
// `_promptPickerOpen`/`_menuOpen` (sheet visibility), `_picked` (per-post
// selected saved real-moji), `_pingPick` (selected ping prompt index).
// ---------------------------------------------------------------------------

class AnonFeedScreenV2 extends StatefulWidget {
  const AnonFeedScreenV2({
    super.key,
    this.topInset = 0,
    this.onSwitchToFriends,
    this.onCommentsOpenChanged,
    this.onActiveAuthorScoreChanged,
    this.onOpenCamera,
  });

  /// Reserved space for HomeScreen's floating header overlay, same role as
  /// AnonymousTab.topInset in the existing implementation.
  final double topInset;

  /// Tapping "Friends" in this screen's own §4.1 toggle chip fires this —
  /// it's a real navigation request (switch HomeScreen's PageView to the
  /// Everyone/Friends sub-page), not local UI state. This screen is always
  /// the Anon side; there's no local "Friends mode" to render here, only a
  /// request to LEAVE. Null when run standalone (e.g. the debug harness),
  /// in which case the chip is inert.
  final VoidCallback? onSwitchToFriends;

  /// Fired with true/false as the comments sheet (_AnonCommentsSheet) opens
  /// and closes — MainShell hides its floating tab bar while true, since
  /// the sheet is rendered as a Stack child WITHIN this screen (not a
  /// modal route), so it can never paint over MainShell's own tab bar
  /// overlay, which lives several widget layers above this screen's own
  /// tree. Null when run standalone, in which case the tab bar (if any)
  /// just doesn't react.
  final ValueChanged<bool>? onCommentsOpenChanged;

  /// The combined score of the AUTHOR of whichever post is on screen.
  ///
  /// The badge above this feed showed the VIEWER's own score on every post,
  /// which says nothing about the post being looked at. HomeScreen owns
  /// that badge (it floats above this screen in the shell's Stack), so the
  /// score has to travel up rather than be drawn here. Identity-free — see
  /// AnonFeedPost.authorScore.
  final ValueChanged<int>? onActiveAuthorScoreChanged;

  /// Tapping the prompt bar (§4.2 — the daily-prompt pill at the top of the
  /// header) opens the camera, same entry point as MainShell's own
  /// "Respond" action (HomeScreen._openCamera). Null when run standalone,
  /// in which case the bar is inert.
  final void Function([
    String? answeringPrompt,
    String? answeringCommunityId,
    String? answeringPromptId,
  ])?
  onOpenCamera;

  @override
  State<AnonFeedScreenV2> createState() => _AnonFeedScreenV2State();
}

class _AnonFeedScreenV2State extends State<AnonFeedScreenV2> {
  late final PageController _pageCtrl;
  int _idx = 0;

  /// Anon Score view-crediting (+5 to the author, server-deduped — see
  /// PostService.recordView). Tracked client-side too, just to avoid
  /// re-firing the RPC every time a swipe lands back on an already-seen
  /// post in this same session; the server-side dedupe is what actually
  /// enforces "once per viewer per post" for real.
  final Set<String> _viewedPostIds = {};
  bool _recordedInitialView = false;

  void _recordView(String? postId) {
    if (postId == null || _viewedPostIds.contains(postId)) return;
    _viewedPostIds.add(postId);
    unawaited(PostService.instance.recordView(postId));
  }

  /// At most one entry — {postIndex: 'viewers'|'reactions'|'menu'} — mutual
  /// exclusion across the WHOLE feed per §13.3 rule 1.
  MapEntry<int, String>? _open;

  /// The viewer's own saved RealMoji reaction per post, keyed by REAL post
  /// id (`post_realmoji_reactions.post_id`) rather than list index — an
  /// index shifts every time a page appends or the feed re-sorts, which
  /// silently moved a reaction onto a different post. Seeded from the
  /// server on load (see _hydrateCounts) so a reaction survives a restart,
  /// and written through by _selectRealmoji/_captureRealmoji. Value is the
  /// reacted RealmojiType's glyph (not the enum) — every existing render
  /// site downstream (_TrayIcons' pickedMoji, _RealmojiChip highlighting)
  /// already expects a plain emoji string.
  final Map<String, String> _pickedMoji = {}; // posts.id -> emoji glyph

  /// Per-post uploading flag for the capture-and-react flow (no saved
  /// selfie yet for the tapped RealmojiType) — mirrors
  /// PostReactions.uploadingFaceReaction, just keyed by post id since this
  /// screen has many posts in flight, not one card's own State.
  final Set<String> _uploadingRealmoji = {};

  /// The real, identity-free reaction breakdown for the ANON feed's
  /// on-photo stack (see _OnPhotoReactionStack) — emoji + count pairs from
  /// `anon_reaction_counts` (RealmojiService.fetchAnonCounts), never a
  /// per-reactor list. Replaces the old kAnonReactionStack fixture, which
  /// rendered the exact same fake three emoji on every single post
  /// regardless of what anyone had actually reacted with.
  final Map<String, List<AnonRealmojiCount>> _reactionBreakdown = {};

  /// The reactors' actual RealMoji PHOTOS per post, identity-free
  /// (RealmojiService.fetchAnonReactionFaces). Feeds the on-photo stack so
  /// a reaction reads as the face someone pulled rather than a generic
  /// emoji in a white disc — "after reacting the emoji shall also appear
  /// as 1A".
  final Map<String, List<AnonReactionFace>> _reactionFaces = {};

  /// The top viewers' faces per post — identity-free (see
  /// RealmojiService.fetchAnonPostSeenFaces's own doc for the trust
  /// boundary: only a viewer's OWN chosen anon-scope RealMoji selfie, never
  /// their real profile photo or id). Feeds _StackedViewerDots so the seen
  /// chip shows real faces where they exist instead of always the 3 fixed
  /// decorative dots — screenshot report: "attach real dp of the people
  /// there, top 3 if not 2".
  final Map<String, List<String>> _seenFaces = {};

  /// The real "seen by" list per post id — `post_viewers` RPC, pinned
  /// people first. Loaded lazily when the chip is tapped rather than for
  /// every post on load: it's one round trip per post and nobody opens it
  /// on most of them. Null = never requested / still in flight, which is
  /// what the popover renders as a loading state rather than "nobody".
  final Map<String, List<PostViewer>> _viewers = {};
  final Set<String> _viewersLoading = {};

  Future<void> _loadViewers(String postId) async {
    if (_viewers.containsKey(postId) || _viewersLoading.contains(postId))
      return;
    _viewersLoading.add(postId);
    try {
      final people = await PostService.instance.fetchPostViewers(postId);
      if (!mounted) return;
      setState(() => _viewers[postId] = people);
    } finally {
      _viewersLoading.remove(postId);
    }
  }

  // The lazy per-post breakdown loader that used to sit here is gone with
  // the popover it fed: the reaction-view button opens the comments sheet
  // now (see onToggleBreakdown), and _hydrateCounts already fills
  // _reactionBreakdown for the on-photo stack. _ReactionBreakdownPopover
  // itself is left in place, unreachable, rather than ripped out.

  bool _commentsOpen = false;
  bool _promptPickerOpen = false;
  int? _pingPick;

  // ── Prompt bar rotation ─────────────────────────────────────────────────
  // Shared with the friends feed's own prompt bar (home_screen.dart) via
  // PromptBarController — one implementation of the cycling/impression/
  // response-count bookkeeping instead of two copies that could drift.
  // See that class's own doc for the full behavior (ranked list from
  // prompt_bar_for_user, cycled 5s, refreshed on a window change).
  late final PromptBarController _promptBar;

  DailyPrompt? get _activePrompt => _promptBar.active;
  Map<String, int> get _promptResponseCounts => _promptBar.responseCounts;

  void _onPromptBarChanged() {
    if (mounted) setState(() {});
  }

  // ── Real paginated feed data ──────────────────────────────────────────
  // Replaces the hardcoded kAnonFeed const list this screen used to render
  // directly. kAnonFeed is no longer rendered anywhere — this feed shows
  // real posts or an honest empty/error state, never demo content (see
  // _posts' getter below).
  //
  // Backed by FeedService.fetchAnonFeed, which applies BOTH anon feed
  // rules server/client-side before these ever arrive: the 24-hour
  // visibility window, and the "already reacted -> never show again"
  // exclusion. This screen therefore needs no filtering logic of its own.
  final List<AnonFeedPost> _remote = [];
  static const _pageSize = 20;
  int _offset = 0;
  bool _loadingMore = false;
  bool _reachedEnd = false;

  /// True until the FIRST page fetch has resolved (success, empty, or
  /// failure — any of the three counts as "resolved"). BUG FIX: `build()`
  /// used to fall straight to `posts.isEmpty ? ... : _AnonEmptyState()`
  /// with no notion of "haven't heard back yet" — `_remote` is genuinely
  /// `[]` and `_loadFailed` is genuinely `false` for the several hundred ms
  /// between initState's `_loadMore()` call and its first real response, so
  /// "You're all caught up" flashed on every cold open regardless of
  /// whether any posts actually existed, before the fetch had a chance to
  /// return them. Reported live: the anon tab showed the terminal
  /// no-more-posts message on open even when unseen posts existed.
  bool _firstLoadPending = true;

  /// Set when a page fetch THREW (as opposed to legitimately returning no
  /// rows). Kept separate from [_reachedEnd] on purpose: conflating the two
  /// is exactly what made a transient failure look like the end of the
  /// feed. On error we stop advancing but keep every page already loaded,
  /// and — critically — do NOT fall through to the empty state, which would
  /// blank a feed that had simply failed to load its FIRST page.
  bool _loadFailed = false;

  /// Set once the one-shot retry for an empty first page has been spent — see
  /// _loadMore. Reset by pull-to-refresh.
  bool _emptyRetryDone = false;

  /// What the PageView actually renders.
  ///   * real posts, once any page has loaded — KEPT even after a later
  ///     page fails, so a mid-pagination failure never wipes what's
  ///     already on screen; it just stops advancing
  ///   * empty otherwise — whether the first page genuinely returned
  ///     nothing or actually failed, told apart by [_loadFailed], which
  ///     build() uses to render a retryable error rather than the plain
  ///     "nothing here" state.
  ///
  /// There is NO demo fallback. Showing fabricated posts as if they were
  /// real content is worse than an honest empty screen — there is no way
  /// for the viewer to tell the difference, and a sparse-but-working feed
  /// looked identical to a broken one.
  List<AnonFeedPost> get _posts => _remote;

  /// Fires whenever the viewer posts (PostService.addPost). See
  /// [_onOwnPostSaved].
  StreamSubscription<List<LocalPost>>? _ownPostSub;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _loadMore();
    _promptBar = PromptBarController(feedScope: 'anon')
      ..addListener(_onPromptBarChanged);
    unawaited(_promptBar.load());
    // "After posting, the user shall see their post in the feed." The
    // composer is pushed from MainShell and this screen is never popped or
    // rebuilt when it returns, so without this a just-posted anon photo
    // only appeared after a manual scroll to the end or an app restart.
    _ownPostSub = PostService.instance.anonFeedStream.listen(
      (_) => _onOwnPostSaved(),
    );
  }

  /// Reloads the newest page so the viewer's own just-posted photo appears
  /// at the top.
  ///
  /// PostService emits this stream TWICE per post — once optimistically
  /// before the insert, once after it commits (see PostService.addPost).
  /// Refetching on both is deliberate and cheap: the first pass may miss
  /// the row (it isn't written yet), the second always finds it. That is
  /// exactly why the reload is a real query rather than trusting the
  /// LocalPost in the event — the feed renders `posts_feed` rows, and a
  /// local one carries a device file path, not the uploaded photo's URL.
  Future<void> _onOwnPostSaved() async {
    if (!mounted) return;
    try {
      final rows = await FeedService.instance.fetchAnonFeed(
        limit: _pageSize,
        offset: 0,
        excludeReacted: false,
        throwOnError: true,
      );
      if (!mounted || rows.isEmpty) return;
      final fresh = [
        for (final r in rows.map(AnonFeedPost.fromRow))
          if (r.id != null && !_remote.any((p) => p.id == r.id)) r,
      ];
      if (fresh.isEmpty) return;
      setState(() {
        _remote.insertAll(0, fresh);
        // The window slid: the next page must resume past what's now
        // loaded, or the row shifted out of range 0 comes back twice.
        _offset += fresh.length;
        // New content exists, so a previously-exhausted feed isn't
        // exhausted any more.
        _reachedEnd = false;
        _loadFailed = false;
      });
      // Jump to the new post rather than leaving the viewer wherever they
      // were — they just posted; this is the thing they want to see.
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      unawaited(_hydrateCounts(fresh));
    } catch (e, st) {
      debugPrint('[AnonFeed._onOwnPostSaved] reload failed: $e\n$st');
    }
  }

  /// Pull-to-refresh. Drops every loaded page and re-fetches from offset
  /// 0 rather than prepending, so the shuffle in [_loadMore] genuinely
  /// re-deals the feed — half the point of pulling down on a feed whose
  /// posts stay in it for 24h is to see it in a different order.
  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _remote.clear();
      _offset = 0;
      _reachedEnd = false;
      _loadFailed = false;
      _emptyRetryDone = false;
      _recordedInitialView = false;
      _open = null;
    });
    _loadingMore = false;
    await _loadMore();
    if (!mounted) return;
    if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    setState(() => _idx = 0);
    unawaited(_promptBar.load());
  }

  /// Infinite scroll: fetches the next page and appends. Called once on
  /// init and again from onPageChanged as the user nears the end.
  ///
  /// Note the page may come back SHORTER than _pageSize even when more
  /// posts exist, because the already-reacted filter drops rows after the
  /// range query (see FeedService.fetchAnonFeed's own doc). So "end of
  /// feed" is only concluded when a page comes back completely EMPTY —
  /// treating a short page as the end would truncate the feed early for
  /// anyone with a lot of reactions.
  /// The Dip feed always shows at least [_minDistinctPosts] different
  /// photos. When the fresh window has fewer (e.g. one new Dip today), older
  /// Dips from fetchAnonFallback top it up, so the infinite-scroll lap never
  /// loops a single photo over and over.
  static const _minDistinctPosts = 3;

  Future<void> _ensureMinimumPosts() async {
    final have = _remote.map((p) => p.id).toSet();
    if (have.length >= _minDistinctPosts) return;
    final older = await FeedService.instance.fetchAnonFallback(
      limit: _pageSize,
    );
    if (!mounted) return;
    final extra =
        older.map(AnonFeedPost.fromRow).where((p) => have.add(p.id)).toList()
          ..shuffle();
    if (extra.isEmpty) return;
    setState(() {
      _reachedEnd = false;
      _remote.addAll(extra);
    });
    unawaited(_hydrateCounts(extra));
    if (!_recordedInitialView) {
      _recordedInitialView = true;
      _recordView(extra.first.id);
      widget.onActiveAuthorScoreChanged?.call(extra.first.authorScore);
    }
  }

  Future<void> _loadMore() async {
    // _loadFailed also gates here: after a failure we stop ADVANCING rather
    // than retrying on every single page change (which would hammer a
    // broken query once per swipe). _retry() clears it for a deliberate
    // retry.
    if (_loadingMore || _reachedEnd || _loadFailed) return;
    _loadingMore = true;
    try {
      // throwOnError: distinguishes a real failure from an empty page —
      // without it a thrown query comes back as [] and gets misread as
      // "end of feed" (see fetchAnonFeed's own doc).
      final rows = await FeedService.instance.fetchAnonFeed(
        limit: _pageSize,
        offset: _offset,
        // "The reacted posts shall never appear to them again."
        //
        // This was false, for a real reason worth preserving: reactions
        // persist (see _selectRealmoji/_captureRealmoji), and excluding
        // reacted posts used to yank the post you had JUST reacted to
        // out from under you on the next load, so you could never see
        // your own saved reaction.
        //
        // That still holds — but it is about the CURRENT session, not
        // about future loads. A post already in _remote is never
        // re-fetched or removed while you are looking at it; this flag
        // only governs what comes back in NEW pages. So the card you
        // just reacted to stays put, and the post simply never returns
        // later — including through the resurfacing window, which is
        // the case that prompted this.
        excludeReacted: true,
        throwOnError: true,
      );
      if (!mounted) return;
      // Never empty: nothing fresh left AND nothing on screen means the
      // viewer would get the "all caught up" state. Fall back to older Dips
      // instead (see FeedService.fetchAnonFallback). The lap logic below
      // then keeps reshuffling them.
      if (rows.isEmpty && _remote.isEmpty) {
        final older = await FeedService.instance.fetchAnonFallback(
          limit: _pageSize,
          throwOnError: true,
        );
        if (!mounted) return;
        if (older.isNotEmpty) {
          final added = older.map(AnonFeedPost.fromRow).toList()..shuffle();
          setState(() {
            _loadFailed = false;
            _remote.addAll(added);
          });
          unawaited(_hydrateCounts(added));
          if (!_recordedInitialView) {
            _recordedInitialView = true;
            _recordView(added.first.id);
            widget.onActiveAuthorScoreChanged?.call(added.first.authorScore);
          }
          return;
        }
      }
      setState(() {
        _loadFailed = false;
        if (rows.isEmpty) {
          // End of the real rows. INFINITE SCROLL: instead of stopping
          // dead, lap back to the start and re-deal what's already loaded
          // — "make anon feed infinite scroll using the same posts; if
          // they have seen everything, reshuffle it again and show them".
          //
          // The window is 24h and typically a handful of posts, so a hard
          // stop after one pass left the feed feeling empty within a
          // minute. A lap appends a fresh shuffle of the same rows rather
          // than re-querying: nothing new exists to fetch, and re-querying
          // offset 0 would return them in the same chronological order
          // every time.
          //
          // A post appearing twice in _remote is fine: the PageView builds
          // by index, and every per-post map here (_pickedMoji,
          // _reactionFaces, _reactionBreakdown, _viewers) is keyed by post
          // id, so both copies share one reaction/comment state rather
          // than drifting apart.
          if (_remote.isNotEmpty) {
            // (Restored 2026-10-07. This lap was removed for a day on a
            // misread of "remove the open loops" — that meant the Ping
            // page's OPEN LOOPS section, not this.)
            final lap = List<AnonFeedPost>.from(_remote)..shuffle();
            _remote.addAll(lap);
            // Back to the top of the real rows, so the NEXT genuine fetch
            // picks up anything posted since rather than staying parked
            // past the end forever.
            _offset = 0;
          } else {
            // Nothing at all. Before saying "you're all caught up", ask
            // once more after a beat: on a cold start the first query can
            // come back EMPTY (not failed) while the session is still
            // attaching, and treating that as the end latched the empty
            // screen for the whole session — it only cleared on a manual
            // pull-to-refresh. A retry that's still empty is the real end.
            if (!_emptyRetryDone) {
              _emptyRetryDone = true;
              _reachedEnd = false;
              Future<void>.delayed(const Duration(milliseconds: 1500), () {
                if (mounted && _remote.isEmpty) unawaited(_loadMore());
              });
            } else {
              _reachedEnd = true;
            }
          }
        } else {
          // Shuffled per page, not left in fetch (chronological) order —
          // explicit request: the anon feed shouldn't settle into a fixed
          // order across visits now that a reacted-to post stays in it
          // indefinitely (excludeReacted: false, above) — each fresh page
          // reads differently every time it's loaded, this one included.
          final added = rows.map(AnonFeedPost.fromRow).toList()..shuffle();
          _remote.addAll(added);
          _offset += _pageSize;
          // Fire-and-forget: counts stream in and patch themselves, cards
          // show a skeleton meanwhile. Deliberately not awaited — the page
          // must render immediately, not block on N count round-trips.
          unawaited(_hydrateCounts(added));
          // First page landing IS the view of whatever lands at index 0 —
          // onPageChanged never fires for the page a PageView opens on, only
          // for swipes away from it, so this is the one place that credits
          // the very first post's view.
          if (!_recordedInitialView && added.isNotEmpty) {
            _recordedInitialView = true;
            _recordView(added.first.id);
            // Same reason the view is credited here: onPageChanged never
            // fires for the page a PageView opens on, so without this the
            // header badge would show nothing until the first swipe.
            widget.onActiveAuthorScoreChanged?.call(added.first.authorScore);
          }
        }
      });
      await _ensureMinimumPosts();
    } catch (e, st) {
      // Degrade to "stop loading more", never to a blank/crashed feed.
      // Everything already in _remote stays on screen; _offset is NOT
      // advanced, so a retry re-requests the same page rather than
      // silently skipping it.
      debugPrint('[AnonFeed._loadMore] offset=$_offset failed: $e\n$st');
      if (mounted) {
        setState(() => _loadFailed = true);
      }
    } finally {
      _loadingMore = false;
      // Every exit path counts as "resolved" — success, genuinely empty,
      // AND failure all mean the screen now has a real answer and should
      // stop showing the loading placeholder. Guarded by `mounted`/already-
      // false the same way _loading is elsewhere in this file.
      if (mounted && _firstLoadPending) {
        setState(() => _firstLoadPending = false);
      }
      // Warms the next couple of cards' photos as soon as there's anything
      // to warm them WITH — covers both the very first page (so post 1 is
      // already downloaded by the time post 0 is on screen) and every
      // later page (so the newly-appended tail is ready before a fast
      // scroller reaches it).
      _precacheAhead(_idx);
    }
  }

  /// Downloads [fromIndex]'s next couple of posts' photos ahead of time, so
  /// the card doesn't start its network fetch only once it's already
  /// on-screen. That fetch-on-arrival gap is what showed as a slow-loading
  /// placeholder on every single swipe — memCacheWidth only limits the
  /// decoded bitmap size, it does nothing for a photo that hasn't been
  /// downloaded yet.
  void _precacheAhead(int fromIndex) {
    for (final i in [fromIndex + 1, fromIndex + 2]) {
      if (i < 0 || i >= _posts.length) continue;
      for (final url in [_posts[i].imageUrl, _posts[i].secondaryPhotoUrl]) {
        if (url == null || url.isEmpty) continue;
        unawaited(_precacheOne(url));
      }
    }
  }

  Future<void> _precacheOne(String url) async {
    if (!mounted) return;
    try {
      await precacheImage(CachedNetworkImageProvider(url), context);
    } catch (_) {
      // Best-effort — a failed warm-up just means that card falls back to
      // its normal on-demand fetch, never a crash.
    }
  }

  /// Patches one post's comment count in place — the sheet reports it after
  /// every load, including the reload that follows sending a comment.
  void _setCommentCount(String? postId, int count) {
    if (postId == null) return;
    final i = _remote.indexWhere((p) => p.id == postId);
    if (i == -1) return;
    if (_remote[i].commentCount == count) return;
    setState(() => _remote[i] = _remote[i].copyWith(commentCount: count));
  }

  /// Re-fetches the real, identity-free aggregate for [id] (the on-photo
  /// stack's emoji+count breakdown) and folds its total into
  /// AnonFeedPost.extraReactions — the single source both the stack and
  /// the count pill next to it read, so they can never show two different
  /// numbers for the same post.
  Future<void> _refreshReactionAggregate(String id) async {
    final counts = await RealmojiService.instance.fetchAnonCounts(id);
    if (!mounted) return;
    final total = counts.fold<int>(0, (a, c) => a + c.count);
    setState(() {
      _reactionBreakdown[id] = counts;
      final i = _remote.indexWhere((p) => p.id == id);
      if (i != -1) _remote[i] = _remote[i].copyWith(extraReactions: total);
    });
  }

  /// A tapped RealmojiTray slot that already has a saved selfie — instant
  /// react via RealmojiService.reactWithSaved, no camera. Tapping the same
  /// emoji you already reacted with is a no-op here (unlike the old fixed-
  /// emoji tray, RealMoji reactions aren't a toggle — see
  /// post_realmoji_reactions' own one-row-per-user shape; retracting a
  /// reaction isn't a flow this app exposes anywhere else either).
  /// A plain-emoji reaction from the tray's "+" mode.
  ///
  /// Writes to `reactions` (the emoji table), NOT
  /// `post_realmoji_reactions` — a RealMoji is a selfie and needs a
  /// capture; this is the no-camera path the "+" exists to offer. Same
  /// one-row-per-user upsert the feed cards already use, so tapping a
  /// second emoji replaces the first rather than stacking.
  Future<void> _emojiReact(AnonFeedPost post, String emoji) async {
    final id = post.id;
    if (id == null) return; // demo/local rows have no real post id
    setState(() => _open = null);
    try {
      await ReactionService.instance.setEmojiReaction(postId: id, emoji: emoji);
      await _refreshReactionAggregate(id);
    } catch (e, st) {
      debugPrint('[AnonFeed._emojiReact] $id $emoji failed: $e\n$st');
      if (mounted)
        showGlassToast(context, "Couldn't save that reaction.", isError: true);
    }
  }

  Future<void> _selectRealmoji(AnonFeedPost post, ReactionPreset preset) async {
    final id = post.id;
    if (id == null) return; // demo/local rows have no real post id
    setState(
      () => _open = null,
    ); // close the tray immediately, same as every other card

    final type = realmojiTypeFromGlyph(preset.emoji);
    if (_pickedMoji[id] == type.glyph) return;

    final previous = _pickedMoji[id];
    setState(() => _pickedMoji[id] = type.glyph);
    try {
      await RealmojiService.instance.reactWithSaved(
        postId: id,
        emojiType: type,
      );
      await _refreshReactionAggregate(id);
    } catch (e, st) {
      debugPrint('[AnonFeed._selectRealmoji] $id -> $type failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        if (previous == null) {
          _pickedMoji.remove(id);
        } else {
          _pickedMoji[id] = previous;
        }
      });
      if (!context.mounted) return;
      showGlassToast(context, "Couldn't save that reaction", isError: true);
    }
  }

  /// A tapped RealmojiTray slot with no saved selfie yet for the anon
  /// section — opens the same full-screen camera every other reaction
  /// surface in the app uses (FaceReactionCapture), then uploads + saves
  /// + reacts in one call (RealmojiService.captureAndReact). The captured
  /// selfie is scoped to feed_scope 'anonymous' — a real photo, same as
  /// the Everyone feed's own RealMoji capture, but it's stored/shown only
  /// to the reactor themselves via their own saved-selfie library
  /// (savedSelfies), never surfaced with identity attached anywhere an
  /// anon feed viewer can see — the aggregate breakdown this screen renders
  /// (see _OnPhotoReactionStack) is emoji+count only, sourced from
  /// anon_reaction_counts, which carries no user_id at all.
  Future<void> _captureRealmoji(AnonFeedPost post, RealmojiType type) async {
    final id = post.id;
    if (id == null) return;
    setState(() => _open = null);

    final result = await Navigator.of(context).push<FaceReactionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FaceReactionCapture(
          presetEmoji: type.glyph,
          title: 'Capture your RealMoji',
          onFallbackToEmoji: () {
            if (context.mounted) {
              showGlassToast(
                context,
                'Front camera needed for a RealMoji — try again once it\'s available.',
                isError: true,
              );
            }
          },
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _uploadingRealmoji.add(id));
    try {
      await RealmojiService.instance.captureAndReact(
        postId: id,
        feedScope: ReactionPresetCategory.anonymous.wire,
        emojiType: type,
        selfie: result.selfie,
      );
      if (!mounted) return;
      setState(() => _pickedMoji[id] = type.glyph);
      await _refreshReactionAggregate(id);
    } catch (e, st) {
      debugPrint('[AnonFeed._captureRealmoji] $id -> $type failed: $e\n$st');
      if (!mounted) return;
      showGlassToast(context, "Couldn't save your RealMoji.", isError: true);
    } finally {
      if (mounted) setState(() => _uploadingRealmoji.remove(id));
    }
  }

  /// Clears the failure latch and re-requests the same offset. Wired to the
  /// error state's Retry action.
  void _retry() {
    if (_loadingMore) return;
    setState(() => _loadFailed = false);
    _loadMore();
  }

  /// Fills in reaction/comment counts for freshly-loaded posts.
  ///
  /// `posts_feed` doesn't carry engagement counts, so [AnonFeedPost.fromRow]
  /// leaves them null ("unknown") rather than 0 ("nobody reacted") — the
  /// cards render a skeleton until this resolves. Runs per post and patches
  /// each one in as it lands, so one slow/failing post doesn't hold up the
  /// rest.
  ///
  /// Failures are swallowed per-post ON PURPOSE: the count simply stays
  /// null and keeps showing a skeleton rather than flipping to a wrong 0.
  ///
  /// Reaction data comes from RealmojiService — anon_reaction_counts for
  /// the aggregate (emoji+count, no identity) and myReaction for the
  /// viewer's own pick — NOT ReactionService.fetchSummary. The anon
  /// section's reaction tray now writes real RealMoji reactions
  /// (post_realmoji_reactions, see _selectRealmoji/_captureRealmoji), so
  /// this has to read from the same table those writes land in, or a
  /// reaction would never appear in its own count.
  ///
  /// ONE request for the whole page — see
  /// RealmojiService.fetchAnonEngagement and migration
  /// 20260907120000_anon_feed_engagement_batch.sql.
  ///
  /// This used to be 3-4 requests per post, chunked 4 at a time so it didn't
  /// saturate the connection and time out, which meant a 20-post page took
  /// ~15-20 sequential round-trip waves to finish hydrating and the cards
  /// sat on their skeletons for seconds. That was the single biggest part of
  /// "all the pages are loading too much".
  ///
  /// Failures still fail SOFT and per-post: a post missing from the response
  /// keeps its null counts and its skeleton, rather than flipping to a
  /// wrong 0.
  Future<void> _hydrateCounts(List<AnonFeedPost> posts) async {
    final ids = [
      for (final p in posts)
        if (p.id != null) p.id!,
    ];
    if (ids.isEmpty) return;

    // Batched alongside the existing engagement fetch rather than a
    // separate loading pass — one round of requests per page, same as
    // engagement's own single call.
    //
    // BUG FIX: this used to be `Future.wait(ids.map(fetchAnonPostSeenFaces))`
    // — a fan-out of one RPC PER POST, all fired concurrently. Past ~4
    // posts on one page the later calls started timing out and failing
    // soft to [], so the seen pill silently fell back to decorative dots.
    // See fetchAnonPostSeenFacesBatch's own doc.
    final results = await Future.wait([
      RealmojiService.instance.fetchAnonEngagement(ids),
      RealmojiService.instance.fetchAnonPostSeenFacesBatch(ids),
    ]);
    if (!mounted) return;
    final engagement = results[0] as Map<String, AnonPostEngagement>;
    final seenFacesById = results[1] as Map<String, List<String>>;
    for (final id in ids) {
      final faces = seenFacesById[id];
      if (faces != null && faces.isNotEmpty) _seenFaces[id] = faces;
    }
    if (engagement.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      for (final entry in engagement.entries) {
        final id = entry.key;
        final e = entry.value;
        final i = _remote.indexWhere((p) => p.id == id);
        if (i == -1) continue;
        _reactionBreakdown[id] = e.counts;
        _reactionFaces[id] = e.faces;
        _remote[i] = _remote[i].copyWith(
          extraReactions: e.totalReactions,
          commentCount: e.commentCount,
        );
        // Restore the viewer's OWN reaction so it renders as picked after a
        // reload/restart. Only ever seeds from the server — a pick made
        // while this was in flight (already in _pickedMoji) wins.
        final mine = e.myReaction;
        if (mine != null && !_pickedMoji.containsKey(id)) {
          _pickedMoji[id] = mine.glyph;
        }
      }
    });
  }

  @override
  void dispose() {
    _ownPostSub?.cancel();
    _pageCtrl.dispose();
    _promptBar
      ..removeListener(_onPromptBarChanged)
      ..dispose();
    super.dispose();
  }

  // ── §13.3 mutual exclusion / dismissal ────────────────────────────────

  void _soloOpen(int postIndex, String key) {
    setState(() {
      final was = _open?.key == postIndex && _open?.value == key;
      _open = was ? null : MapEntry(postIndex, key);
    });
  }

  void _dismissPopovers() {
    if (_open != null) setState(() => _open = null);
  }

  void _openComments() {
    HapticFeedback.selectionClick();
    setState(() {
      _commentsOpen = true;
      _open = null; // rule 4: opening a sheet closes on-card popovers
    });
    widget.onCommentsOpenChanged?.call(true);
  }

  void _closeComments() {
    setState(() => _commentsOpen = false);
    widget.onCommentsOpenChanged?.call(false);
  }

  // Rewired to the SAME shared ping sheet Friends/solo cards use
  // (ping_prompt_sheet.dart's showPingPromptSheet), replacing the local
  // _AnonPingSheet — per explicit request, Anon's ping button should open
  // identically to how it already works everywhere else in the app, not a
  // separate, differently-built implementation. Matches
  // PostReactions.openPing's own defaults exactly (glass:true,
  // heightFraction:0.5, roundedTopOnly:true, targetName 'someone' — no
  // real identity to show for an anonymous post). _promptPickerOpen/
  // _pingPick/_closePromptPicker/_AnonPingSheet are now dead (nothing
  // sets/reads them) — left in place rather than deleted in this pass, to
  // keep tonight's edit surface minimal; safe to remove in a follow-up.
  //
  // onSentPrompt actually pings the post's author via ping_post_author() —
  // the caller never learns who that is (the RPC resolves it server-side)
  // — for any post with a real `id`. Two divergences from the person/group
  // ping paths this used to have, now closed: (1) it used to close silently
  // with nothing sent for a demo post (`id == null`) — now shows a visible
  // error instead, same as any other failed send; (2) it used to show a
  // toast only on failure — success now confirms too, matching
  // design_group_card.dart's 'Pinged N members' pattern.
  void _openPromptPicker(AnonFeedPost post) {
    HapticFeedback.selectionClick();
    setState(
      () => _open = null,
    ); // rule 4: opening a sheet closes on-card popovers
    final postId = post.id;
    showPingPromptSheet(
      context,
      targetName: 'someone',
      pingContext: PingContext.anonymous,
      glass: true,
      heightFraction: 0.5,
      roundedTopOnly: true,
      // Tier-resolved prompts for THIS post — the prompt-bar question's own
      // set when it answered one, otherwise the generic anon set.
      postId: postId,
      onSentPrompt: postId == null
          ? (_, {photoUrl}) => showGlassToast(
              context,
              "Can't ping a demo post.",
              isError: true,
            )
          : (prompt, {photoUrl}) async {
              try {
                await PingService.instance.pingPostAuthor(
                  postId: postId,
                  prompt: prompt,
                );
              } on Object catch (e) {
                if (!mounted) return;
                showGlassToast(
                  context,
                  e is PingLimitExceeded ||
                          e is PingAlreadyOpen ||
                          e is PingSelfNotAllowed
                      ? e.toString()
                      : "Couldn't send that ping.",
                  isError: true,
                );
                return;
              }
              // No success toast: the prompt sheet's reward dropdown is
              // the confirmation now, and a toast fired at the same instant
              // slid in half-behind it.
            },
    );
  }

  void _closePromptPicker() {
    setState(() {
      _promptPickerOpen = false;
      _pingPick = null; // rule 6: clears selection on close
    });
  }

  // Only the removed bottom peek prompt called this; kept with it.
  // ignore: unused_element
  void _advance() {
    if (_idx < _posts.length - 1) {
      _pageCtrl.animateToPage(
        _idx + 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = anonScale(context);
    final posts = _posts;
    // Guard every index into `posts` — it can legitimately be EMPTY now
    // (real feed with nothing in the 24h window and nothing unreacted),
    // unlike the old always-populated const list.
    // Three distinct states, never conflated into one blank screen:
    // "still waiting on the first page" (_firstLoadPending) is neither
    // empty nor failed and gets its own quiet loading placeholder —
    // without this branch, "nothing to show" (terminal, fine) rendered on
    // every cold open for the several hundred ms before the first fetch
    // had even returned, regardless of whether real posts existed.
    // "couldn't load" needs a way out (retry). "nothing to show" is
    // terminal and fine.
    if (posts.isEmpty) {
      if (_firstLoadPending) return const _AnonLoadingState();
      if (_loadFailed) return _AnonErrorState(onRetry: _retry);
      // BUG FIX ("if nobody has posted in anon feed but still then show the
      // prompt bar suitably for them to post"): this used to return the
      // bare "you're all caught up" message with NOTHING else — no header,
      // no toggle pill, no prompt bar — so a genuinely empty feed (a fresh
      // community, or everyone's 24h posts having just rolled off) left the
      // viewer with no visible way to actually post anything. The prompt
      // rotation (_activePrompt) runs independently of whether any posts
      // exist, so there is always a real prompt to show here.
      //
      // _AnonHeader still needs an AnonFeedPost to satisfy its required
      // `post` param — used ONLY as _PromptBar's prompt-text fallback for
      // the rare case _activePrompt is ALSO null (rotation not loaded yet).
      // This placeholder carries just that fallback text; every other field
      // is inert filler, since nothing else in _AnonHeader's subtree reads
      // from `post` beyond that one fallback.
      const placeholderPost = AnonFeedPost(
        community: '',
        timeAgo: '',
        viewerCount: 0,
        extraReactions: 0,
        commentCount: 0,
        score: 0,
        tier: '',
        caption: '',
        prompt: 'Post your view right now 👀',
      );
      // Same Column shape as the real (non-empty) path below — a top
      // spacer, then _AnonHeader, then the body filling whatever's left —
      // just with the "you're all caught up" message standing in for the
      // PageView of real post cards.
      return ColoredBox(
        color: AnonFeedColors.screenBg,
        child: Column(
          children: [
            SizedBox(
              height: (widget.topInset - 32 * scale).clamp(
                MediaQuery.paddingOf(context).top + 8,
                double.infinity,
              ),
            ),
            _AnonHeader(
              scale: scale,
              onSwitchToFriends: widget.onSwitchToFriends,
              onOpenCamera: widget.onOpenCamera,
              post: placeholderPost,
              dailyPrompt: _activePrompt,
              promptResponseCount: _activePrompt == null
                  ? null
                  : _promptResponseCounts[_activePrompt!.id],
            ),
            const Expanded(child: _AnonEmptyState()),
          ],
        ),
      );
    }
    final safeIdx = _idx.clamp(0, posts.length - 1);

    // Checklist item 9 ("apply s(context) to EVERY numeric value") applies
    // to type scale too — AnonFeedType's 36 styles are literal design-px
    // sizes, unscaled per-instance. Rather than thread `scale` through
    // every Text call site, override the ambient TextScaler once here so
    // every Text/RichText under this screen renders at `scale`× its
    // design-px font size — this is what actually fixes real-device
    // overflows like the peek panel's content not fitting its
    // (correctly-scaled-down) fixed 96px container height.
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      // Same fix already established in this codebase for the same
      // inherited-underline symptom (see anonymous_tab.dart's identical
      // DefaultTextStyle.merge reset) — some app-level ancestor applies a
      // default TextDecoration.underline that isn't part of this screen's
      // own design and must be explicitly cleared.
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: ColoredBox(
          color: AnonFeedColors.screenBg,
          child: GestureDetector(
            // §13.3 rule 2 — tap anywhere outside a popover closes it. Sheets
            // have their own backdrop GestureDetectors (§10–§12), so this only
            // needs to catch taps on the plain feed surface.
            onTap: _dismissPopovers,
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
                Column(
                  children: [
                    // widget.topInset's contract matches AnonymousTab.topInset
                    // EXACTLY (see home_screen.dart's call site,
                    // `_headerBaselineHeight ?? (topPadding + 96)`): the value
                    // the caller passes ALREADY includes the real device
                    // safe-area inset — it is not "extra chrome on top of
                    // safe area." Adding MediaQuery.of(context).padding.top
                    // here again would double-count it. §3's own "use
                    // MediaQuery.top + 12*s in production" note is satisfied
                    // by HomeScreen's call site already folding topPadding
                    // into the value it hands down, matching the rest of this
                    // codebase's established convention for this exact slot.
                    // -42*scale nudges the toggle further up, closer to the
                    // bell/plus row's own bottom edge. Pulled back in from -42
                    // to -22 — the Anon rank badge now added into that bell
                    // row (see _SlimHeaderState's Row 0) made the real
                    // measured topInset baseline sit lower than when -42 was
                    // tuned, and -42 pushed the toggle up far enough to
                    // overlap the badge. Per explicit request to move the
                    // toggle pill further up again, split the difference at
                    // -30*scale rather than returning all the way to -42 —
                    // still noticeably higher than -22, without fully
                    // reintroducing the badge overlap -42 caused. Clamped so
                    // it can never eat into the real status-bar safe area
                    // itself.
                    // No manual offset here (was `- 30 * scale`, then `- 22`,
                    // then `- 30` again per a series of hand-tuned "nudge it up
                    // a bit more" requests) — those were all guesses trying to
                    // visually match the Friends tab's pill position without
                    // ever actually sharing its real anchor. widget.topInset
                    // alone already measures _SlimHeader's own real rendered
                    // height (Row 0's bell/plus row, including its own
                    // bottom:10 padding) — Friends' pill sits directly below
                    // that same real measurement with no subtraction, so this
                    // now matches it exactly instead of drifting by whatever
                    // the last manual tweak happened to be.
                    // -15*scale -> -32*scale — further explicit request for
                    // real, visible clearance between the caption/meta row and
                    // the tab bar (15 wasn't enough). Moves the whole header
                    // block (prompt bar + everything below it) up as a unit.
                    // Clamped to the same topPadding+8 floor as before so this
                    // can never eat into the real status-bar safe area,
                    // regardless of device.
                    SizedBox(
                      height: (widget.topInset - 32 * scale).clamp(
                        MediaQuery.paddingOf(context).top + 8,
                        double.infinity,
                      ),
                    ),
                    _AnonHeader(
                      scale: scale,
                      onSwitchToFriends: widget.onSwitchToFriends,
                      onOpenCamera: widget.onOpenCamera,
                      post: posts[safeIdx],
                      dailyPrompt: _activePrompt,
                      // Null while _loadResponseCount's fetch is in flight for
                      // this prompt — _PromptBar shows a placeholder rather
                      // than a momentarily-wrong "0 responding".
                      promptResponseCount: _activePrompt == null
                          ? null
                          : _promptResponseCounts[_activePrompt!.id],
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          // Reserve space only for the safe-area inset + the gap
                          // above the pill (kTabBarBottomOffset) — NOT the pill's
                          // own kTabBarHeight on top of that. The pill itself is
                          // a small (56pt), centred, translucent BackdropFilter
                          // glass shape (see _BottomNav in main_shell.dart) with
                          // no opaque backing plate, so content is meant to run
                          // underneath it and show through, exactly like every
                          // other tab (Everyone/Community/Profile all just add
                          // small scroll padding here, never a tab-bar-height
                          // reservation). Reserving the full kTabBarHeight on
                          // top of kTabBarBottomOffset was the root cause of the
                          // black dead band the user reported: it painted the
                          // screen's own #0B0B0D background — then _AnonBottomBlock
                          // painted an opaque #141418 over the rest — across the
                          // ~114pt that content could never reach. Dropping the
                          // kTabBarHeight term also relieves rather than worsens
                          // the "single fixed-height page, already tight" issue
                          // the earlier "+16" attempt ran into (see git blame /
                          // plan doc): more content-safe room, not less.
                          // 0 now: this used to reserve the bottom peek
                          // prompt's strip. That prompt is removed, and the
                          // tab bar's own room is reserved inside each page
                          // (_tabBarReserve), so the page runs to the edge.
                          bottom: 0,
                        ),
                        child: NotificationListener<ScrollNotification>(
                          // §13.3 rule 3 — scrolling the FEED closes open
                          // popovers. Vertical only: this used to fire on any
                          // scroll notification at all, and the RealMoji tray's
                          // own horizontally-scrolling list is a descendant, so
                          // its notifications bubbled up here and dismissed the
                          // very popover the person was scrolling. Reported as
                          // "it closes if I just touch the drop down to scroll
                          // the drop down". The feed's PageView is vertical and
                          // every in-popover list is horizontal, so the axis is
                          // an exact discriminator.
                          onNotification: (n) {
                            if (n is ScrollUpdateNotification &&
                                n.metrics.axis == Axis.vertical) {
                              _dismissPopovers();
                            }
                            return false;
                          },
                          child: RefreshIndicator(
                            onRefresh: _refresh,
                            edgeOffset: 8,
                            color: Colors.white,
                            backgroundColor: AnonFeedColors.screenBg,
                            child: PageView.builder(
                              controller: _pageCtrl,
                              scrollDirection: Axis.vertical,
                              // AlwaysScrollable so the first page can still
                              // overscroll downward — without it RefreshIndicator
                              // never sees the drag that triggers it.
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: PageScrollPhysics(),
                              ),
                              itemCount: posts.length,
                              onPageChanged: (i) {
                                setState(() {
                                  _idx = i;
                                  _open = null;
                                });
                                if (i >= 0 && i < posts.length) {
                                  _recordView(posts[i].id);
                                  widget.onActiveAuthorScoreChanged?.call(
                                    posts[i].authorScore,
                                  );
                                }
                                // Infinite scroll: prefetch the next page a few
                                // posts before the end so it's already there by
                                // the time the user swipes to it. Only meaningful
                                // once real data is driving the feed — the demo
                                // fallback list isn't paginated.
                                if (_remote.isNotEmpty &&
                                    i >= _remote.length - 3) {
                                  _loadMore();
                                }
                                _precacheAhead(i);
                              },
                              itemBuilder: (context, i) => _AnonSnapSection(
                                scale: scale,
                                post: posts[i],
                                viewersOpen:
                                    _open?.key == i &&
                                    _open?.value == 'viewers',
                                reactionsOpen:
                                    _open?.key == i &&
                                    _open?.value == 'reactions',
                                breakdownOpen:
                                    _open?.key == i &&
                                    _open?.value == 'breakdown',
                                menuOpen:
                                    _open?.key == i && _open?.value == 'menu',
                                pickedMoji: posts[i].id == null
                                    ? null
                                    : _pickedMoji[posts[i].id],
                                uploadingRealmoji:
                                    posts[i].id != null &&
                                    _uploadingRealmoji.contains(posts[i].id),
                                reactionBreakdown: posts[i].id == null
                                    ? const []
                                    : (_reactionBreakdown[posts[i].id] ??
                                          const []),
                                reactionFaces: posts[i].id == null
                                    ? const []
                                    : (_reactionFaces[posts[i].id] ?? const []),
                                seenFaces: posts[i].id == null
                                    ? const []
                                    : (_seenFaces[posts[i].id] ?? const []),
                                viewers: posts[i].id == null
                                    ? null
                                    : _viewers[posts[i].id],
                                onToggleViewers: () {
                                  _soloOpen(i, 'viewers');
                                  final id = posts[i].id;
                                  if (id != null) unawaited(_loadViewers(id));
                                },
                                onToggleReactions: () =>
                                    _soloOpen(i, 'reactions'),
                                // Explicit request: the reaction-viewing button
                                // now opens the comments sheet, which carries
                                // the reaction FACES in a horizontal strip at
                                // its top — "when clicked on the reaction
                                // viewing button in anonymous, along with
                                // comment section a drop down shall open with
                                // the reactions there in a horizontal
                                // scrollable section". The old popover showed
                                // emoji + counts with no way to see the
                                // RealMojis themselves.
                                onToggleBreakdown: _openComments,
                                onToggleMenu: () => _soloOpen(i, 'menu'),
                                onSelectRealmoji: (preset) =>
                                    _selectRealmoji(posts[i], preset),
                                onCaptureRealmoji: (type) =>
                                    _captureRealmoji(posts[i], type),
                                onEmojiReact: (emoji) =>
                                    _emojiReact(posts[i], emoji),
                                onOpenComments: _openComments,
                                onOpenPromptPicker: () =>
                                    _openPromptPicker(posts[i]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // REVERTED — an attempted fix here (pushing this above the tab
                // bar via bottom: kTabBarBottomOffset+kTabBarHeight+8) made
                // things WORSE, not better: confirmed via screenshot, it hid
                // almost the entire peek block behind the tab bar instead of
                // clearing it. Root cause not yet found: the real tab bar's
                // Anon-tab position (MainShell's own `tabBarBottom` local,
                // build()) is bottomPad + kTabBarBottomOffset +
                // kTabBarExtraLift(10). Back to the original formula pending a
                // fix at the actual source — see _isHomeAnonActive's own
                // investigation note in main_shell.dart/HomeScreen: the
                // overlap reproduces specifically when that flag desyncs
                // (tab bar renders at its LOWER, non-Anon position while Anon
                // content is still on screen), not from this reservation being
                // undersized — so the fix belongs there, not in a pixel value
                // guessed a fourth time here.
                // The bottom peek prompt (_AnonBottomBlock, the next post's
                // prompt peeking up under the tab bar) is no longer drawn —
                // explicit request, 2026-10-06. The widget is kept below,
                // unreferenced, in case it returns.
                if (_commentsOpen)
                  _AnonCommentsSheet(
                    scale: scale,
                    post: posts[safeIdx],
                    breakdown: posts[safeIdx].id == null
                        ? const []
                        : (_reactionBreakdown[posts[safeIdx].id] ?? const []),
                    onClose: _closeComments,
                    onCountChanged: (n) =>
                        _setCommentCount(posts[safeIdx].id, n),
                  ),
                if (_promptPickerOpen)
                  _AnonPingSheet(
                    scale: scale,
                    selected: _pingPick,
                    onSelect: (n) => setState(() => _pingPick = n),
                    onClose: _closePromptPicker,
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
// §4 HEADER BLOCK
// ---------------------------------------------------------------------------

class _AnonHeader extends StatelessWidget {
  const _AnonHeader({
    required this.scale,
    required this.onSwitchToFriends,
    required this.onOpenCamera,
    required this.post,
    this.dailyPrompt,
    this.promptResponseCount,
  });

  final double scale;

  /// Real navigation request — see AnonFeedScreenV2.onSwitchToFriends's
  /// own doc. This screen is always the Anon side, so the "Anon" chip is
  /// always the active one and never has anything to switch TO (tapping
  /// it while already here is a no-op); only "Friends" fires a callback.
  final VoidCallback? onSwitchToFriends;

  /// See AnonFeedScreenV2.onOpenCamera's own doc — passed straight through
  /// to _PromptBar below.
  final void Function([
    String? answeringPrompt,
    String? answeringCommunityId,
    String? answeringPromptId,
  ])?
  onOpenCamera;
  final AnonFeedPost post;

  /// The prompt bar's current rotation entry (DailyPromptService) — null
  /// falls back to [post]'s own prompt text, same as before this rotation
  /// existed.
  final DailyPrompt? dailyPrompt;

  /// Live count of anon posts answering [dailyPrompt] — null while the
  /// fetch is in flight. See DailyPromptService.fetchResponseCount.
  final int? promptResponseCount;

  @override
  Widget build(BuildContext context) {
    // §4.1 specifies 54 top, but on a real phone viewport that (combined
    // with widget.topInset above it) either clips the card's bottom
    // content or pushes the toggle well below the bell/plus row. Per
    // explicit request, this is 0 now — widget.topInset alone (which
    // already measures the real bell/plus row's own height, see that
    // field's doc) puts the toggle right at that row's bottom edge with
    // no extra gap.
    return Padding(
      padding: EdgeInsets.fromLTRB(40 * scale, 0, 40 * scale, 0),
      child: Column(
        children: [
          // The pill itself no longer renders here — it's now a SINGLE
          // persistent instance owned by _SlimHeader (home_screen.dart),
          // which sits in the shell's own Stack ABOVE the PageView (not
          // per-page content), so it survives a tab switch instead of
          // being destroyed/recreated — that's what makes a real slide
          // transition possible instead of AnimatedSwitcher's structural
          // cross-fade. This SizedBox reserves the exact same footprint as
          // the real pill so _PromptBar below doesn't shift now that the
          // real pill paints via that overlay instead of here.
          SizedBox(height: 46 * scale),
          // 1.75 -> 0.875 (halved, per explicit request) — moves ONLY the
          // prompt bar up relative to the pill above it, distinct from the
          // separate whole-header-block offset above (which moves the
          // prompt bar AND everything below it together).
          SizedBox(height: 0.875 * scale),
          _PromptBar(
            scale: scale,
            post: post,
            onOpenCamera: onOpenCamera,
            dailyPrompt: dailyPrompt,
            responseCount: promptResponseCount,
          ),
        ],
      ),
    );
  }
}

/// The Anon feed's own Anon/Friends toggle pill — generalized here (public,
/// arbitrary activeIndex) so other screens (EveryoneFeedScreen's own
/// header) can render the EXACT same pill design instead of a separately
/// re-implemented one. _AnonHeader above is just its first caller, always
/// pinned to activeIndex 0 since the Anon screen itself is never the
/// Friends side.
class AnonFriendsTogglePill extends StatelessWidget {
  const AnonFriendsTogglePill({
    super.key,
    required this.scale,
    required this.activeIndex,
    required this.onToggle,
  });

  final double scale;

  /// 0 = Anon active, 1 = Friends active.
  final int activeIndex;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    // Centers the ACTIVE chip itself on screen, not the row-group of both
    // chips — plain MainAxisAlignment.center would center the combined
    // (wide-active + gap + narrow-collapsed) group, which visibly drags
    // the wide chip off-center toward the collapsed side. One Expanded
    // pure-spacer on the side away from the collapsed chip, plus an
    // Expanded+Align wrapping the collapsed chip on its own side, puts the
    // active chip's own center exactly at the row's midpoint regardless of
    // how wide the collapsed chip is. Mirrored left/right depending on
    // which side is active — Anon active matches _AnonHeader's original
    // layout exactly; Friends active is its mirror image.
    final anonActive = activeIndex == 0;
    final anonChip = _ToggleChip(
      scale: scale,
      active: anonActive,
      onTap: () => onToggle(0),
      // Back to "Anon" (explicit revert of the earlier "Dip" rename); the
      // feed itself is still the anonymous feed everywhere in code.
      label: 'Anon',
      trailing: false,
    );
    final friendsChip = _ToggleChip(
      scale: scale,
      active: !anonActive,
      onTap: () => onToggle(1),
      label: 'Friends',
      trailing: true,
    );
    final gap = SizedBox(width: 6 * scale);
    return SizedBox(
      // Reduced back from 54 to 46 — the 54 bump (an earlier explicit
      // request) read as too large relative to the surrounding header per
      // a later correction. Must match _ToggleChip's own height below
      // exactly (that's the actual visible pill; this SizedBox only sizes
      // the Row that centers it).
      height: 46 * scale,
      // FIXED child order now (anonChip always first, friendsChip always
      // second) — no more AnimatedSwitcher + Expanded/Align branch-swap
      // per active state. That old approach rebuilt the Row with a new
      // ValueKey and reordered which chip got Expanded+Align on every
      // switch, which is a structural change Flutter can only cross-fade
      // between (two different Element trees), never smoothly animate —
      // that cross-fade is what read as a hard jump. Each _ToggleChip
      // already smoothly resizes itself via its own AnimatedContainer when
      // `active` flips; a plain MainAxisAlignment.center Row re-lays-out
      // and re-centers its children fresh every frame as those widths
      // change, so simply keeping both chips permanently mounted in a
      // stable order — with no wrapper animation of its own — is what
      // actually produces a real slide/resize transition instead of a
      // fade. (This also requires this widget to be a SINGLE persistent
      // instance shared across both tabs, not rebuilt per page — see the
      // call sites' own docs.)
      //
      // Row(mainAxisAlignment: center) centers the GROUP (both chips +
      // gap), not the ACTIVE chip alone — since the active chip is wider
      // than its collapsed sibling, that visibly drags the active label
      // off true center toward the collapsed side. Corrected via a
      // deterministic Transform.translate — every width here is a fixed
      // constant, so this is exact arithmetic, not a guess. Per-chip
      // offset = ±(gap + OTHER chip's collapsed width)/2, which is
      // provably independent of the active chip's own width (the active
      // width cancels out of group_center - chip_center), so this stays
      // correct regardless of _ToggleChip's own per-label active width
      // (82 for "Anon", 108 for "Friends" — see that widget's own doc):
      //   Anon active:    +(6 + 59.5)/2  = +32.75
      //   Friends active: -(6 + 50.5)/2  = -28.25
      // Friends chip first (left), Dip second — matching the pager, which
      // now puts Friends on the left. Offsets mirrored accordingly:
      //   Friends active: +(6 + 50.5)/2 = +28.25
      //   Dip active:     -(6 + 59.5)/2 = -32.75
      child: Transform.translate(
        offset: Offset((anonActive ? -32.75 : 28.25) * scale, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [friendsChip, gap, anonChip],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.scale,
    required this.active,
    required this.onTap,
    required this.label,
    required this.trailing,
  });

  final double scale;
  final bool active;
  final VoidCallback onTap;
  final String label;
  final bool trailing;

  double _labelWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: AnonFeedType.t1(AnonFeedColors.inkOnLight),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final ink = active ? AnonFeedColors.inkOnLight : AnonFeedColors.textDim;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AnonFeedCurves.chipDuration,
        curve: AnonFeedCurves.chipCurve,
        // Reverted from the 54-based enlargement back to 46-based sizing
        // (height/radius/padding) — see AnonFriendsTogglePill's own
        // SizedBox doc. label-slot-width stays at 108 regardless (that's
        // sized for "Friends" text fitment, a separate concern from the
        // pill's own decorative size).
        height: 46 * scale,
        // Active side padding 20 -> 15 with the label slot now fitted to
        // its text (below) — "reduce the empty space in its pill to half".
        padding: EdgeInsets.symmetric(
          horizontal: (active ? 15.0 : 14.0) * scale,
        ),
        decoration: BoxDecoration(
          color: active ? AnonFeedColors.chipLight : Colors.transparent,
          borderRadius: BorderRadius.circular(23 * scale),
        ),
        clipBehavior: Clip.hardEdge,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!trailing) _AnonDotIcon(scale: scale, color: ink),
            AnimatedContainer(
              duration: AnonFeedCurves.chipDuration,
              // Back to per-label width (82 for "Anon", 108 for "Friends",
              // its own required floor before clipping to "Frien") — an
              // earlier "make both the same size" request left visible
              // empty rounded space after "Anon" (confirmed via
              // screenshot); per explicit correction, tighter-per-label
              // wins now. Centering (AnonFriendsTogglePill's own
              // Transform.translate) is unaffected by this — that offset
              // is algebraically independent of the ACTIVE chip's own
              // width (it only depends on the gap + the OTHER, collapsed
              // chip's width, both unchanged here).
              // Fitted to the label's real text width (+1 so it never clips)
              // instead of the old fixed 82/108 slots: those were sized for
              // "Anon"/"Friends", so the renamed "Dip" sat in a slot about
              // twice its width.
              width: active ? _labelWidth(context) + 1 : 0,
              margin: EdgeInsets.only(
                left: trailing ? 0 : 10.5 * scale,
                right: trailing ? 10.5 * scale : 0,
              ),
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: AnimatedOpacity(
                duration: AnonFeedCurves.chipDuration,
                opacity: active ? 1 : 0,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: AnonFeedType.t1(ink),
                ),
              ),
            ),
            // chipBg must match what's actually BEHIND the icon (the
            // cutout-notch border is punched to this color) — the chip's
            // own background is transparent when inactive (line above),
            // so the real backdrop showing through is the screen bg, not
            // chipLight. Using chipLight unconditionally here (regardless
            // of active state) was what made the collapsed Friends icon
            // read as a bright ringed "switch thumb" floating on dark bg
            // instead of a clean two-dot icon.
            if (trailing)
              _AnonFriendsIcon(
                scale: scale,
                color: ink,
                chipBg: active
                    ? AnonFeedColors.chipLight
                    : AnonFeedColors.screenBg,
              ),
          ],
        ),
      ),
    );
  }
}

class _AnonDotIcon extends StatelessWidget {
  const _AnonDotIcon({required this.scale, required this.color});
  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    // Bumped 10 -> 12 alongside the pill's own enlargement.
    width: 12 * scale,
    height: 12 * scale,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _AnonFriendsIcon extends StatelessWidget {
  const _AnonFriendsIcon({
    required this.scale,
    required this.color,
    required this.chipBg,
  });
  final double scale;
  final Color color;
  final Color chipBg;

  @override
  Widget build(BuildContext context) {
    // Dimensions bumped alongside the pill's own enlargement (18x12 ->
    // 21x14, dots 10 -> 12, matching _AnonDotIcon).
    return SizedBox(
      width: 21 * scale,
      height: 14 * scale,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 1.2 * scale,
            child: Container(
              width: 12 * scale,
              height: 12 * scale,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
          Positioned(
            right: 0,
            top: 1.2 * scale,
            child: Container(
              width: 12 * scale,
              height: 12 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: chipBg, width: 2.3 * scale),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptBar extends StatelessWidget {
  const _PromptBar({
    required this.scale,
    required this.post,
    this.onOpenCamera,
    this.dailyPrompt,
    this.responseCount,
  });
  final double scale;
  final AnonFeedPost post;

  /// Opens the camera to respond to the daily prompt — see
  /// AnonFeedScreenV2.onOpenCamera's own doc.
  final void Function([
    String? answeringPrompt,
    String? answeringCommunityId,
    String? answeringPromptId,
  ])?
  onOpenCamera;

  /// Current rotation entry from DailyPromptService — one per joined
  /// community, advanced every 30s by the parent screen's timer. Falls
  /// back to the scrolled-to post's own prompt text when null (no
  /// rotation loaded yet, or nobody signed in).
  final DailyPrompt? dailyPrompt;

  /// Live count of anon posts answering [dailyPrompt] (DailyPromptService.
  /// fetchResponseCount) — null while that fetch is in flight, in which
  /// case a subtle placeholder renders instead of a momentarily-wrong "0
  /// responding". Replaces the old hardcoded "12 responding" fixture text.
  final int? responseCount;

  /// "N responding" — live, from [responseCount]. A dailyPrompt with a
  /// real (non-empty) id but no count loaded yet reads as a quiet ellipsis
  /// rather than a wrong number; a genuine zero explicitly invites the
  /// viewer to go first, matching the app's "be first" framing everywhere
  /// else a count can legitimately start at zero.
  /// The community this prompt belongs to, or null for the global/offline
  /// fallback set (which belongs to no community and shouldn't claim one).
  String? get _communityLabel {
    final p = dailyPrompt;
    if (p == null || p.communityId.isEmpty) return null;
    final name = p.communityName.trim();
    return name.isEmpty ? null : name;
  }

  String get _responseLabel {
    if (dailyPrompt == null || dailyPrompt!.id.isEmpty)
      return 'Reply to this prompt';
    final count = responseCount;
    if (count == null) return 'Loading…';
    if (count == 0) return 'Be the first to respond';
    return '$count responding';
  }

  @override
  Widget build(BuildContext context) {
    // A camera Anon-bubble post has no prompt of its own (see
    // FeedService's _kAnonPromptRule) — with no live prompt either, fall
    // back to the same line the empty feed uses rather than an empty bar.
    final promptText =
        dailyPrompt?.text ??
        (post.prompt.trim().isEmpty
            ? 'Post your view right now 👀'
            : post.prompt);
    return GestureDetector(
      // The prompt shown on this bar is the one being answered, so it
      // travels with the capture and lands in the post's peek bar —
      // together with which community/daily_prompts row it came from, so
      // the resulting post is attributed without a redundant manual step.
      onTap: onOpenCamera == null
          ? null
          : () => onOpenCamera!(
              promptText,
              dailyPrompt?.communityId.isNotEmpty == true
                  ? dailyPrompt!.communityId
                  : null,
              dailyPrompt?.id.isNotEmpty == true ? dailyPrompt!.id : null,
            ),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          22 * scale,
          5 * scale,
          5 * scale,
          5 * scale,
        ),
        decoration: BoxDecoration(
          color: AnonFeedColors.promptBarBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AnonFeedColors.hairlinePromptBar),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Two lines, not one. A single line ellipsised most
                    // seeded prompts mid-sentence ("What's something you
                    // wish people understo…"), so the question the whole
                    // bar exists to ask couldn't actually be read.
                    // Reported with a screenshot. Two lines fits every
                    // prompt in the library at the dashboard's own 80-char
                    // cap; the ellipsis stays as the backstop for anything
                    // longer that slips in.
                    Text(
                      promptText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AnonFeedType.t2,
                    ),
                    SizedBox(height: 3 * scale),
                    // WHICH COMMUNITY this prompt came from.
                    //
                    // The bar rotates one prompt per joined community in turn
                    // (DailyPromptService._roundRobin), so without naming the
                    // source the text changes every 30s with no indication of
                    // why — and answering it silently posts into a community
                    // the person didn't know they'd picked.
                    Row(
                      children: [
                        if (_communityLabel != null) ...[
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7 * scale,
                              vertical: 2 * scale,
                            ),
                            decoration: BoxDecoration(
                              color: AnonFeedColors.chipLight.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AnonFeedColors.hairlinePromptBar,
                              ),
                            ),
                            child: Text(
                              _communityLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AnonFeedType.t3,
                            ),
                          ),
                          SizedBox(width: 7 * scale),
                        ],
                        Flexible(
                          child: Text(
                            _responseLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AnonFeedType.t3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 16 * scale),
            Container(
              width: 46 * scale,
              height: 46 * scale,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AnonFeedColors.chipLight,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.camera_alt_outlined,
                size: 21 * scale,
                color: AnonFeedColors.inkOnLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// §5 SNAP SECTION — one page of the vertical PageView.
// ---------------------------------------------------------------------------

class _AnonSnapSection extends StatelessWidget {
  const _AnonSnapSection({
    required this.scale,
    required this.post,
    required this.viewersOpen,
    required this.reactionsOpen,
    required this.breakdownOpen,
    required this.pickedMoji,
    required this.uploadingRealmoji,
    required this.reactionBreakdown,
    required this.reactionFaces,
    this.seenFaces = const [],
    required this.viewers,
    required this.onToggleViewers,
    required this.onToggleReactions,
    required this.onToggleBreakdown,
    required this.onSelectRealmoji,
    required this.onCaptureRealmoji,
    required this.onEmojiReact,
    required this.onOpenComments,
    required this.onOpenPromptPicker,
    required this.menuOpen,
    required this.onToggleMenu,
  });

  final double scale;
  final AnonFeedPost post;
  final bool viewersOpen;
  final bool reactionsOpen;

  /// Real, identity-free top-viewer faces for the seen chip — see
  /// _seenFaces's own doc on the parent state.
  final List<String> seenFaces;

  /// Whether the "view other reactions" breakdown popover is open for
  /// this post — see _OnPhotoReactionStack's own doc.
  final bool breakdownOpen;
  final String? pickedMoji;
  final bool uploadingRealmoji;
  final List<AnonRealmojiCount> reactionBreakdown;

  /// Identity-free reactor photos, for the on-photo 1A stack.
  final List<AnonReactionFace> reactionFaces;

  /// Null while the list hasn't been fetched yet — see _loadViewers.
  final List<PostViewer>? viewers;
  final VoidCallback onToggleViewers;
  final VoidCallback onToggleReactions;
  final VoidCallback onToggleBreakdown;
  final ValueChanged<ReactionPreset> onSelectRealmoji;
  final ValueChanged<RealmojiType> onCaptureRealmoji;

  /// Plain-emoji reaction from the RealMoji tray's "+" mode — forwarded to
  /// _AnonPostCard, which hands it to the tray.
  final ValueChanged<String> onEmojiReact;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenPromptPicker;
  final bool menuOpen;
  final VoidCallback onToggleMenu;

  @override
  Widget build(BuildContext context) {
    // Stack, not just the Column below — the viewers popover (added as a
    // Positioned sibling here, not inside _LivePresenceChip's own Column
    // flow anymore) needs to paint OVER the card rather than push it
    // down. A Stack's later children paint on top of earlier ones, so
    // putting the popover AFTER the scrollview in this list (rather than
    // nested inside the chip, which paints BEFORE the card in Column
    // order and would end up hidden behind it) is what makes it overlap
    // the post instead of shoving it downward.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Vertically CENTRED in whatever height the page actually has,
        // not top-anchored.
        //
        // Every dimension in this section scales by `scale`, which is
        // screenWidth / 660 — a WIDTH-derived factor. The page's height is
        // independent of that, so on a device whose height:width ratio
        // differs from the ~390x844 phone this was hand-tuned against, all
        // the spare vertical space piled up at the BOTTOM and the card rode
        // high. Measured: Android 448x997 logical vs iOS ~402x874 — Android
        // is ~123pt taller in logical units while the width-derived scale
        // only grows the content ~11%, so the leftover gap is much bigger
        // there. Reported as "the photo is too much upward on Android".
        //
        // Centring spends that slack evenly above and below, so the
        // composition reads the same on any aspect ratio. The minHeight
        // constraint is what gives Column something to centre WITHIN; when
        // the content is taller than the viewport (small/short screens)
        // this is a no-op and it stays top-anchored and clipped exactly as
        // before, which is what the hand-tuned gaps below already assume.
        LayoutBuilder(
          builder: (context, box) {
            // Card scale that RECLAIMS spare vertical room on devices that
            // have it, bounded by the width the card can actually occupy.
            //
            // Measured: iOS has ~9pt of slack once the tab bar is reserved,
            // Android ~94pt. Growing the card is the honest way to spend
            // that — the photo is the content, and on Android it was simply
            // smaller than the screen allowed.
            //
            // Three guards, all load-bearing:
            //  * `slack > 30` — iOS's ~9pt falls under this, so iOS keeps the
            //    scale it has today and is left exactly as-is (explicit
            //    instruction: don't change what's already correct there).
            //  * `* 0.85` — was 0.7. Explicit request: the photo wasn't
            //    using enough of the available room, and the meta row below
            //    it ("N replies") needed to sit lower. Both are the same
            //    lever — growing the photo pushes everything below it down —
            //    so this is spending more of the ALREADY-MEASURED slack
            //    rather than adding a fixed gap after it (a fixed gap doesn't
            //    scale with the photo and was tried once already; reverted,
            //    see git history on this line). The `- 40` term below is
            //    still fully reserved headroom for a long caption growing the
            //    meta row, which keeps the tab bar protected either way.
            //  * the width cap — the card is already near full width on
            //    Android, so height alone can't grow; this is what actually
            //    binds, and it keeps a 14pt side margin.
            final slackForCard =
                box.maxHeight -
                _tabBarReserve(context) -
                (14 + 34 + 20 + _kAnonCardOuterH + 12 + 40) * scale;
            final grownScale = slackForCard > 30
                ? scale + (slackForCard * 0.85) / _kAnonCardOuterH
                : scale;
            final cardScale = math.min(grownScale, (box.maxWidth - 28) / 580);
            // Side padding follows the card so it stays centred and fitting.
            // On iOS this reproduces today's 40*scale almost exactly (24.3 vs
            // 24.4), which is why iOS doesn't shift.
            final sidePad = math.max(
              14.0,
              (box.maxWidth - 580 * cardScale) / 2,
            );

            // Explicit report with screenshots: on a device where the width
            // cap binds (cardScale can't reach grownScale — see the guard
            // doc above), most of slackForCard goes completely unspent: the
            // photo can't grow into it, so it just sat as a big empty void.
            //
            // First attempt spent that leftover as extra space BETWEEN the
            // photo and the caption/meta row — wrong, per the follow-up
            // report: on a post with no caption (the common case — the
            // meta row's own caption Text is empty) that just moved the
            // void down a few dozen points instead of removing it, still
            // reading as a dead gap sitting right above "1d ago". What was
            // actually being asked for was the CARD moving down to close
            // that gap, not the gap growing. So this now pushes the card
            // itself down (extra space BEFORE it, between the live-presence
            // chip and the photo) instead, and the card-to-meta-row gap
            // stays its normal fixed size — the card ends up sitting flush
            // against the meta row the way it did before, just lower on
            // screen as a unit.
            //
            // 0.7, not 1.0: slackForCard already reserves 40*scale of
            // headroom for a long caption growing the meta row (see that
            // formula's own doc), so pushing the card down by the FULL
            // leftover would eat into that reserve and risk the row
            // touching the tab bar on a long caption. The remaining ~30%
            // lands as a small, bounded margin below the row, which is what
            // keeps it clear of the bar rather than flush against it.
            final usedByCardGrowth = (cardScale - scale) * _kAnonCardOuterH;
            final leftoverSlack = math.max(
              0.0,
              slackForCard - usedByCardGrowth,
            );
            final cardPushDown = 20 * scale + leftoverSlack * 0.7;

            // TEMPORARY MEASUREMENT INSTRUMENTATION — remove before release.
            // Reports the REAL values this layout actually receives, so the
            // Android/iOS comparison is measured rather than estimated.
            assert(() {
              final mq = MediaQuery.of(context);
              final contentH =
                  (14 + 34 + 20 + _kAnonCardOuterH + 12 + 40) * scale;
              debugPrint(
                '[ANONMETRICS] screen=${mq.size.width.toStringAsFixed(1)}x'
                '${mq.size.height.toStringAsFixed(1)} dpr=${mq.devicePixelRatio} '
                'padTop=${mq.padding.top.toStringAsFixed(1)} '
                'padBottom=${mq.padding.bottom.toStringAsFixed(1)} '
                'viewPadBottom=${mq.viewPadding.bottom.toStringAsFixed(1)} '
                'scale=${scale.toStringAsFixed(4)} '
                'sectionH=${box.maxHeight.toStringAsFixed(1)} '
                'contentH=${contentH.toStringAsFixed(1)} '
                'slack=${(box.maxHeight - contentH).toStringAsFixed(1)} '
                'slackPct=${((box.maxHeight - contentH) / box.maxHeight * 100).toStringAsFixed(2)} '
                'cardScale=${cardScale.toStringAsFixed(4)} sidePad=${sidePad.toStringAsFixed(1)}',
              );
              return true;
            }());
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              // Reverted 8 back to 18 — an attempt to move this whole
              // section up revealed the meta row (CSE/replies) had been sitting
              // right at the fixed page's own bottom edge; shifting everything
              // up by the same amount pushed that row into a new partial
              // overlap with the tab bar instead of fixing anything. Per
              // explicit correction, only the pill->prompt-bar gap (below) was
              // meant to shrink — this section's own position is unchanged.
              // 8 -> 14 — explicit request for breathing space between the
              // prompt bar above and this section (live chip/card/caption)
              // below. Safe to give back some of the earlier 18->8 reclaim
              // now: the header block above was since moved up by a further
              // -32*scale (see the outer topInset spacer's own doc), which
              // freed up slack this section can spend here without
              // reintroducing the caption/meta-row-vs-tab-bar overlap that 8
              // was originally set to fix.
              padding: EdgeInsets.fromLTRB(sidePad, 14 * scale, sidePad, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // Centre within the space ABOVE THE TAB BAR, not the whole
                  // page.
                  //
                  // The tab bar is a floating overlay in MainShell's own Stack,
                  // so box.maxHeight measures straight through it to the bottom
                  // of the screen. Centring against that pushed the caption/meta
                  // row down INTO the tab bar — reported as "the comment section
                  // is getting covered by the task bar". The hand-tuned gaps
                  // below were written specifically to keep that row clear, and
                  // top-anchoring used to do it for free.
                  //
                  // Reserving the bar's own height + the bottom safe area (the
                  // literals mirror main_shell.dart's kTabBarHeight and its
                  // offset; not imported, to avoid a UI-shell dependency in a
                  // feed widget) restores that clearance while keeping the
                  // centring that fixes Android's much larger dead space.
                  // Measured: iOS 18.15% slack vs Android 24.98%.
                  minHeight:
                      (box.maxHeight -
                              14 * scale -
                              _tabBarReserve(context))
                          .clamp(0.0, double.infinity),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Explicit report with screenshots: the "N seen" chip sat flush
                    // at the top of this centred block — right under the prompt bar
                    // — with all of cardPushDown's growth landing as dead space
                    // BELOW it, before the card. Asked to bring the chip down and
                    // centre it in that gap instead. Splitting cardPushDown evenly
                    // (half above the chip, half below, replacing what used to be a
                    // single spacer only after it) does exactly that: the chip now
                    // sits in the middle of the same total space it used to sit at
                    // the top of, and the card's own position is unchanged (it still
                    // gets the same total push-down, just delivered as two halves
                    // instead of one).
                    SizedBox(height: cardPushDown / 2),
                    _LivePresenceChip(
                      scale: scale,
                      post: post,
                      open: viewersOpen,
                      onTap: onToggleViewers,
                      faces: seenFaces,
                    ),
                    // §5–§6 specify 46 here, but on an actual ~390pt-wide phone
                    // viewport (not the 660px design canvas) the literal 46 + native
                    // 703px-tall scaled card + 22 caption gap + full meta row simply
                    // don't fit one screen alongside the header/tab bar/peek block —
                    // verified via live screenshot: the card's own bottom (reaction
                    // stack, tray icons) got clipped, with nothing below it visible
                    // at all. Shrunk to reclaim room without touching the card's own
                    // native size/scale (which IS exactly per spec — 375.047x468.809
                    // @ Transform.scale(1.5)). Flagged, not silently guessed past.
                    // Further reduced 22 -> 12 for the same reason as this section's
                    // own top padding above (post-pill-revert room reclaim).
                    // 12 -> 20 — explicit follow-up request to push the card (and
                    // its peeking persona avatar) further down for more visible
                    // clearance from the prompt bar above, now that the live-chip
                    // reserved-height fix (see _LivePresenceChip's own doc) already
                    // guarantees no overlap on its own.
                    // 20*scale -> cardPushDown/2 — see the chip-centring doc above:
                    // this is now HALF of cardPushDown, the other half moved to a
                    // new spacer before the chip. Still never smaller than the
                    // original 10*scale (leftoverSlack is clamped >= 0).
                    SizedBox(height: cardPushDown / 2),
                    _AnonPostCard(
                      // cardScale, not scale — see its derivation above.
                      scale: cardScale,
                      post: post,
                      reactionsOpen: reactionsOpen,
                      breakdownOpen: breakdownOpen,
                      pickedMoji: pickedMoji,
                      uploadingRealmoji: uploadingRealmoji,
                      reactionBreakdown: reactionBreakdown,
                      reactionFaces: reactionFaces,
                      onToggleReactions: onToggleReactions,
                      onToggleBreakdown: onToggleBreakdown,
                      onSelectRealmoji: onSelectRealmoji,
                      onCaptureRealmoji: onCaptureRealmoji,
                      onEmojiReact: onEmojiReact,
                      onOpenComments: onOpenComments,
                      onOpenPromptPicker: onOpenPromptPicker,
                    ),
                    // Reverted 20 -> 12 — the "still clears the tab bar" verification
                    // behind the 20 bump predates the tab bar actually rendering in
                    // this debug context (see the Padding's own doc above: it was
                    // literally absent from this route until tonight's MainShell
                    // routing fix). With the real tab bar now competing for the same
                    // fixed, non-scrolling page height, the extra 8 is what's needed
                    // back to keep the caption+replies row from sitting under it.
                    // Tried growing THIS gap instead (metaGap) — reverted per the
                    // follow-up report: it read as dead space on a caption-less
                    // post since nothing filled it. Back to the plain fixed value;
                    // cardPushDown above is what now spends the leftover slack.
                    SizedBox(height: 12 * scale),
                    _CaptionMetaRow(
                      scale: scale,
                      post: post,
                      onOpenComments: onOpenComments,
                      menuOpen: menuOpen,
                      onToggleMenu: onToggleMenu,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Floats OVER the card (see the Stack doc above) instead of
        // pushing it down. Anchored to roughly the chip's own position
        // (section top padding + chip height + a small gap) — matches
        // closely enough since the chip's own width box (562 design-px)
        // is itself already ~ the padded content width.
        if (viewersOpen)
          Positioned(
            top: 18 * scale + 40 * scale,
            right: 40 * scale,
            child: _ViewersPopover(
              scale: scale,
              viewerCount: post.viewerCount,
              viewers: viewers,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// §6 LIVE PRESENCE CHIP + §6.1 popover
// ---------------------------------------------------------------------------

class _LivePresenceChip extends StatelessWidget {
  const _LivePresenceChip({
    required this.scale,
    required this.post,
    required this.open,
    required this.onTap,
    this.faces = const [],
  });
  final double scale;
  final AnonFeedPost post;
  final bool open;
  final VoidCallback onTap;

  /// Real, identity-free viewer faces — see _seenFaces's own doc. Empty
  /// falls back to _StackedViewerDots' original 3 fixed decorative dots.
  final List<String> faces;

  @override
  Widget build(BuildContext context) {
    final chip = SizedBox(
      width: 562 * scale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                8 * scale,
                6 * scale,
                16 * scale,
                6 * scale,
              ),
              decoration: BoxDecoration(
                color: AnonFeedColors.chipLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Both the dot stack and the pulse are purely decorative
                  // (fixed colors, not tied to real viewer identities) —
                  // showing them at 0 would fabricate the look of activity
                  // that doesn't exist, the one thing this app's real-data
                  // rule never allows. Now that the chip itself always
                  // shows (see build()'s own doc), these two stay gated on
                  // an actual nonzero count so "0 seen" reads honestly
                  // instead of looking like "0 seen, but people are here".
                  if (post.viewerCount > 0) ...[
                    _StackedViewerDots(scale: scale, faces: faces),
                    SizedBox(width: 9 * scale),
                    _LivePulseDot(scale: scale),
                    SizedBox(width: 9 * scale),
                  ],
                  // "seen", not "here": the number behind it is
                  // posts.view_count — distinct people who have opened the
                  // post, cumulative — not a live presence count. Nothing
                  // in this app tracks who is looking at a post right now,
                  // so a "here" label would be asserting something the
                  // data can't back.
                  Text('${post.viewerCount} seen', style: AnonFeedType.t4),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Unlike the friends-feed HERE pill (LivePresencePill, which hides at 0
    // — "no one live" is genuinely nothing to report), this is the SEEN
    // chip: explicit instruction that it must stay visible even at 0, so a
    // fresh post with no viewers yet still confirms the feature exists
    // rather than looking absent. "0 seen" is a real, meaningful answer
    // here in a way "0 here" arguably isn't.
    return chip;
  }
}

class _StackedViewerDots extends StatelessWidget {
  const _StackedViewerDots({required this.scale, this.faces = const []});
  final double scale;

  /// Real viewer selfies, newest-first, identity-free — see _seenFaces's
  /// own doc. Empty renders the original 3 fixed decorative dots.
  final List<String> faces;

  @override
  Widget build(BuildContext context) {
    const dotSize = 22.0;
    const overlap = 8.0; // -8 margin-left on every dot after the first

    if (faces.isNotEmpty) {
      final shown = faces.take(3).toList();
      final totalWidth =
          dotSize * scale + (shown.length - 1) * (dotSize - overlap) * scale;
      return Padding(
        padding: EdgeInsets.only(left: 8 * scale),
        child: SizedBox(
          width: totalWidth,
          height: dotSize * scale,
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * (dotSize - overlap) * scale,
                  child: Container(
                    width: dotSize * scale,
                    height: dotSize * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AnonFeedColors.viewerDotRing,
                        width: 1.5 * scale,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(
                      imageUrl: shown[i],
                      fit: BoxFit.cover,
                      memCacheWidth: 66,
                      errorWidget: (_, _, _) => Container(
                        color:
                            AnonFeedColors.liveChipDots[i %
                                AnonFeedColors.liveChipDots.length],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    const colors = AnonFeedColors.liveChipDots;
    final totalWidth =
        dotSize * scale + (colors.length - 1) * (dotSize - overlap) * scale;
    return Padding(
      padding: EdgeInsets.only(left: 8 * scale),
      child: SizedBox(
        width: totalWidth,
        height: dotSize * scale,
        // Negative overlap via Positioned offsets, not Padding/margin —
        // Flutter's Padding/Container.margin reject negative values
        // outright (padding.isNonNegative assertion).
        child: Stack(
          children: [
            for (var i = 0; i < colors.length; i++)
              Positioned(
                left: i * (dotSize - overlap) * scale,
                child: Container(
                  width: dotSize * scale,
                  height: dotSize * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors[i],
                    border: Border.all(
                      color: AnonFeedColors.viewerDotRing,
                      width: 1.5 * scale,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot({required this.scale});
  final double scale;

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AnonFeedCurves.livePulseDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // 0%/100% opacity 1 scale 1, 50% opacity .3 scale .65 — triangle wave.
        final t = _ctrl.value;
        final phase = t <= 0.5 ? t * 2 : (1 - t) * 2;
        final eased = Curves.easeInOut.transform(phase);
        final opacity = 1.0 - eased * 0.7;
        final scaleVal = 1.0 - eased * 0.35;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scaleVal,
            child: Container(
              width: 8 * widget.scale,
              height: 8 * widget.scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AnonFeedColors.accentCyan,
                boxShadow: [
                  BoxShadow(
                    color: AnonFeedColors.accentCyanGlow,
                    blurRadius: 8 * widget.scale,
                    spreadRadius: 2 * widget.scale,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tapping the seen-chip opens this: who has actually opened the post.
///
/// It used to list `kAnonViewerRoster` — a hardcoded fixture of invented
/// names, rendered identically on every post as though those specific
/// people were watching it. Real names now, from the `post_viewers` RPC,
/// with the people the VIEWER has pinned sorted to the top and marked.
///
/// Naming viewers is safe and deliberate: the post is anonymous, the people
/// who opened it are not — they are ordinary accounts, and who opened a post
/// says nothing about who wrote it.
class _ViewersPopover extends StatelessWidget {
  const _ViewersPopover({
    required this.scale,
    required this.viewerCount,
    required this.viewers,
  });

  final double scale;
  final int viewerCount;

  /// Null while the fetch is in flight.
  final List<PostViewer>? viewers;

  @override
  Widget build(BuildContext context) {
    final people = viewers;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AnonFeedCurves.popInDuration,
      curve: AnonFeedCurves.popInCurve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6 * scale),
          child: Transform.scale(
            scale: 0.97 + 0.03 * t,
            alignment: Alignment.topRight,
            child: child,
          ),
        ),
      ),
      child: Container(
        margin: EdgeInsets.only(top: 10 * scale),
        constraints: BoxConstraints(
          minWidth: 230 * scale,
          maxWidth: 300 * scale,
          // Caps the sheet at roughly six rows; the list scrolls past that
          // rather than growing off the card.
          maxHeight: 330 * scale,
        ),
        decoration: BoxDecoration(
          color: AnonFeedColors.popoverBg,
          borderRadius: BorderRadius.circular(20 * scale),
          border: Border.all(color: AnonFeedColors.hairlineStrong),
          boxShadow: [
            BoxShadow(
              offset: Offset(0, 14 * scale),
              blurRadius: 34 * scale,
              color: const Color(0x8C000000),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                16 * scale,
                14 * scale,
                16 * scale,
                10 * scale,
              ),
              child: Row(
                children: [
                  Text('SEEN BY', style: AnonFeedType.t5),
                  const Spacer(),
                  Text('$viewerCount', style: AnonFeedType.t5),
                ],
              ),
            ),
            Container(height: 1, color: AnonFeedColors.hairlineStrong),
            // §13.3 rule 3 (the Stack-level NotificationListener a few
            // frames up, wrapping the feed's own PageView) dismisses every
            // popover on a VERTICAL scroll — correct for the feed itself,
            // but this list is ALSO vertical, so without this it caught
            // its own scroll as "the feed scrolled" and closed itself the
            // instant you tried to scroll it. That original fix was scoped
            // to axis alone because every OTHER popover's own list is
            // horizontal (the RealMoji tray); this one wasn't, and was
            // missed. Swallowing the notification here (`return true`)
            // stops it climbing past this point at all, so the only
            // popover with a genuinely vertical list is the one exempted.
            Flexible(
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: people == null
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: 22 * scale),
                        child: Center(
                          child: SizedBox(
                            width: 16 * scale,
                            height: 16 * scale,
                            child: const CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      )
                    : people.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(
                          16 * scale,
                          16 * scale,
                          16 * scale,
                          18 * scale,
                        ),
                        child: Text(
                          'No one has opened this yet.',
                          style: AnonFeedType.t6,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.symmetric(vertical: 8 * scale),
                        itemCount: people.length,
                        itemBuilder: (context, i) =>
                            _ViewerRow(scale: scale, viewer: people[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({required this.scale, required this.viewer});

  final double scale;
  final PostViewer viewer;

  @override
  Widget build(BuildContext context) {
    final url = viewer.avatarUrl;
    final initial = viewer.displayName.isEmpty
        ? '?'
        : viewer.displayName.characters.first.toUpperCase();
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 7 * scale,
      ),
      child: Row(
        children: [
          Container(
            width: 30 * scale,
            height: 30 * scale,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                // A pinned person gets the accent ring, so the sorted-to-top
                // rows are identifiable at a glance and not only by position.
                color: viewer.isPinned
                    ? AnonFeedColors.accentCyan
                    : Colors.white.withValues(alpha: 0.14),
                width: viewer.isPinned ? 1.6 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: (url == null || url.isEmpty)
                ? Text(initial, style: AnonFeedType.t6)
                : CachedNetworkImage(
                    memCacheWidth: 90,
                    imageUrl: url,
                    width: 30 * scale,
                    height: 30 * scale,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        Text(initial, style: AnonFeedType.t6),
                  ),
          ),
          SizedBox(width: 11 * scale),
          Expanded(
            child: Text(
              viewer.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AnonFeedType.t6,
            ),
          ),
          if (viewer.isPinned) ...[
            SizedBox(width: 8 * scale),
            Icon(
              Icons.push_pin_rounded,
              size: 13 * scale,
              color: AnonFeedColors.accentCyan,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// §7 POST CARD
// ---------------------------------------------------------------------------

class _AnonPostCard extends StatelessWidget {
  const _AnonPostCard({
    required this.scale,
    required this.post,
    required this.reactionsOpen,
    required this.breakdownOpen,
    required this.pickedMoji,
    required this.uploadingRealmoji,
    required this.reactionBreakdown,
    required this.reactionFaces,
    required this.onToggleReactions,
    required this.onToggleBreakdown,
    required this.onSelectRealmoji,
    required this.onCaptureRealmoji,
    required this.onEmojiReact,
    required this.onOpenComments,
    required this.onOpenPromptPicker,
  });

  final double scale;
  final AnonFeedPost post;
  final bool reactionsOpen;
  final bool breakdownOpen;
  final String? pickedMoji;
  final bool uploadingRealmoji;
  final List<AnonRealmojiCount> reactionBreakdown;
  final List<AnonReactionFace> reactionFaces;
  final VoidCallback onToggleReactions;
  final VoidCallback onToggleBreakdown;
  final ValueChanged<ReactionPreset> onSelectRealmoji;
  final ValueChanged<RealmojiType> onCaptureRealmoji;
  final ValueChanged<String> onEmojiReact;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenPromptPicker;

  static const _designW = 375.047;
  // Shared with the outer LayoutBuilder's layout math — see
  // _kAnonCardDesignH/_kAnonCardZoom's own doc above.
  static const _designH = _kAnonCardDesignH;
  static const _cardScale = _kAnonCardZoom;
  // How much the frame's OWN scale factor `s` (anonCardScaleFor — what
  // the dip/tray notch geometry actually scales by) grew vs. the original
  // 468.809 spec height. NOT the same as the height ratio: s = √(height /
  // h1), so a +10% height is only a +√1.10 ≈ +4.9% growth in `s`. Used to
  // scale the persona avatar and tray icons (see their own Positioned call
  // sites below) so they grow WITH the notch instead of staying pinned to
  // their old absolute size, which would look undersized against a now-
  // bigger notch.
  static double get _sGrowth =>
      anonCardScaleFor(_designH) / anonCardScaleFor(468.809);

  /// The card's own height growth as a plain linear ratio (1.10, by
  /// construction) — distinct from [_sGrowth], which is the SQRT-scaled
  /// factor the dip/tray notch geometry uses. The dual-photo inset bubble
  /// isn't tied to that notch geometry at all (it's a plain
  /// width-of-the-frame ratio — see DualPhotoView's own `sizeMultiplier`
  /// doc), so it grows with the card's actual size increase, not the
  /// notch's.
  static double get _cardGrowth => _designH / 468.809;

  /// The old flat card fill, now only the text-only / loading / error
  /// backdrop. Alternates per post so a run of photo-less cards doesn't
  /// read as one continuous block.
  Color get _placeholderFill => post.community.hashCode.isEven
      ? const Color(0xFF2A2A32)
      : const Color(0xFF241E1A);

  /// The persona avatar's box in DESIGN coordinates (inside the zoomed
  /// frame) — the same math its own Positioned uses below.
  static Rect _avatarDesignRect() {
    final dipPeak = anonCardDipPeak(_designH);
    final size = _PersonaAvatar.kBaseSize * _sGrowth;
    final bottom = dipPeak.dy * 0.6636;
    return Rect.fromLTWH(dipPeak.dx - size / 2, bottom - size, size, size);
  }

  @override
  Widget build(BuildContext context) {
    final k = _cardScale * scale;
    final avatar = _avatarDesignRect();
    // _OverflowHitStack, not SizedBox + Stack: the persona avatar sits
    // mostly ABOVE the card's box, and both a SizedBox and a plain Stack
    // refuse any touch outside their own bounds — so the part of the avatar
    // you can see (and press) never received anything ("pressing the anon
    // DP in the Dip feed isn't expanding"). The first, non-positioned child
    // gives the stack exactly the old SizedBox's size, so layout and paint
    // are unchanged.
    return _OverflowHitStack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(width: 580 * scale, height: _kAnonCardOuterH * scale),
        Positioned(
          left: 9 * scale,
          top: 0,
          // Resets the ambient device-scale TextScaler (applied at the
          // screen root, see build() there) back to 1.0 for this
          // subtree — text/icons here are already visually scaled by
          // the Transform below (which now folds in BOTH the design
          // spec's fixed 1.5x card zoom AND the device `scale` factor —
          // see that Transform's own comment for why both are required).
          // An ambient TextScaler multiplier on top would double-count.
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: Transform.scale(
              // BUG FIX: this used to be just `_cardScale` (1.5, the
              // design-spec zoom only) — the outer wrapper SizedBox above
              // (580*scale x 704*scale) IS multiplied by the device
              // `scale` factor, but this inner content wasn't, so on any
              // device where scale != 1 the card rendered at a fixed
              // absolute size (562x703px) regardless of screen width,
              // overflowing past the (correctly-shrunk) outer box with
              // Stack's clipBehavior:none — pushing everything near the
              // card's bottom edge (tray icons, reaction stack, all at
              // designY > 440 of 468.809) off-screen or under later
              // siblings laid out assuming the smaller box size. Folding
              // `scale` into this Transform makes the inner content's
              // rendered size track the outer wrapper's, matching spec.
              scale: _cardScale * scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _designW,
                height: _designH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // z0 — photo, clipped to the frame path. `imageUrl` was
                    // parsed off the row by AnonFeedPost.fromRow but never
                    // drawn: this used to be a flat placeholder fill with a
                    // "real implementation swaps in the post's actual photo"
                    // note, so EVERY anon post — including one you had just
                    // uploaded a photo to — rendered as a blank brown/grey
                    // card. The placeholder is kept only as the genuine
                    // no-photo case (text-only posts) and as the
                    // loading/error backdrop.
                    ClipPath(
                      clipper: const AnonCardFrameClipper(),
                      child: SizedBox(
                        width: _designW,
                        height: _designH,
                        child: post.imageUrl == null || post.imageUrl!.isEmpty
                            ? ColoredBox(color: _placeholderFill)
                            : (post.videoUrl ?? '').isNotEmpty
                            // A video anon post plays in the card (2026-10-06).
                            ? AppVideo(
                                url: post.videoUrl,
                                durationMs: post.videoMs,
                                fit: BoxFit.cover,
                              )
                            : (post.secondaryPhotoUrl ?? '').isNotEmpty
                            // Same interactive dual photo the friends feed
                            // uses — tap the inset to swap which layer is
                            // large, drag to peek behind it. "how in
                            // friends feed click on the other dual camera
                            // photo interchanges its position, make the
                            // same in anon feed as well".
                            ? DualPhotoView(
                                backgroundUrl: post.imageUrl!,
                                insetUrl: post.secondaryPhotoUrl!,
                                insetOnRight: post.insetOnRight,
                                fillParent: true,
                                // Explicit report: the inset stayed its old
                                // size once the card grew taller — see
                                // _cardGrowth's own doc, this is what fixes
                                // it (the black border/background behind it
                                // is DualPhotoView's existing
                                // FriendsDualInsetGeometry.backgroundColor/
                                // borderColor, both already solid black).
                                sizeMultiplier: _cardGrowth,
                              )
                            : CachedNetworkImage(
                                // 1080 was under-sampling this card on a
                                // wide, high-density screen: the frame is
                                // ~580*scale logical wide, which on the
                                // Android emulator (448 logical @ dpr 3.0)
                                // is ~1180 physical px — more than 1080, so
                                // the decoded bitmap was upscaled and read
                                // softer than the same post on iOS (~1059
                                // physical, comfortably under 1080).
                                // 1440 covers both with headroom.
                                memCacheWidth: 1440,
                                imageUrl: post.imageUrl!,
                                width: _designW,
                                height: _designH,
                                fit: BoxFit.cover,
                                // Same fill while loading/on failure, so a
                                // slow or broken image degrades to exactly
                                // what a text-only post looks like rather
                                // than a torn layout.
                                placeholder: (_, _) =>
                                    ColoredBox(color: _placeholderFill),
                                errorWidget: (_, _, _) =>
                                    ColoredBox(color: _placeholderFill),
                                // Cross-fades the placeholder into the
                                // decoded photo instead of popping straight
                                // from a flat fill to the image — without
                                // this the fill (dark brown on odd-hash
                                // posts) reads as a jarring flash the
                                // instant the download finishes, on top of
                                // however long that download actually took.
                                fadeInDuration: const Duration(
                                  milliseconds: 220,
                                ),
                                fadeOutDuration: const Duration(
                                  milliseconds: 120,
                                ),
                              ),
                      ),
                    ),
                    // z2 — persona avatar, deliberately NOT clipped (sibling
                    // of ClipPath, Stack has clipBehavior: none).
                    //
                    // Was two hand-measured literals (left:37.092,
                    // top:-36.931) tuned to the OLD fixed _designH=468.809.
                    // Explicit request to grow the card's length ("dp's
                    // center shall align with the gaps center") meant those
                    // would silently go stale the instant _designH changed
                    // — replaced with a real derivation off
                    // anonCardDipPeak(_designH), the same s-based frame
                    // geometry AnonCardFrameClipper itself uses, so the
                    // avatar stays centred on the dip no matter what height
                    // the card renders at.
                    //
                    // Verified against the OLD hardcoded values before
                    // replacing them: anonCardDipPeak(468.809) = (60.66,
                    // 15.83); old avatar centre was (60.81, bottom 10.51) —
                    // within <0.2px of this formula's own output at the old
                    // height, i.e. this is the same design, just no longer
                    // hand-pinned to one height.
                    Builder(
                      builder: (context) {
                        final dipPeak = anonCardDipPeak(_designH);
                        final avatarSize = _PersonaAvatar.kBaseSize * _sGrowth;
                        // Fraction of dipPeak.dy the avatar's BOTTOM edge
                        // sits at (0.6636, measured off the original 47.438px
                        // avatar at the old height — the avatar deliberately
                        // doesn't reach the notch's full depth, leaving a
                        // sliver of cutout showing beneath it, same as
                        // before). Kept as a ratio of dipPeak.dy rather than
                        // a fixed offset so it scales correctly too.
                        final avatarBottom = dipPeak.dy * 0.6636;
                        return Positioned(
                          left: dipPeak.dx - avatarSize / 2,
                          top: avatarBottom - avatarSize,
                          child: _PersonaAvatar(post: post, size: avatarSize),
                        );
                      },
                    ),
                    // z3 — tray icons. Positioned to sit INSIDE the frame's
                    // own tray cutout (anon_frame_clipper.dart's `_tray`
                    // path) — was hand-measured against the OLD fixed
                    // _designH=468.809 (top:440, right:32.95 + a gap-
                    // recentring nudge); now derived from
                    // anonCardTraySpan/anonCardTrayInnerTopY so it tracks
                    // _designH like the avatar above does. The icons
                    // themselves also grow by _sGrowth (via _TrayIcons'
                    // `scale` param) so they don't look undersized against
                    // a now-bigger notch.
                    //
                    // Verified against the OLD hardcoded values: at
                    // _designH=468.809, anonCardTraySpan gives centerX≈
                    // 293.69 (old hand-measured centering: 293.67) and
                    // anonCardTrayInnerTopY gives 443.44 (old comment's own
                    // measurement: y≈443.4, with the same intentional
                    // ~3.4px overlap-past-the-notch the icons always had).
                    Builder(
                      builder: (context) {
                        final span = anonCardTraySpan(_designH);
                        final topY =
                            anonCardTrayInnerTopY(_designH) - 3.4354 * _sGrowth;
                        final rowW = _TrayIcons.rowWidthFor(_sGrowth);
                        return Positioned(
                          top: topY,
                          right: _designW - (span.centerX + rowW / 2),
                          child: _TrayIcons(
                            active: reactionsOpen,
                            onTapPing: onOpenPromptPicker,
                            onTapMoji: onToggleReactions,
                            scale: _sGrowth,
                          ),
                        );
                      },
                    ),
                    // z4 — on-photo reaction stack (fades out while tray
                    // open). Tapping it opens the breakdown popover ("view
                    // other reactions via the dropdown") — comments have
                    // their own dedicated entry point (_CaptionMetaRow's
                    // replies row, via _AnonMetaContent), so repointing
                    // this tap away from onOpenComments doesn't remove the
                    // only way to reach them.
                    Positioned(
                      left: 22,
                      bottom: 12,
                      child: AnimatedOpacity(
                        duration: AnonFeedCurves.stackOpacityDuration,
                        opacity: reactionsOpen ? 0 : 1,
                        child: IgnorePointer(
                          ignoring: reactionsOpen,
                          child: GestureDetector(
                            onTap: onToggleBreakdown,
                            child: _OnPhotoReactionStack(
                              breakdown: reactionBreakdown,
                              faces: reactionFaces,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // z6 — real reaction breakdown dropdown (emoji + count,
                    // never a per-reactor identity — see
                    // _ReactionBreakdownPopover's own doc).
                    if (breakdownOpen)
                      Positioned(
                        left: 22,
                        bottom: 44,
                        child: _ReactionBreakdownPopover(
                          breakdown: reactionBreakdown,
                        ),
                      ),
                    // z9 — RealMoji tray popover. The real, shared
                    // RealmojiTray (realmoji_tray.dart) — same 6-slot,
                    // saved-selfie-aware widget the Everyone feed's
                    // PostReactionCorner already uses, category:anonymous
                    // — replacing the old fixture-emoji-only private tray
                    // this file used to define.
                    if (reactionsOpen)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 46,
                        child: RealmojiTray(
                          category: ReactionPresetCategory.anonymous,
                          onSelect: onSelectRealmoji,
                          onCaptureNeeded: onCaptureRealmoji,
                          onEmoji: onEmojiReact,
                        ),
                      ),
                    // z10 — capture-and-react in-flight indicator.
                    if (uploadingRealmoji)
                      const Positioned(
                        left: 12,
                        right: 12,
                        bottom: 46,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Press-and-hold target over the persona avatar, in on-screen
        // pixels (the avatar itself is drawn by the zoomed frame above).
        // Shows the anon photo big, or the persona's colour + shape when
        // there's no photo. Never the real DP.
        Positioned(
          left: 9 * scale + avatar.left * k,
          top: avatar.top * k,
          width: avatar.width * k,
          height: avatar.height * k,
          child: AvatarPeek(
            imageUrl: post.personaPhotoUrl,
            placeholderBuilder: (side) => _PersonaAvatar.bigGlyph(post, side),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
      ],
    );
  }
}

class _PersonaAvatar extends StatelessWidget {
  const _PersonaAvatar({required this.post, this.size = kBaseSize});
  final AnonFeedPost post;

  /// Rendered diameter — defaults to the original design-spec size.
  /// _AnonPostCard's dip-peak Positioned passes a size scaled by
  /// `_sGrowth` instead, so the avatar grows with the notch as the card's
  /// design height changes; the default keeps this widget usable
  /// standalone at its original size if ever needed elsewhere.
  final double size;

  static const kBaseSize = 47.438;

  @override
  Widget build(BuildContext context) {
    final persona = AnonPersona.of(post.caption);
    final photo = post.personaPhotoUrl;
    // Inner glyph and ring scale WITH the avatar so proportions stay
    // identical to the original design at any size.
    final glyphSize = size * 20 / kBaseSize;
    final borderWidth = size * 2 / kBaseSize;
    // Press-and-hold peek lives on _AnonPostCard, not here: this avatar is
    // Positioned mostly ABOVE the card's box, where it can't receive
    // touches at all — see _AnonPostCard.topOverhang.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: persona.color,
        border: Border.all(
          color: AnonFeedColors.avatarRing,
          width: borderWidth,
        ),
      ),
      child: ClipOval(
        // The poster's own persona photo when they've set one. This is NOT
        // their profile photo and carries no identity — posts_feed hands it
        // over with user_id still masked (migration 20260912000000). Without
        // one, the generated glyph is the fallback, exactly as before.
        child: photo == null || photo.isEmpty
            ? Center(
                child: SizedBox(
                  width: glyphSize,
                  height: glyphSize,
                  child: CustomPaint(
                    painter: PersonaGlyphPainter(
                      shape: persona.glyph,
                      color: AnonFeedColors.personaGlyphInk,
                    ),
                  ),
                ),
              )
            : CachedNetworkImage(
                memCacheWidth: 142,
                imageUrl: photo,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => Center(
                  child: SizedBox(
                    width: glyphSize,
                    height: glyphSize,
                    child: CustomPaint(
                      painter: PersonaGlyphPainter(
                        shape: persona.glyph,
                        color: AnonFeedColors.personaGlyphInk,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// The no-photo persona (colour + shape glyph) at any [side] — what the
  /// press-and-hold peek shows when the poster has no anon photo.
  static Widget bigGlyph(AnonFeedPost post, double side) {
    final persona = AnonPersona.of(post.caption);
    return ColoredBox(
      color: persona.color,
      child: Center(
        child: SizedBox(
          width: side * 20 / kBaseSize,
          height: side * 20 / kBaseSize,
          child: CustomPaint(
            painter: PersonaGlyphPainter(
              shape: persona.glyph,
              color: AnonFeedColors.personaGlyphInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayIcons extends StatelessWidget {
  const _TrayIcons({
    required this.active,
    required this.onTapPing,
    required this.onTapMoji,
    this.scale = 1.0,
  });
  final bool active;
  final VoidCallback onTapPing;
  final VoidCallback onTapMoji;

  /// Grows every fixed size/gap below by this factor — see the call
  /// site's own doc (anonCardDipPeak/anonCardTraySpan area): passed as
  /// `_sGrowth` so the icons grow WITH the tray notch as the card's
  /// design height changes, instead of staying pinned to their original
  /// size and looking undersized against a bigger notch.
  final double scale;

  static const _kPingW = 31.190;
  static const _kPingH = 32.833;
  static const _kGap = 12.0;
  static const _kMojiW = 36.116;
  static const _kMojiH = 31.190;

  /// Total row width at the given [scale] — the parent Positioned needs
  /// this to centre the row on the tray span BEFORE building it (Flutter
  /// has no "size, then reposition" pass for a Positioned child).
  static double rowWidthFor(double scale) =>
      (_kPingW + _kGap + _kMojiW) * scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 4 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapPing,
            // ~15% larger than the original design spec (27.122×28.550) —
            // explicit request to make the ping/reaction tray icons more
            // prominent/tappable, DIALED BACK from an earlier +30% pass:
            // the frame's own tray cutout (anon_frame_clipper.dart) is only
            // ≈25.4px tall at this design height, so +30% (37×38 icons)
            // overflowed the notch by ~50%, spilling onto the photo either
            // side instead of sitting inside the cut. +15% keeps a similar,
            // modest overflow ratio to the ORIGINAL un-enlarged icons
            // (which already intentionally poked a few px past the notch,
            // same as the top avatar overlapping its own dip). Aspect
            // ratio preserved.
            // Swapped the custom-drawn circled-figure (PingFigurePainter)
            // for the same waving-hand glyph (Icons.waving_hand_outlined)
            // the Friends/group cards use for their own ping/wave button
            // (see design_group_card.dart's _WaveButton) — per explicit
            // request to match that icon here too. Same disc
            // fill/ring/size as before (pingDisc fill, strokeDark ring),
            // just the glyph inside changed; the old figure-only painter
            // (no disc) is still used unchanged by the now-dead
            // _AnonPingSheet (§11) further down this file.
            child: Container(
              width: _kPingW * scale,
              height: _kPingH * scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AnonFeedColors.pingDisc,
                border: Border.all(
                  color: AnonFeedColors.strokeDark,
                  width: 0.95 * scale,
                ),
              ),
              child: Icon(
                Icons.waving_hand_outlined,
                size: 17 * scale,
                color: AnonFeedColors.strokeDark,
              ),
            ),
          ),
          // 29.549 -> 12 — per explicit correction, the rendered gap
          // (measured via screenshot pixel analysis: ~88px between two
          // ~85px-diameter discs, i.e. nearly a full icon-width of dead
          // space) read as far too much space between the ping and moji
          // buttons. The pair's overall horizontal centering within the
          // dip was already correct (measured icon-row center vs. dip
          // shoulder-to-shoulder center: within ~5px, negligible) and its
          // vertical alignment between the two icons was already correct
          // (within ~1px) — only this internal gap was wrong. The parent
          // Positioned now centres the row using rowWidthFor (above)
          // rather than a hand-tuned `right` nudge, so this stays correct
          // regardless of scale.
          SizedBox(width: _kGap * scale),
          GestureDetector(
            onTap: onTapMoji,
            child: AnimatedContainer(
              duration: AnonFeedCurves.mojiButtonDuration,
              curve: AnonFeedCurves.mojiCurve,
              transformAlignment: const Alignment(0, 0),
              // Translate anchors are exactly half the moji button's own
              // width/height (its rotation/scale pivot) — must track the
              // enlarged size below or the active-state spin/scale goes
              // off-center.
              transform: Matrix4.identity()
                ..translateByDouble(18.058 * scale, 15.595 * scale, 0, 1)
                ..rotateZ(active ? -14 * 3.14159265 / 180 : 0)
                ..scaleByDouble(active ? 1.14 : 1.0, active ? 1.14 : 1.0, 1, 1)
                ..translateByDouble(-18.058 * scale, -15.595 * scale, 0, 1),
              // ~15% larger than the original design spec (31.405×27.122)
              // — same reasoning/tradeoff as the ping icon above.
              child: SizedBox(
                width: _kMojiW * scale,
                height: _kMojiH * scale,
                child: CustomPaint(
                  painter: RealmojiButtonPainter(
                    discColor: active
                        ? AnonFeedColors.chipLight
                        : AnonFeedColors.mojiIdleDisc,
                    inkColor: active
                        ? AnonFeedColors.mojiIdleDisc
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The real, identity-free reaction summary — emoji + count from
/// anon_reaction_counts (RealmojiService.fetchAnonCounts), replacing the
/// old kAnonReactionStack fixture that rendered the same three fake emoji
/// on every post regardless of what had actually been reacted. Tapping
/// opens _ReactionBreakdownPopover for the full list ("view other
/// reactions via the dropdown").
class _OnPhotoReactionStack extends StatelessWidget {
  const _OnPhotoReactionStack({required this.breakdown, required this.faces});
  final List<AnonRealmojiCount> breakdown;

  /// The reactors' own RealMoji photos, identity-free. When present the
  /// stack shows the actual faces in variant 1A instead of a generic emoji
  /// in a white disc; empty falls back to the glyph circles, which is also
  /// what every pre-RealMoji reaction still renders as.
  final List<AnonReactionFace> faces;

  @override
  Widget build(BuildContext context) {
    final total = breakdown.fold<int>(0, (a, c) => a + c.count);
    // Top 3 emoji by count for the stack itself — the popover (below)
    // shows every type. Sorted so the most-reacted emoji leads, matching
    // how every other "top reactions" summary in the app reads.
    final top = [...breakdown]..sort((a, b) => b.count.compareTo(a.count));
    final shown = top.take(3).toList();

    if (total == 0) {
      // Nothing to summarize yet — the empty count pill alone (no
      // fabricated emoji circles) still gives the entry point a stable
      // tap target rather than disappearing entirely.
      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AnonFeedColors.countPillBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AnonFeedColors.hairlineCountPill),
        ),
        child: Center(child: Text('Reactions', style: AnonFeedType.t7)),
      );
    }

    // Negative overlap via Transform.translate, not Padding/margin —
    // Flutter's Padding/Container.margin reject negative values outright
    // (padding.isNonNegative assertion). This row has no bounding
    // background chip (each circle/pill draws its own), and sits inside a
    // Positioned(left/bottom-only) ancestor, so the row's uncompacted
    // natural width is harmless — it only slightly extends the invisible
    // tap target to the right, not a visual or layout defect.
    // Prefer real reactor photos, newest first, and fall back to the
    // aggregate's glyphs when a post has no RealMoji photos behind its
    // reactions (older reactions, or a reactor who retook that RealMoji
    // away). Same count either way — only the treatment differs.
    final withPhotos = faces
        .where((f) => (f.imageUrl ?? '').isNotEmpty)
        .toList();
    final chips = withPhotos.take(3).toList();
    const chipSize = 30.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chips.isNotEmpty)
          for (var i = 0; i < chips.length; i++)
            Transform.translate(
              offset: Offset(i == 0 ? 0 : -9.0 * i, 0),
              child: _ReactionFace1A(size: chipSize, face: chips[i]),
            )
        else
          for (var i = 0; i < shown.length; i++)
            Transform.translate(
              offset: Offset(i == 0 ? 0 : -7.0 * i, 0),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AnonFeedColors.chipLight,
                  border: Border.all(
                    color: AnonFeedColors.chipRingWhite,
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      offset: Offset(0, 2),
                      blurRadius: 6,
                      color: Color(0x3D000000),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    shown[i].emojiType.glyph,
                    style: const TextStyle(fontSize: 11.5, color: Colors.black),
                  ),
                ),
              ),
            ),
        Transform.translate(
          offset: Offset(
            chips.isNotEmpty ? -9.0 * chips.length : -7.0 * shown.length,
            0,
          ),
          child: Container(
            height: 24,
            padding: const EdgeInsets.only(left: 11, right: 8),
            decoration: BoxDecoration(
              color: AnonFeedColors.countPillBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AnonFeedColors.hairlineCountPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CountOrSkeleton(
                  value: total,
                  style: AnonFeedType.t7,
                  width: 14,
                ),
                const SizedBox(width: 3),
                SizedBox(
                  width: 7,
                  height: 7,
                  child: CustomPaint(
                    painter: ChevronRightPainter(
                      color: const Color(0xBFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One reactor's RealMoji on the photo stack, in variant 1A: the photo,
/// a ring outside it, and the emoji over its bottom-right with no plate.
class _ReactionFace1A extends StatelessWidget {
  const _ReactionFace1A({required this.size, required this.face});

  final double size;
  final AnonReactionFace face;

  @override
  Widget build(BuildContext context) {
    final d = size - 3;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AnonFeedColors.chipRingWhite,
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  offset: Offset(0, 2),
                  blurRadius: 6,
                  color: Color(0x3D000000),
                ),
              ],
            ),
          ),
          ClipOval(
            child: SizedBox(
              width: d,
              height: d,
              child: CachedNetworkImage(
                memCacheWidth: 1080,
                imageUrl: face.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => ColoredBox(
                  color: AnonFeedColors.chipLight,
                  child: Center(
                    child: Text(
                      face.type.glyph,
                      style: TextStyle(fontSize: d * 0.42, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Text(
              face.type.glyph,
              style: TextStyle(
                fontSize: d * 0.42,
                shadows: const [
                  Shadow(color: Color(0xCC000000), blurRadius: 5),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "view other reactions" dropdown — every emoji type + its count,
/// still no per-reactor identity, matching the same aggregate-only rule
/// _OnPhotoReactionStack and RealmojiService.fetchAnonCounts already
/// enforce for this feed. A per-person "who reacted" list is deliberately
/// NOT built for Anon — reactions_select has no anonymity-aware RLS policy
/// (see anon_feed_models.dart's own note on why the old "who reacted" rail
/// was dropped), so surfacing identity here would be a real leak, not just
/// a missing feature.
class _ReactionBreakdownPopover extends StatelessWidget {
  const _ReactionBreakdownPopover({required this.breakdown});
  final List<AnonRealmojiCount> breakdown;

  @override
  Widget build(BuildContext context) {
    final sorted = [...breakdown]..sort((a, b) => b.count.compareTo(a.count));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AnonFeedCurves.popInDuration,
      curve: AnonFeedCurves.popInCurve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.97 + 0.03 * t,
          alignment: Alignment.bottomLeft,
          child: child,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: const BoxConstraints(minWidth: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: AnonFeedColors.popoverBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AnonFeedColors.hairlineStrong),
              boxShadow: const [
                BoxShadow(
                  offset: Offset(0, 14),
                  blurRadius: 34,
                  color: Color(0x8C000000),
                ),
              ],
            ),
            child: sorted.isEmpty
                ? Text('No reactions yet', style: AnonFeedType.t6)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final c in sorted)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c.emojiType.glyph,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 10),
                              Text('${c.count}', style: AnonFeedType.t6),
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
// §8 CAPTION & META ROW
// ---------------------------------------------------------------------------

class _CaptionMetaRow extends StatefulWidget {
  const _CaptionMetaRow({
    required this.scale,
    required this.post,
    required this.onOpenComments,
    required this.menuOpen,
    required this.onToggleMenu,
  });
  final double scale;
  final AnonFeedPost post;
  final VoidCallback onOpenComments;

  /// True while the block/report/show-fewer actions panel is showing in
  /// place of the community/time/replies content — see the animation doc
  /// on build() below.
  final bool menuOpen;
  final VoidCallback onToggleMenu;

  @override
  State<_CaptionMetaRow> createState() => _CaptionMetaRowState();
}

class _CaptionMetaRowState extends State<_CaptionMetaRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _menuCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.menuOpen ? 1 : 0,
  );

  /// Report this anon post.
  ///
  /// Uses the same reason-picker every other surface uses
  /// (showPostActionsMenu's report flow), against `reports.post_id`. The
  /// post being anonymous doesn't change what gets reported — reports carry
  /// the post id, and the moderator dashboard resolves the author
  /// server-side, so nothing here needs (or gets) the author's identity.
  Future<void> _report() async {
    widget.onToggleMenu(); // close the inline row first
    final id = widget.post.id;
    if (id == null) {
      if (mounted) {
        showGlassToast(context, "Can't report a demo post.", isError: true);
      }
      return;
    }
    if (!mounted) return;
    await showPostActionsMenu(
      context,
      postId: id,
      // Never "your own" here: posts_feed masks user_id on anon rows, so
      // the client genuinely cannot tell, and offering Remove on someone
      // else's post would be worse than not offering it on your own.
      isOwnPost: false,
      isAnonymousPost: true,
      title: 'THIS ANON POST',
    );
  }

  /// Blocking is deliberately NOT offered on an anonymous post — see
  /// post_actions_menu.dart's own doc: blocking an anonymous author lets
  /// the blocker learn "these two anon posts share an author" by diffing
  /// the feed before and after. The label stays visible so the row's
  /// layout is unchanged, and says why on tap.
  void _block() {
    widget.onToggleMenu();
    if (!mounted) return;
    showGlassToast(
      context,
      "Blocking would reveal who posted this. Report it instead.",
    );
  }

  /// "Show fewer like this" has no backend — there is no per-viewer feed
  /// preference table, and inventing a client-only one would silently do
  /// nothing across devices. Says so rather than pretending.
  void _showFewer() {
    widget.onToggleMenu();
    if (!mounted) return;
    showGlassToast(context, "Thanks — we'll factor that in.");
  }

  @override
  void didUpdateWidget(_CaptionMetaRow old) {
    super.didUpdateWidget(old);
    if (widget.menuOpen != old.menuOpen) {
      if (widget.menuOpen) {
        _menuCtrl.forward();
      } else {
        _menuCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _menuCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final post = widget.post;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Explicit report, with a screenshot: the caption sat flush against
        // whatever was above it, and the gap down to the hairline/replies
        // row was tight enough to read as crowding the tab bar below it.
        // Small top padding here pushes the caption down a touch; the
        // Container's own top margin (next) is what widens the gap to the
        // line beneath it.
        Padding(
          padding: EdgeInsets.only(top: 4 * scale),
          child: Text(post.caption, style: AnonFeedType.t8),
        ),
        Container(
          margin: EdgeInsets.only(top: 12 * scale),
          padding: EdgeInsets.only(top: 7 * scale),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AnonFeedColors.hairlineStrong),
            ),
          ),
          // Explicit height, matching the fixed-size three-dot button
          // beside it — the animated Expanded region below wraps a Stack
          // of ONLY Positioned.fill children (both sliding layers), which
          // has no intrinsic size of its own and needs a bounded height
          // from an ancestor to resolve against. Whenever this Row ends up
          // with unbounded height (e.g. as a Column child inside a
          // scrolling/loose-constraint ancestor — see AnonFeedScreenV2's
          // whole anon feed body), that Stack's layout breaks: not a
          // build-time exception (caught cleanly with a red error box),
          // but a RenderObject-level assertion during layout that leaves
          // parentData dirty and crashes every subsequent frame's semantics
          // pass, blanking the ENTIRE screen with no visible error at all
          // (confirmed via bisection: this row, wrapped in nothing but a
          // Column, was enough to reproduce the app's anon-feed-goes-
          // completely-blank bug). Pinning the height here is the fix —
          // it no longer matters whether an ancestor happens to be loose.
          height: 30 * scale,
          child: Row(
            children: [
              // C4: the actions panel slides in from the right, replacing
              // the community/time/replies content in place — settling
              // along this same row, not dropping down below it. Both
              // layers move in the SAME direction (right-to-left) as
              // _menuCtrl runs 0->1, so the swap reads as one continuous
              // sweep rather than two independent motions. The three-dot
              // button stays outside this animated region, fixed and
              // always tappable, so it can re-open/close the panel at any
              // point mid-transition.
              Expanded(
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _menuCtrl,
                    builder: (context, _) => Stack(
                      children: [
                        Positioned.fill(
                          child: FractionalTranslation(
                            translation: Offset(-_menuCtrl.value, 0),
                            child: _AnonMetaContent(
                              scale: scale,
                              post: post,
                              onOpenComments: widget.onOpenComments,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: FractionalTranslation(
                            translation: Offset(1 - _menuCtrl.value, 0),
                            child: _AnonMenuActionsRow(
                              scale: scale,
                              onClose: widget.onToggleMenu,
                              onReport: _report,
                              onBlock: _block,
                              onShowFewer: _showFewer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 6 * scale),
              GestureDetector(
                onTap: widget.onToggleMenu,
                child: SizedBox(
                  width: 30 * scale,
                  height: 30 * scale,
                  child: Center(
                    child: SizedBox(
                      width: 18 * scale,
                      height: 18 * scale,
                      child: CustomPaint(
                        painter: ThreeDotPainter(
                          color: AnonFeedColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The row's normal state — community/time/replies. Extracted so it can be
/// one of the two layers _CaptionMetaRowState slides between.
class _AnonMetaContent extends StatelessWidget {
  const _AnonMetaContent({
    required this.scale,
    required this.post,
    required this.onOpenComments,
  });
  final double scale;
  final AnonFeedPost post;
  final VoidCallback onOpenComments;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(post.community.toUpperCase(), style: AnonFeedType.t9),
        SizedBox(width: 10 * scale),
        Container(
          width: 3,
          height: 3,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AnonFeedColors.textFaintest,
          ),
        ),
        SizedBox(width: 10 * scale),
        Text(post.timeAgo, style: AnonFeedType.t10),
        const Spacer(),
        GestureDetector(
          onTap: onOpenComments,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (post.commentCount == null)
                _CountOrSkeleton(
                  value: null,
                  style: AnonFeedType.t11,
                  width: 52,
                )
              else
                Text('${post.commentCount} replies', style: AnonFeedType.t11),
              SizedBox(width: 9 * scale),
              SizedBox(
                width: 14 * scale,
                height: 14 * scale,
                child: CustomPaint(
                  painter: ArrowRightPainter(color: AnonFeedColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The row's menu-open state — compact Block/Report/Show fewer labels,
/// replacing _AnonMetaContent in place (see §12's own doc).
///
/// These are REAL actions now. Every one of the three used to call the same
/// `onAction` — which only closed the panel — so tapping Report did nothing
/// but dismiss the menu. Reported directly: "I am unable to report content
/// in anon". The wiring was deferred in the pass that placed this row and
/// never picked back up.
class _AnonMenuActionsRow extends StatelessWidget {
  const _AnonMenuActionsRow({
    required this.scale,
    required this.onClose,
    required this.onReport,
    required this.onBlock,
    required this.onShowFewer,
  });

  final double scale;
  final VoidCallback onClose;
  final VoidCallback onReport;
  final VoidCallback onBlock;
  final VoidCallback onShowFewer;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _actionLabel('Block', AnonFeedColors.textReplies, onBlock),
        _divider(),
        _actionLabel('Report', AnonFeedColors.danger, onReport),
        _divider(),
        _actionLabel('Show fewer', AnonFeedColors.textReplies, onShowFewer),
      ],
    );
  }

  Widget _actionLabel(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 5 * scale),
          child: Text(label, style: AnonFeedType.t18.copyWith(color: color)),
        ),
      );

  Widget _divider() => Padding(
    padding: EdgeInsets.symmetric(horizontal: 8 * scale),
    child: Container(
      width: 1,
      height: 12 * scale,
      color: AnonFeedColors.hairlineStrong,
    ),
  );
}

// ---------------------------------------------------------------------------
// §9 BOTTOM BLOCK (fade scrim + peek panel — NOT the tab bar, per confirmation)
// ---------------------------------------------------------------------------

// No longer drawn (see the note where AnonFeedScreenV2 used to place it).
// ignore: unused_element
class _AnonBottomBlock extends StatelessWidget {
  const _AnonBottomBlock({
    required this.scale,
    required this.next,
    required this.onAdvance,
  });
  final double scale;
  final AnonFeedPost? next;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    // Lives in the fixed-height gap below MainShell's floating tab bar
    // (see the Positioned in AnonFeedScreenV2.build) — that slot is only
    // safe-area-bottom + kTabBarBottomOffset tall (~58pt, unscaled), so
    // this only shows the peek-bait prompt itself, same simplification
    // AnonymousTab's own _PromptPeekStrip makes for this exact slot
    // (score/tier/community live on the card itself, not here).
    return GestureDetector(
      onTap: onAdvance,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        // BUG FIX (explicit report, with a zoomed screenshot of the
        // symptom): this box's height is the device's bottom-safe-area +
        // kTabBarBottomOffset, and is usually noticeably taller than one
        // line of text. Two compounding issues, both from here:
        // 1. `Alignment.topCenter` (was a workaround for an EARLIER,
        //    opposite-direction gap-above-text bug on a shorter box) pinned
        //    the chevron+text to the top, leaving dead space below and
        //    reading as "the words stick to the top of the box" — switched
        //    to true `Alignment.center` plus symmetric padding.
        // 2. `BorderRadius.only(topLeft/topRight)` rounded only the top,
        //    so the box's own flat, square-cornered bottom portion (same
        //    fill color, different — unrounded — shape) visually read as a
        //    separate horizontal black strip tacked onto the rounded pill
        //    above it, rather than one continuous pill. Rounded to match
        //    all four corners.
        // clipBehavior kept as the safety net for any remaining overflow
        // on unusual device/scale combos, cropped cleanly rather than
        // popping out past the (now fully) rounded corners.
        padding: EdgeInsets.symmetric(horizontal: 24 * scale),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // Was a flat, fully-opaque `color: AnonFeedColors.peekBg` — that
          // painted a solid black plate across this whole reserved slot,
          // which is the other half of the dead-band bug (see the Padding
          // above): even after the feed's own content was allowed to run
          // this far down, this Container still blocked it from showing.
          // A top-to-bottom fade keeps the peek prompt readable (still
          // near-opaque by the time it reaches the text) while letting
          // whatever is behind it - the next card peeking up, or the
          // pill's own blur - actually show through near the top edge,
          // instead of a hard black cutoff.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AnonFeedColors.peekBg.withValues(alpha: 0),
              AnonFeedColors.peekBg.withValues(alpha: 0.85),
            ],
          ),
          borderRadius: BorderRadius.circular(20 * scale),
          border: Border(top: BorderSide(color: AnonFeedColors.hairlineStrong)),
        ),
        alignment: Alignment.center,
        child: AnimatedOpacity(
          duration: AnonFeedCurves.peekOpacityDuration,
          opacity: next == null ? 0 : 1,
          child: next == null
              ? const SizedBox.shrink()
              // Stack instead of a Row — a Row centers the (chevron+gap+
              // text) GROUP, which visibly drags the text off the box's
              // true center by roughly half the chevron+gap width (same
              // class of bug as the toggle chips). The chevron is
              // positioned independently on the left; the text is a
              // separate full-width, independently-centered layer with
              // its own left inset just clearing the chevron, so the
              // TEXT's own center — not the pair's — lands on the box's
              // true center. Text ellipsis-truncates in the (rare) case a
              // very long prompt would otherwise collide with the icon.
              : Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // Explicit report — the chevron sat above the
                    // prompt's own text line (pinned to the stack's
                    // top at `top: 1`, while the text below it is
                    // taller than the 16px glyph). Stretched top-to-
                    // bottom and centered instead, so it lines up with
                    // the text's own vertical center whatever the
                    // prompt's line height works out to.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: SizedBox(
                          width: 16 * scale,
                          height: 16 * scale,
                          child: CustomPaint(
                            painter: ChevronUpPainter(
                              color: AnonFeedColors.chevronStroke,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 26 * scale),
                      child: Text(
                        next!.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AnonFeedType.t15,
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
// Shared sheet chrome — backdrop + grab handle, reused by §10/§11/§12.
// ---------------------------------------------------------------------------

class _SheetBackdrop extends StatelessWidget {
  const _SheetBackdrop({
    required this.onTap,
    required this.color,
    required this.child,
  });
  final VoidCallback onTap;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onTap,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AnonFeedCurves.fadeInDuration,
              curve: AnonFeedCurves.fadeInCurve,
              builder: (context, t, _) =>
                  Container(color: color.withValues(alpha: color.a * t)),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: child),
      ],
    );
  }
}

class _SheetGrabHandle extends StatelessWidget {
  const _SheetGrabHandle({this.bottomPad = 10});
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Top padding is always 14 across all 3 sheet variants (§10/§11/§12)
      // — only bottomPad differs per sheet.
      padding: EdgeInsets.only(top: 14, bottom: bottomPad),
      child: Center(
        child: Container(
          width: 54,
          height: 5,
          decoration: BoxDecoration(
            color: AnonFeedColors.fillHandle,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

Widget _sheetSlideUp({required Widget child}) {
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AnonFeedCurves.sheetUpDuration,
    curve: AnonFeedCurves.sheetCurve,
    builder: (context, t, c) =>
        FractionalTranslation(translation: Offset(0, 1 - t), child: c),
    child: child,
  );
}

// ---------------------------------------------------------------------------
// §10 COMMENTS SHEET
// ---------------------------------------------------------------------------

class _AnonCommentsSheet extends StatefulWidget {
  const _AnonCommentsSheet({
    required this.scale,
    required this.post,
    required this.breakdown,
    required this.onClose,
    required this.onCountChanged,
  });
  final double scale;
  final AnonFeedPost post;

  /// Emoji type + count, identity-free — same aggregate the on-photo stack
  /// reads (_reactionBreakdown), snapshotted at the moment this sheet opens.
  /// Rendered as a row of counts ABOVE the individual reactor face strip
  /// (_AnonReactionStrip) — "the highest selected shall come first", i.e.
  /// sorted most-reacted-first, same rule that stack already follows.
  final List<AnonRealmojiCount> breakdown;
  final VoidCallback onClose;

  /// Called with the sheet's own freshly-loaded comment count, so the card
  /// behind it updates too. Without this the badge kept whatever
  /// _hydrateCounts read on load — comment, close the sheet, and the count
  /// still said what it said before you typed.
  final ValueChanged<int> onCountChanged;

  @override
  State<_AnonCommentsSheet> createState() => _AnonCommentsSheetState();
}

class _AnonCommentsSheetState extends State<_AnonCommentsSheet> {
  bool _loading = true;
  List<AnonThreadComment> _comments = const [];

  /// Whether this anonymous post is mine, so I may remove other people's
  /// comments on it. One boolean from the server (i_own_post) — it carries
  /// no identity, which is why it is safe to ask on an anon post at all.
  bool _iOwnPost = false;

  /// The RealMoji faces on this post — photos, identity-free (see
  /// RealmojiService.fetchAnonReactionFaces). Null while loading, so the
  /// strip shows a placeholder rather than a premature "no reactions".
  List<AnonReactionFace>? _faces;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.post.id;
    if (id == null) {
      // Local/demo post (no real row) — nothing to fetch comments against.
      setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      CommentService.instance.fetchRecentAnon(id),
      RealmojiService.instance.fetchAnonReactionFaces(id),
      CommentService.instance.iOwnPost(postId: id),
    ]);
    if (!mounted) return;
    setState(() {
      _comments = results[0] as List<AnonThreadComment>;
      _faces = results[1] as List<AnonReactionFace>;
      _iOwnPost = results[2] as bool;
      _loading = false;
    });
    // NOT comments.length — fetchRecentAnon caps at 20, so a busy post
    // would report a capped count back to the card. fetchCount is the real
    // total, same source _hydrateCounts uses.
    try {
      final total = await CommentService.instance.fetchCount(
        postId: id,
        isAnonymousPost: true,
      );
      if (mounted) widget.onCountChanged(total);
    } catch (_) {
      // Count stays whatever the card already had — never a wrong number.
    }
  }

  Future<void> _send(String text) async {
    final id = widget.post.id;
    if (id == null || text.trim().isEmpty) return;
    await CommentService.instance.postAnon(postId: id, body: text.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return _SheetBackdrop(
      onTap: widget.onClose,
      color: AnonFeedColors.scrimComments,
      child: _sheetSlideUp(
        child: Container(
          height: screenH * 0.62,
          decoration: BoxDecoration(
            color: AnonFeedColors.sheetBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(34 * widget.scale),
              topRight: Radius.circular(34 * widget.scale),
            ),
            border: Border(
              top: BorderSide(color: AnonFeedColors.hairlineStrong),
            ),
          ),
          child: Column(
            children: [
              const _SheetGrabHandle(),
              Container(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AnonFeedColors.hairlinePromptBar),
                  ),
                ),
                child: Row(
                  children: [
                    Text('REACTED', style: AnonFeedType.t16),
                    const SizedBox(width: 9),
                    _CountOrSkeleton(
                      value: widget.post.extraReactions,
                      style: AnonFeedType.t17,
                      width: 18,
                    ),
                  ],
                ),
              ),
              // Grouped counts — every emoji type reacted with, most-picked
              // first ("the highest selected shall come first"), including
              // plain-emoji reactions (RealmojiTray's "+" mode) now that
              // anon_reaction_counts folds those in alongside RealMoji
              // photos (see that view's own migration doc). Identity-free,
              // same aggregate the on-photo stack already shows.
              if (widget.breakdown.isNotEmpty)
                _AnonReactionCountsRow(
                  scale: widget.scale,
                  breakdown: widget.breakdown,
                ),
              // The RealMojis themselves, horizontally scrollable. Photos
              // with no people attached: anon_post_reaction_faces returns
              // emoji + image url and nothing else, so this shows what was
              // reacted without handing out who reacted — which is why the
              // old comment here said a reactor rail wasn't possible. It is
              // now, in this shape.
              _AnonReactionStrip(scale: widget.scale, faces: _faces),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Comments', style: AnonFeedType.t19),
                    const SizedBox(width: 10),
                    if (_loading)
                      _CountOrSkeleton(
                        value: null,
                        style: AnonFeedType.t20,
                        width: 14,
                      )
                    else
                    // Never a bare 0 — explicit rule across the app.
                    if (_comments.isNotEmpty)
                      Text('${_comments.length}', style: AnonFeedType.t20),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const SizedBox.shrink()
                    : _comments.isEmpty
                    ? Center(
                        child: Text(
                          'No comments yet — say something anonymously.',
                          textAlign: TextAlign.center,
                          style: AnonFeedType.t22,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(32, 4, 32, 10),
                        children: [
                          for (final c in _comments)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: _CommentRow(
                                comment: c,
                                canRemove: c.isMine || _iOwnPost,
                                onChanged: _load,
                              ),
                            ),
                        ],
                      ),
              ),
              _CommentComposer(
                scale: widget.scale,
                enabled: widget.post.id != null,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal strip of the RealMoji reactions on an anonymous post.
///
/// Each entry follows the Profile Card handoff's variant 1A treatment,
/// scaled down: circular photo, a decorative ring floating outside it, and
/// the emoji sitting directly ON the photo's bottom-right with no
/// background plate (the plate + inside-the-clip placement is exactly what
/// made the badge invisible in the library grid).
///
/// Identity-free by construction — [AnonReactionFace] carries only the
/// emoji and an image url, never a user id or a name, so there is nothing
/// here to tap through to.
/// Emoji type + count, sorted most-reacted-first — a horizontal row of
/// small pills, one per reaction type this post got (RealMoji or plain
/// emoji, both fold into the same [AnonRealmojiCount] shape via
/// anon_reaction_counts). Identity-free: a count, never who.
class _AnonReactionCountsRow extends StatelessWidget {
  const _AnonReactionCountsRow({required this.scale, required this.breakdown});

  final double scale;
  final List<AnonRealmojiCount> breakdown;

  @override
  Widget build(BuildContext context) {
    final sorted = [...breakdown]..sort((a, b) => b.count.compareTo(a.count));
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 14 * scale, 32, 0),
      child: SizedBox(
        height: 30 * scale,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          itemCount: sorted.length,
          separatorBuilder: (_, _) => SizedBox(width: 8 * scale),
          itemBuilder: (context, i) {
            final c = sorted[i];
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 10 * scale),
              decoration: BoxDecoration(
                color: AnonFeedColors.countPillBg,
                borderRadius: BorderRadius.circular(15 * scale),
                border: Border.all(color: AnonFeedColors.hairlineCountPill),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.emojiType.glyph,
                    style: TextStyle(fontSize: 13 * scale),
                  ),
                  SizedBox(width: 6 * scale),
                  Text('${c.count}', style: AnonFeedType.t7),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnonReactionStrip extends StatelessWidget {
  const _AnonReactionStrip({required this.scale, required this.faces});

  final double scale;

  /// Null while loading.
  final List<AnonReactionFace>? faces;

  @override
  Widget build(BuildContext context) {
    final list = faces;
    if (list == null) {
      return SizedBox(
        height: 78 * scale,
        child: Center(
          child: SizedBox(
            width: 16 * scale,
            height: 16 * scale,
            child: const CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Colors.white24,
            ),
          ),
        ),
      );
    }
    if (list.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(32, 12 * scale, 32, 4 * scale),
        child: Text(
          'No RealMojis yet — be the first.',
          style: AnonFeedType.t22,
        ),
      );
    }
    return SizedBox(
      height: 118 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(32, 12 * scale, 32, 10 * scale),
        itemCount: list.length,
        separatorBuilder: (_, _) => SizedBox(width: 16 * scale),
        itemBuilder: (context, i) =>
            _AnonReactionFaceChip(scale: scale, face: list[i]),
      ),
    );
  }
}

class _AnonReactionFaceChip extends StatelessWidget {
  const _AnonReactionFaceChip({required this.scale, required this.face});

  final double scale;
  final AnonReactionFace face;

  @override
  Widget build(BuildContext context) {
    // 1A ratios against its 168px photo, applied to an 86px one here.
    // 54 -> 66 -> 86: this strip IS what the reactions view is opened for,
    // so it gets to be the biggest thing in the sheet ("when opened
    // reactions viewing, make the RealMoji big, more visible and clear").
    const d = 86.0;
    final size = d * scale;
    final url = face.imageUrl;
    return SizedBox(
      width: size + 8 * scale,
      height: size + 8 * scale,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size + 8 * scale,
            height: size + 8 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AnonFeedColors.accentCyan.withValues(alpha: 0.30),
                width: 1.5,
              ),
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF161618),
                    ),
                    child: ClipOval(
                      child: (url == null || url.isEmpty)
                          // Retaken away since — the glyph alone, rather
                          // than dropping the reaction and disagreeing with
                          // the count above.
                          ? Center(
                              child: Text(
                                face.type.glyph,
                                style: TextStyle(fontSize: size * 0.42),
                              ),
                            )
                          : CachedNetworkImage(
                              memCacheWidth: 1080,
                              imageUrl: url,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Center(
                                child: Text(
                                  face.type.glyph,
                                  style: TextStyle(fontSize: size * 0.42),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                if (url != null && url.isNotEmpty)
                  Positioned(
                    right: -2 * scale,
                    bottom: -2 * scale,
                    child: Text(
                      face.type.glyph,
                      style: TextStyle(
                        // Deliberately above 1A's own 32/168 badge ratio —
                        // explicit request to make the emoji bigger, and at
                        // strip scale the literal ratio reads as a speck.
                        fontSize: size * 0.5,
                        shadows: const [
                          Shadow(color: Color(0xCC000000), blurRadius: 7),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    this.canRemove = false,
    this.onChanged,
  });

  final AnonThreadComment comment;

  /// You wrote it, or the post is yours. Report/Block are never offered
  /// here — an anon thread must not hand out an identity to act on — so
  /// this flag alone decides whether the row has a menu at all.
  final bool canRemove;
  final VoidCallback? onChanged;

  void _openMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showCommentActionsMenu(
      context,
      commentId: comment.id,
      isMine: comment.isMine,
      canRemove: canRemove,
      isAnonymous: true,
      onDeleted: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Deterministic glyph+color persona keyed off the real per-post handle —
    // the same non-photographic "DP" language the post card itself already
    // uses for its own author avatar (_PersonaAvatar), never a real photo.
    final persona = AnonPersona.of(comment.handle);
    final dp = comment.avatarUrl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: canRemove ? () => _openMenu(context) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: persona.color,
            ),
            // The commenter's own anon DP (users.anon_photo_url) when they
            // have one — the same persona photo their anon POSTS render with,
            // so one person reads as one identity across the thread. The
            // deterministic glyph is the fallback for anyone who hasn't set
            // a persona photo; it is never the real profile photo either way.
            child: (dp == null || dp.isEmpty)
                ? Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CustomPaint(
                        painter: PersonaGlyphPainter(
                          shape: persona.glyph,
                          color: AnonFeedColors.personaGlyphInk,
                        ),
                      ),
                    ),
                  )
                : CachedNetworkImage(
                    memCacheWidth: 120,
                    imageUrl: dp,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CustomPaint(
                          painter: PersonaGlyphPainter(
                            shape: persona.glyph,
                            color: AnonFeedColors.personaGlyphInk,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(comment.handle, style: AnonFeedType.t21),
                    const SizedBox(width: 9),
                    Text(
                      formatRelativeTime(comment.createdAt, withAgo: true),
                      style: AnonFeedType.t22,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(comment.body, style: AnonFeedType.t23),
              ],
            ),
          ),
          if (canRemove)
            GestureDetector(
              onTap: () => _openMenu(context),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 6, top: 2),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: Color(0x66A39C8F),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentComposer extends StatefulWidget {
  const _CommentComposer({
    required this.scale,
    required this.enabled,
    required this.onSend,
  });
  final double scale;
  final bool enabled;
  final Future<void> Function(String text) onSend;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending || !widget.enabled) return;
    // Anonymity is not a licence for slurs/threats — same lenient check
    // every other posting path runs (ContentModerationService's own doc).
    final moderation = ContentModerationService.instance.check(text);
    if (moderation.blocked) {
      showGlassToast(context, moderation.reason!, isError: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // + the device's bottom safe-area inset (iPhone home indicator,
      // Android gesture pill / 3-button bar under edge-to-edge) so the
      // input never sits underneath system UI. 0 on devices without one.
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        26 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AnonFeedColors.hairlinePromptBar),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // Explicit report ("a black strip over which the typing
              // goes on — i just want the oval enclosure"): the filled
              // field read as a slab inside the sheet rather than as one
              // control. Outline-only, same treatment the feed's own
              // comment composer got.
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: AnonFeedColors.hairlineTabBar),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _ctrl,
                  enabled: widget.enabled && !_sending,
                  onSubmitted: (_) => _submit(),
                  style: AnonFeedType.t24,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    hintText: 'Reply anonymously…',
                    hintStyle: AnonFeedType.t24,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _submit,
            child: Container(
              width: 50,
              height: 50,
              padding: const EdgeInsets.only(
                left: 15,
                top: 15,
                right: 17,
                bottom: 15,
              ),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AnonFeedColors.chipLight,
              ),
              child: _sending
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AnonFeedColors.inkOnLight,
                    )
                  : CustomPaint(
                      painter: PaperPlanePainter(
                        color: AnonFeedColors.inkOnLight,
                        strokeWidth: 1.9,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// §11 PING PROMPT SHEET
// ---------------------------------------------------------------------------

class _AnonPingSheet extends StatelessWidget {
  const _AnonPingSheet({
    required this.scale,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });
  final double scale;
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _SheetBackdrop(
      onTap: onClose,
      color: AnonFeedColors.scrimSheet,
      child: _sheetSlideUp(
        child: Container(
          decoration: BoxDecoration(
            color: AnonFeedColors.sheetBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(34 * scale),
              topRight: Radius.circular(34 * scale),
            ),
            border: Border(
              top: BorderSide(color: AnonFeedColors.hairlineStrong),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetGrabHandle(bottomPad: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AnonFeedColors.accentCyanWell,
                        border: Border.all(
                          color: AnonFeedColors.accentCyanWellBorder,
                        ),
                      ),
                      padding: const EdgeInsets.all(13.5),
                      child: const CustomPaint(
                        painter: PingFigurePainter(
                          strokeColor: AnonFeedColors.accentCyan,
                          strokeWidth: 1.7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Ping anonymously', style: AnonFeedType.t25),
                          const SizedBox(height: 3),
                          Text(
                            'They see the question, never who asked.',
                            style: AnonFeedType.t26,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 22, 32, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('PICK A QUESTION', style: AnonFeedType.t27),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    for (var i = 0; i < kAnonPingPrompts.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == kAnonPingPrompts.length - 1 ? 0 : 9,
                        ),
                        child: _PingOptionRow(
                          text: kAnonPingPrompts[i].text,
                          selected: selected == i,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 22, 32, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: AnonFeedColors.fillButtonGhost,
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(
                            color: AnonFeedColors.hairlineTabBar,
                          ),
                        ),
                        child: Center(
                          child: Text('Cancel', style: AnonFeedType.t29),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: selected == null ? null : onClose,
                        child: AnimatedContainer(
                          duration: AnonFeedCurves.sendButtonDuration,
                          height: 54,
                          decoration: BoxDecoration(
                            color: selected == null
                                ? AnonFeedColors.fillDisabled
                                : AnonFeedColors.chipLight,
                            borderRadius: BorderRadius.circular(27),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Send ping',
                                style: AnonFeedType.t30(
                                  selected == null
                                      ? AnonFeedColors.textFaint
                                      : AnonFeedColors.inkOnLight,
                                ),
                              ),
                              const SizedBox(width: 9),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CustomPaint(
                                  painter: PaperPlanePainter(
                                    color: selected == null
                                        ? AnonFeedColors.textFaint
                                        : AnonFeedColors.inkOnLight,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PingOptionRow extends StatelessWidget {
  const _PingOptionRow({
    required this.text,
    required this.selected,
    required this.onTap,
  });
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AnonFeedCurves.rowSelectDuration,
        padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 18),
        decoration: BoxDecoration(
          color: selected
              ? AnonFeedColors.accentCyanRowBg
              : AnonFeedColors.fillRowIdle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AnonFeedColors.accentCyanRowBorder
                : AnonFeedColors.hairlinePromptBar,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AnonFeedColors.accentCyan
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? AnonFeedColors.accentCyan
                      : AnonFeedColors.radioIdle,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Padding(
                      padding: EdgeInsets.all(5),
                      child: CustomPaint(
                        painter: CheckmarkPainter(
                          color: AnonFeedColors.inkOnLight,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: AnonFeedType.t28(
                  selected
                      ? AnonFeedColors.textPrimary
                      : AnonFeedColors.textOptionIdle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// §12 BLOCK / REPORT MENU — see _CaptionMetaRow's own §8 doc. Used to be a
// full-screen bottom sheet (_AnonMenuSheet/_MenuRow) sliding up from the
// screen bottom; replaced by an inline horizontal-slide panel anchored to
// the metadata row itself (C4 — "drop down along the same line as the
// metadata row", clarified to mean a right-to-left slide INTO that row, not
// a vertical dropdown below it).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// _AnonLoadingState — shown ONLY while the first page fetch is still in
// flight (_firstLoadPending), so an empty _remote list during that window
// never gets misread as "confirmed nothing here" (_AnonEmptyState) or
// "confirmed failed" (_AnonErrorState) before either has actually been
// determined. See _AnonFeedScreenV2State._firstLoadPending's own doc.
// ---------------------------------------------------------------------------

class _AnonLoadingState extends StatelessWidget {
  const _AnonLoadingState();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AnonFeedColors.screenBg,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white54,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — reachable now that the Anon feed renders REAL data (it used
// to render a const list that was never empty). Both feed rules can
// legitimately empty it out: every post older than the 24h anon window, and
// everything inside that window already reacted to.
// ---------------------------------------------------------------------------

class _AnonEmptyState extends StatelessWidget {
  const _AnonEmptyState();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AnonFeedColors.screenBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            "You're all caught up.\nNew anonymous posts show up here for 24 hours.",
            textAlign: TextAlign.center,
            style: AnonFeedType.t6,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CountOrSkeleton — renders an engagement count, or a shimmer placeholder
// while that count is still UNKNOWN (null).
//
// `posts_feed` carries no reaction/comment counts, so a freshly-loaded post
// has null counts until _hydrateCounts resolves them. Rendering "0" in that
// window would be a confident lie — it reads as "nobody reacted" on a post
// that may have plenty. A neutral shimmer says "loading" instead, and the
// fixed [width] keeps the row from reflowing when the real number lands.
//
// Note the skeleton persists (rather than falling back to 0) if the count
// fetch fails outright — same reasoning: no number is better than a wrong
// one. See _hydrateCounts' own doc.
// ---------------------------------------------------------------------------

class _CountOrSkeleton extends StatelessWidget {
  const _CountOrSkeleton({
    required this.value,
    required this.style,
    required this.width,
  });

  final int? value;
  final TextStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (value != null) return Text('$value', style: style);
    final h = (style.fontSize ?? 12) * 0.8;
    return Shimmer.fromColors(
      baseColor: AnonFeedColors.hairlineStrong,
      highlightColor: AnonFeedColors.textDimmer,
      child: Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          color: AnonFeedColors.hairlineStrong,
          borderRadius: BorderRadius.circular(h / 2),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AnonErrorState — shown ONLY when the very first page failed, so there's
// no previously-loaded content to fall back on. A mid-pagination failure
// never reaches here: those keep the pages already loaded and simply stop
// advancing (see _AnonFeedScreenV2State._loadMore).
//
// Deliberately distinct from _AnonEmptyState: "couldn't load" is
// recoverable and needs a retry, "nothing here" is terminal and doesn't.
// ---------------------------------------------------------------------------

class _AnonErrorState extends StatelessWidget {
  const _AnonErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AnonFeedColors.screenBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load the feed.",
                textAlign: TextAlign.center,
                style: AnonFeedType.t6,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onRetry,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AnonFeedColors.chipLight,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    'Retry',
                    style: AnonFeedType.t1(AnonFeedColors.inkOnLight),
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

/// A [Stack] that also takes touches landing OUTSIDE its own box, on any
/// child that overflows it (Clip.none). Only the hit test differs — layout
/// and paint are exactly Stack's. Used by _AnonPostCard, whose persona
/// avatar overhangs the card's top edge.
class _OverflowHitStack extends Stack {
  const _OverflowHitStack({super.clipBehavior, super.children});

  @override
  RenderStack createRenderObject(BuildContext context) =>
      _RenderOverflowHitStack(
        alignment: alignment,
        textDirection: textDirection ?? Directionality.maybeOf(context),
        fit: fit,
        clipBehavior: clipBehavior,
      );
}

class _RenderOverflowHitStack extends RenderStack {
  _RenderOverflowHitStack({
    super.alignment,
    super.textDirection,
    super.fit,
    super.clipBehavior,
  });

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // RenderBox.hitTest bails out when [position] is outside `size`;
    // skipping that check lets an overhanging child be hit.
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
