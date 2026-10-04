import 'dart:async';
import 'dart:math' as math;
import '../../core/feature_flags.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent, RealtimeChannel;

import '../../core/supabase_config.dart';
import '../../features/composer/composer_screen.dart';
import '../../features/composer/dual_photo_compositor.dart'
    show kFriendsPostAspect;
import '../../main_shell.dart' show kTabBarHeight, kTabBarBottomOffset;
import '../../features/groups/moments/locked_replies_screen.dart';
import '../../features/moderation/post_actions_menu.dart';
import '../../services/current_user_service.dart';
import '../../services/feed_refresh_signal.dart';
import '../../services/feed_service.dart';
import '../../services/moment_service.dart';
import '../../services/people_service.dart';
import '../../services/post_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'memory_detail_screen.dart';
import 'single_post_detail_screen.dart';
import 'widgets/design_group_card.dart';
import 'widgets/design_solo_card.dart';
import 'widgets/everyone_post_card.dart';
import 'widgets/memory_feed_card.dart';
import 'widgets/moment_card.dart';
import 'widgets/people_suggestion_strip.dart';
import 'widgets/single_post_card.dart';
import 'widgets/spotlight_card.dart';
import 'widgets/spotlight_feed_controller.dart';
import 'widgets/spotlight_privileges_controller.dart';

/// Which post set this screen renders — the two "Everyone"/"Friends" tabs
/// share every bit of card rendering (SpotlightCard, DesignSoloCard,
/// DesignGroupCard, the loading/empty states) and differ only in what's
/// fetched and how a fetched page is post-processed, so this is a mode
/// flag on one screen rather than a second near-duplicate file.
enum FeedAudience { everyone, friends }

class EveryoneFeedScreen extends StatefulWidget {
  const EveryoneFeedScreen({
    required this.chromeCollapsed,
    this.topInset = 0,
    this.audience = FeedAudience.everyone,
    super.key,
  });

  /// [FeedAudience.friends]: real friends-feed rules (FeedService.
  /// fetchFriendsFeed — accepted friends OR shared community-audience,
  /// deduped and exclusion-tested server-side). No per-page shuffle, no
  /// demo Moment padding, no infinite lap-wrap once real data runs out,
  /// and a live realtime subscription on `posts` so a qualifying post
  /// appears without a manual refresh. Also skips the "everyone" feed's
  /// group-post blending (fetchGroupFeed) and the viewer's own
  /// just-posted local items — a friends feed shows other people's posts.
  final FeedAudience audience;

  /// HomeScreen's own scroll-driven chrome-collapse state (shared with the
  /// Anonymous tab's header) — kept for the rest of the header (bell,
  /// reaction, toggle, score), which still hides/reappears on scroll as one
  /// coordinated unit. The Wall preview strip used to collapse in lockstep
  /// with this too; it's unwired for now (deferred post-launch — see
  /// WallService/WallPreviewStrip, both still intact, just not called from
  /// here), so this field no longer affects it.
  final bool chromeCollapsed;

  /// Reserved space for HomeScreen's floating _SlimHeader (which overlays
  /// this screen via a Stack, same as AnonymousTab.topInset) — without
  /// this, the header (Anon/Friends toggle pill included) paints directly
  /// on top of the feed's first item instead of above it. Defaults to 0
  /// for the standalone screenshot-mode call sites (main.dart) that render
  /// this screen with no floating header at all.
  final double topInset;

  @override
  State<EveryoneFeedScreen> createState() => _EveryoneFeedScreenState();
}

class _EveryoneFeedScreenState extends State<EveryoneFeedScreen> {
  static const _pageSize = 20;

  List<FeedItem> _localItems = [];
  // Accumulated remote+group pages, each page shuffled independently at
  // fetch time (see _loadPage) — never re-sorted as a whole, so page
  // boundaries stay stable and no post gets stranded unseen by a bad
  // whole-list shuffle.
  final List<FeedItem> _pagedItems = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _offset = 0;
  // Friends mode only — group_post_audience_feed pages independently of
  // the personal-post offset above, since the two are separate RPCs with
  // separate result sizes.
  int _groupAudienceOffset = 0;

  /// Index in [_pagedItems] where the current lap began. Dedupe is scoped to
  /// the lap, so a re-dealt post is allowed to appear again on the next one
  /// — see the lap-wrap in _loadPage.
  int _lapStartIndex = 0;
  // Lap count + throttle for the infinite-loop-once-real-data-runs-out
  // behavior (see _loadPage) — only engages once we've actually wrapped,
  // so normal paginated scrolling through real data is never throttled.
  int _lap = 0;
  DateTime? _lastLoopFetch;

  /// Friends mode has a real end (the infinite re-deal was deliberately
  /// removed — see _loadPage), so it never laps and therefore never engages
  /// _lap's throttle above. Without this flag, every scroll frame near the
  /// bottom of an exhausted feed fired both RPCs again, forever. Set once
  /// both sources return a short page; cleared by _refresh.
  bool _friendsFeedEnded = false;

