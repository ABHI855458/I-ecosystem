import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../../screens/feed/widgets/post_card_shared.dart'
    show showPostCommentsSheet;
import '../../services/highlight_service.dart';
import '../../services/post_service.dart' show PostService, PostViewer;
import '../../services/reaction_service.dart'
    show ReactionService, ReactionSummary;
import '../../widgets/emoji_burst.dart';
import '../../widgets/story_progress_bars.dart';
import '../profile_v2/profile_navigation.dart';
import '../profile_v2/profile_v2_tokens.dart';
import 'highlight_models.dart';

// ---------------------------------------------------------------------------
// The story — what a polaroid opens into.
//
// One photo at a time, full screen, with progress bars across the top. Each
// photo moves on by itself; tap the right or left edge to skip, hold to
// pause, swipe down to close. When a highlight ends the next one in the
// list plays by itself, and the viewer closes after the last.
//
// A short VIDEO plays in place of a photo: its bar follows the clip's real
// position (so a slow connection can't skip it), and it moves on when the
// clip ends. Hold pauses it too.
//
// Reactions go against the photo's own post (see HighlightPhoto.postId),
// so the owner gets the ordinary reaction notification and "seen by" is the
// ordinary post_views list.
// ---------------------------------------------------------------------------

const kHighlightPhotoDuration = Duration(seconds: 4);
const _kQuickEmoji = ['❤️', '🔥', '😂', '😮', '😍'];

/// Everything the viewer does that touches the network or the device, so a
/// test can stand in for it.
class HighlightStoryDelegate {
  const HighlightStoryDelegate();

  bool isMine(Highlight h) => HighlightService.instance.isMine(h);

  Future<void> markSeen(Highlight h) => HighlightService.instance.markSeen(h);

  Future<void> recordView(String postId) =>
      PostService.instance.recordView(postId);

  Future<ReactionSummary?> fetchSummary(String postId) async {
    try {
      return await ReactionService.instance.fetchSummary(postId);
    } catch (_) {
      return null;
    }
  }

  Future<void> react(String postId, String emoji) =>
      ReactionService.instance.setEmojiReaction(postId: postId, emoji: emoji);

  Future<void> unreact(String postId) =>
      ReactionService.instance.removeEmojiReaction(postId);

  Future<List<PostViewer>> fetchViewers(String postId) =>
      PostService.instance.fetchPostViewers(postId);

  /// Waits until [url] is decoded so the timer doesn't run over a blank
  /// screen. Never throws; gives up after a few seconds.
  Future<void> preload(BuildContext context, String url) async {
    try {
      await precacheImage(
        CachedNetworkImageProvider(url),
        context,
      ).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Widget buildPhoto(BuildContext context, HighlightPhoto photo) =>
      CachedNetworkImage(
        imageUrl: photo.url,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) => const SizedBox.expand(),
        errorWidget: (_, _, _) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white.withValues(alpha: 0.4),
            size: 40,
          ),
        ),
      );
}

