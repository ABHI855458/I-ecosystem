import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../main_shell.dart' show kTabBarBottomOffset, kTabBarHeight;
import '../../screens/feed/widgets/photo_post_card.dart';
import '../../screens/feed/widgets/text_post_card.dart';
import '../../services/feed_service.dart';
import '../../services/ping_service.dart';
import '../../services/post_service.dart';
import '../../shared/feed_notif_bar.dart';
import '../ping/ping_prompt_sheet.dart';
import 'score_service.dart';
import 'viewer_service.dart';

// ---------------------------------------------------------------------------
// Post model + data
// collageLayout: 0=single, 1=sideBySide(2), 2=triptych(3), 3=grid2x2(4), 4=scrapbook(5)
// ---------------------------------------------------------------------------

class _AnonPost {
  const _AnonPost({
    required this.id,
    this.realId,
    required this.handle,
    required this.vibe,
    required this.text,
    required this.timeLeft,
    required this.timeAgo,
    required this.relatables,
    this.communities = const [],
    this.personaPhotoUrl,
    this.photoUrl,
    this.localPhotoPath,
    this.collagePhotos,
    this.collageLayout = 0,
    this.aspectRatio = 4.0 / 5.0,
    this.replyingTo,
    this.anonScore,
    this.posterScore = 60,
    this.pingCount = 0,
    this.commentCount = 0,
  });

  final int id;

  /// Real posts-table UUID, set only for genuine backend posts (live
  /// submissions and fetchAnonFeed rows) — [id] stays a synthetic
  /// hashCode purely to key the demo viewer/score simulation maps
  /// (int-keyed below), which have no use for a real UUID. This is
  /// what ReactionService/RealMoji must query against; null falls back to
  /// id.toString() for the old static _kPosts demo entries only.
  final String? realId;
  String get postId => realId ?? id.toString();

  final String handle;
  final String vibe;
  final String text;
  final String timeLeft;
  final String timeAgo;
  final int relatables;
  final List<String> communities;

  /// The poster's anon persona photo (set via Profile > Anon persona
  /// photo) — never their real profile photo. Null falls back to a plain
  /// silhouette glyph, not initials (initials can hint at a real name).
  final String? personaPhotoUrl;

  /// A real network photo for this post, when set — takes priority over
  /// [collagePhotos]'s flat Color swatches. Demo data needs at least one of
  /// these to honestly verify the image-dominant layout and persona-photo
  /// corner overlap; a flat Color has no visual edge/texture to check either
  /// against.
  final String? photoUrl;

  /// Local file path for a just-captured post, before its Supabase image
  /// upload finishes (PostService.addPost emits optimistically, ahead of
  /// the upload — see PostService._saveToSupabase). Only ever set for
  /// posts converted from a live PostService.anonFeedStream event, never
  /// for demo data. [photoUrl] takes priority when both are set.
  final String? localPhotoPath;
  final List<Color>? collagePhotos;
  final int collageLayout;
  final double aspectRatio;
  final String? replyingTo;
  final int? anonScore;
  final int posterScore;
  final int pingCount;
  final int commentCount;

  /// True when this post has no photo at all (text-only ghost-prompt
  /// reply) — drives whether the itemBuilder below routes to
  /// PhotoPostCard or TextPostCard.
  bool get hasPhoto =>
      photoUrl != null ||
      localPhotoPath != null ||
      (collagePhotos != null && collagePhotos!.isNotEmpty);

  bool get isSinglePhoto =>
      collagePhotos != null && collagePhotos!.length == 1 && collageLayout == 0;
}

// ---------------------------------------------------------------------------
// Comment model
// ---------------------------------------------------------------------------

class _Comment {
  const _Comment({
    required this.handle,
    required this.text,
    required this.timeAgo,
    this.likes = 0,
    this.replies = const [],
  });
  final String handle;
  final String text;
  final String timeAgo;
  final int likes;
  final List<_Comment> replies;
}

const _kPosts = [
  _AnonPost(
    id: 1,
    handle: 'paper_crane42',
    vibe: 'late night thoughts',
    text:
        "Does anyone else feel like they're performing a version of themselves that isn't really them?",
    timeLeft: '6h left',
    timeAgo: '2h ago',
    relatables: 47,
    communities: ['CSE', '3rd Year', 'Campus'],
    personaPhotoUrl: 'https://i.pravatar.cc/120?img=12',
    photoUrl: 'https://picsum.photos/seed/anonpost1/600/800',
    collagePhotos: [Color(0xFF1C2030), Color(0xFF2A1520), Color(0xFF1A2A1A)],
    collageLayout: 2, // triptych
    replyingTo: 'Who are you when no one\'s watching?',
    anonScore: 156,
    posterScore: 230,
    pingCount: 23,
    commentCount: 14,
  ),
  _AnonPost(
    id: 2,
    handle: 'velvet_echo19',
    vibe: 'exam stress',
    text: "Failed my internals again. Can't tell my parents.",
    timeLeft: '4h left',
    timeAgo: '4h ago',
    relatables: 31,
    communities: ['CSE', 'Campus'],
    collagePhotos: [Color(0xFF0E0C18)],
    collageLayout: 0,
    aspectRatio: 4.0 / 5.0,
    replyingTo: 'What\'s been weighing on you this week?',
    anonScore: 89,
    posterScore: 89,
    pingCount: 15,
    commentCount: 8,
  ),
  _AnonPost(
    id: 3,
    handle: 'midnight_owl73',
    vibe: 'hot take',
    text:
        "The canteen coffee is genuinely better than Starbucks and I will die on this hill",
    timeLeft: '7h left',
    timeAgo: '1h ago',
    relatables: 156,
    communities: ['CSE', 'Photography', 'Campus'],
    collagePhotos: [
      Color(0xFF2A1510),
      Color(0xFF0F1E2A),
      Color(0xFF1C2030),
      Color(0xFF1E1A2E),
    ],
    collageLayout: 3, // 2x2 grid
    replyingTo: 'Unpopular opinion: campus edition 🔥',
    anonScore: 312,
    posterScore: 450,
    pingCount: 41,
    commentCount: 31,
  ),
  _AnonPost(
    id: 4,
    handle: 'cloud_walker55',
    vibe: 'missing someone',
    text:
        "Saw my ex at the library today. We didn't talk. It's been 8 months and it still hurts.",
    timeLeft: '2h left',
    timeAgo: '6h ago',
    relatables: 28,
    communities: ['3rd Year', 'Campus'],
    collagePhotos: [Color(0xFF0F1E2A), Color(0xFF1C1A28)],
    collageLayout: 1, // side by side
    replyingTo: 'Something you\'re not over yet',
    anonScore: 44,
    posterScore: 35,
    pingCount: 9,
    commentCount: 5,
  ),
  _AnonPost(
    id: 5,
    handle: 'amber_drift08',
    vibe: 'random thought',
    text:
        "Why do we shake hands with strangers but hug people we haven't seen in years. Social norms are wild.",
    timeLeft: '5h left',
    timeAgo: '3h ago',
    relatables: 92,
    communities: ['CSE', 'Music', 'Campus'],
    anonScore: 203,
    posterScore: 180,
    pingCount: 18,
    commentCount: 12,
  ),
];

