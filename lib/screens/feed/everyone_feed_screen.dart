import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/glass.dart';
import '../../features/composer/composer_screen.dart';
import '../../services/feed_service.dart';
import '../../services/post_service.dart';
import '../../services/wall_service.dart';
import 'memory_detail_screen.dart';
import 'single_post_detail_screen.dart';
import 'widgets/everyone_post_card.dart';
import 'widgets/group_post_cards/group_post_card.dart';
import 'widgets/memory_feed_card.dart';
import 'widgets/moment_card.dart';
import 'widgets/personal_post_card.dart';
import 'widgets/single_post_card.dart';
import 'widgets/spotlight_card.dart';
import 'widgets/spotlight_feed_controller.dart';
import 'widgets/spotlight_privileges_controller.dart';
import 'widgets/wall_preview_strip.dart';

class EveryoneFeedScreen extends StatefulWidget {
  const EveryoneFeedScreen({
    required this.chromeCollapsed,
    this.topInset = 0,
    super.key,
  });

  /// HomeScreen's own scroll-driven chrome-collapse state (shared with the
  /// Anonymous tab's header) — the Wall preview strip collapses/reappears
  /// in lockstep with the rest of the header (bell, reaction, toggle,
  /// score) rather than tracking its own independent scroll delta, so
  /// "everything hides on scroll, everything reappears at the complete
  /// top" reads as one coordinated header, not two separate mechanisms.
  final bool chromeCollapsed;

  /// Reserved space for HomeScreen's floating _SlimHeader (which overlays
  /// this screen via a Stack, same as AnonymousTab.topInset) — without
  /// this, WallPreviewStrip renders at y=0 and the header (Anon/Friends
  /// toggle pill included) paints directly on top of it instead of above
  /// it. Defaults to 0 for the standalone screenshot-mode call sites
  /// (main.dart) that render this screen with no floating header at all.
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
  List<Highlight> _highlights = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _offset = 0;
  // Lap count + throttle for the infinite-loop-once-real-data-runs-out
  // behavior (see _loadPage) — only engages once we've actually wrapped,
  // so normal paginated scrolling through real data is never throttled.
  int _lap = 0;
  DateTime? _lastLoopFetch;
  StreamSubscription<List<LocalPost>>? _sub;

  final _spotlightController = SpotlightFeedController();
  final _privileges = SpotlightPrivilegesController();