  /// Friends mode no longer stops at that end ("friends feed shall never be
  /// empty ... make the friends feed infinite scroll"). It continues with
  /// campus posts the viewer is allowed to see (fetchEveryoneFeed, gated by
  /// the same RLS as every other read), then with labelled Rewind laps.
  ///
  /// Sections are keyed by their start index in [_pagedItems]. A non-null
  /// label renders as a divider there, and the on-screen dedupe in [_slots]
  /// restarts at every section, so a Rewind lap may repeat posts. The Everyone
  /// mode's own laps register here too (label null). Before this, [_allItems]
  /// deduped globally and silently swallowed every lap.
  final Map<int, String?> _sectionStarts = {};
  int _campusOffset = 0;
  bool _campusExhausted = false;
  StreamSubscription<List<LocalPost>>? _sub;

  // Friends-mode only — live push so a qualifying friend/community post
  // appears without the viewer pulling to refresh (see class doc).
  RealtimeChannel? _postsChannel;
  Timer? _realtimeDebounce;

  bool get _isFriends => widget.audience == FeedAudience.friends;

  // ---- "New on campus" suggestion strips (Friends feed only) ------------
  // Explicit request: new people's photo + name with an Add button, mixed
  // into the feed at random spots so it feels alive as people join.
  List<Map<String, dynamic>> _suggestions = const [];
  /// user id -> circle name, for people added from a strip this session.
  final Map<String, String> _suggestAdded = {};
  Set<String> _suggestHidden = {};
  final _suggestRng = math.Random();
  /// Posts before each strip — random per session, stable across rebuilds.
  final List<int> _suggestGaps = [];
  static const _kSuggestHiddenKey = 'feed_suggest_hidden';
  static const _kSuggestPerStrip = 5;