const _kComments = <int, List<_Comment>>{
  1: [
    _Comment(
      handle: 'night_owl42',
      text: 'This hits so hard. Every single day.',
      timeAgo: '1h ago',
      likes: 14,
      replies: [
        _Comment(
          handle: 'ghost_verse',
          text: "Exactly, it's so draining after a while",
          timeAgo: '45m ago',
          likes: 4,
        ),
      ],
    ),
    _Comment(
      handle: 'soft_rain',
      text: 'PhD in performing for others 🎭',
      timeAgo: '30m ago',
      likes: 9,
    ),
    _Comment(
      handle: 'ember_9',
      text:
          'The gap between who you are and who they think you are just grows every year',
      timeAgo: '15m ago',
      likes: 6,
    ),
    _Comment(
      handle: 'quiet_loop',
      text: 'There are two of me and only one shows up to college',
      timeAgo: '8m ago',
      likes: 3,
    ),
  ],
  2: [
    _Comment(
      handle: 'quiet_storm',
      text: 'Telling parents feels impossible. Mine would spiral.',
      timeAgo: '3h ago',
      likes: 22,
      replies: [
        _Comment(
          handle: 'velvet_sky',
          text: 'Breathe. One internal at a time.',
          timeAgo: '2h ago',
          likes: 8,
        ),
        _Comment(
          handle: 'night_owl42',
          text: 'Have you talked to anyone else about it?',
          timeAgo: '1h ago',
          likes: 3,
        ),
      ],
    ),
    _Comment(
      handle: 'frost_bit',
      text: "You're not the only one hiding this. We got you.",
      timeAgo: '2h ago',
      likes: 11,
    ),
    _Comment(
      handle: 'river_echo',
      text: 'Same boat. Feel free to DM me',
      timeAgo: '1h ago',
      likes: 5,
    ),
  ],
  3: [
    _Comment(
      handle: 'amber_drift',
      text: 'FINALLY someone said it 🙌',
      timeAgo: '45m ago',
      likes: 31,
    ),
    _Comment(
      handle: 'pixel_haze',
      text:
          'The filter machine is broken tho 😭 took my 20 rs and gave me sadness',
      timeAgo: '30m ago',
      likes: 18,
      replies: [
        _Comment(
          handle: 'midnight_sun',
          text: 'The tea from Block C compensates tho',
          timeAgo: '20m ago',
          likes: 7,
        ),
      ],
    ),
    _Comment(
      handle: 'cloud_nine',
      text: 'Controversial but I respect the commitment',
      timeAgo: '1h ago',
      likes: 5,
    ),
    _Comment(
      handle: 'rain_drop7',
      text: 'I am willing to debate this at length. In the canteen.',
      timeAgo: '15m ago',
      likes: 12,
    ),
  ],
  4: [
    _Comment(
      handle: 'lonely_star',
      text: '8 months and it still hits. I feel you.',
      timeAgo: '5h ago',
      likes: 19,
    ),
    _Comment(
      handle: 'blue_echo',
      text: 'Library is genuinely the worst place to run into them',
      timeAgo: '4h ago',
      likes: 8,
      replies: [
        _Comment(
          handle: 'ghost_walk',
          text: 'Or the best? The eye contact moment then looking away',
          timeAgo: '3h ago',
          likes: 3,
        ),
      ],
    ),
    _Comment(
      handle: 'dust_wave',
      text: "Time's weird. Some things just don't dissolve.",
      timeAgo: '2h ago',
      likes: 6,
    ),
  ],
  5: [
    _Comment(
      handle: 'chaos_theory',
      text: 'Bro just accidentally deconstructed all of society',
      timeAgo: '2h ago',
      likes: 27,
    ),
    _Comment(
      handle: 'river_stone',
      text: 'Shaking hands is genuinely a weird ritual if you think about it',
      timeAgo: '1h ago',
      likes: 14,
    ),
    _Comment(
      handle: 'neon_glow',
      text: 'Social norms = collective hallucinations at scale',
      timeAgo: '30m ago',
      likes: 9,
    ),
    _Comment(
      handle: 'ink_drop',
      text: "Anthropology class is hitting different after reading this",
      timeAgo: '10m ago',
      likes: 4,
    ),
  ],
};

// ---------------------------------------------------------------------------
// AnonymousTab
// ---------------------------------------------------------------------------

class AnonymousTab extends StatefulWidget {
  const AnonymousTab({
    super.key,
    this.selectedCommunity = 'All',
    this.onNotify,
    this.topInset = 0,
  });

  final String selectedCommunity;

