import 'package:flutter/material.dart';

import '../../screens/feed/memory_detail_screen.dart';
import '../../screens/feed/single_post_detail_screen.dart';
import '../../screens/feed/widgets/design_solo_card.dart';
import '../../screens/feed/widgets/everyone_post_card.dart';
import '../../screens/feed/widgets/memory_feed_card.dart';
import '../../services/feed_service.dart';
import 'profile_v2_tokens.dart';

// ---------------------------------------------------------------------------
// PostsList — the profile's Posts tab.
//
// Replaces PostsGrid, which rendered PV2Data.posts: six hardcoded colour
// swatches carrying no post id and no photo. Nothing could be done TO one of
// those tiles — no delete, no reaction, no tap-through — because there was
// no post behind it.
//
// This renders the SAME cards the feed renders, full width, so a post looks
// and behaves identically wherever it is seen. The comment thread arrives
// with DesignSoloCard rather than being rebuilt here. A card cannot fit in
// PostsGrid's 3-column ~128x160 tile, which is why the grid had to go
// rather than gain buttons.
//
// Item #1 — showReactionsViewer/showActionRail (forwarded to both cards
// below) let the two profile surfaces diverge from the feed and from each
// other: MyProfileScreen passes viewer:true/rail:false (author-only
// "Reactions", no Ping/RealMoji on your own posts); TheirProfileScreen
// passes the defaults (no viewer, Ping/RealMoji kept, same as the feed).
// ---------------------------------------------------------------------------

/// Opens the full view of [item] — photo plus its replies. The memory fork
/// mirrors the feed's own `_openDetail` (everyone_feed_screen.dart), so a
/// post opens the same screen whether it was tapped on a profile or in the
/// feed.
Future<void> openPostDetail(BuildContext context, FeedItem item) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => item.type == 'memory'
          ? MemoryDetailScreen(item: item)
          : SinglePostDetailScreen(item: item),
    ),
  );
}

class PostsList extends StatelessWidget {
  const PostsList({
    super.key,
    required this.items,
    this.leading,
    this.overlayBuilder,
    this.emptyLabel = 'No posts yet.',
    this.displayName,
    this.avatarUrl,
    this.showReactionsViewer = false,
    this.showActionRail = true,
  });

  final List<FeedItem> items;

  /// The profile owner's real name — only a FALLBACK now, for a post whose
  /// author row didn't resolve. Each post's own author (item.username, set
  /// by FeedService._attachAuthors) wins: on a Duo post where the owner is
  /// the PARTNER, forcing the owner's name into the author slot showed
  /// "shreyasgalag & shreyasgalag" with the same photo twice. Needed because
  /// fetchUserPosts does not join `users` (no confirmed PostgREST embed —
  /// see FeedItem.avatarUrl's own note), so a card would otherwise show the
  /// owner of the very profile you are standing on as "someone" when the
  /// author lookup comes back empty.
  final String? displayName;

  /// Same, for the owner's profile photo.
  final String? avatarUrl;

  /// Item #1 — true only on the profile owner's OWN posts (MyProfileScreen):
  /// shows the author-only "Reactions" viewer below each post instead of
  /// the removed public pill/dropdown.
  final bool showReactionsViewer;

  /// Item #1 — Ping/RealMoji. False on your own profile (reacting to your
  /// own post is meaningless there), true everywhere else including
  /// TheirProfileScreen.
  final bool showActionRail;

  /// Prepended above the first card — the self profile's "add post"
  /// affordance. Absent on someone else's profile, where you cannot post.
  final Widget? leading;

  /// Per-post chrome laid over the card — the self profile's options button
  /// and its delete menu. Keyed by post id, not index, because an optimistic
  /// delete shifts every index after it.
  final Widget Function(FeedItem item)? overlayBuilder;

  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(height: 10),
        ],
        if (items.isEmpty && leading == null)
          _empty()
        else
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _post(context, items[i]),
          ],
      ],
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26),
      alignment: Alignment.center,
      child: Text(
        emptyLabel,
        style: PV2.body(
          size: 12,
          weight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _post(BuildContext context, FeedItem item) {
    // The overlay sits OUTSIDE any clip, same reason PostsGrid layered its
    // own: the options menu is wider than the card's corner and clipping
    // would cut the panel in half.
    final card = _card(context, item);
    if (overlayBuilder == null) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [card, overlayBuilder!(item)],
    );
  }

  /// Mirrors the feed's own card fork (everyone_feed_screen.dart) so the two
  /// surfaces cannot drift on how a post is rendered.
  ///
  /// The tap comes from a plain GestureDetector here, NOT from SpotlightCard,
  /// which is what supplies it in the feed: SpotlightCard also binds
  /// double-tap-to-react and long-press-to-pick, and those are feed
  /// behaviours — reacting on a profile happens through the card's own
  /// RealMoji button, deliberately.
  Widget _card(BuildContext context, FeedItem item) {
    final Widget card = item.type != 'memory'
        ? DesignSoloCard(
            postId: item.postId,
            username: item.username ?? displayName ?? 'someone',
            userId: item.userId,
            avatarUrl: item.avatarUrl ?? avatarUrl,
            // Shared (Duo) post — DesignSoloCard draws the fused
            // "username & partnerName" header only when these are set.
            // fetchUserPosts/fetchProfilePostsForViewer both already
            // resolve them onto `item` (via _attachAuthors); this card
            // just never forwarded them, so a Us-album post on a profile
            // rendered as if it had one author. Reported as "both the
            // users name isn't visible... in us album in profile".
            partnerUserId: item.partnerUserId,
            partnerName: item.partnerName,
            partnerAvatarUrl: item.partnerAvatarUrl,
            // The blue-flame streak overlay on the fused avatar — the feed's
            // own card (everyone_feed_screen.dart) already forwards this;
            // this one didn't, so a Duo post lost its streak the moment
            // it was viewed from a profile instead of the feed.
            pairStreak: item.pairStreak,
            caption: item.caption,
            photoUrl: item.photoUrl,
            photoUrls: item.photos,
            commentCount: item.commentCount,
            onCommentTap: () => openPostDetail(context, item),
            showReactionsViewer: showReactionsViewer,
            showActionRail: showActionRail,
            // A post on a PROFILE (own or someone else's) shows who has
            // SEEN it, all-time — not who is live-present, which is a
            // feed-only concept.
            viewerSeen: true,
            secondaryPhotoUrl: item.secondaryPhotoUrl,
            insetOnRight: item.insetOnRight,
            photoPath: item.photoPath,
            aspectRatio: item.aspectRatio,
            // MyProfileScreen supplies its own "..." (delete) via
            // overlayBuilder — this card's own inline one would otherwise
            // land right next to it instead of underneath it whenever the
            // header is wider than the plain-author case (a Duo post's
            // fused avatar + two names). See hideOwnOptionsButton's own doc.
            hideOwnOptionsButton: overlayBuilder != null,
          )
        : EveryonePostCard(
            postId: item.postId,
            media: MemoryFeedCard(item: item),
            username: item.username ?? displayName ?? 'someone',
            userId: item.userId,
            avatarUrl: item.avatarUrl ?? avatarUrl,
            caption: item.caption,
            commentCount: item.commentCount,
            onCommentTap: () => openPostDetail(context, item),
            showReactionsViewer: showReactionsViewer,
            showActionRail: showActionRail,
          );

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () => openPostDetail(context, item),
      child: card,
    );
  }
}