  @override
  void initState() {
    super.initState();
    _localItems = PostService.instance.everyonePosts
        .map(FeedItem.fromLocalPost)
        .toList();
    _sub = PostService.instance.everyoneFeedStream.listen((posts) {
      if (mounted) {
        setState(
            () => _localItems = posts.map(FeedItem.fromLocalPost).toList());
      }
    });
    _spotlightController.spotlightPostId.addListener(_onSpotlightChanged);
    _loadPage();
    // First page loads with no scroll notification ever having fired, so it
    // would otherwise sit at focus=0 (fully blurred/dimmed) until the user
    // nudges the pager. Force one recompute once the first frame lays out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _spotlightController.onScroll());
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
  /// the initial load and every subsequent scroll-triggered page. The Wall
  /// highlights strip is unpaginated (fetched once, page 0 only).
  Future<void> _loadPage() async {
    if (_loadingMore) return;
    // Only throttles once a lap has actually happened (tiny real dataset
    // + fast scrolling) — real paginated fetches are never delayed.
    if (_lap > 0 && _lastLoopFetch != null &&
        DateTime.now().difference(_lastLoopFetch!) <
            const Duration(milliseconds: 1500)) {
      return;
    }
    _loadingMore = true;
    final isFirstPage = _offset == 0 && _lap == 0;

    // try/finally: any fetch/mapping error must never leave _loadingMore
    // stuck true, or every future scroll-triggered call silently no-ops at
    // the guard above forever (see AnonymousTab._loadMoreRemote's own note
    // — the exact bug that caused a real permanent dead-end there).
    try {
      final results = await Future.wait([
        FeedService.instance.fetchEveryoneFeed(limit: _pageSize, offset: _offset),
        FeedService.instance.fetchGroupFeed(limit: _pageSize, offset: _offset),
        if (isFirstPage) WallService.instance.fetchTopHighlights(),
      ]);
      if (!mounted) return;

      final remote = results[0] as List<FeedItem>;
      final group = results[1] as List<FeedItem>;
      final localIds = _localItems.map((i) => i.postId).toSet();
      // Shuffle WITHIN this page only — keeps pagination boundaries stable
      // (a post fetched on page 2 always renders after every page-1
      // post), instead of a global reshuffle that could strand a post
      // unseen.
      var page = [
        ...remote.where((i) => !localIds.contains(i.postId)),
        ...group,
      ]..shuffle();
      // Cheap dedup at a lap boundary: drop anything that's also one of
      // the last few already-loaded posts, so wrapping doesn't repeat a
      // post back-to-back. Not exhaustive — good enough per spec.
      final tailIds = _pagedItems.reversed.take(3).map((i) => i.postId).toSet();
      page = page.where((i) => !tailIds.contains(i.postId)).toList();

      // Fewer than a full page (including empty) means we've hit the end
      // of real data — wrap the offset back to 0 and start a new lap
      // instead of stopping the feed dead.
      final reachedEnd = remote.length < _pageSize;

      setState(() {
        _pagedItems.addAll(page);
        if (isFirstPage) _highlights = results[2] as List<Highlight>;
        if (reachedEnd) {
          _offset = 0;
          _lap++;
          _lastLoopFetch = DateTime.now();
        } else {
          _offset += _pageSize;
        }
        _loading = false;
      });
    } finally {
      _loadingMore = false;
    }
    // The FIRST postFrameCallback (initState) fires while this screen is
    // still showing _LoadingList (no real SpotlightCards mounted yet, so
    // nothing registers with the controller and the recompute is a
    // silent no-op) — without a second one here, every card's focus
    // stays stuck at its default 0 (fully blurred/dimmed) until the user
    // manually scrolls, which reads as "the whole feed loaded blurred."
    WidgetsBinding.instance.addPostFrameCallback((_) => _spotlightController.onScroll());
  }

  Future<void> _refresh() async {
    setState(() {
      _pagedItems.clear();
      _offset = 0;
      _lap = 0;
      _lastLoopFetch = null;
    });
    await _loadPage();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spotlightController.spotlightPostId.removeListener(_onSpotlightChanged);
    _spotlightController.dispose();
    _privileges.dispose();
    super.dispose();
  }

  // Live local posts (just-submitted this session) always lead, newest
  // first; _pagedItems is already in final render order (each fetched page
  // shuffled independently, pages appended in fetch order — see
  // _loadPage) so no further sort happens here.
  List<FeedItem> get _allItems {
    final localIds = _localItems.map((i) => i.postId).toSet();
    return [
      ..._localItems,
      ..._pagedItems.where((i) => !localIds.contains(i.postId)),
    ];
  }

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
      return const _LoadingList();
    }

    final items = _allItems;
    if (items.isEmpty) {
      return _EmptyState(onOpenCamera: () => Navigator.of(context).push(openCameraRoute()));
    }

    // Interleaves the DEMO Moment cards (moment_card.dart) among real posts
    // — every 3rd post — so the Moments/Bucket card UI is visually testable
    // in the feed immediately, without needing enough real Bucket data to
    // populate a live feed integration. Object, not a sealed type: this
    // list only ever holds FeedItem, DemoMoment, or _WallStripSlot,
    // discriminated by `is` in the itemBuilder below.
    final slots = <Object>[];
    // The Wall strip is now a genuine first list item, not a Column sibling
    // with its own AnimatedSize/chromeCollapsed-driven collapse — it scrolls
    // away with everything else at the same rate, no separate animation, no
    // snap, no phantom reserved space once scrolled past. See this widget's
    // own build() doc below for what this replaced.
    if (_highlights.isNotEmpty) slots.add(_WallStripSlot(_highlights));
    var momentIdx = 0;
    for (var i = 0; i < items.length; i++) {
      slots.add(items[i]);
      if ((i + 1) % 3 == 0 && momentIdx < kDemoMoments.length) {
        slots.add(kDemoMoments[momentIdx]);
        momentIdx++;
      }
    }