  Future<void> _loadSuggestions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _suggestHidden =
          (prefs.getStringList(_kSuggestHiddenKey) ?? const []).toSet();
    } catch (_) {}
    final rows = await PeopleService.instance.suggestedPeople();
    if (!mounted) return;
    setState(() => _suggestions = rows);
  }

  void _hideSuggestion(String id) {
    setState(() => _suggestHidden = {..._suggestHidden, id});
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_kSuggestHiddenKey, _suggestHidden.toList());
      } catch (_) {}
    }());
  }

  int _suggestGap(int i) {
    while (_suggestGaps.length <= i) {
      _suggestGaps.add(
        _suggestGaps.isEmpty
            ? 2 + _suggestRng.nextInt(2) // first strip after 2-3 posts
            : 6 + _suggestRng.nextInt(4), // then every 6-9
      );
    }
    return _suggestGaps[i];
  }

  /// Weaves strips into [slots] after a random number of posts each; each
  /// strip shows the next few people, and strips stop when they run out.
  List<Object> _withSuggestions(List<Object> slots) {
    if (!_isFriends || _suggestions.isEmpty) return slots;
    final visible = [
      for (final p in _suggestions)
        if (!_suggestHidden.contains(p['user_id'])) p,
    ];
    if (visible.isEmpty) return slots;
    final out = <Object>[];
    var strip = 0, sinceLast = 0;
    for (final slot in slots) {
      out.add(slot);
      if (slot is! FeedItem) continue;
      sinceLast++;
      final start = strip * _kSuggestPerStrip;
      if (start >= visible.length || sinceLast < _suggestGap(strip)) continue;
      out.add(_SuggestionSlot(
        visible.sublist(start, math.min(start + _kSuggestPerStrip, visible.length)),
      ));
      strip++;
      sinceLast = 0;
    }
    return out;
  }

  final _spotlightController = SpotlightFeedController();
  final _privileges = SpotlightPrivilegesController();

  /// My own `users.id`, so the "..." menu can offer Remove on my rows and
  /// Report/Block on everyone else's. Null until it resolves; the menu
  /// treats that as "not mine", which is the safe default — offering Report
  /// on your own post is a harmless mistake, offering Remove on someone
  /// else's is not.
  String? _myUserId;

  /// Opens the shared post menu for a feed row.
  ///
  /// This feed had no menu at all: there was no way to report or take down
  /// anything in Friends/Everyone, only in Anon and inside a Moment.
  /// Reported as "the dropdown to report which you give in moments, give it
  /// everywhere".
  Future<void> _openPostMenu(FeedItem item) async {
    // An anonymous row arrives with user_id masked (posts_feed's CASE), so
    // it can be reported but never blocked — blocking would let you learn
    // that two anonymous posts share an author.
    final authorId = item.userId.trim();
    await showPostActionsMenu(
      context,
      postId: item.postId,
      isOwnPost: authorId.isNotEmpty && authorId == _myUserId,
      isAnonymousPost: authorId.isEmpty,
      authorUsersId: authorId.isEmpty ? null : authorId,
      title: item.isMoment ? 'THIS MOMENT' : 'THIS POST',
      onDeleted: () {
        if (!mounted) return;
        setState(() {
          _localItems.removeWhere((i) => i.postId == item.postId);
          _pagedItems.removeWhere((i) => i.postId == item.postId);
        });
      },
    );
  }

  Future<void> _resolveMe() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      if (mounted) setState(() => _myUserId = id);
    } catch (_) {
      // Signed out — menu stays on its Report/Block default.
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_resolveMe());
    if (_isFriends) unawaited(_loadSuggestions());
    // The viewer's own just-posted items only belong in the Everyone feed —
    // a Friends feed is specifically OTHER people's posts.
    if (!_isFriends) {
      _localItems = PostService.instance.everyonePosts
          .map(FeedItem.fromLocalPost)
          .toList();
      _sub = PostService.instance.everyoneFeedStream.listen((posts) {
        if (mounted) {
          setState(
            () => _localItems = posts.map(FeedItem.fromLocalPost).toList(),
          );
        }
      });
    } else {
      _subscribeToPostChanges();
    }
    _spotlightController.spotlightPostId.addListener(_onSpotlightChanged);
    // A friendship change alters what this feed's query is ALLOWED to
    // return (RLS re-evaluates the friend gate per row), but nothing was
    // asking it to re-query — so an accepted request only showed up after a
    // manual pull-to-refresh. See feed_refresh_signal.dart.
    feedRefreshSignal.addListener(_onFeedRefreshSignal);
    _loadPage();
    // First page loads with no scroll notification ever having fired, so it
    // would otherwise sit at focus=0 (fully blurred/dimmed) until the user
    // nudges the pager. Force one recompute once the first frame lays out.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _spotlightController.onScroll(),
    );
  }

  /// Coalesces a burst of inserts (e.g. several friends posting close
  /// together) into one merge instead of one per row. Same pattern as
  /// PingPage._scheduleReload.
  void _scheduleRealtimeMerge() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_mergeNewFriendsPosts());
    });
  }

  void _subscribeToPostChanges() {
    _postsChannel = supabase
        .channel('friends_feed_live_${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (_) => _scheduleRealtimeMerge(),
        )
        // Also UPDATE, not just INSERT — a mutual Duo post is the SAME
        // posts.id every time it's toggled (sync_us_album_post's own
        // ON CONFLICT DO UPDATE, not a fresh insert), so re-mutualising an
        // already-existing post after locking it only ever UPDATEs that row
        // (deleted_at back to NULL). The insert-only listener never saw
        // that, so the post only reappeared on a manual pull-to-refresh —
        // "the feed shall be instantaneous at the moment post" needed this.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'posts',
          callback: (_) => _scheduleRealtimeMerge(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_posts',
          callback: (_) => _scheduleRealtimeMerge(),
        )
        .subscribe();
  }

  /// Re-fetches page 0 and prepends whatever isn't already loaded — keeps
  /// the viewer's scroll position intact instead of resetting the whole
  /// feed on every new post the way a full [_refresh] would.
  Future<void> _mergeNewFriendsPosts() async {
    final results = await Future.wait([
      FeedService.instance.fetchFriendsFeed(limit: _pageSize, offset: 0),
      FeedService.instance.fetchFriendsGroupFeed(limit: _pageSize, offset: 0),
    ]);
    if (!mounted) return;
    // Adds as it goes, so a post that arrives from BOTH sources in the same
    // merge is kept once. A plain `.where` against a frozen set (what this
    // was) lets every copy past, since none of them are in the set yet.
    final seenIds = _pagedItems.map((i) => i.postId).toSet();
    final fresh = [...results[0], ...results[1]]
        .where((i) => seenIds.add(i.postId))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    if (fresh.isEmpty) return;
    setState(() => _pagedItems.insertAll(0, fresh));
  }

  /// Real contributor counts for the Moment cards in [page], keyed by post
  /// id — one batched RPC per page rather than one per card (see
  /// MomentService.replyCounts). Fire-and-forget: a Moment card renders
  /// straight away with its fallback count and updates when this lands, so
  /// the feed never blocks on it.
  final Map<String, int> _momentReplyCounts = {};

  Future<void> _refreshMomentCounts(List<FeedItem> page) async {
    final ids = [
      for (final i in page)
        if (i.isMoment) i.postId,
    ];
    if (ids.isEmpty) return;
    final counts = await MomentService.instance.replyCounts(ids);
    if (!mounted || counts.isEmpty) return;
    setState(() => _momentReplyCounts.addAll(counts));
  }

  void _onSpotlightChanged() {
    final id = _spotlightController.spotlightPostId.value;
    FeedItem? item;
    if (id != null) {
      for (final i in _allItems) {
        if (i.postId == id) {
          item = i;
          break;
        }
      }
    }
    _privileges.updateSpotlight(item);
  }

  /// Fetches the next page (offset-based) and appends it — call for both
  /// the initial load and every subsequent scroll-triggered page.
  Future<void> _loadPage() async {
    if (_loadingMore) return;
    final wasEnded = _friendsFeedEnded;
    // Only throttles once a lap has actually happened (tiny real dataset
    // + fast scrolling) — real paginated fetches are never delayed. Friends
    // mode never laps (see below), so this guard never engages there.
    if (_lap > 0 &&
        _lastLoopFetch != null &&
        DateTime.now().difference(_lastLoopFetch!) <
            const Duration(milliseconds: 1500)) {
      return;
    }
    _loadingMore = true;

    // try/finally: any fetch/mapping error must never leave _loadingMore
    // stuck true, or every future scroll-triggered call silently no-ops at
    // the guard above forever (see AnonymousTab._loadMoreRemote's own note
    // — the exact bug that caused a real permanent dead-end there).
    try {
      if (_isFriends && _friendsFeedEnded) {
        await _loadFriendsOverflow();
        return;
      }
      if (_isFriends) {
        // Friends' own posts are a bounded list. After they run out,
        // _loadFriendsOverflow carries on (see _sectionStarts).
        //
        // It is NOT chronological. This comment used to claim "no shuffle,
        // strict chronological order", which the code ~15 lines below has
        // contradicted since the per-launch shuffle landed: each page is
        // split into the viewer's OWN posts (newest first) followed by
        // everyone else's, shuffled. The shuffle is per FETCHED PAGE and
        // applied once before appending, so it never reorders cards already
        // on screen — see that block's own doc.
        //
        // Two sources merged the same way the Everyone feed merges
        // personal+group
        // posts: personal (accepted-friend OR shared-audience) via
        // fetchFriendsFeed, plus group posts the poster explicitly opened
        // to Friends/a shared community via fetchFriendsGroupFeed — each
        // paginated independently since they're separate RPCs.
        final results = await Future.wait([
          FeedService.instance.fetchFriendsFeed(
            limit: _pageSize,
            offset: _offset,
          ),
          FeedService.instance.fetchFriendsGroupFeed(
            limit: _pageSize,
            offset: _groupAudienceOffset,
          ),
          // ANONYMOUS Moments — first page only. They are few, they don't
          // paginate, and re-fetching them on every page would just feed
          // the dedupe. See FeedService.fetchAnonMoments for why they come
          // from posts_feed rather than this feed's own query.
          if (_pagedItems.isEmpty)
            FeedService.instance.fetchAnonMoments()
          else
            Future<List<FeedItem>>.value(const []),
        ]);
        if (!mounted) return;
        final personal = results[0];
        final groupAudience = results[1];
        final anonMoments = results[2];
        // FULL dedupe here, not the Everyone feed's cheap last-3 check.
        // Two reasons this feed genuinely repeats posts without it:
        //   * its two sources page independently, and an offset only
        //     advances on a FULL page — so a source that returns 3 rows
        //     keeps offset 0 and hands back those same 3 rows on the next
        //     load, appending them a second time;
        //   * one post can reach you through more than one route at once —
        //     the poster is your friend AND picked a community you're in
        //     ("if the person is in more than one, ex a friend and a
        //     community, or overlapping, still the post shall be shown
        //     only once"). friends_feed already ORs those two branches into
        //     one row server-side, but the merge below is where a personal
        //     and a group-audience copy of the same id would collide.
        // The dedupe is against THIS lap only (see the lap-wrap below), not
        // against everything ever loaded — otherwise the second lap would
        // dedupe itself away to nothing.
        final seenIds = _pagedItems
            .skip(_lapStartIndex)
            .map((i) => i.postId)
            .toSet();
        final page = <FeedItem>[];
        for (final item in [
          ...personal,
          ...groupAudience,
          ...anonMoments,
        ]) {
          if (seenIds.add(item.postId)) page.add(item);
        }
        // Own post(s) first (freshest first among those), everything else
        // shuffled — explicit follow-up: "my own post go out of feed after
        // 24 hrs, other[s] stay... every time the user comes the posts
        // shall be shuffled/resurface[d]". "Every time the user COMES" —
        // i.e. once per feed-open/refresh, not mid-scroll: this shuffles
        // only the NEWLY fetched (already fully deduped-against-shown)
        // items in THIS page, once, right before they're appended. It never
        // re-touches an item already sitting in _pagedItems, so scrolling
        // further can only ever ADD cards below the fold, never reorder
        // what's already on screen — see the removed "exhausted" re-deal
        // right below for what used to do exactly that reordering.
        final mine = <FeedItem>[];
        final others = <FeedItem>[];
        for (final item in page) {
          (item.userId.isNotEmpty && item.userId == _myUserId ? mine : others)
              .add(item);
        }
        mine.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        others.shuffle();
        page
          ..clear()
          ..addAll(mine)
          ..addAll(others);

        // BUG FIX ("i am seeing the same post several times... when i am
        // scrolling the posts are getting shuffled"): this used to re-deal
        // (shuffle + re-append) every post already loaded once both real
        // sources ran dry, on the theory that a small friends feed "feeling
        // empty" was worse than repeating content. That is exactly a
        // mechanism for visibly reordering AND duplicating posts you have
        // already scrolled past — the two symptoms reported. Removed
        // outright: the feed now genuinely ends when there is nothing left,
        // which is what "I shall see all of friends' posts" actually means
        // — a bounded, real list, not an infinite reshuffled loop standing
        // in for one.
        setState(() {
          _pagedItems.addAll(page);
          if (personal.length == _pageSize) _offset += _pageSize;
          if (groupAudience.length == _pageSize) {
            _groupAudienceOffset += _pageSize;
          }
          // Neither source filled a page, so neither offset advanced —
          // every further call would re-fetch these exact same rows. That
          // is the real end of this bounded feed.
          if (personal.length < _pageSize && groupAudience.length < _pageSize) {
            _friendsFeedEnded = true;
          }
          _loading = false;
        });
        _refreshMomentCounts(page);
      } else {
        final results = await Future.wait([
          FeedService.instance.fetchEveryoneFeed(
            limit: _pageSize,
            offset: _offset,
          ),
          FeedService.instance.fetchGroupFeed(
            limit: _pageSize,
            offset: _offset,
          ),
          // See the Friends branch — first page only.
          if (_pagedItems.isEmpty)
            FeedService.instance.fetchAnonMoments()
          else
            Future<List<FeedItem>>.value(const []),
        ]);
        if (!mounted) return;

        final remote = results[0];
        final group = results[1];
        final anonMoments = results[2];
        final localIds = _localItems.map((i) => i.postId).toSet();
        // Shuffle WITHIN this page only — keeps pagination boundaries stable
        // (a post fetched on page 2 always renders after every page-1
        // post), instead of a global reshuffle that could strand a post
        // unseen.
        var page = [
          ...remote.where((i) => !localIds.contains(i.postId)),
          ...group,
          ...anonMoments,
        ]..shuffle();
        // Full dedup against THIS LAP (since _lapStartIndex), same scope
        // the Friends feed already uses — not just the last-3-item check
        // this used to be. That cheap version was fine for an ordinary post
        // (plenty of others to bury it before it could recur), but group
        // posts are comparatively rare: fetchGroupFeed's own offset walks
        // independently of fetchEveryoneFeed's (see this branch's own
        // Future.wait), and once fetchGroupFeed runs past its own small
        // result count it starts returning ones already seen many pages
        // back — well outside a last-3 window — reported live as "the same
        // group post twice". A new lap (reachedEnd below) still resets this
        // scope, so intentional resurfacing after a full wrap is unchanged.
        final seenIds = _pagedItems
            .skip(_lapStartIndex)
            .map((i) => i.postId)
            .toSet();
        page = page.where((i) => seenIds.add(i.postId)).toList();

        // Fewer than a full page (including empty) means we've hit the end
        // of real data — wrap the offset back to 0 and start a new lap
        // instead of stopping the feed dead.
        final reachedEnd = remote.length < _pageSize;

        setState(() {
          _pagedItems.addAll(page);
          if (reachedEnd) {
            _offset = 0;
            _lap++;
            _lastLoopFetch = DateTime.now();
            // New lap starts here — same bookkeeping the Friends branch
            // does on its own wrap, and what makes the dedup above scoped
            // to "this lap" rather than "forever" (which would eventually
            // dedupe the feed down to nothing).
            _lapStartIndex = _pagedItems.length;
            _sectionStarts[_lapStartIndex] = null;
          } else {
            _offset += _pageSize;
          }
          _loading = false;
        });
        _refreshMomentCounts(page);
      }
    } finally {
      _loadingMore = false;
      // _loading (the full-screen skeleton) used to be cleared ONLY on the
      // success path, inside each branch's setState. Every other way out of
      // the try left it true forever: an early `if (!mounted) return`, or
      // anything throwing (there is no catch here — only this finally). The
      // Friends feed was the visible victim, because its _localItems is
      // always empty by design (see initState), so `_loading &&
      // _localItems.isEmpty` reduces to plain `_loading` — the screen sat
      // on two shimmer placeholder cards instead of ever reaching its real
      // content or its empty state. Clearing it here makes the skeleton
      // resolve on EVERY exit path, not just the happy one.
      if (mounted && _loading) setState(() => _loading = false);
    }
    // Friends ran out on THIS call: start the campus section now rather
    // than waiting for another scroll. A feed with no friend posts at all
    // has nothing to scroll, so it would otherwise sit on its empty state.
    if (_isFriends && !wasEnded && _friendsFeedEnded && mounted) {
      unawaited(_loadPage());
    }
    // The FIRST postFrameCallback (initState) fires while this screen is
    // still showing _LoadingList (no real SpotlightCards mounted yet, so
    // nothing registers with the controller and the recompute is a
    // silent no-op) — without a second one here, every card's focus
    // stays stuck at its default 0 (fully blurred/dimmed) until the user
    // manually scrolls, which reads as "the whole feed loaded blurred."
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _spotlightController.onScroll(),
    );
  }

  /// What Friends mode shows once friends' own posts are exhausted, in
  /// order:
  ///  1. campus posts the viewer can see and hasn't been shown (RLS decides
  ///     "can see", exactly as for every other read, so nothing the audience
  ///     rules hide can leak in here);
  ///  2. once those run dry, a Rewind lap: everything shown so far, shuffled,
  ///     under its own divider so it reads as a second look, not a bug.
  /// Rewind laps go through the same 1.5s lap throttle as Everyone mode.
  Future<void> _loadFriendsOverflow() async {
    if (!_campusExhausted) {
      final rows = await FeedService.instance.fetchEveryoneFeed(
        limit: _pageSize,
        offset: _campusOffset,
        excludeReacted: false,
      );
      if (!mounted) return;
      final shown = {
        for (final i in [..._localItems, ..._pagedItems]) i.postId,
      };
      final fresh = rows.where((i) => shown.add(i.postId)).toList()..shuffle();
      setState(() {
        if (fresh.isNotEmpty && !_sectionStarts.values.contains(_kCampusLabel) &&
            !_sectionStarts.values.contains(_kCampusLabelNoFriends)) {
          _sectionStarts[_pagedItems.length] = shown.length == fresh.length
              ? _kCampusLabelNoFriends
              : _kCampusLabel;
        }
        _pagedItems.addAll(fresh);
        if (rows.length < _pageSize) {
          _campusExhausted = true;
        } else {
          _campusOffset += _pageSize;
        }
        _loading = false;
      });
      if (fresh.isNotEmpty) _refreshMomentCounts(fresh);
      if (fresh.isNotEmpty || !_campusExhausted) return;
    }

    // Rewind lap.
    // A Moment that has ended since it was loaded never comes back in a
    // Rewind lap: Moments last 24h, full stop.
    final momentCutoff =
        DateTime.now().subtract(FeedService.momentVisibleWindow);
    final pool = <String, FeedItem>{
      for (final i in [..._localItems, ..._pagedItems])
        if (!i.isMoment ||
            (kMomentsEnabled &&
                i.createdAt != null &&
                i.createdAt!.isAfter(momentCutoff)))
          i.postId: i,
    }.values.toList()
      ..shuffle();
    if (pool.isEmpty) return; // genuinely nothing anywhere yet
    setState(() {
      _sectionStarts[_pagedItems.length] = _lap == 0 ? _kRewindLabel : null;
      _pagedItems.addAll(pool);
      _lap++;
      _lastLoopFetch = DateTime.now();
      _loading = false;
    });
  }

  static const _kCampusLabel = "You're all caught up ✨ · More from your campus";
  static const _kCampusLabelNoFriends =
      "Your friends haven't posted yet · Here's what's happening on campus";
  static const _kRewindLabel = 'Rewind ⏪';

  /// Render order: live local posts, then [_pagedItems] with a divider at
  /// each labelled section start. At most one copy of a post per section.
  List<Object> get _slots {
    final out = <Object>[];
    var seen = <String>{};
    for (final item in _localItems) {
      if (seen.add(item.postId)) out.add(item);
    }
    for (var i = 0; i < _pagedItems.length; i++) {
      if (_sectionStarts.containsKey(i)) {
        seen = <String>{};
        final label = _sectionStarts[i];
        if (label != null) out.add(_FeedDivider(label));
      }
      final item = _pagedItems[i];
      if (seen.add(item.postId)) out.add(item);
    }
    return _withSuggestions(out);
  }

  /// Re-query on a visibility change. Not wired straight to [_refresh]
  /// because a ValueNotifier can fire while this screen is off-stage (the
  /// accept happens on a profile pushed above it), and _refresh calls
  /// setState — so the mounted check has to happen here, not there.
  void _onFeedRefreshSignal() {
    if (!mounted) return;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    // A scroll-triggered _loadPage may be in flight; it early-returns at
    // the _loadingMore guard, so clearing _pagedItems FIRST and then
    // calling _loadPage could leave the feed empty until the next scroll —
    // the list renders _EmptyState in the gap. Waiting for the in-flight
    // page to settle means the clear-and-reload below always actually
    // reloads.
    while (_loadingMore) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    setState(() {
      _pagedItems.clear();
      _offset = 0;
      _groupAudienceOffset = 0;
      _lapStartIndex = 0;
      _lap = 0;
      _lastLoopFetch = null;
      _friendsFeedEnded = false;
      _sectionStarts.clear();
      _campusOffset = 0;
      _campusExhausted = false;
    });
    if (_isFriends) unawaited(_loadSuggestions());
    await _loadPage();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _postsChannel?.unsubscribe();
    _realtimeDebounce?.cancel();
    feedRefreshSignal.removeListener(_onFeedRefreshSignal);
    _spotlightController.spotlightPostId.removeListener(_onSpotlightChanged);
    _spotlightController.dispose();
    _privileges.dispose();
    super.dispose();
  }

  // Live local posts (just-submitted this session) always lead, newest
  // first; _pagedItems is already in final render order (each fetched page
  // shuffled independently, pages appended in fetch order — see
  // _loadPage) so no further sort happens here.
  // One authoritative dedupe, at the single point everything renders
  // through (_slots): no insertion path can put the same post on screen
  // twice within a section. Only a labelled Rewind / Everyone lap may repeat
  // a post, and only in a later section. _mergeNewFriendsPosts' own dedupe
  // once let two copies from one merge batch through, which is why this
  // lives here and not upstream.
  List<FeedItem> get _allItems => _slots.whereType<FeedItem>().toList();

  void _openDetail(FeedItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => item.type == 'memory'
            ? MemoryDetailScreen(item: item)
            : SinglePostDetailScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _localItems.isEmpty) {
      // BUG FIX (explicit report, with a screenshot): _LoadingList used to
      // take no topInset at all, unlike the real content ListView below
      // (which pads by `widget.topInset` to clear the floating header —
      // see that ListView's own doc). Without it, the shimmer skeleton's
      // first card rendered right up against the header's bottom edge
      // with no reserved gap, and the header's own opaque backing (see
      // home_screen.dart's DecoratedBox) ending flush against that card
      // read as a visible horizontal strip between them. Passing the same
      // inset here makes the loading state reserve exactly the space the
      // loaded state does, so nothing sits flush against the header in
      // either state.
      return _LoadingList(topInset: widget.topInset);
    }

    final slots = _slots;
    if (!slots.any((s) => s is FeedItem)) {
      return _EmptyState(
        onOpenCamera: () => Navigator.of(context).push(openCameraRoute()),
      );
    }

    // Real posts only — the DEMO Moment cards (kDemoMoments) that used to be
    // interleaved every 3rd post are gone. They were visual filler for
    // testing the Moment card before real Moments existed, and now that
    // Moments post and reply for real they only made the feed look like it
    // held content it didn't. Object, not a sealed type: this list (_slots)
    // holds FeedItem, MomentEntry or a _FeedDivider section label,
    // discriminated by `is` in the itemBuilder below. (Used to also hold a Wall-strip marker as the first slot —
    // deferred post-launch, see WallService/WallPreviewStrip, both left
    // intact but unwired.)

    return RefreshIndicator(
      color: const Color(0xFFE1306C),
      backgroundColor: const Color(0xFF1A1A20),
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            _spotlightController.onScroll();
            // Trigger the next page a bit before the true end so it's
            // ready by the time the user reaches it.
            final m = notification.metrics;
            if (m.maxScrollExtent - m.pixels < 800) _loadPage();
          }
          return false;
        },
        // widget.topInset used to reserve HomeScreen's floating
        // _SlimHeader as a spacer OUTSIDE this scrollable (a Column +
        // AnimatedContainer above an Expanded ListView) — that made the
        // feed's own top a hard floor short of the real top of the
        // screen, so content never actually scrolled up through the
        // header band the way Ping's single SingleChildScrollView (whose
        // inset is padding, not a sibling spacer) does. Moving the inset
        // into the ListView's own padding puts it back inside the
        // scrollable, so the first post now slides up underneath the
        // header on scroll instead of stopping below it — while
        // BouncingScrollPhysics still settles pixels back to exactly 0,
        // so the very top still ends the scroll, just further up than
        // before. TweenAnimationBuilder replaces the old
        // AnimatedContainer for animating that padding as topInset itself
        // shrinks (header collapsing) — ListView.padding isn't itself
        // animatable.
        //
        // The inset is now CONSTANT while scrolling (HomeScreen passes the
        // full header height, see its topInset). It used to shrink by
        // ~150px the moment you scrolled past 8px, animated over 220ms —
        // so the whole list slid up under your finger mid-scroll (and back
        // down at the top), and the TweenAnimationBuilder rebuilt the entire
        // ListView every frame of that. That slide was the "fluctuating,
        // not smooth like Instagram" feel. The header now simply collapses
        // over content that never moves on its own.
        child: Builder(
          builder: (context) => ListView.builder(
            key: _spotlightController.viewportKey,
            controller: _spotlightController.scrollController,
            physics: const BouncingScrollPhysics(),
            // Build ~2 screens ahead/behind instead of the 250px default:
            // cards (and their network loads) are ready BEFORE they scroll
            // into view, and aren't torn down the instant they leave it,
            // so nothing pops in or resizes while you're looking.
            cacheExtent: 1600,
            // +14 top: explicit report — the first post sat flush against
            // the Friends/Anon toggle pill with no breathing room between
            // the two. Bottom: the floating tab bar is an overlay in the
            // shell's Stack, so without this the last card scrolls under
            // it and its actions become untappable (the "tab bar covers
            // the post" report).
            padding: EdgeInsets.only(
              top: widget.topInset + 14,
              // + viewInsets.bottom: without it, a comment box on a post
              // near the end of the feed had no scroll room left for
              // Flutter's own focus-follows-keyboard (Scrollable.
              // ensureVisible) to bring it above the keyboard — the list's
              // maxScrollExtent stopped short, so the keyboard simply
              // covered the box with nowhere for it to go. Reported as
              // "when typing... the typing bar is covering it full".
              bottom: MediaQuery.paddingOf(context).bottom +
                  kTabBarHeight +
                  kTabBarBottomOffset +
                  16 +
                  MediaQuery.viewInsetsOf(context).bottom,
            ),
            // +1 in friends mode for the post-size selector that leads the
            // list — "give option ... in friends posting section above".
            itemCount: slots.length,
            itemBuilder: (context, i) {
              final slot = slots[i];
              if (slot is _FeedDivider) return _FeedDividerView(label: slot.label);
              if (slot is _SuggestionSlot) {
                return PeopleSuggestionStrip(
                  people: slot.people,
                  added: _suggestAdded,
                  onAdded: (id, circle) =>
                      setState(() => _suggestAdded[id] = circle),
                  onDismiss: _hideSuggestion,
                );
              }
              if (slot is MomentEntry) {
                return Padding(
                  // Matches the 40px bottom-only gap every post uses
                  // (was vertical:8 symmetric — a smaller, asymmetric
                  // gap around Moment cards specifically, breaking the
                  // otherwise-uniform feed rhythm). Horizontal 12 is
                  // Moment's own intentional inset (a distinct
                  // card-in-card look, unlike full-bleed posts), left
                  // as-is.
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                  child: MomentCard(
                    moment: slot,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LockedRepliesScreen(
                          momentId: slot.id,
                          title: slot.title,
                          replies: slot.replies,
                        ),
                      ),
                    ),
                  ),
                );
              }
              final item = slot as FeedItem;
              // A REAL posted Moment (posts.post_type = 'moment') gets
              // the same gradient card as the demo entries above — it
              // used to fall through to DesignSoloCard and render as an
              // ordinary post, because FeedItem carried no post_type.
              if (item.isMoment) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
                  child: MomentCard(
                    moment: MomentEntry.fromFeedItem(
                      item,
                      replyCount: _momentReplyCounts[item.postId],
                    ),
                    onMenu: () => _openPostMenu(item),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LockedRepliesScreen(
                          momentId: item.postId,
                          title: (item.caption ?? '').trim().isEmpty
                              ? 'Moment'
                              : item.caption!.trim(),
                          // Nothing stores contributions to a real moment
                          // yet — the screen opens empty rather than
                          // showing another moment's demo replies.
                          replies: const [],
                        ),
                      ),
                    ),
                  ),
                );
              }
              // EveryonePostCard is content-sized (header + inset image
              // + action row + comments row), not full-bleed like
              // MemoryFeedCard/SinglePostCard were — so it no longer
              // needs the Expanded height-forcing wrapper those did.
              // SpotlightCard still supplies the vertical-pager focus/
              // blur/scale mechanic and the whole-card tap-to-open-
              // detail gesture; its own floating action pill is turned
              // off (showActionOverlay: false) since the card now draws
              // its own action row instead.
              return Padding(
                // 40 — bumped again (was 28, itself doubled from 14 per an
                // earlier correction) after a follow-up report that the gap
                // into the next post's header — specifically its presence
                // pill — still read as too tight. Single shared gap source
                // for every card type (solo/group both route through this
                // same wrapper, neither has its own outer margin), so it
                // stays uniform regardless of what's on either side —
                // including right after a comment card, into the next
                // post's header.
                //
                // Horizontal 8 added per explicit follow-up: "let there be
                // some minute gap between the walls of phone and the
                // posts" — both card types were running full-bleed to the
                // screen edges (0 side margin), which is also part of why
                // the corner radius read as less curved than intended: a
                // rounded corner flush against the screen edge shows less
                // of its own arc than the same radius once there is empty
                // space beside it to curve into. Kept deliberately small
                // ("minute") rather than matching the Moment cards' 12, so
                // personal/group posts still read as the wider, more
                // full-bleed treatment relative to Moments' card-in-card
                // look.
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 40),
                child: SpotlightCard(
                  item: item,
                  controller: _spotlightController,
                  privileges: _privileges,
                  onTap: () => _openDetail(item),
                  showActionOverlay: false,
                  // Plain continuous free-scroll feed now (no page-per-
                  // post centering) — see SpotlightCard.enableFocusEffect's
                  // own doc for why the blur/dim/scale treatment is
                  // switched off here specifically.
                  enableFocusEffect: false,
                  // GROUP posts (item.groupName != null) — including a
                  // private group's post reaching you only through your
                  // community (item.groupPostLocked: same card, photos
                  // after the first blurred, taps say "Be a friend to see
                  // it") — get DesignGroupCard. Memory layouts keep
                  // EveryonePostCard's own card. Regular individual posts
                  // get DesignSoloCard.
                  child: item.groupName != null
                      ? DesignGroupCard(item: item)
                      : item.type != 'memory'
                      ? DesignSoloCard(
                          postId: item.postId,
                          username: item.username ?? 'someone',
                          userId: item.userId,
                          avatarUrl: item.avatarUrl,
                          // Shared (Duo) post — the card draws a fused
                          // avatar and both names when these are set, and
                          // pings both people. Null on every ordinary post.
                          partnerUserId: item.partnerUserId,
                          partnerName: item.partnerName,
                          partnerAvatarUrl: item.partnerAvatarUrl,
                          pairStreak: item.pairStreak,
                          caption: item.caption,
                          photoUrl: item.photoUrl,
                          photoUrls: item.photos,
                          commentCount: item.commentCount,
                          onCommentTap: () => _openDetail(item),
                          onDeleted: () {
                            if (!mounted) return;
                            setState(() {
                              _localItems.removeWhere((i) => i.postId == item.postId);
                              _pagedItems.removeWhere((i) => i.postId == item.postId);
                            });
                          },
                          secondaryPhotoUrl: item.secondaryPhotoUrl,
                          insetOnRight: item.insetOnRight,
                          photoPath: item.photoPath,
                          aspectRatio: item.aspectRatio,
                        )
                      : EveryonePostCard(
                          postId: item.postId,
                          media: item.type == 'memory'
                              ? MemoryFeedCard(item: item)
                              : SinglePostCard(item: item, showFooter: false),
                          username: item.username ?? 'someone',
                          userId: item.userId,
                          avatarUrl: item.avatarUrl,
                          caption: item.caption,
                          commentCount: item.commentCount,
                          onCommentTap: () => _openDetail(item),
                          groupName: item.groupName,
                          communityTag: item.communityTag,
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingList extends StatefulWidget {
  const _LoadingList({required this.topInset});

  final double topInset;

  @override
  State<_LoadingList> createState() => _LoadingListState();
}

class _LoadingListState extends State<_LoadingList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0.04,
      end: 0.12,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => ListView.builder(
        padding: EdgeInsets.fromLTRB(12, widget.topInset + 8, 12, 100),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ShimmerCard(opacity: _anim.value),
        ),
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard({required this.opacity});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: kFriendsPostAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpenCamera});
  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Campus is quiet... be the first 👀',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onOpenCamera,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white70,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



/// A "New on campus" strip inside the Friends feed (see _withSuggestions).
class _SuggestionSlot {
  const _SuggestionSlot(this.people);
  final List<Map<String, dynamic>> people;
}

/// A section label inside the Friends feed (see _sectionStarts).
class _FeedDivider {
  const _FeedDivider(this.label);
  final String label;
}

class _FeedDividerView extends StatelessWidget {
  const _FeedDividerView({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
      child: Row(
        children: [
          line,
          const SizedBox(width: 12),
          Flexible(
            flex: 4,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 12),
          line,
        ],
      ),
    );
  }
}
