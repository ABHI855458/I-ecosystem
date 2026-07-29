import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../screens/feed/widgets/photo_post_card.dart';
import '../../screens/feed/widgets/text_post_card.dart';
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
    required this.handle,
    required this.vibe,
    required this.text,
    required this.timeLeft,
    required this.timeAgo,
    required this.relatables,
    this.communities = const [],
    this.personaPhotoUrl,
    this.photoUrl,
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
  bool get hasPhoto => photoUrl != null || (collagePhotos != null && collagePhotos!.isNotEmpty);

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
        _Comment(handle: 'ghost_verse', text: "Exactly, it's so draining after a while", timeAgo: '45m ago', likes: 4),
      ],
    ),
    _Comment(handle: 'soft_rain', text: 'PhD in performing for others 🎭', timeAgo: '30m ago', likes: 9),
    _Comment(handle: 'ember_9', text: 'The gap between who you are and who they think you are just grows every year', timeAgo: '15m ago', likes: 6),
    _Comment(handle: 'quiet_loop', text: 'There are two of me and only one shows up to college', timeAgo: '8m ago', likes: 3),
  ],
  2: [
    _Comment(
      handle: 'quiet_storm',
      text: 'Telling parents feels impossible. Mine would spiral.',
      timeAgo: '3h ago',
      likes: 22,
      replies: [
        _Comment(handle: 'velvet_sky', text: 'Breathe. One internal at a time.', timeAgo: '2h ago', likes: 8),
        _Comment(handle: 'night_owl42', text: 'Have you talked to anyone else about it?', timeAgo: '1h ago', likes: 3),
      ],
    ),
    _Comment(handle: 'frost_bit', text: "You're not the only one hiding this. We got you.", timeAgo: '2h ago', likes: 11),
    _Comment(handle: 'river_echo', text: 'Same boat. Feel free to DM me', timeAgo: '1h ago', likes: 5),
  ],
  3: [
    _Comment(handle: 'amber_drift', text: 'FINALLY someone said it 🙌', timeAgo: '45m ago', likes: 31),
    _Comment(
      handle: 'pixel_haze',
      text: 'The filter machine is broken tho 😭 took my 20 rs and gave me sadness',
      timeAgo: '30m ago',
      likes: 18,
      replies: [
        _Comment(handle: 'midnight_sun', text: 'The tea from Block C compensates tho', timeAgo: '20m ago', likes: 7),
      ],
    ),
    _Comment(handle: 'cloud_nine', text: 'Controversial but I respect the commitment', timeAgo: '1h ago', likes: 5),
    _Comment(handle: 'rain_drop7', text: 'I am willing to debate this at length. In the canteen.', timeAgo: '15m ago', likes: 12),
  ],
  4: [
    _Comment(handle: 'lonely_star', text: '8 months and it still hits. I feel you.', timeAgo: '5h ago', likes: 19),
    _Comment(
      handle: 'blue_echo',
      text: 'Library is genuinely the worst place to run into them',
      timeAgo: '4h ago',
      likes: 8,
      replies: [
        _Comment(handle: 'ghost_walk', text: 'Or the best? The eye contact moment then looking away', timeAgo: '3h ago', likes: 3),
      ],
    ),
    _Comment(handle: 'dust_wave', text: "Time's weird. Some things just don't dissolve.", timeAgo: '2h ago', likes: 6),
  ],
  5: [
    _Comment(handle: 'chaos_theory', text: 'Bro just accidentally deconstructed all of society', timeAgo: '2h ago', likes: 27),
    _Comment(handle: 'river_stone', text: 'Shaking hands is genuinely a weird ritual if you think about it', timeAgo: '1h ago', likes: 14),
    _Comment(handle: 'neon_glow', text: 'Social norms = collective hallucinations at scale', timeAgo: '30m ago', likes: 9),
    _Comment(handle: 'ink_drop', text: "Anthropology class is hitting different after reading this", timeAgo: '10m ago', likes: 4),
  ],
};

// ---------------------------------------------------------------------------
// AnonymousTab
// ---------------------------------------------------------------------------