    return Column(
      children: [
        // Reserves room for HomeScreen's floating _SlimHeader overlay only
        // — see widget.topInset's own doc. Unrelated to the Wall strip's
        // old collapse animation (removed below, see _WallStripSlot):
        // this spacer doesn't hide/show on scroll, it's set once (softened
        // by AnimatedContainer purely for the single cold-start measurement
        // transition, see HomeScreen._headerBaselineHeight's own doc) and
        // stays constant.
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: widget.topInset,
        ),
        Expanded(
          child: RefreshIndicator(
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
              // Plain continuous ListView, not PageView — no page-snap, no
              // neighbor peek. EveryonePostCard is content-sized (not
              // full-bleed), so each item takes only the height its own
              // content needs and the next post sits directly below it,
              // exactly like a normal Instagram-style feed. BouncingScrollPhysics
              // for natural momentum/overscroll (iOS-style rubber-band),
              // matching the free-scroll feel spec asks for.
              child: ListView.builder(
                key: _spotlightController.viewportKey,
                controller: _spotlightController.scrollController,
                physics: const BouncingScrollPhysics(),
                itemCount: slots.length,
                itemBuilder: (context, i) {
                  final slot = slots[i];
                  if (slot is _WallStripSlot) {
                    return WallPreviewStrip(highlights: slot.highlights);
                  }
                  if (slot is DemoMoment) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: MomentCard(
                        moment: slot,
                        onTap: () => showGlassToast(context, 'Moments coming soon'),
                      ),
                    );
                  }
                  final item = slot as FeedItem;
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                      // Three card treatments in the same merged, sorted feed:
                      // GROUP posts (item.groupName != null) get the 4-layout
                      // collage treatment (Float/Mosaic/Stack/Strip — see
                      // widgets/group_post_cards/), replacing the plain
                      // EveryonePostCard they used to render through. Memory
                      // layouts keep EveryonePostCard's own card. Regular
                      // individual single-photo posts get the dark
                      // dual-camera PostCard (post_card.dart) via its
                      // PersonalPostCard adapter, which owns real reaction
                      // data the same way EveryonePostCard does.
                      child: item.groupName != null
                          ? GroupPostCard(item: item)
                          : item.type != 'memory'
                              ? PersonalPostCard(
                                  postId: item.postId,
                                  handle: item.username ?? 'someone',
                                  avatar: item.avatarUrl,
                                  backPhoto: item.photoUrl,
                                  commentCount: item.commentCount,
                                  onOpenComments: () => _openDetail(item),
                                )
                              : EveryonePostCard(
                                  postId: item.postId,
                                  media: item.type == 'memory'
                                      ? MemoryFeedCard(item: item)
                                      : SinglePostCard(item: item, showFooter: false),
                                  username: item.username ?? 'someone',
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
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Wall strip slot — a plain data-holding marker, not a widget, so it can
// sit in `slots` alongside FeedItem/DemoMoment and be discriminated by
// `is` in itemBuilder just like them. See the Wall-strip-related comments
// in build() above for why this replaced the old AnimatedSize/
// chromeCollapsed-driven collapse.
// ---------------------------------------------------------------------------

class _WallStripSlot {
  const _WallStripSlot(this.highlights);
  final List<Highlight> highlights;
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingList extends StatefulWidget {
  const _LoadingList();

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
    _anim = Tween<double>(begin: 0.04, end: 0.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
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
      aspectRatio: 4 / 5,
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
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white70, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

