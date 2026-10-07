import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../services/ping_realmoji_service.dart';
import '../../services/ping_service.dart';
import '../../shared/time_ago.dart';
import '../../widgets/emoji_burst.dart';
import '../../widgets/story_progress_bars.dart';
import '../profile_v2/profile_navigation.dart';
import '../profile_v2/profile_v2_tokens.dart';
import 'ping_realmoji.dart';
import 'ping_turns.dart';
import 'text_ping_card.dart';

// ---------------------------------------------------------------------------
// The reply story — what a face in the Friends feed's REPLIES row opens
// into. It looks and moves like the highlight story on purpose (explicit
// request, 2026-10-07: "make it like to view the replies ... it shall open
// just like how highlights appear"): full screen, bars across the top, tap
// the edges to move, hold to pause, swipe down to close.
//
// ONE PERSON AT A TIME, LATEST FIRST. Everything that person has sent back
// on my open pings is one story. It opens on the most recent one and then
// goes back through the earlier ones ("when opened he gets to be on the
// recent sent and as well see the previous sent"), so the first bar is the
// newest. When their story ends, the next person's plays; after the last,
// it closes. SWIPING SIDEWAYS jumps a whole person at a time ("swiping
// shall go to next story").
//
// REACTIONS are the Ping page's own ("you can react there as well, just
// like in ping reactions"): one button opens the same RealMoji tray, with
// the heart as its first chip, and wears whatever I reacted with. A double
// tap is the quick heart.
//
// A reply counts as opened the moment it is actually on screen — never
// while it is still loading, and never if it failed to load — which is
// the same rule the Ping page's own viewer follows.
// ---------------------------------------------------------------------------

const kReplyStoryDuration = Duration(seconds: 5);

const _kHeart = Color(0xFFFF5C7A);

/// Everything the viewer does that touches the network or the device, so a
/// test can stand in for it.
class ReplyStoryDelegate {
  const ReplyStoryDelegate();

  Future<void> markViewed(String replyId) =>
      PingService.instance.markViewed(replyId);

  /// Hearts or un-hearts a reply. Returns whether it is hearted now.
  Future<bool> toggleHeart(String replyId) async =>
      (await PingService.instance.toggleReaction(replyId)).$1;

  /// The RealMoji reactions on these replies (mine among them).
  Future<List<PingRealmoji>> fetchReactions(List<String> replyIds) =>
      PingRealmojiService.instance.fetchFor(replyIds: replyIds);

  /// Opens the Ping page's reaction tray for [replyId] and completes when
  /// it closes. [onHeart] is its heart chip; [onReacted] runs after a
  /// RealMoji lands.
  Future<void> pickReaction(
    BuildContext context, {
    required String replyId,
    required bool heartLiked,
    required VoidCallback onHeart,
    required VoidCallback onReacted,
  }) => showPingRealmojiPicker(
    context,
    replyId: replyId,
    onHeart: onHeart,
    heartLiked: heartLiked,
    onReacted: onReacted,
  );

  /// Gets [url] decoded and returns the photo's shape (width / height), so
  /// it can be laid out whole before the timer starts. Null when it can't
  /// be loaded. Never throws.
  Future<double?> loadPhoto(BuildContext context, String url) {
    final done = Completer<double?>();
    final stream = CachedNetworkImageProvider(
      url,
    ).resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    void finish(double? aspect) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete(aspect);
    }

    listener = ImageStreamListener(
      (info, _) {
        final h = info.image.height;
        finish(h == 0 ? null : info.image.width / h);
      },
      onError: (_, _) => finish(null),
    );
    stream.addListener(listener);
    return done.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        stream.removeListener(listener);
        return null;
      },
    );
  }

  Widget buildPhoto(BuildContext context, String url) => Image(
    image: CachedNetworkImageProvider(url),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF121216)),
  );

  Widget buildSelfie(BuildContext context, String url) => CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    memCacheWidth: 360,
    errorWidget: (_, _, _) => const SizedBox.shrink(),
  );
}