/// Opens the story on [highlights], starting at [initialIndex]. Completes
/// when it closes; the value is true when it played through to the end
/// (rather than being dismissed part-way).
Future<bool> openHighlightStory(
  BuildContext context, {
  required List<Highlight> highlights,
  int initialIndex = 0,
  Object? heroTag,
  void Function(Highlight highlight)? onEdit,
}) async {
  if (highlights.isEmpty) return false;
  final finished = await Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder<bool>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => HighlightStoryViewer(
        highlights: highlights,
        initialIndex: initialIndex,
        heroTag: heroTag,
        onEdit: onEdit,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
  return finished ?? false;
}

class HighlightStoryViewer extends StatefulWidget {
  const HighlightStoryViewer({
    super.key,
    required this.highlights,
    this.initialIndex = 0,
    this.heroTag,
    this.onEdit,
    this.delegate = const HighlightStoryDelegate(),
    this.photoDuration = kHighlightPhotoDuration,
  });

  final List<Highlight> highlights;
  final int initialIndex;

  /// Matches the tapped polaroid's Hero, for the first photo only.
  final Object? heroTag;

  /// Shown as "Edit" on my own highlight.
  final void Function(Highlight highlight)? onEdit;

  final HighlightStoryDelegate delegate;
  final Duration photoDuration;

  @override
  State<HighlightStoryViewer> createState() => _HighlightStoryViewerState();
}

class _HighlightStoryViewerState extends State<HighlightStoryViewer>
    with SingleTickerProviderStateMixin {
  late int _h = widget.initialIndex.clamp(0, widget.highlights.length - 1);
  int _p = 0;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.photoDuration,
  )..addStatusListener(_onProgressStatus);

  /// Bumped on every photo change so a slow preload for a photo the viewer
  /// has already left can't start the timer on the wrong one.
  int _gen = 0;
  bool _held = false;
  bool _sheetOpen = false;
  bool _closing = false;
  double _dragDy = 0;

  final _summaries = <String, ReactionSummary>{};
  final _viewers = <String, List<PostViewer>>{};
  final _seenMarked = <String>{};
  final _bursts = <_Burst>[];
  int _burstSeq = 0;

  /// The clip on screen, once it is ready to draw; null for a photo, and
  /// while a video is still loading (its poster shows meanwhile).
  VideoPlayerController? _video;
  String? _videoFor;
  bool _muted = false;

  Highlight get _highlight => widget.highlights[_h];
  HighlightPhoto get _photo => _highlight.photos[_p];
  bool get _mine => widget.delegate.isMine(_highlight);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPhoto());
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

  /// Starts [photo]'s clip. False when it can't be played — the caller
  /// then shows its poster for the usual few seconds instead.
  Future<bool> _startVideo(HighlightPhoto photo, int gen) async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(photo.videoUrl!),
    );
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
      _videoFor = photo.postId;
    });
    if (!_held && !_sheetOpen) unawaited(controller.play());
    return true;
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _next();
  }

  Future<void> _startPhoto() async {
    if (!mounted) return;
    final gen = ++_gen;
    final highlight = _highlight;
    final photo = _photo;
    _dropVideo();
    _progress
      ..stop()
      ..value = 0;

    if (_seenMarked.add(highlight.id)) {
      unawaited(widget.delegate.markSeen(highlight));
      // One view per opened highlight, on its first photo: enough for the
      // owner's "seen by", without a row (and a pinned-view notification)
      // per photo.
      if (!_mine) {
        unawaited(widget.delegate.recordView(highlight.photos.first.postId));
      }
    }
    unawaited(_loadMeta(photo, highlight));

    if (photo.isVideo) {
      // The poster is on screen while the clip gets ready.
      if (await _startVideo(photo, gen)) return;
      if (!mounted || gen != _gen) return;
    }
    await widget.delegate.preload(context, photo.url);
    if (!mounted || gen != _gen) return;
    if (!_held && !_sheetOpen) unawaited(_progress.forward(from: 0));
  }

  /// Resumes whatever is on screen: the clip if there is one, else the
  /// photo's timer.
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

  Future<void> _loadMeta(HighlightPhoto photo, Highlight highlight) async {
    final mine = widget.delegate.isMine(highlight);
    final results = await Future.wait<Object?>([
      widget.delegate.fetchSummary(photo.postId),
      if (mine)
        widget.delegate
            .fetchViewers(highlight.photos.first.postId)
            .then<Object?>((v) => v)
            .catchError((_) => const <PostViewer>[]),
    ]);
    if (!mounted) return;
    setState(() {
      final summary = results[0] as ReactionSummary?;
      if (summary != null) _summaries[photo.postId] = summary;
      if (mine && results.length > 1) {
        _viewers[highlight.id] = results[1] as List<PostViewer>;
      }
    });
  }

  void _next() {
    if (_closing) return;
    if (_p < _highlight.photos.length - 1) {
      setState(() => _p++);
      unawaited(_startPhoto());
    } else if (_h < widget.highlights.length - 1) {
      setState(() {
        _h++;
        _p = 0;
      });
      unawaited(_startPhoto());
    } else {
      _close(finished: true);
    }
  }

  void _prev() {
    if (_closing) return;
    if (_p > 0) {
      setState(() => _p--);
    } else if (_h > 0) {
      setState(() {
        _h--;
        _p = 0;
      });
    }
    unawaited(_startPhoto());
  }

  void _close({bool finished = false}) {
    if (_closing) return;
    _closing = true;
    _pause();
    Navigator.of(context).pop(finished);
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

  Future<void> _react(String emoji, Offset at) async {
    final photo = _photo;
    final before = _summaries[photo.postId];
    final removing = before?.myEmoji == emoji;
    HapticFeedback.lightImpact();
    if (!removing) {
      setState(() => _bursts.add(_Burst(++_burstSeq, at, emoji)));
    }
    // Optimistic: the picked chip lights up at once.
    setState(() {
      final counts = Map<String, int>.from(before?.emojiCounts ?? const {});
      final old = before?.myEmoji;
      if (old != null) {
        final n = (counts[old] ?? 1) - 1;
        if (n <= 0) {
          counts.remove(old);
        } else {
          counts[old] = n;
        }
      }
      if (!removing) counts[emoji] = (counts[emoji] ?? 0) + 1;
      _summaries[photo.postId] = ReactionSummary(
        emojiCounts: counts,
        myEmoji: removing ? null : emoji,
        faceReactions: before?.faceReactions ?? const [],
        myFaceReaction: before?.myFaceReaction,
      );
    });
    try {
      if (removing) {
        await widget.delegate.unreact(photo.postId);
      } else {
        await widget.delegate.react(photo.postId, emoji);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (before == null) {
          _summaries.remove(photo.postId);
        } else {
          _summaries[photo.postId] = before;
        }
      });
    }
  }

  Future<void> _withPause(Future<void> Function() body) async {
    _sheetOpen = true;
    _pause();
    try {
      await body();
    } finally {
      _sheetOpen = false;
      if (mounted) _resume();
    }
  }

  void _openReactions() {
    final photo = _photo;
    final highlight = _highlight;
    final summary = _summaries[photo.postId];
    unawaited(
      _withPause(() async {
        final done = Completer<void>();
        showPostCommentsSheet(
          context,
          postId: photo.postId,
          isGroup: false,
          reactionCount: summary?.totalReactionCount ?? 0,
          onPosted: () => unawaited(_loadMeta(photo, highlight)),
        );
        // showPostCommentsSheet doesn't hand back its route; wait for the
        // sheet route above this one to go away before resuming.
        void check() {
          if (!mounted) {
            done.complete();
            return;
          }
          if (ModalRoute.of(context)?.isCurrent ?? true) {
            done.complete();
          } else {
            Future<void>.delayed(const Duration(milliseconds: 250), check);
          }
        }

        Future<void>.delayed(const Duration(milliseconds: 400), check);
        await done.future;
      }),
    );
  }

  void _openSeenBy() {
    final viewers = _viewers[_highlight.id] ?? const <PostViewer>[];
    unawaited(
      _withPause(
        () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: PV2.raised,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (context) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seen by ${viewers.length}',
                    style: PV2.display(size: 18),
                  ),
                  const SizedBox(height: 10),
                  if (viewers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Nobody has opened it yet.',
                        style: PV2.body(size: 13.5, color: PV2.inkMember),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: viewers.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Text(
                            viewers[i].displayName,
                            style: PV2.body(size: 14.5),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final highlight = _highlight;
    final photo = _photo;
    final summary = _summaries[photo.postId];
    final dragT = (_dragDy / 320).clamp(0.0, 1.0);

    Widget image = widget.delegate.buildPhoto(context, photo);
    if (widget.heroTag != null && _h == widget.initialIndex && _p == 0) {
      image = Hero(tag: widget.heroTag!, child: image);
    }
    // The clip, once ready, over its own poster — whole, never cropped.
    final video = _video;
    if (video != null && _videoFor == photo.postId) {
      image = Stack(
        fit: StackFit.expand,
        children: [
          image,
          Center(
            child: AspectRatio(
              aspectRatio: video.value.aspectRatio,
              child: VideoPlayer(video),
            ),
          ),
        ],
      );
    }

    return Material(
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
        child: Transform.translate(
          offset: Offset(0, _dragDy),
          child: Transform.scale(
            scale: 1 - dragT * 0.08,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The photo.
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: media.padding.top + 58,
                      bottom: media.padding.bottom + 86,
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(photo.postId),
                      child: image,
                    ),
                  ),
                ),

                // Tap zones: edges skip at once; the middle is for hold
                // (pause) and double-tap (heart), so skipping never waits
                // on a double-tap timeout.
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 28,
                        child: GestureDetector(
                          key: const ValueKey('story-prev'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _prev,
                          onLongPressStart: (_) => _hold(true),
                          onLongPressEnd: (_) => _hold(false),
                        ),
                      ),
                      Expanded(
                        flex: 44,
                        child: GestureDetector(
                          key: const ValueKey('story-middle'),
                          behavior: HitTestBehavior.opaque,
                          onDoubleTapDown: _mine
                              ? null
                              : (d) => unawaited(
                                  _react('❤️', d.globalPosition),
                                ),
                          onDoubleTap: _mine ? null : () {},
                          onLongPressStart: (_) => _hold(true),
                          onLongPressEnd: (_) => _hold(false),
                        ),
                      ),
                      Expanded(
                        flex: 28,
                        child: GestureDetector(
                          key: const ValueKey('story-next'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _next,
                          onLongPressStart: (_) => _hold(true),
                          onLongPressEnd: (_) => _hold(false),
                        ),
                      ),
                    ],
                  ),
                ),

                // Top: progress bars + whose it is.
                Positioned(
                  left: 12,
                  right: 12,
                  top: media.padding.top + 8,
                  child: Column(
                    children: [
                      StoryProgressBars(
                        count: highlight.photos.length,
                        index: _p,
                        progress: _progress,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _mine
                                ? null
                                : () {
                                    final id = highlight.ownerId;
                                    _close();
                                    unawaited(openProfile(context, id));
                                  },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _Avatar(
                                  url: highlight.ownerAvatarUrl,
                                  name: highlight.ownerName,
                                ),
                                const SizedBox(width: 9),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      highlight.title,
                                      style: GoogleFonts.caveat(
                                        fontSize: 23,
                                        height: 1,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _mine
                                          ? 'You'
                                          : (highlight.ownerName.isEmpty
                                                ? 'someone'
                                                : highlight.ownerName),
                                      style: PV2.body(
                                        size: 11.5,
                                        color: Colors.white.withValues(
                                          alpha: 0.62,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (_mine && widget.onEdit != null)
                            _TopButton(
                              label: 'Edit',
                              onTap: () {
                                final h = highlight;
                                _close();
                                widget.onEdit!(h);
                              },
                            ),
                          if (photo.isVideo)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleMute,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  _muted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  size: 23,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            key: const ValueKey('story-close'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _close,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.close_rounded,
                                size: 26,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Bottom: react (a friend's) or who saw / reacted (mine).
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: media.padding.bottom + 18,
                  child: _mine
                      ? _OwnerBar(
                          seenCount: _viewers[highlight.id]?.length,
                          reactionCount: summary?.totalReactionCount ?? 0,
                          onSeen: _openSeenBy,
                          onReactions: _openReactions,
                        )
                      : _ReactBar(
                          myEmoji: summary?.myEmoji,
                          onPick: (emoji, at) => unawaited(_react(emoji, at)),
                        ),
                ),

                for (final b in _bursts)
                  EmojiBurst(
                    key: ValueKey(b.id),
                    origin: b.at,
                    emoji: b.emoji,
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
    );
  }
}

class _Burst {
  _Burst(this.id, this.at, this.emoji);
  final int id;
  final Offset at;
  final String emoji;
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: 17,
      backgroundColor: const Color(0xFF26262B),
      backgroundImage: has ? CachedNetworkImageProvider(url!) : null,
      child: has
          ? null
          : Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: PV2.display(size: 14),
            ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: Colors.white.withValues(alpha: 0.14),
        ),
        child: Text(label, style: PV2.body(size: 12.5, weight: FontWeight.w700)),
      ),
    );
  }
}

class _ReactBar extends StatelessWidget {
  const _ReactBar({required this.myEmoji, required this.onPick});

  final String? myEmoji;
  final void Function(String emoji, Offset at) onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: Colors.white.withValues(alpha: 0.1),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in _kQuickEmoji)
              Builder(
                builder: (context) {
                  final picked = myEmoji == e;
                  return GestureDetector(
                    key: ValueKey('story-react-$e'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final box = context.findRenderObject() as RenderBox?;
                      final at = box == null
                          ? Offset.zero
                          : box.localToGlobal(box.size.center(Offset.zero));
                      onPick(e, at);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        color: picked
                            ? PV2.accent.withValues(alpha: 0.28)
                            : Colors.transparent,
                        border: Border.all(
                          color: picked
                              ? PV2.accent.withValues(alpha: 0.9)
                              : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _OwnerBar extends StatelessWidget {
  const _OwnerBar({
    required this.seenCount,
    required this.reactionCount,
    required this.onSeen,
    required this.onReactions,
  });

  /// Null while it's still loading.
  final int? seenCount;
  final int reactionCount;
  final VoidCallback onSeen;
  final VoidCallback onReactions;

  @override
  Widget build(BuildContext context) {
    Widget pill(IconData icon, String label, VoidCallback onTap) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              color: Colors.white.withValues(alpha: 0.12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: PV2.body(size: 13, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        pill(
          Icons.remove_red_eye_outlined,
          seenCount == null ? 'Seen by …' : 'Seen by $seenCount',
          onSeen,
        ),
        const SizedBox(width: 10),
        pill(
          Icons.favorite_rounded,
          reactionCount == 0 ? 'Reactions' : '$reactionCount',
          onReactions,
        ),
      ],
    );
  }
}
