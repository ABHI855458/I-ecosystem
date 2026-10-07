import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/moderation/post_actions_menu.dart';
import '../../services/current_user_service.dart';
import '../../services/feed_service.dart';
import '../../services/post_service.dart' show PostService, PostViewer;
import '../../services/reaction_service.dart';
import 'widgets/post_card_shared.dart'
    show PostCommentCard, ReactionPreviewChip, SeenDropdown, SeenPill;
import 'widgets/post_photo_carousel.dart';

/// How replies are composed on a post.
///
/// [text] is the ordinary comment thread and is the only mode implemented.
/// [photo] is the parked Moments model — replying with a photo of your own
/// is what unlocks the post you are looking at. It exists here as a declared
/// seam so that feature changes this one field and the composer it selects,
/// rather than rebuilding this screen; it deliberately throws rather than
/// rendering a half-working stub.
enum PostReplyMode { text, photo }

/// The expanded view of a post — photo, reaction count, who's seen it, the
/// "..." menu and the full reply thread. Explicit request: "when clicked on
/// post it shall open full screen... able to see reactions and comments as
/// well", followed by "in profile section in anon thing there shall be
/// three dots and as well the seen pill... shall be actually working... same
/// data as in the anon page".
///
/// Reacting itself still happens on the card, not here — the chip here
/// stays a static (no tap target) COUNT + identity-free face/emoji preview,
/// the same non-identifying summary the feed's own ReactionPreviewChip
/// always showed. That part is deliberate and unchanged: a reactor's
/// identity is never shown for an anonymous post anywhere in the app (see
/// _AnonSnapSection's "Identity-free reactor photos" in anon_feed_screen.dart),
/// so this screen doesn't invent an exception. Seen-by is different — the
/// anon feed already treats VIEWER identity as safe to name (the post being
/// anonymous protects its AUTHOR, not whoever looked at it), so the SeenPill
/// here mirrors that, real names and all, same as every other post's.
/// Seen-by and the "..." menu only ever show for a post you own.
class SinglePostDetailScreen extends StatefulWidget {
  const SinglePostDetailScreen({
    super.key,
    required this.item,
    this.replyMode = PostReplyMode.text,
    this.lockedUntilReply = false,
  });

  final FeedItem item;

  /// See [PostReplyMode]. Defaults to the ordinary comment thread.
  final PostReplyMode replyMode;

  /// Moments only: hide the photo until the viewer has replied. Declared for
  /// the parked photo-reply model; not implemented yet.
  final bool lockedUntilReply;

  @override
  State<SinglePostDetailScreen> createState() => _SinglePostDetailScreenState();
}

class _SinglePostDetailScreenState extends State<SinglePostDetailScreen> {
  FeedItem get item => widget.item;

  ReactionSummary _summary = const ReactionSummary.empty();

  /// A group item's postId is the group_posts row id (see how
  /// DesignGroupCard builds GroupCardPost from it) — same either/or every
  /// other reaction call site in this app uses.
  bool get _isGroupPost => item.groupName != null;

  /// Non-null once resolved from `users` — null (never guessed) is what
  /// keeps [_isOwnPost] honestly false until it actually resolves, rather
  /// than flashing the owner-only controls on for a frame.
  String? _myUserId;

  /// `item.userId` is the poster's real id even for an anonymous post
  /// opened from the profile's own Anon tab — that query is filtered to
  /// the caller's own rows, so posts_feed's identity mask never applies to
  /// it (see MyProfileScreen._loadMyAnonPosts's own doc). Someone else's
  /// anonymous post reaches this screen with a null/empty userId instead
  /// (properly masked), which this comparison naturally treats as false.
  bool get _isOwnPost => _myUserId != null && _myUserId == item.userId;

  /// A Duo post belongs to both partners.
  bool get _isMyDuoPost =>
      _myUserId != null && _myUserId == item.partnerUserId;

  /// Who sees the seen pill (2026-10-07): the poster, their Duo partner,
  /// or — on a group post — the group's members. Nobody else. Membership
  /// isn't on the feed item, but group_post_viewers only answers members,
  /// so a non-empty list is itself the proof.
  bool get _canSeeViewers =>
      _isOwnPost || _isMyDuoPost || (_isGroupPost && _viewers.isNotEmpty);

  /// Non-null userId means "render as anonymous" — see FeedItem.anonName's
  /// own doc.
  bool get _isAnonymousPost => item.anonName != null;

  List<PostViewer> _viewers = const [];
  bool _showSeenDropdown = false;

  @override
  void initState() {
    super.initState();
    if (widget.replyMode == PostReplyMode.photo || widget.lockedUntilReply) {
      // Refuse loudly rather than silently falling back to the text thread:
      // a Moments post opened with the wrong composer would look like it
      // worked while quietly discarding the photo-reply rule.
      throw UnimplementedError(
        'PostReplyMode.photo / lockedUntilReply are the parked Moments '
        'photo-reply model and are not implemented yet.',
      );
    }
    _load();
  }

  Future<void> _load() async {
    final postId = _isGroupPost ? null : item.postId;
    final groupPostId = _isGroupPost ? item.postId : null;
    final results = await Future.wait([
      ReactionService.instance.fetchSummary(postId, groupPostId: groupPostId),
      CurrentUserService.instance.resolveId().catchError((_) => ''),
      _isGroupPost
          ? PostService.instance.fetchGroupPostViewers(groupPostId!)
          : PostService.instance.fetchPostViewers(postId!),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = results[0] as ReactionSummary;
      final myId = results[1] as String;
      _myUserId = myId.isEmpty ? null : myId;
      _viewers = results[2] as List<PostViewer>;
    });
  }