/// Opens the reply story on [stories], starting with the person at
/// [initialIndex]. Completes when it closes, with the ids of the replies
/// that were opened while it was up.
Future<Set<String>> openReplyStory(
  BuildContext context, {
  required List<ReplyStory> stories,
  int initialIndex = 0,
}) async {
  if (stories.isEmpty) return const {};
  final opened = await Navigator.of(context, rootNavigator: true)
      .push<Set<String>>(
        PageRouteBuilder<Set<String>>(
          opaque: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, _, _) =>
              ReplyStoryViewer(stories: stories, initialIndex: initialIndex),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
        ),
      );
  return opened ?? const {};
}

class ReplyStoryViewer extends StatefulWidget {
  const ReplyStoryViewer({
    super.key,
    required this.stories,
    this.initialIndex = 0,
    this.delegate = const ReplyStoryDelegate(),
    this.itemDuration = kReplyStoryDuration,
  });

  final List<ReplyStory> stories;
  final int initialIndex;
  final ReplyStoryDelegate delegate;
  final Duration itemDuration;

  @override
  State<ReplyStoryViewer> createState() => _ReplyStoryViewerState();
}

class _ReplyStoryViewerState extends State<ReplyStoryViewer>
    with SingleTickerProviderStateMixin {
  late int _s = widget.initialIndex.clamp(0, widget.stories.length - 1);

  /// Position inside the story: 0 is the person's LATEST reply.
  int _i = 0;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.itemDuration,
  )..addStatusListener(_onProgressStatus);

  /// Bumped on every move, so a slow load for a reply the viewer has
  /// already left can't start the timer on the wrong one.
  int _gen = 0;
  bool _held = false;
  bool _sheetOpen = false;
  bool _closing = false;
  double _dragDy = 0;
  double _dragDx = 0;

  /// Replies opened while this viewer was up — handed back on close.
  final _opened = <String>{};

  /// reply id -> its photo's shape, once decoded.
  final _aspects = <String, double>{};

  /// Replies whose photo could not be loaded (they stay unopened).
  final _failed = <String>{};

  /// reply id -> hearted, where it differs from what the row came with.
  final _hearts = <String, bool>{};
  final _heartBusy = <String>{};

  /// reply id -> its RealMoji reactions, once asked for.
  final _reactions = <String, List<PingRealmoji>>{};
  final _reactionsAsked = <int>{};
  final _bursts = <_Burst>[];
  int _burstSeq = 0;

  VideoPlayerController? _video;
  String? _videoFor;
  bool _muted = false;

  ReplyStory get _story => widget.stories[_s];
  ReceivedReplyRow get _reply => _story.replies[_i];

  bool _hearted(ReceivedReplyRow r) => _hearts[r.replyId] ?? r.myReaction;

  /// The RealMoji I left on [r], if any.
  PingRealmoji? _myRealmoji(ReceivedReplyRow r) =>
      (_reactions[r.replyId] ?? const <PingRealmoji>[])
          .where((x) => x.isMine)
          .firstOrNull;

  /// Fetches the reactions for [ids] and replaces what is held for them.
  /// Best-effort: a failed fetch leaves what is there.
  Future<void> _loadReactions(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final rows = await widget.delegate.fetchReactions(ids);
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          _reactions[id] = const [];
        }
        for (final x in rows) {
          final id = x.replyId;
          if (id != null) _reactions[id] = [...?_reactions[id], x];
        }
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _dropVideo();
    _progress.dispose();
    super.dispose();
  }

  void _dropVideo() {
    final v = _video;
    _video = null;
    _videoFor = null;
    if (v != null) {
      v.removeListener(_onVideoTick);
      unawaited(v.dispose());
    }
  }

  /// The bar follows the clip, not a clock: buffering can't run it out.
  void _onVideoTick() {
    final v = _video;
    if (v == null || !mounted || _closing) return;
    final value = v.value;
    final total = value.duration.inMilliseconds;
    if (!value.isInitialized || total <= 0) return;
    final t = value.position.inMilliseconds / total;
    if (value.isCompleted || t >= 0.995) {
      // Not from inside the controller's own notification: moving on
      // disposes it.
      v.removeListener(_onVideoTick);
      Future<void>.microtask(() {
        if (mounted && _video == v) _next();
      });
    } else {
      _progress.value = t.clamp(0.0, 0.99);
    }
  }

  /// Starts [r]'s clip. False when it can't be played.
  Future<bool> _startVideo(ReceivedReplyRow r, int gen) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(r.videoUrl!));
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
    } catch (_) {
      unawaited(controller.dispose());
      return false;
    }
    if (!mounted || gen != _gen) {
      unawaited(controller.dispose());
      return true;
    }
    await controller.setLooping(false);
    await controller.setVolume(_muted ? 0 : 1);
    controller.addListener(_onVideoTick);
    setState(() {
      _video = controller;
      _videoFor = r.replyId;
    });
    if (!_held && !_sheetOpen) unawaited(controller.play());
    return true;
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _next();
  }

  /// Opened = it is on screen now. Told to the server once, and only for a
  /// reply that hadn't been opened before.
  void _markOpened(ReceivedReplyRow r) {
    if (r.viewed || !_opened.add(r.replyId)) return;
    unawaited(widget.delegate.markViewed(r.replyId));
  }

  Future<void> _start() async {
    if (!mounted) return;
    final gen = ++_gen;
    final r = _reply;
    _dropVideo();
    _progress
      ..stop()
      ..value = 0;
    // Once per person: what I have already reacted with on theirs.
    if (_reactionsAsked.add(_s)) {
      unawaited(_loadReactions([for (final x in _story.replies) x.replyId]));
    }

    if (r.videoUrl != null) {
      if (await _startVideo(r, gen)) {
        if (mounted && gen == _gen) _markOpened(r);
        return;
      }
      if (!mounted || gen != _gen) return;
    }
    final url = r.photoUrl;
    if (url != null && url.isNotEmpty) {
      var aspect = _aspects[r.replyId];
      aspect ??= await widget.delegate.loadPhoto(context, url);
      if (!mounted || gen != _gen) return;
      if (aspect == null) {
        // Not opened: it comes back in REPLIES for another try.
        setState(() => _failed.add(r.replyId));
      } else {
        setState(() {
          _aspects[r.replyId] = aspect!;
          _failed.remove(r.replyId);
        });
        _markOpened(r);
      }
    } else if (r.videoUrl == null) {
      // Words, or a plain ping back: nothing to wait for.
      _markOpened(r);
    } else {
      // A clip that would not play and has no still to fall back on.
      setState(() => _failed.add(r.replyId));
    }
    if (!_held && !_sheetOpen) unawaited(_progress.forward(from: 0));
  }

  void _resume() {
    if (_held || _sheetOpen || _closing) return;
    final v = _video;
    if (v != null) {
      unawaited(v.play());
    } else {
      unawaited(_progress.forward());
    }
  }

  void _pause() {
    _progress.stop();
    final v = _video;
    if (v != null) unawaited(v.pause());
  }

  /// On to the one they sent BEFORE this; then the next person; then out.
  void _next() {
    if (_closing) return;
    if (_i < _story.replies.length - 1) {
      setState(() => _i++);
      unawaited(_start());
    } else if (_s < widget.stories.length - 1) {
      setState(() {
        _s++;
        _i = 0;
      });
      unawaited(_start());
    } else {
      _close();
    }
  }

  /// Back towards their latest; from there, to the person before.
  void _prev() {
    if (_closing) return;
    if (_i > 0) {
      setState(() => _i--);
    } else if (_s > 0) {
      setState(() {
        _s--;
        _i = 0;
      });
    }
    unawaited(_start());
  }

  /// A swipe to the left: the next PERSON, whatever is left of this one.
  void _nextStory() {
    if (_closing) return;
    if (_s < widget.stories.length - 1) {
      setState(() {
        _s++;
        _i = 0;
      });
      unawaited(_start());
    } else {
      _close();
    }
  }

  /// A swipe to the right: the person before (or, on the first, back to
  /// the top of this one).
  void _prevStory() {
    if (_closing) return;
    setState(() {
      if (_s > 0) _s--;
      _i = 0;
    });
    unawaited(_start());
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _pause();
    Navigator.of(context).pop(_opened);
  }

  /// The Ping page's reaction tray, with the story held still under it —
  /// and under the selfie camera, if picking a RealMoji leads there.
  Future<void> _openReactions() async {
    if (_sheetOpen || _closing) return;
    final r = _reply;
    _sheetOpen = true;
    _pause();
    try {
      await widget.delegate.pickReaction(
        context,
        replyId: r.replyId,
        heartLiked: _hearted(r),
        onHeart: () => unawaited(_heart()),
        onReacted: () => unawaited(_loadReactions([r.replyId])),
      );
      // The tray can hand over to a full-screen selfie camera after it
      // closes; wait until this screen is the one in front again.
      while (mounted && !(ModalRoute.of(context)?.isCurrent ?? true)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      _sheetOpen = false;
      if (mounted) _resume();
    }
  }

  void _hold(bool held) {
    _held = held;
    if (held) {
      _pause();
    } else {
      _resume();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    final v = _video;
    if (v != null) unawaited(v.setVolume(_muted ? 0 : 1));
  }

  /// [only] true = a double tap, which hearts but never takes one back.
  Future<void> _heart({Offset? at, bool only = false}) async {
    final r = _reply;
    final was = _hearted(r);
    if (only && was) {
      if (at != null) setState(() => _bursts.add(_Burst(++_burstSeq, at)));
      return;
    }
    if (!_heartBusy.add(r.replyId)) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _hearts[r.replyId] = !was;
      if (!was && at != null) _bursts.add(_Burst(++_burstSeq, at));
    });
    try {
      final now = await widget.delegate.toggleHeart(r.replyId);
      if (mounted && now != !was) setState(() => _hearts[r.replyId] = now);
    } catch (_) {
      // A heart that looks landed but wasn't is worse than none.
      if (mounted) setState(() => _hearts[r.replyId] = was);
    } finally {
      _heartBusy.remove(r.replyId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final story = _story;
    final r = _reply;
    final dragT = (_dragDy / 320).clamp(0.0, 1.0);
    final firstName = story.name.trim().split(' ').first;

    return PopScope<Set<String>>(
      // The system back gesture hands back what was opened too.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Material(
        color: Colors.black.withValues(alpha: 1 - dragT * 0.6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) {
            final next = (_dragDy + d.delta.dy).clamp(0.0, 600.0);
            if (next > 0) _pause();
            setState(() => _dragDy = next);
          },
          onVerticalDragEnd: (d) {
            if (_dragDy > 110 || (d.primaryVelocity ?? 0) > 700) {
              _close();
            } else {
              setState(() => _dragDy = 0);
              _resume();
            }
          },
          // Sideways: the page follows the finger a little, and a real
          // swipe changes person.
          onHorizontalDragUpdate: (d) {
            _pause();
            setState(
              () => _dragDx = (_dragDx + d.delta.dx).clamp(-160.0, 160.0),
            );
          },
          onHorizontalDragCancel: () {
            setState(() => _dragDx = 0);
            _resume();
          },
          onHorizontalDragEnd: (d) {
            final dx = _dragDx;
            final v = d.primaryVelocity ?? 0;
            setState(() => _dragDx = 0);
            if (dx < -70 || v < -600) {
              _nextStory();
            } else if (dx > 70 || v > 600) {
              _prevStory();
            } else {
              _resume();
            }
          },
          child: Transform.translate(
            offset: Offset(_dragDx * 0.6, _dragDy),
            child: Transform.scale(
              scale: 1 - dragT * 0.08,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // What they sent.
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        media.padding.top + 76,
                        14,
                        media.padding.bottom + 104,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(r.replyId),
                          child: _content(r, firstName),
                        ),
                      ),
                    ),
                  ),

                  // Tap zones: the edges move at once; the middle is for
                  // hold (pause) and double-tap (heart), so moving never
                  // waits on a double-tap timeout.
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 28,
                          child: GestureDetector(
                            key: const ValueKey('reply-story-prev'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _prev,
                            onLongPressStart: (_) => _hold(true),
                            onLongPressEnd: (_) => _hold(false),
                          ),
                        ),
                        Expanded(
                          flex: 44,
                          child: GestureDetector(
                            key: const ValueKey('reply-story-middle'),
                            behavior: HitTestBehavior.opaque,
                            onDoubleTapDown: (d) => unawaited(
                              _heart(at: d.globalPosition, only: true),
                            ),
                            onDoubleTap: () {},
                            onLongPressStart: (_) => _hold(true),
                            onLongPressEnd: (_) => _hold(false),
                          ),
                        ),
                        Expanded(
                          flex: 28,
                          child: GestureDetector(
                            key: const ValueKey('reply-story-next'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _next,
                            onLongPressStart: (_) => _hold(true),
                            onLongPressEnd: (_) => _hold(false),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top: one bar per thing they sent, then who and when.
                  Positioned(
                    left: 12,
                    right: 12,
                    top: media.padding.top + 8,
                    child: Column(
                      children: [
                        StoryProgressBars(
                          count: story.replies.length,
                          index: _i,
                          progress: _progress,
                        ),
                        const SizedBox(height: 12),
                        _header(story, r),
                      ],
                    ),
                  ),

                  // Bottom: what it answers, and the heart.
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: media.padding.bottom + 20,
                    child: _footer(r),
                  ),

                  for (final b in _bursts)
                    EmojiBurst(
                      key: ValueKey(b.id),
                      origin: b.at,
                      emoji: '❤️',
                      particleCount: 9,
                      onComplete: () {
                        if (mounted) setState(() => _bursts.remove(b));
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ReplyStory story, ReceivedReplyRow r) {
    final ago = formatRelativeTime(r.createdAt, withAgo: true);
    // "Latest" only means something when there is an earlier one.
    final when = story.replies.length < 2
        ? ago
        : '${_i == 0 ? 'Latest' : 'Earlier'} · $ago';
    final has = story.avatarUrl != null && story.avatarUrl!.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final id = story.replierId;
              _close();
              unawaited(openProfile(context, id));
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 19,
                    backgroundColor: const Color(0xFF26262B),
                    backgroundImage: has
                        ? CachedNetworkImageProvider(story.avatarUrl!)
                        : null,
                    child: has
                        ? null
                        : Text(
                            story.name.isEmpty
                                ? '?'
                                : story.name[0].toUpperCase(),
                            style: PV2.display(size: 15),
                          ),
                  ),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        story.name.isEmpty ? 'Someone' : story.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PV2.display(
                          size: 17,
                          letterSpacing: -0.2,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        when,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PV2.body(
                          size: 12,
                          weight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (r.videoUrl != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleMute,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 23,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
        const SizedBox(width: 4),
        GestureDetector(
          key: const ValueKey('reply-story-close'),
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
            ),
            child: Icon(
              Icons.close_rounded,
              size: 21,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer(ReceivedReplyRow r) {
    final prompt = r.prompt.trim();
    final hearted = _hearted(r);
    final mine = _myRealmoji(r);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prompt.isNotEmpty) ...[
          Text(
            'to your ping  “$prompt”',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PV2.body(
              size: 12.5,
              weight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
        ],
        GestureDetector(
          key: const ValueKey('reply-story-react'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_openReactions()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.fromLTRB(mine != null ? 8 : 20, 8, 22, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              color: mine != null
                  ? PV2.accent.withValues(alpha: 0.14)
                  : hearted
                  ? _kHeart.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: mine != null
                    ? PV2.accent.withValues(alpha: 0.6)
                    : hearted
                    ? _kHeart.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wears what I reacted with, the way the Ping page's
                // button does: my RealMoji, else the heart, else "add".
                SizedBox(
                  height: 30,
                  child: Center(
                    child: mine != null
                        ? PingRealmojiFace(r: mine, size: 30)
                        : Icon(
                            hearted
                                ? Icons.favorite_rounded
                                : Icons.add_reaction_outlined,
                            size: 21,
                            color: hearted ? _kHeart : Colors.white,
                          ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  mine != null
                      ? 'Reacted'
                      : hearted
                      ? 'Loved'
                      : 'React',
                  style: PV2.body(
                    size: 14,
                    weight: FontWeight.w700,
                    color: mine != null
                        ? PV2.accent
                        : hearted
                        ? _kHeart
                        : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The reply itself: a clip, a photo shown whole, their words, or — for
  /// a plain ping back — a quiet line saying so.
  Widget _content(ReceivedReplyRow r, String firstName) {
    final video = _video;
    if (video != null && _videoFor == r.replyId) {
      return _card(
        aspect: video.value.aspectRatio,
        child: VideoPlayer(video),
        r: r,
      );
    }
    if (_failed.contains(r.replyId)) {
      return _notice(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load this one",
        body: 'It stays in your replies — try again in a bit.',
      );
    }
    final url = r.photoUrl;
    if (url != null && url.isNotEmpty) {
      final aspect = _aspects[r.replyId];
      if (aspect == null) return const _Loading();
      return _card(
        aspect: aspect,
        child: widget.delegate.buildPhoto(context, url),
        r: r,
      );
    }
    if (r.videoUrl != null) return const _Loading();
    final words = (r.body ?? '').trim();
    if (words.isEmpty || words == kPingBackBody) {
      return _notice(
        emoji: '👋',
        title: '$firstName pinged you back',
        body: 'No photo this time — just a wave.',
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: TextPingCard(text: words),
        ),
      ),
    );
  }

  /// A photo or clip at its own shape — whole, never cropped — with the
  /// front-camera inset and their words laid over it.
  Widget _card({
    required double aspect,
    required Widget child,
    required ReceivedReplyRow r,
  }) {
    final words = (r.body ?? '').trim();
    final selfie = r.selfieUrl;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect.clamp(0.4, 2.4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: LayoutBuilder(
              builder: (context, box) {
                final insetW = (box.maxWidth * 0.27).clamp(64.0, 120.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    if (selfie != null && selfie.isNotEmpty)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          width: insetW,
                          height: insetW * 1.25,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 1.5,
                            ),
                            color: Colors.white.withValues(alpha: 0.08),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: widget.delegate.buildSelfie(context, selfie),
                        ),
                      ),
                    if (words.isNotEmpty && words != kPingBackBody)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: 0.72),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 34, 16, 16),
                            child: Text(
                              words,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: PV2.body(
                                size: 15,
                                weight: FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice({
    IconData? icon,
    String? emoji,
    required String title,
    required String body,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null)
              Text(emoji, style: const TextStyle(fontSize: 54, height: 1.1))
            else
              Icon(
                icon,
                size: 40,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: PV2.display(size: 22, letterSpacing: -0.3),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: PV2.body(
                size: 14,
                color: Colors.white.withValues(alpha: 0.55),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Burst {
  _Burst(this.id, this.at);
  final int id;
  final Offset at;
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
    ),
  );
}