  /// Reports a merged viewer-activity message up to the shared
  /// [FeedNotifController] hosted in HomeScreen — this tab no longer shows
  /// its own toast locally (see HomeScreen.build/_FeedNotifHost).
  final void Function(String message, FeedNotifSeverity severity)? onNotify;

  /// Fixed top padding reserved for HomeScreen's always-pinned toggle row —
  /// NOT the full collapsible header (identity row/pills/prompt composer),
  /// which floats OVER this tab's content as an overlay rather than
  /// pushing it down (see HomeScreen.build). This is a constant, so the
  /// PageView's own available height never changes with the header's
  /// collapsed/expanded state — see the root-cause note on
  /// _AnonymousTabState.build's Padding below for why that matters.
  final double topInset;

  @override
  State<AnonymousTab> createState() => _AnonymousTabState();
}

class _AnonymousTabState extends State<AnonymousTab> {
  late final PageController _pageCtrl;
  int _activePage = 0;

  // Scroll-reveal focus (feature: PhotoPostCard's prompt/caption fade). One
  // continuous 0..1 ValueNotifier per post id, created lazily and kept for
  // the lifetime of this tab (the demo post list is fixed, so there's no
  // unbounded growth to worry about). 0 = peeking (prompt fully visible), 1
  // = dead-centered/full focus (prompt faded out) — see _updateFocus.
  final Map<int, ValueNotifier<double>> _focusNotifiers = {};

  ValueNotifier<double> _focusFor(int postId) =>
      _focusNotifiers.putIfAbsent(postId, () => ValueNotifier(0.0));

