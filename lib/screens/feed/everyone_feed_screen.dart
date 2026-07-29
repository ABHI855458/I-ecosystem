import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/composer/composer_screen.dart';
import '../../services/feed_service.dart';
import '../../services/post_service.dart';
import '../../services/wall_service.dart';
import 'memory_detail_screen.dart';
import 'single_post_detail_screen.dart';
import 'widgets/memory_feed_card.dart';
import 'widgets/single_post_card.dart';
import 'widgets/spotlight_card.dart';
import 'widgets/spotlight_feed_controller.dart';
import 'widgets/spotlight_privileges_controller.dart';
import 'widgets/wall_preview_strip.dart';

class EveryoneFeedScreen extends StatefulWidget {
  const EveryoneFeedScreen({super.key});

  @override
  State<EveryoneFeedScreen> createState() => _EveryoneFeedScreenState();
}

class _EveryoneFeedScreenState extends State<EveryoneFeedScreen> {
  List<FeedItem> _remoteItems = [];
  List<FeedItem> _localItems = [];
  List<Highlight> _highlights = [];
  bool _loading = true;
  bool _wallCollapsed = false;
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
    _load();
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

  Future<void> _load() async {
    final results = await Future.wait([
      FeedService.instance.fetchEveryoneFeed(),
      WallService.instance.fetchTopHighlights(),
    ]);
    if (mounted) {
      setState(() {
        _remoteItems = results[0] as List<FeedItem>;
        _highlights = results[1] as List<Highlight>;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spotlightController.spotlightPostId.removeListener(_onSpotlightChanged);
    _spotlightController.dispose();
    _privileges.dispose();
    super.dispose();
  }

  List<FeedItem> get _allItems {
    final localIds = _localItems.map((i) => i.postId).toSet();
    return [
      ..._localItems,
      ..._remoteItems.where((i) => !localIds.contains(i.postId)),
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

    // Floating bottom nav overlays tab content rather than reserving layout
    // space (see MainShell), so the pager must leave room itself — same
    // approach as the Anonymous tab's navBarBottom padding.
    final navBarBottom = 56.0 + MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        // Collapses away once the user pages past the first post, so the
        // post can use the freed space — reappears when scrolled back to
        // the top. The Anonymous/Everyone toggle lives above this (in
        // HomeScreen's header) and always stays visible regardless.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: (_wallCollapsed || _highlights.isEmpty)
              ? const SizedBox.shrink()
              : WallPreviewStrip(highlights: _highlights),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: navBarBottom),
            child: RefreshIndicator(
            color: const Color(0xFFE1306C),
            backgroundColor: const Color(0xFF1A1A20),
            onRefresh: _load,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification) {
                  _spotlightController.onScroll();
                  // Direction-based with a dead zone (matches the bottom
                  // nav's own shrink logic) — an absolute-position
                  // threshold flickered by re-triggering on every pixel
                  // hovering near the cutoff.
                  final delta = notification.scrollDelta;
                  if (delta != null) {
                    if (delta > 2 && !_wallCollapsed) {
                      setState(() => _wallCollapsed = true);
                    } else if (delta < -2 && _wallCollapsed) {
                      setState(() => _wallCollapsed = false);
                    }
                  }
                } else if (notification is ScrollEndNotification) {
                  _spotlightController.onScrollEnd();
                  if (notification.metrics.pixels <= 10 && _wallCollapsed) {
                    setState(() => _wallCollapsed = false);
                  }
                }
                return false;
              },
              child: PageView.builder(
                key: _spotlightController.viewportKey,
                controller: _spotlightController.scrollController,
                scrollDirection: Axis.vertical,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PostHeaderBlob(item: item),
                        const SizedBox(height: 8),
                        Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SpotlightCard(
                            item: item,
                            controller: _spotlightController,
                            privileges: _privileges,
                            onTap: () => _openDetail(item),
                            child: item.type == 'memory'
                                ? MemoryFeedCard(item: item)
                                : SinglePostCard(item: item),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        ),
      ],
    );
  }
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

// ---------------------------------------------------------------------------
// Post header — name + branch in one pill, separate from the post bubble
// ---------------------------------------------------------------------------

class _PostHeaderBlob extends StatelessWidget {
  const _PostHeaderBlob({required this.item});
  final FeedItem item;

  String get _timeLabel {
    final createdAt = item.createdAt;
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final name = item.username ?? 'someone';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (item.branch != null) ...[
              const SizedBox(width: 7),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                item.branch!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (_timeLabel.isNotEmpty) ...[
              const SizedBox(width: 7),
              Text(
                '· $_timeLabel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