  /// The "..." menu — Remove on your own post (a Duo post is both
  /// partners'), Report/Block on someone else's. Group posts route through
  /// their own menu, which removes via remove_group_post.
  Future<void> _openMenu() async {
    final authorId = item.userId.isEmpty ? null : item.userId;
    if (_isGroupPost) {
      await showGroupPostActionsMenu(
        context,
        groupPostId: item.postId,
        authorUsersId: authorId,
        isOwnPost: _isOwnPost,
        onDeleted: () {
          if (mounted) Navigator.of(context).pop();
        },
      );
      return;
    }
    await showPostActionsMenu(
      context,
      postId: item.postId,
      isOwnPost: _isOwnPost || _isMyDuoPost,
      isAnonymousPost: _isAnonymousPost,
      authorUsersId: authorId,
      onDeleted: () {
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
        // Explicit request: "there shall be three dots" — Remove/Report/
        // Block, the same menu every other post surface offers. This
        // screen had a close button and nothing else.
        actions: [
          GestureDetector(
            onTap: _openMenu,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.more_horiz_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      // The reply composer has to ride above the keyboard rather than sit
      // under it — this screen gained a text input when it gained a thread.
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          _buildBlurredBg(),
          // Photo, caption and replies scroll as one column. This used to be
          // a fixed Stack with the footer pinned to the bottom, which had no
          // room for a comment thread of any length.
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 56, bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_buildPhoto(), _buildFooter(), _buildReplies()],
              ),
            ),
          ),
          // Who's seen this — only for the post's owners (see
          // _canSeeViewers), the same SeenPill/SeenDropdown every other
          // post surface uses. Explicit request: "the seen pill... shall be
          // actually working... same data as in the anon page".
          if (_canSeeViewers)
            Positioned(
              top: 60,
              right: 56,
              child: SeenPill(
                viewers: _viewers,
                compact: true,
                onTap: () => setState(() => _showSeenDropdown = !_showSeenDropdown),
              ),
            ),
          if (_canSeeViewers && _showSeenDropdown)
            Positioned(
              top: 100,
              right: 12,
              child: SeenDropdown(viewers: _viewers),
            ),
        ],
      ),
    );
  }

  /// The post's replies. [PostCommentCard] loads and posts them itself
  /// against the real `comments` table (CommentService) — the same thread
  /// DesignSoloCard shows on the card — so this screen only has to hand it
  /// an id and say which table that id belongs to.
  Widget _buildReplies() {
    // A locked private-group post (seen only through a shared community):
    // no composer the server would refuse, just a quiet line.
    if (item.groupPostLocked) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF101012),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_rounded, size: 15, color: Colors.white.withValues(alpha: 0.55)),
            const SizedBox(width: 10),
            Text(
              'Be a friend to comment',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }
    return PostCommentCard(
      postId: _isGroupPost ? null : item.postId,
      groupPostId: _isGroupPost ? item.postId : null,
      isGroup: _isGroupPost,
      reactionCount: _summary.totalEmojiCount,
    );
  }

  Widget _buildBlurredBg() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPhotoWidget(fit: BoxFit.cover),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
      ],
    );
  }

  /// Multi-photo posts kept losing every frame but the cover here: this
  /// screen read photoUrl and ignored item.photos entirely. Route the same
  /// PostPhotoCarousel the cards use when there is more than one.
  Widget _buildPhoto() {
    final photos = resolvePostPhotos(
      photoUrls: item.photos,
      singleUrl: item.photoUrl,
    );

    // A local capture (a post made this session) has no URL yet, so the
    // carousel — which is URL-only — can't render it.
    if (item.photoPath == null && photos.length > 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: PostPhotoCarousel(
          photoUrls: photos,
          aspectRatio: 4 / 5,
          borderRadius: 20,
          showScrim: false,
          // Locked private-group post: first photo clear, the rest blurred.
          blurFromIndex: item.groupPostLocked ? 1 : null,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        // Bounded rather than filling the viewport, so the replies below are
        // always reachable by scrolling rather than starting off-screen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.62,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _buildPhotoWidget(fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildPhotoWidget({required BoxFit fit}) {
    if (item.photoPath != null) {
      return Image.file(File(item.photoPath!), fit: fit);
    }
    if (item.photoUrl != null) {
      return CachedNetworkImage(
              memCacheWidth: 1080,imageUrl: item.photoUrl!, fit: fit);
    }
    final color = _hashColor(item.postId);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Color _hashColor(String id) {
    const colors = [
      Color(0xFF1C2A3C),
      Color(0xFF301A28),
      Color(0xFF1E2C1E),
      Color(0xFF2A1A10),
      Color(0xFF1A203C),
    ];
    return colors[id.hashCode.abs() % colors.length];
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The aggregate count only — no reactor identity, no tap target.
          // See this screen's own class doc.
          if (_summary.totalEmojiCount > 0) ...[
            // Faces as well as the count — see the album viewer's own note.
            ReactionPreviewChip(
              count: _summary.totalEmojiCount + _summary.faceReactions.length,
              faces: _summary.faceReactions,
              emojiCounts: _summary.emojiCounts,
              onTap: () {},
            ),
            const SizedBox(height: 12),
          ],
          if (item.caption != null && item.caption!.isNotEmpty)
            Text(
              item.caption!,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          if (item.musicTitle != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.music_note, color: Colors.white54, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${item.musicTitle}${item.musicArtist != null ? ' · ${item.musicArtist}' : ''}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
