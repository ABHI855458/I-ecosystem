import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../services/current_user_service.dart';
import '../../services/post_service.dart' show PostService, PostViewer;
import '../../services/us_album_service.dart';
import '../../screens/feed/widgets/post_card_shared.dart'
    show ReactionPreviewChip, SeenDropdown, SeenPill, showPostCommentsSheet;
import '../../services/reaction_service.dart' show ReactionService, ReactionSummary;
import '../moderation/post_actions_menu.dart';
import 'profile_v2_data.dart';
import 'profile_v2_icons.dart';

// ---------------------------------------------------------------------------
// AlbumPhotoViewer — full-screen, swipeable viewer for a Duo's photos.
// Opened by tapping a photo tile in AlbumMosaic (see that file's own
// _photoTile — previously only the small privacy badge in the corner was
// tappable at all; the tile itself had no full-screen entry point).
// ---------------------------------------------------------------------------

void showAlbumPhotoViewer(
  BuildContext context, {
  required List<AlbumPhoto> photos,
  required int initialIndex,
  VoidCallback? onChanged,
  ValueChanged<String>? onRemoved,
}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => AlbumPhotoViewer(
        photos: photos,
        initialIndex: initialIndex,
        onChanged: onChanged,
        onRemoved: onRemoved,
      ),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class AlbumPhotoViewer extends StatefulWidget {
  const AlbumPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.onChanged,
    this.onRemoved,
  });

  final List<AlbumPhoto> photos;
  final int initialIndex;

  /// Fired after a photo is removed, so the album behind this viewer can
  /// refetch instead of showing a tile that no longer exists.
  final VoidCallback? onChanged;

  /// Fired with the removed photo's id, before [onChanged] — lets the album
  /// drop that tile instantly rather than after its refetch.
  final ValueChanged<String>? onRemoved;

  @override
  State<AlbumPhotoViewer> createState() => _AlbumPhotoViewerState();
}

class _AlbumPhotoViewerState extends State<AlbumPhotoViewer> {
  late final PageController _ctrl = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// My own `users.id`, for telling my photos from the other person's.
  /// Null until it resolves — the menu then offers Report rather than
  /// Remove, which is the safe direction (and the only one the DB would
  /// have allowed anyway).
  String? _myUserId;

  /// Photos removed in this session, hidden immediately so the viewer
  /// doesn't keep showing something that is already gone.
  final _removed = <String>{};

  /// photo id -> the `posts` row it was published as, once resolved.
  ///
  /// A mutual album photo is mirrored into `posts` by a trigger, and that
  /// row is what actually holds its reactions and comments. Without this
  /// lookup the album viewer could only offer the "..." menu, so reacting
  /// or commenting on a photo of the two of you meant finding it again in
  /// the feed. Absent key = private photo (no post) or still loading.
  final _feedPostIds = <String, String?>{};

  /// photo id -> the pair's ping streak, once resolved. Same lazy per-photo
  /// resolution as [_feedPostIds], off the post id that lookup produces —
  /// the streak is a property of the two people, but it is fetched through
  /// the POST so the server can gate it on can_view_post().
  final _pairStreaks = <String, int?>{};

  /// photo id -> everyone who has opened its post, all-time — the same
  /// post_viewers RPC every other post's SeenPill/SeenDropdown reads.
  /// Explicit request: "the us album photo... able to view... who all saw
  /// it" — a mutual photo had reactions and comments already, but no
  /// viewers list at all.
  final _viewers = <String, List<PostViewer>>{};

  /// photo id -> its reaction summary, for the count ReactionPreviewChip
  /// shows. The old bottom-left PostReactionStack this replaces fetched its
  /// own reactor list internally; the chip needs the count handed to it.
  final _reactionSummaries = <String, ReactionSummary>{};

  /// Only ever true for the photo on screen — the seen dropdown for
  /// whichever page is current, dismissed on swipe like every other
  /// per-card popover in this app.
  bool _showSeenDropdown = false;

  List<AlbumPhoto> get _visible => [
        for (final p in widget.photos)
          if (p.id == null || !_removed.contains(p.id)) p,
      ];

  @override
  void initState() {
    super.initState();
    _resolveMe();
    _resolveFeedPost(widget.photos[widget.initialIndex]);
  }

  /// Resolved lazily, per photo, as it comes into view — an album can hold
  /// many photos and only the one on screen needs its post.
  Future<void> _resolveFeedPost(AlbumPhoto photo) async {
    final id = photo.id;
    if (id == null || _feedPostIds.containsKey(id)) return;
    final postId = await DuoService.instance.feedPostIdForPhoto(id);
    if (!mounted) return;
    setState(() => _feedPostIds[id] = postId);
    if (postId == null) return;
    final results = await Future.wait([
      DuoService.instance.pairStreakForPost(postId),
      PostService.instance.fetchPostViewers(postId),
      ReactionService.instance.fetchSummary(postId),
    ]);
    if (!mounted) return;
    final streak = results[0] as int?;
    setState(() {
      if (streak != null) _pairStreaks[id] = streak;
      _viewers[id] = results[1] as List<PostViewer>;
      _reactionSummaries[id] = results[2] as ReactionSummary;
    });
  }

  /// Comments open as a sheet over the photo, not as a pushed route.
  /// Explicit correction: "comments is opening a different page, let it open
  /// a drop down there only" — leaving the viewer to read a comment lost the
  /// photo and the swipe position. Same sheet the reactions chip opens, so
  /// both entry points land in one place.
  /// [postId] is null for a photo that is still private — it has no `posts`
  /// row, so there is genuinely nothing to comment on yet. The controls stay
  /// visible either way (see their own doc in build) and this says why.
  void _openComments(AlbumPhoto photo, String? postId) {
    if (postId == null) {
      showGlassToast(
        context,
        'Make this photo mutual to react and comment on it.',
      );
      return;
    }
    showPostCommentsSheet(
      context,
      postId: postId,
      isGroup: false,
      reactionCount: _reactionSummaries[photo.id]?.totalReactionCount ?? 0,
      onPosted: () => _resolveFeedPost(photo),
    );
  }