class AnonymousTab extends StatefulWidget {
  const AnonymousTab({super.key, this.selectedCommunity = 'All', this.onScrollProgress});

  final String selectedCommunity;
  final ValueChanged<double>? onScrollProgress;

  @override
  State<AnonymousTab> createState() => _AnonymousTabState();
}

class _AnonymousTabState extends State<AnonymousTab> {
  late final PageController _pageCtrl;
  int _activePage = 0;

  // Score service
  late final ScoreService _scoreService;
  late StreamSubscription<ScoreEvent> _scoreSub;
  late final Map<int, int> _liveTotals;

  // Viewer service
  late final ViewerService _viewerService;
  late StreamSubscription<ViewEvent> _viewerSub;
  final Map<int, int> _watchingNow = {};
  final Map<int, List<ViewEvent>> _viewHistory = {};

  // Unified notification queue (merges score + viewer events)
  final List<String> _notifQueue = [];
  bool _notifShowing = false;
  int _notifKey = 0;
  Timer? _mergeTimer;
  final List<String> _mergeViewerNames = [];
  int _mergeViewerMysteryCount = 0;

  List<_AnonPost> get _filtered {
    if (widget.selectedCommunity == 'All') return _kPosts;
    return _kPosts
        .where((p) => p.communities.contains(widget.selectedCommunity))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.92);
    _pageCtrl.addListener(() {
      final page = _pageCtrl.page ?? 0.0;
      widget.onScrollProgress?.call(page.clamp(0.0, 1.0));
      final idx = page.round();
      if (idx != _activePage && mounted) {
        setState(() => _activePage = idx);
      }
    });

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
  }

  // ── Score event handler ───────────────────────────────────────────────────

  void _onScore(ScoreEvent event) {
    if (!mounted) return;
    // Track score internally but do NOT surface score notifications in the feed
    setState(() {
      _liveTotals[event.postId] = (_liveTotals[event.postId] ?? 0) + event.amount;
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
      final name = _mergeViewerNames.isNotEmpty ? _mergeViewerNames.first : 'someone';
      msg = '$name visited  👁';
    } else if (_mergeViewerNames.isNotEmpty) {
      final others = totalWatchers - 1;
      msg = '${_mergeViewerNames.first} + $others ${others == 1 ? 'other' : 'others'}  👁';
    } else {
      msg = '$totalWatchers people visited  👁';
    }

    _mergeViewerNames.clear();
    _mergeViewerMysteryCount = 0;

    setState(() => _notifQueue.add(msg));
    _maybeShowNotif();
  }

  void _maybeShowNotif() {
    if (_notifShowing || _notifQueue.isEmpty) return;
    setState(() {
      _notifShowing = true;
      _notifKey++;
    });
  }

  void _onNotifDismissed() {
    if (!mounted) return;
    setState(() {
      _notifShowing = false;
      if (_notifQueue.isNotEmpty) _notifQueue.removeAt(0);
    });
    if (_notifQueue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), _maybeShowNotif);
    }
  }

  @override
  void didUpdateWidget(AnonymousTab old) {
    super.didUpdateWidget(old);
    if (old.selectedCommunity != widget.selectedCommunity) {
      // Deferred: jumpToPage() fires the PageController listener
      // synchronously, which calls widget.onScrollProgress -> HomeScreen's
      // setState. Calling that inline here happens *during* HomeScreen's
      // own build (didUpdateWidget runs mid-tree-update), which is the
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
    _mergeTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _filtered;
    if (posts.isEmpty) {
      return Center(
        child: Text(
          'No posts yet',
          style: GoogleFonts.inter(fontSize: 14, color: Colors.white30),
        ),
      );
    }
    // Shrink PageView so the bottom peek stays above the nav bar overlay
    final navBarBottom = 56.0 + MediaQuery.of(context).padding.bottom;
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Padding(
        padding: EdgeInsets.only(bottom: navBarBottom),
        child: Stack(
          children: [
          NotificationListener<ScrollNotification>(
            onNotification: (_) => false,
            child: PageView.builder(
              scrollDirection: Axis.vertical,
              controller: _pageCtrl,
              itemCount: posts.length,
              itemBuilder: (context, i) {
                final post = posts[i];
                final branch = post.communities.isNotEmpty ? post.communities.first : 'Campus';
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      post.hasPhoto
                          ? PhotoPostCard(
                              postId: post.id.toString(),
                              media: _AnonMedia(post: post),
                              allowFaceReactions: false,
                              pingContext: PingContext.anonymous,
                              pingTargetName: post.handle,
                              pingGlass: false,
                              posterScore: post.posterScore,
                              personaPhotoUrl: post.personaPhotoUrl,
                              branch: branch,
                              promptQuestion: post.replyingTo,
                              answerText: post.text,
                              commentCount: post.commentCount,
                              onCommentTap: () => _openAnonComments(context, post),
                            )
                          : TextPostCard(
                              postId: post.id.toString(),
                              allowFaceReactions: false,
                              pingContext: PingContext.anonymous,
                              pingTargetName: post.handle,
                              pingGlass: false,
                              posterScore: post.posterScore,
                              personaPhotoUrl: post.personaPhotoUrl,
                              branch: branch,
                              // A text-only post is a ghost-prompt reply by
                              // definition; fall back to a generic label in
                              // the unlikely case demo data omits it.
                              promptQuestion: post.replyingTo ?? 'Anonymous reply',
                              answerText: post.text,
                              commentCount: post.commentCount,
                              onCommentTap: () => _openAnonComments(context, post),
                            ),
                      if (viewHistory.isNotEmpty)
                        Positioned(
                          top: 6, left: 6,
                          child: _CyanDot(count: viewHistory.length),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Unified notification toast — one at a time, queued + merged
          if (_notifShowing && _notifQueue.isNotEmpty)
            _NotifToast(
              key: ValueKey('notif_$_notifKey'),
              message: _notifQueue.first,
              onDismissed: _onNotifDismissed,
            ),
          ],
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
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: AppColors.cardSurface),
        errorWidget: (context, url, error) => Container(
          color: AppColors.cardSurface,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted, size: 32),
          ),
        ),
      );
    }
    // This feed's demo layouts (triptych/grid/scrapbook) were never
    // actually implemented beyond the first flat-color swatch — unchanged
    // from before, not a regression introduced by this swap.
    return Container(color: post.collagePhotos!.first);
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

class _CyanDotState extends State<_CyanDot> with SingleTickerProviderStateMixin {
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
    _scale = Tween<double>(begin: 0.85, end: 1.20).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.55, end: 1.0).animate(
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
// Unified notification toast — frosted glass, queued, merges events
// ---------------------------------------------------------------------------

class _NotifToast extends StatefulWidget {
  const _NotifToast({super.key, required this.message, required this.onDismissed});
  final String message;
  final VoidCallback onDismissed;

  @override
  State<_NotifToast> createState() => _NotifToastState();
}

class _NotifToastState extends State<_NotifToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;
  bool _dismissCalled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.8),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    Future.delayed(const Duration(milliseconds: 2800), _dismiss);
  }

  void _dismiss() {
    if (_dismissCalled || !mounted) return;
    _dismissCalled = true;
    _ctrl.reverse().whenComplete(widget.onDismissed);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // Sits below the status bar and clear of the card's own persona-
      // photo/prompt header (which now lives inside the card itself, not a
      // separate blob above it).
      top: MediaQuery.of(context).padding.top + 16,
      left: 0,
      right: 0,
      child: Center(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _opacity,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.message,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white30),
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
                  Icon(Icons.reply_rounded, size: 14, color: AppColors.coral.withValues(alpha: 0.80)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${_replyingTo!.handle}',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _replyingTo = null),
                    child: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
                  ),
                ],
              ),
            ),
          // Input bar
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: const Icon(Icons.person_outline, size: 16, color: Colors.white54),
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
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white30),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    child: const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
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
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white30),
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
                                          ? AppColors.coral.withValues(alpha: 0.80)
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
                  .map((r) => _CommentTile(
                        comment: r,
                        depth: 1,
                        onLike: () => onLikeReply?.call(r),
                      ))
                  .toList(),
            ),
          if (depth == 0)
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        ],
      ),
    );
  }
}