  /// Pings the post's author without the caller ever learning who that is
  /// (server-resolved by ping_post_author) — only for a post with a real
  /// backend id; the old static demo entries have none, so their ping
  /// button stays exactly as decorative as it always was.
  void _pingPostAuthor(_AnonPost post, String prompt) {
    final realId = post.realId;
    if (realId == null) return;
    PingService.instance.pingPostAuthor(postId: realId, prompt: prompt).catchError((Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is PingLimitExceeded ? e.toString() : "Couldn't send that ping.")),
      );
    });
  }

  void _updateFocus(double page) {
    final posts = _filtered;
    for (var i = 0; i < posts.length; i++) {
      final focus = (1 - (page - i).abs()).clamp(0.0, 1.0);
      _focusFor(posts[i].id).value = focus;
    }
  }

  // Score service
  late final ScoreService _scoreService;
  late StreamSubscription<ScoreEvent> _scoreSub;
  late final Map<int, int> _liveTotals;

  // Viewer service
  late final ViewerService _viewerService;
  late StreamSubscription<ViewEvent> _viewerSub;
  final Map<int, int> _watchingNow = {};
  final Map<int, List<ViewEvent>> _viewHistory = {};

  // Viewer-event merge (score events are tracked separately and never
  // surfaced in the toast — see _onScore). The merged message is handed off
  // to widget.onNotify; queueing/showing/dismiss timing lives in the shared
  // FeedNotifController owned by HomeScreen.
  Timer? _mergeTimer;
  final List<String> _mergeViewerNames = [];
  int _mergeViewerMysteryCount = 0;

  // Real posts submitted this session (camera tab + prompt bar's Respond
  // button both funnel into the same PostService.addPost, so one
  // subscription here covers both) — prepended ahead of the static demo
  // list, newest first (PostService already inserts newest-first on its
  // own end). Empty until the first live submission; the feed is 100%
  // demo content (_kPosts) until then, same as before tonight.
  List<_AnonPost> _liveAnonPosts = [];
  StreamSubscription<List<LocalPost>>? _liveAnonSub;

  // Real paginated backend posts (see FeedService.fetchAnonFeed) — leads
  // _kPosts (the static demo filler) in _filtered below. Same per-page
  // shuffle pattern as EveryoneFeedScreen._loadPage: each fetched page is
  // shuffled independently and appended, so page boundaries stay stable.
  static const _pageSize = 20;
  final List<_AnonPost> _remotePosts = [];
  int _remoteOffset = 0;
  bool _loadingMoreRemote = false;
  // Lap count + throttle for the infinite-loop-once-real-data-runs-out
  // behavior (see _loadMoreRemote) — mirrors EveryoneFeedScreen's _lap.
  int _remoteLap = 0;
  DateTime? _lastRemoteLoopFetch;

  _AnonPost _anonPostFromRemote(Map<String, dynamic> r) {
    final id = r['id'] as String;
    return _AnonPost(
      id: id.hashCode,
      realId: id,
      // Anonymous rows never carry a username (posts_feed nulls user_id for
      // non-authors — see supabase/schema.sql's posts_feed view) — a stable
      // pseudo-handle derived from the post id, not a real identity.
      handle: 'anon_${id.substring(0, 6)}',
      vibe: '',
      text: r['content'] as String? ?? '',
      timeLeft: '',
      timeAgo: 'now',
      relatables: 0,
      photoUrl: r['image_url'] as String?,
      aspectRatio: _parseAspectRatio(r['aspect_ratio'] as String?),
      replyingTo: r['prompt'] as String?,
    );
  }

  /// posts.aspect_ratio is TEXT storing 'W:H' (e.g. '4:5'), not a number —
  /// casting it straight to num crashed every real-post fetch (see
  /// _loadMoreRemote's try/finally for why that used to permanently kill
  /// pagination on the first bad row).
  static double _parseAspectRatio(String? raw) {
    final parts = raw?.split(':');
    if (parts?.length == 2) {
      final w = double.tryParse(parts![0]);
      final h = double.tryParse(parts[1]);
      if (w != null && h != null && h != 0) return w / h;
    }
    return 4.0 / 5.0;
  }

  Future<void> _loadMoreRemote() async {
    if (_loadingMoreRemote) return;
    // Only throttles once a lap has actually happened (tiny real dataset
    // + fast scrolling) — real paginated fetches are never delayed.
    if (_remoteLap > 0 && _lastRemoteLoopFetch != null &&
        DateTime.now().difference(_lastRemoteLoopFetch!) <
            const Duration(milliseconds: 1500)) {
      return;
    }
    _loadingMoreRemote = true;
    // try/finally: a single bad row (e.g. an unexpected aspect_ratio shape
    // — see _parseAspectRatio's own doc for the exact crash this used to
    // hit) must never leave _loadingMoreRemote stuck true, or every future
    // call silently no-ops at the guard above forever — that was the
    // actual cause of the reported dead-end, not the wrap logic itself.
    try {
      final rows = await FeedService.instance
          .fetchAnonFeed(limit: _pageSize, offset: _remoteOffset);
      if (!mounted) return;
      var page = rows.map(_anonPostFromRemote).toList()..shuffle();
      // Cheap dedup at a lap boundary — drop anything matching one of the
      // last few already-loaded posts so wrapping doesn't repeat one
      // back-to-back. Not exhaustive — good enough per spec.
      final tailIds = _remotePosts.reversed.take(3).map((p) => p.postId).toSet();
      page = page.where((p) => !tailIds.contains(p.postId)).toList();

      // Fewer than a full page (including empty) means we've hit the end
      // of real data — wrap the offset back to 0 and start a new lap
      // instead of stopping the feed dead.
      final reachedEnd = rows.length < _pageSize;

      setState(() {
        _remotePosts.addAll(page);
        if (reachedEnd) {
          _remoteOffset = 0;
          _remoteLap++;
          _lastRemoteLoopFetch = DateTime.now();
        } else {
          _remoteOffset += _pageSize;
        }
      });
    } finally {
      _loadingMoreRemote = false;
    }
  }

  _AnonPost _anonPostFromLocal(LocalPost p) => _AnonPost(
        // p.id is a real UUID string now (composer_screen.dart used to
        // generate a millisecond-timestamp string, which int.parse could
        // read — that broke the moment posts.id insert was fixed to use
        // real UUIDs, throwing FormatException on every real submission).
        // _AnonPost.id only exists to key the demo-only viewer-count/score
        // simulation maps below (_liveTotals/_watchingNow/_viewHistory),
        // which have no real backend meaning for a genuine post — a stable
        // hash is enough to give each real post its own slot without
        // colliding with the small int ids _kPosts' demo entries use.
        id: p.id.hashCode,
        realId: p.id,
        handle: p.username,
        vibe: '',
        text: p.caption,
        timeLeft: '',
        timeAgo: 'now',
        relatables: 0,
        communities: p.branch != null ? [p.branch!] : const [],
        photoUrl: p.photoUrl,
        // Set until the Supabase upload finishes and this post is
        // refetched with a real photoUrl — see localPhotoPath's own doc
        // comment on _AnonPost.
        localPhotoPath: p.photoUrl == null ? p.photoPath : null,
        aspectRatio: p.aspectRatio,
      );

  List<_AnonPost> get _filtered {
    final all = [..._liveAnonPosts, ..._remotePosts, ..._kPosts];
    if (widget.selectedCommunity == 'All') return all;
    return all
        .where((p) => p.communities.contains(widget.selectedCommunity))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    // 1.0, not the old 0.92 — a fractional viewport peeked BOTH neighbors
    // symmetrically (top and bottom), which is wrong for this feed: only
    // the NEXT post below should ever peek, never the one above. The
    // deliberate, asymmetric, prompt-specific peek is now its own overlay
    // (_PromptPeekStrip below), not a side effect of the page's own
    // viewport sizing.
    _pageCtrl = PageController(viewportFraction: 1.0);
    _updateFocus(0.0);
    _pageCtrl.addListener(() {
      final page = _pageCtrl.page ?? 0.0;
      final idx = page.round();
      if (idx != _activePage && mounted) {
        setState(() => _activePage = idx);
      }
      _updateFocus(page);
      // Load the next page a few posts before the user actually hits the
      // end, same lead-time idea as EveryoneFeedScreen's 800px scroll
      // threshold.
      if (idx >= _filtered.length - 3) _loadMoreRemote();
    });
    _loadMoreRemote();

    // Score service
    _liveTotals = {for (final p in _kPosts) p.id: p.anonScore ?? 0};
    _scoreService = ScoreService();
    _scoreSub = _scoreService.stream.listen(_onScore);
    _scoreService.subscribeRealtime(supabase);
    _scoreService.startDemo(_kPosts.map((p) => p.id).toList());

    // Viewer service
    _viewerService = ViewerService();
    _viewerSub = _viewerService.stream.listen(_onView);
    _viewerService.subscribeRealtime(supabase);
    _viewerService.startDemo(_kPosts.map((p) => p.id).toList());

    // Real posts — see _liveAnonPosts' own doc comment. Seeded from
    // whatever's already in PostService (e.g. submitted just before this
    // widget mounted) plus live updates for anything submitted while it's
    // up.
    _liveAnonPosts = PostService.instance.anonPosts
        .map(_anonPostFromLocal)
        .toList();
    _liveAnonSub = PostService.instance.anonFeedStream.listen((posts) {
      if (!mounted) return;
      setState(() {
        _liveAnonPosts = posts.map(_anonPostFromLocal).toList();
      });
    });
  }

  // ── Score event handler ───────────────────────────────────────────────────

  void _onScore(ScoreEvent event) {
    if (!mounted) return;
    // Track score internally but do NOT surface score notifications in the feed
    setState(() {
      _liveTotals[event.postId] =
          (_liveTotals[event.postId] ?? 0) + event.amount;
    });
  }

  // ── Viewer event handler ──────────────────────────────────────────────────

  void _onView(ViewEvent event) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _watchingNow[event.postId] = (_watchingNow[event.postId] ?? 0) + 1;
      _viewHistory.putIfAbsent(event.postId, () => []).add(event);
      if (event.isMystery) {
        _mergeViewerMysteryCount++;
      } else {
        _mergeViewerNames.add(event.viewerName);
      }
    });
    final stayMs = 15000 + math.Random().nextInt(20000);
    Future.delayed(Duration(milliseconds: stayMs), () {
      if (!mounted) return;
      setState(() {
        final c = _watchingNow[event.postId] ?? 0;
        if (c > 0) _watchingNow[event.postId] = c - 1;
      });
    });
    _scheduleMerge();
  }

  // ── Notification merge + queue ────────────────────────────────────────────

  void _scheduleMerge() {
    _mergeTimer?.cancel();
    _mergeTimer = Timer(const Duration(milliseconds: 3500), _flushMerge);
  }

  void _flushMerge() {
    if (!mounted) return;
    if (_mergeViewerNames.isEmpty && _mergeViewerMysteryCount == 0) return;

    final totalWatchers = _mergeViewerNames.length + _mergeViewerMysteryCount;
    String msg;
    if (totalWatchers == 1) {
      final name = _mergeViewerNames.isNotEmpty
          ? _mergeViewerNames.first
          : 'someone';
      msg = '$name visited  👁';
    } else if (_mergeViewerNames.isNotEmpty) {
      final others = totalWatchers - 1;
      msg =
          '${_mergeViewerNames.first} + $others ${others == 1 ? 'other' : 'others'}  👁';
    } else {
      msg = '$totalWatchers people visited  👁';
    }

    _mergeViewerNames.clear();
    _mergeViewerMysteryCount = 0;

    // Bigger merges are more noteworthy — hold them onscreen longer.
    final severity = totalWatchers == 1
        ? FeedNotifSeverity.minor
        : totalWatchers >= 5
        ? FeedNotifSeverity.major
        : FeedNotifSeverity.standard;

    widget.onNotify?.call(msg, severity);
  }

  @override
  void didUpdateWidget(AnonymousTab old) {
    super.didUpdateWidget(old);
    if (old.selectedCommunity != widget.selectedCommunity) {
      // Deferred: jumpToPage() fires the PageController listener
      // synchronously, which calls setState on this same State object mid
      // rebuild (didUpdateWidget runs mid-tree-update), which is the
      // illegal-reentrant-setState crash. Post-frame defers it until the
      // current build has finished.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pageCtrl.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _scoreSub.cancel();
    _scoreService.dispose();
    _viewerSub.cancel();
    _viewerService.dispose();
    _liveAnonSub?.cancel();
    _mergeTimer?.cancel();
    _pageCtrl.dispose();
    for (final n in _focusNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _filtered;
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'No posts yet',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF999999),
          ),
        ),
      );
    }
    // The nav bar is now a small floating frosted-glass pill (not a
    // full-width opaque bar), so the feed intentionally runs the full
    // height behind it — the pill's own blur keeps content legible where
    // it overlaps, matching the design's "content visible through the
    // pill" intent instead of reserving dead space above it.
    // ROOT CAUSE (first-post-renders-compressed bug) + fix: each page's
    // post is sized width-driven (imageAspectRatio) with a Flexible(loose)
    // fallback that gracefully SHRINKS the image if the page doesn't have
    // enough vertical room — see PhotoPostCard's own doc comment on
    // imageAspectRatio. That fallback used to matter because this tab used
    // to be handed a PageView viewport whose height varied with
    // HomeScreen's collapsible header (identity row/pills/prompt composer):
    // full-size at rest (least room) vs collapsed after a scroll-down (most
    // room) — so the very first post rendered small (shrunk to fit under
    // the at-rest header) and only reached its true aspect-ratio size once
    // the user scrolled and the header collapsed. Fix: HomeScreen no longer
    // reserves layout space for that header at all — it floats OVER this
    // tab's content as an overlay instead (see HomeScreen.build), so this
    // Padding's `top: widget.topInset` is a constant (just the always-
    // pinned toggle row's height) that never changes with the header's
    // collapsed state. The PageView's available height is therefore
    // identical on every frame from the very first one — there is no
    // "shrink then correct" left to have, because the input driving
    // Flexible(loose)'s fallback never moves in the first place.
    //
    // `bottom` is new — ROOT CAUSE of the tab bar covering a post's own
    // reaction/comment row: a post's own natural content height (badge +
    // prompt + avatar + image + comments) is a fixed ~642pt regardless of
    // topInset — PhotoPostCard/TextPostCard size to their own content, not
    // to whatever room happens to be left (see their own Align(topCenter)
    // doc comments). Pushing the whole feed down by topInset without
    // reserving matching room at the BOTTOM just walks a post's fixed-
    // height bottom edge further down the screen — directly into the tab
    // bar, which sits at a fixed distance from the screen's own bottom
    // edge, unrelated to topInset. This reservation gives PageView's own
    // available height a hard ceiling, so Flexible(loose)'s image-shrink
    // fallback — which already exists for exactly this "not enough room"
    // case — engages for real instead of never being tight enough to
    // matter. Verified via a real on-device RenderBox probe: with
    // HomeScreen's topInset in play this pulls a post's own bottom edge up
    // ~65px (the image shrinks by that much), landing 16px clear of the
    // tab bar's own top edge instead of ~47-93px past it. Costs nothing
    // when topInset is small (this feed run standalone, or HomeScreen's
    // header reservation ever shrinks) — content already fits inside a
    // smaller box with room to spare there, so no compression triggers.
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      // Outer Stack is NOT inset — the peek strip below (a direct child of
      // THIS Stack, a sibling of the Padding, not nested inside it) needs
      // the exact same coordinate space MainShell's tab bar uses
      // (screen-relative, no ancestor padding eating into it), or matching
      // its `bottom:` expression numerically still doesn't put them at the
      // same physical position — see the peek's own Positioned below for
      // the bug this fixes. Only the PageView itself gets the top/bottom
      // reservations.
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: widget.topInset,
              bottom: MediaQuery.paddingOf(context).bottom +
                  kTabBarBottomOffset +
                  kTabBarHeight +
                  16,
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) => false,
              child: PageView.builder(
                scrollDirection: Axis.vertical,
                controller: _pageCtrl,
                itemCount: posts.length,
                itemBuilder: (context, i) {
                  final post = posts[i];
                  final branch = post.communities.isNotEmpty
                      ? post.communities.first
                      : 'Campus';
                  final viewHistory = _viewHistory[post.id] ?? const [];

                  // Built to POST_CARD_SPEC.md (project root): PhotoPostCard/
                  // TextPostCard (screens/feed/widgets/) render the ghost
                  // prompt text block, the persona-icon + branch-tag identity
                  // row, and reaction/ping — this feed no longer has its own
                  // bespoke card. Routed on post.hasPhoto: photo posts get
                  // the image-dominant card, text-only posts get the
                  // compact, content-sized one. allowFaceReactions is false
                  // here — the Anonymous feed is emoji-only reactions, so the
                  // BeReal-style face-reaction row never shows on this feed
                  // regardless of any reaction data. The viewer-activity dot
                  // has no slot on either card, so it's layered on top here
                  // as an approximate corner badge instead.
                  return Padding(
                    // Bottom padding here does NOT control the gap to the
                    // peek strip — measured and confirmed: this post's own
                    // Column is height-constrained by Align(topCenter)
                    // higher up the tree (see PhotoPostCard/TextPostCard's
                    // own doc comments), so it renders at its natural size
                    // regardless of how much trailing space this Padding
                    // reserves; a real RenderBox probe showed changing this
                    // 70 -> 110 moved the post's rendered bottom edge by
                    // exactly 0px. The actual fix for post-vs-tab-bar
                    // clearance is the `bottom:` on this whole Padding
                    // (top-level, see above) plus the peek strip now
                    // sitting BEHIND the tab bar rather than needing its
                    // own reserved gap at all — this value is back at its
                    // original 70, kept only as normal breathing room
                    // under the comments row.
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 70),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Community indicator — the single place a post's
                        // community shows, a small badge above the card
                        // naming which community this post belongs to. It
                        // sits outside/above the card entirely, so it reads
                        // at a glance before the post itself even loads in.
                        // Nothing else on the card repeats this — no tag on
                        // the photo, no second badge.
                        _CommunityBadge(label: branch),
                        const SizedBox(height: 4),
                        // Flexible(loose), not a bare Stack: this page item
                        // gets a TIGHT height from the PageView's
                        // SliverFillViewport, and a plain Column child would
                        // be measured with unbounded height first (Flutter's
                        // normal non-flex-child sizing pass), which lets
                        // PhotoPostCard's own internal image expand to its
                        // full natural size instead of the shrink-to-fit
                        // behavior it relies on — that reliably overflowed
                        // the page by 300+ px. Flexible caps this Stack (and
                        // everything inside it) to whatever height remains
                        // after the badge above, so the card's own
                        // Flexible/loose image sizing (see PhotoPostCard)
                        // absorbs the difference exactly like it already
                        // does for any other tight-viewport slack.
                        Flexible(
                          fit: FlexFit.loose,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              post.hasPhoto
                                  ? PhotoPostCard(
                                      postId: post.postId,
                                      media: _AnonMedia(post: post),
                                      allowFaceReactions: false,
                                      pingContext: PingContext.anonymous,
                                      pingTargetName: post.handle,
                                      onSentPrompt: (prompt, {photoUrl}) =>
                                          _pingPostAuthor(post, prompt),
                                      posterScore: post.posterScore,
                                      personaPhotoUrl: post.personaPhotoUrl,
                                      branch: branch,
                                      promptQuestion: post.replyingTo,
                                      answerText: post.text,
                                      commentCount: post.commentCount,
                                      onCommentTap: () =>
                                          _openAnonComments(context, post),
                                      focusValue: _focusFor(post.id),
                                    )
                                  : TextPostCard(
                                      postId: post.postId,
                                      allowFaceReactions: false,
                                      pingContext: PingContext.anonymous,
                                      pingTargetName: post.handle,
                                      onSentPrompt: (prompt, {photoUrl}) =>
                                          _pingPostAuthor(post, prompt),
                                      posterScore: post.posterScore,
                                      personaPhotoUrl: post.personaPhotoUrl,
                                      branch: branch,
                                      // A text-only post is a ghost-prompt
                                      // reply by definition; fall back to a
                                      // generic label in the unlikely case
                                      // demo data omits it.
                                      promptQuestion:
                                          post.replyingTo ?? 'Anonymous reply',
                                      answerText: post.text,
                                      commentCount: post.commentCount,
                                      onCommentTap: () =>
                                          _openAnonComments(context, post),
                                    ),
                              if (viewHistory.isNotEmpty)
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: _CyanDot(count: viewHistory.length),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // The peek-bait: as a post is focused, the NEXT post's own
            // prompt text peeks up from the bottom edge, drawing the eye
            // down to scroll. ONLY the next post below ever peeks — never
            // the one above (see the viewportFraction note in initState).
            // Swaps to whichever post is now "next" the instant
            // _activePage changes (in the PageController listener above),
            // so the moment a post becomes focused its own prompt hides
            // (PhotoPostCard's own focus-fade) and the FOLLOWING post's
            // prompt begins peeking here instead.
            //
            // Opacity is tied directly to that upcoming post's own focus
            // value (0..1, the same continuous per-pixel value PhotoPostCard
            // reads for its own prompt-fade — see _updateFocus) rather than
            // being a flat on/off swap at the page-settle boundary: while
            // the current post is dead-centered (page ≈ _activePage), the
            // next post's focus is 0, so the strip sits at max opacity; as
            // the user drags toward it, its focus rises continuously toward
            // 1 and the strip fades out in step, finishing the handoff
            // exactly as that post reaches full focus (and its own on-card
            // prompt has faded to nothing per the opposite rule) — a smooth
            // rise/fade tied to the drag, not a snap.
            if (_activePage + 1 < posts.length)
              // Stacked-card peek, sitting BELOW the floating pill tab bar
              // (in the gap between the pill's own bottom edge and the
              // screen's true bottom) rather than tucked behind it — fully
              // visible, no part of the card hidden under the bar. Height
              // is exactly that gap (bottomPad + kTabBarBottomOffset, the
              // same offset the bar itself is pinned by, so this can't
              // drift out of sync with it), positioned flush to the true
              // screen bottom so it sits right up against the pill's own
              // underside with no dead space between them.
              Positioned(
                left: 20,
                right: 20,
                bottom: 0,
                height: MediaQuery.of(context).padding.bottom + kTabBarBottomOffset,
                child: ValueListenableBuilder<double>(
                  valueListenable: _focusFor(posts[_activePage + 1].id),
                  builder: (context, nextFocus, child) {
                    final opacity = (1 - nextFocus).clamp(0.0, 1.0);
                    return IgnorePointer(
                      ignoring: opacity < 0.05,
                      child: Opacity(opacity: opacity, child: child),
                    );
                  },
                  child: _PromptPeekStrip(
                    post: posts[_activePage + 1],
                    onTap: () => _pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
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
// _PromptPeekStrip — the Anonymous feed's peek-bait: a rounded-top card
// sitting below the tab bar, showing the UPCOMING post's ghost-prompt
// question — a stacked-card affordance that pulls the eye (and thumb)
// downward. Deliberately its own overlay rather than a side effect of
// PageView's viewportFraction (see _pageCtrl's own note) — that's what keeps
// this asymmetric (bottom only) and lets it show specifically the prompt
// text rather than whatever happens to sit at the next card's own top edge.
// Hides itself (returns nothing) when the upcoming post has no prompt to
// show (a photo-only reply with no ghost-prompt text), same "don't show an
// empty affordance" rule the reactions rows use.
// ---------------------------------------------------------------------------

class _PromptPeekStrip extends StatelessWidget {
  const _PromptPeekStrip({required this.post, required this.onTap});

  final _AnonPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final prompt = post.replyingTo;
    if (prompt == null || prompt.isEmpty) return const SizedBox.shrink();

    // Fully visible now (the enclosing Positioned in _AnonymousTabState.
    // build sizes this to exactly the gap below the tab bar, not taller
    // than it) — rounded top corners kept purely for the "stacked card"
    // look, not because anything's clipping the bottom edge anymore.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          prompt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF888888),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Anonymous post card — now PhotoPostCard/TextPostCard (see
// screens/feed/widgets/photo_post_card.dart, text_post_card.dart,
// post_card_shared.dart) rather than a bespoke widget here. What's left in
// this file is just the glue those cards need: the demo media builder
// (they take an arbitrary `media` widget and don't know about this feed's
// photoUrl/Color-block data) and the comment sheet opener. No timestamp
// glue: this app dropped timestamps from the design entirely, so there's
// nothing to pass through or parse here anymore.
//
// Capabilities this swap genuinely drops or changes — flagged, not silently
// lost:
//   - The custom 🔥/💀/⭕/👀 reaction popup is gone. Reaction tap opens the
//     shared ReactionPickerPopup (a real emoji set) instead, and long-press
//     opens face capture only when allowFaceReactions is true (false here,
//     per the emoji-only-on-Anonymous rule).
//   - Reactions are now backed by ReactionService (real Supabase queries
//     keyed on `postId`), not local widget state. Since these are demo
//     posts with fake int ids (not real `posts` rows), expect the reaction
//     summary to load empty/zero rather than showing the old canned counts.
//   - `pingCount` (shown next to the send icon before) has no equivalent
//     slot on either card's action row — it's not displayed anymore.
//   - The film-grain texture overlay is dropped. It clipped to the old
//     card's own rounded Container; reproducing it from outside would mean
//     guessing the new cards' internal corner radius and risks grain
//     bleeding past the real rounded corners, so it's cut rather than
//     hacked back on.
//   - The ghost-prompt pulse animation no longer pauses when a card scrolls
//     off the active PageView page (its ticker runs continuously — no
//     isActive hook).
// ---------------------------------------------------------------------------

void _openAnonComments(BuildContext context, _AnonPost post) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommentSheet(post: post),
  );
}

/// Only ever constructed when `post.hasPhoto` is true — the caller passes
/// `media: null` for text-only posts instead of an empty placeholder, so
/// this doesn't need its own "no photo" fallback branch.
class _AnonMedia extends StatelessWidget {
  const _AnonMedia({required this.post});
  final _AnonPost post;

  @override
  Widget build(BuildContext context) {
    final url = post.photoUrl;
    if (url != null) {
      return CachedNetworkImage(
              memCacheWidth: 1080,
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            Container(color: const Color(0xFFECECEC)),
        errorWidget: (context, url, error) => Container(
          color: const Color(0xFFF0F0F0),
          child: const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Color(0xFF999999),
              size: 32,
            ),
          ),
        ),
      );
    }
    // Just-captured post, still uploading (see localPhotoPath's own doc
    // comment) — same Image.file(File(path)) pattern used for the same
    // situation elsewhere (profile_screen.dart's own posts tab,
    // single_post_detail_screen.dart), not a one-off.
    final localPath = post.localPhotoPath;
    if (localPath != null) {
      return Image.file(File(localPath), fit: BoxFit.cover);
    }
    // This feed's demo layouts (triptych/grid/scrapbook) were never
    // actually implemented beyond the first flat-color swatch — unchanged
    // from before, not a regression introduced by this swap.
    return Container(color: post.collagePhotos!.first);
  }
}

// ---------------------------------------------------------------------------
// _CommunityBadge — small pill above each post naming its community (e.g.
// "CSE"). Light/bordered rather than BranchTag's dark-on-photo treatment,
// since this sits directly on the feed's own white background, not over an
// image.
// ---------------------------------------------------------------------------

class _CommunityBadge extends StatelessWidget {
  const _CommunityBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: const Color(0xFF555555),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CyanDot — pulsing cyan visitor activity indicator
// ---------------------------------------------------------------------------

class _CyanDot extends StatefulWidget {
  const _CyanDot({required this.count});
  final int count;
  @override
  State<_CyanDot> createState() => _CyanDotState();
}

class _CyanDotState extends State<_CyanDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.20,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(
      begin: 0.55,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00FFFF);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cyan.withValues(alpha: _opacity.value),
          boxShadow: [
            BoxShadow(
              color: cyan.withValues(alpha: 0.45 * _opacity.value),
              blurRadius: 4 * _scale.value,
              spreadRadius: 0.5 * _scale.value,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mutable comment model (runtime state, not const)
// ---------------------------------------------------------------------------

class _MutableComment {
  _MutableComment({required this.handle, required this.text})
    : timeAgo = 'just now',
      likes = 0,
      replies = [];

  _MutableComment._from(_Comment c)
    : handle = c.handle,
      text = c.text,
      timeAgo = c.timeAgo,
      likes = c.likes,
      replies = c.replies.map(_MutableComment._from).toList();

  final String handle;
  final String text;
  final String timeAgo;
  int likes;
  bool liked = false;
  final List<_MutableComment> replies;
}

// ---------------------------------------------------------------------------
// Comment sheet
// ---------------------------------------------------------------------------

class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.post});
  final _AnonPost post;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late List<_MutableComment> _comments;
  _MutableComment? _replyingTo;

  @override
  void initState() {
    super.initState();
    final src = _kComments[widget.post.id] ?? [];
    _comments = src.map(_MutableComment._from).toList();
    _sortComments();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sortComments() {
    _comments.sort((a, b) => b.likes.compareTo(a.likes));
    for (final c in _comments) {
      c.replies.sort((a, b) => b.likes.compareTo(a.likes));
    }
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (_replyingTo != null) {
        _replyingTo!.replies.add(_MutableComment(handle: 'you', text: text));
        _replyingTo = null;
      } else {
        _comments.insert(0, _MutableComment(handle: 'you', text: text));
      }
    });
    _ctrl.clear();
    FocusScope.of(context).unfocus();
  }

  void _toggleLike(_MutableComment c) {
    setState(() {
      if (c.liked) {
        c.liked = false;
        c.likes = (c.likes - 1).clamp(0, 9999);
      } else {
        c.liked = true;
        c.likes += 1;
      }
      _sortComments();
    });
  }

  void _startReply(_MutableComment c) {
    setState(() => _replyingTo = c);
    _ctrl.text = '';
    FocusScope.of(context).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Color(0xFF16151A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Text(
                  'Comments',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_comments.length}',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white38),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          // Comment list
          Expanded(
            child: _comments.isEmpty
                ? Center(
                    child: Text(
                      'No comments yet. Be first.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white30,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _comments.length,
                    itemBuilder: (_, i) => _CommentTile(
                      comment: _comments[i],
                      depth: 0,
                      onLike: () => _toggleLike(_comments[i]),
                      onReply: () => _startReply(_comments[i]),
                      onLikeReply: (r) => _toggleLike(r),
                    ),
                  ),
          ),
          // Reply banner
          if (_replyingTo != null)
            Container(
              color: Colors.white.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.reply_rounded,
                    size: 14,
                    color: AppColors.coral.withValues(alpha: 0.80),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${_replyingTo!.handle}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          // Input bar
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              color: const Color(0xFF16151A),
            ),
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E2A52),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: _replyingTo != null
                          ? 'Reply to ${_replyingTo!.handle}...'
                          : 'Add a comment...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white30,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _submit,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.coral,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: Colors.white,
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

// ---------------------------------------------------------------------------
// Comment tile — supports 1 level of nesting
// ---------------------------------------------------------------------------

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.depth,
    this.onLike,
    this.onReply,
    this.onLikeReply,
  });

  final _MutableComment comment;
  final int depth;
  final VoidCallback? onLike;
  final VoidCallback? onReply;
  final void Function(_MutableComment)? onLikeReply;

  static const _avatarColors = [
    Color(0xFF2E4A6E),
    Color(0xFF3E2E5E),
    Color(0xFF2E5E3E),
    Color(0xFF5E3E2E),
    Color(0xFF4A2E4A),
    Color(0xFF2E4E4E),
  ];

  Color _handleColor(String h) =>
      _avatarColors[h.hashCode.abs() % _avatarColors.length];

  @override
  Widget build(BuildContext context) {
    final avatarSize = depth == 0 ? 32.0 : 26.0;
    final leftPad = depth == 0 ? 16.0 : 44.0;

    return Padding(
      padding: EdgeInsets.only(left: leftPad, right: 16, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: _handleColor(comment.handle),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      comment.handle[0].toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: depth == 0 ? 12 : 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            comment.handle,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            comment.timeAgo,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white30,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        comment.text,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // Like button
                          GestureDetector(
                            onTap: onLike,
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  comment.liked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 13,
                                  color: comment.liked
                                      ? AppColors.coral
                                      : Colors.white.withValues(alpha: 0.35),
                                ),
                                if (comment.likes > 0) ...[
                                  const SizedBox(width: 3),
                                  Text(
                                    '${comment.likes}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: comment.liked
                                          ? AppColors.coral.withValues(
                                              alpha: 0.80,
                                            )
                                          : Colors.white30,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (depth == 0) ...[
                            const SizedBox(width: 14),
                            GestureDetector(
                              onTap: onReply,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                'Reply',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white38,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Nested replies (max depth 1)
          if (comment.replies.isNotEmpty && depth == 0)
            Column(
              children: comment.replies
                  .map(
                    (r) => _CommentTile(
                      comment: r,
                      depth: 1,
                      onLike: () => onLikeReply?.call(r),
                    ),
                  )
                  .toList(),
            ),
          if (depth == 0)
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        ],
      ),
    );
  }
}