  Future<void> _resolveMe() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      if (mounted) setState(() => _myUserId = id);
    } catch (_) {
      // Signed out — Report-only, see _myUserId's doc.
    }
  }

  Future<void> _openMenu(AlbumPhoto photo) async {
    final id = photo.id;
    if (id == null) return; // mock/design-gallery tile, nothing to act on
    await showAlbumPhotoActionsMenu(
      context,
      photoId: id,
      isMine: photo.uploaderId != null && photo.uploaderId == _myUserId,
      uploaderUsersId: photo.uploaderId,
      onDeleted: () {
        if (!mounted) return;
        setState(() {
          _removed.add(id);
          if (_index >= _visible.length) {
            _index = (_visible.length - 1).clamp(0, 1 << 30);
          }
        });
        widget.onRemoved?.call(id);
        widget.onChanged?.call();
        // Nothing left to look at.
        if (_visible.isEmpty && mounted) Navigator.of(context).maybePop();
      },
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _visible;
    if (photos.isEmpty) return const SizedBox.shrink();
    final photo = photos[_index.clamp(0, photos.length - 1)];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: photos.length,
              onPageChanged: (i) {
                setState(() {
                  _index = i;
                  _showSeenDropdown = false;
                });
                _resolveFeedPost(photos[i]);
              },
              itemBuilder: (context, i) {
                final p = photos[i];
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    // Rounded rather than hard-cornered, matching the album
                    // tiles the photo opens from. Explicit request: "make
                    // the photos to be in a smooth edged layout in us album
                    // opening".
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: p.imageUrl != null
                            ? CachedNetworkImage(
                                memCacheWidth: 1080,
                                imageUrl: p.imageUrl!,
                                fit: BoxFit.contain,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white24,
                                  size: 48,
                                ),
                              )
                            : DecoratedBox(
                                decoration: BoxDecoration(color: p.color),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // The "..." — Remove on your own photo, Report / Block on the
            // other person's. The viewer had no actions at all before, so
            // there was no way to take down a photo from a Duo or
            // report the person who added it.
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.more_horiz_rounded,
                    color: Colors.white, size: 26),
                onPressed: () => _openMenu(photo),
              ),
            ),
            // The pair's blue flame, centred at the top — the two of you,
            // and how many days the ping streak between you has run. Centred
            // rather than cornered because both corners are already taken
            // (close left, "..." right), and it belongs to BOTH people here
            // rather than to one side of the screen.
            if (photo.id != null && (_pairStreaks[photo.id] ?? 0) > 0)
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: PV2Icons.blueFlameStreak(
                    _pairStreaks[photo.id]!,
                    flameSize: 34,
                  ),
                ),
              ),
            // Who has seen this photo's post, all-time — the same
            // SeenPill/SeenDropdown every other post uses. Explicit
            // request: "able to view... who all saw it" — reactions and
            // comments already existed here, a viewers list didn't.
            if (photo.id != null)
              Positioned(
                top: 52,
                right: 12,
                child: SeenPill(
                  viewers: _viewers[photo.id!] ?? const [],
                  compact: true,
                  onTap: () => setState(
                    () => _showSeenDropdown = !_showSeenDropdown,
                  ),
                ),
              ),
            if (photo.id != null && _showSeenDropdown)
              Positioned(
                top: 92,
                right: 12,
                child: SeenDropdown(viewers: _viewers[photo.id!] ?? const []),
              ),
            // Reactions (bottom-left) and comments (bottom-right) for the
            // photo on screen — the same two things every post gets, in the
            // same places.
            //
            // Shown on EVERY page, not only published ones. Explicit
            // request: "on every page the reaction, seen and as well the
            // comment section shall be seen" — these used to be gated on the
            // photo having a `posts` row, so they blinked out of existence
            // while swiping through an album that is mostly private. A
            // private photo genuinely has nothing to react or comment to
            // (the mirroring trigger only publishes mutual ones), so the
            // controls stay in place and say why instead of vanishing.
            //
            // Reactions is the same non-identifying ReactionPreviewChip
            // every other post shows; tapping it opens the same comments
            // sheet Comments does, with the reactor strip on top.
            if (photo.id != null) ...[
              Positioned(
                left: 16,
                bottom: 52,
                child: ReactionPreviewChip(
                  // Count AND faces. Passing only the count rendered a bare
                  // "2 >" with no avatar — the same chip shows the reactors'
                  // RealMoji thumbnails everywhere else, and the preview is
                  // the point of it. Reported with a screenshot of both
                  // states side by side.
                  count: (_reactionSummaries[photo.id]?.totalEmojiCount ?? 0) +
                      (_reactionSummaries[photo.id]?.faceReactions.length ?? 0),
                  faces: _reactionSummaries[photo.id]?.faceReactions ?? const [],
                  emojiCounts:
                      _reactionSummaries[photo.id]?.emojiCounts ?? const {},
                  onTap: () => _openComments(photo, _feedPostIds[photo.id]),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 46,
                child: GestureDetector(
                  onTap: () => _openComments(photo, _feedPostIds[photo.id]),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mode_comment_outlined,
                            size: 15, color: Colors.white),
                        SizedBox(width: 7),
                        Text(
                          'Comments',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (photos.length > 1)
              Positioned(
                bottom: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${_index + 1} / ${photos.length}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 18,
              right: 16,
              child: Text(
                photo.ago,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
