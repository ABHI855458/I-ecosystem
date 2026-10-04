import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/glass.dart' show showGlassToast;
import '../../../screens/feed/widgets/post_photo_carousel.dart';
import '../../../services/community_feed_service.dart';
import '../../../services/community_service.dart';
import '../../../services/current_user_service.dart';
import '../../../main_shell.dart' show kTabBarHeight, kTabBarBottomOffset;
import '../community_composer_screen.dart';
import 'community_join_sheet.dart';
import 'community_message_bar.dart';
import 'community_post_menu.dart';
import 'community_tokens.dart';

// ---------------------------------------------------------------------------
// ANNOUNCEMENTS tab — chip strip of joined communities + manage button,
// PRIORITY (dashboard-authored community_feed_items), THE FEED (member
// community_posts: text/images/PDFs, named or anonymous).
//
// Previously 100% mock (community_models.dart's `priorityNotices`/
// `feedPosts`/`filterChips`). The chip strip used to filter POSTS BY TAG
// within one implied community ("CSE"); it now SWITCHES WHICH COMMUNITY is
// showing, which is the actual product shape — see CommunityScreen, the new
// scope owner that fetches the joined-communities list and the selected
// community's leaderboard, and passes both down here and to the STREAKS tab.
//
// Not carried forward from the mock: per-chip unread-count/dot badges.
// Rendering those honestly needs a priority-item count PER joined
// community, which is an extra fetch per chip — deferred rather than
// half-built (e.g. faked from data already in memory for the selected
// community only).
// ---------------------------------------------------------------------------

class CommunityAnnouncementsTab extends StatefulWidget {
  const CommunityAnnouncementsTab({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.communities,
    required this.onSelectCommunity,
    required this.onCommunitiesChanged,
    this.openJoin,
    this.showJoinInChips = true,
    this.showChips = true,
  });

  /// False when this board is opened as ONE chat from the Community chat
  /// list (community_chat_list.dart) — the list itself is the switcher, so
  /// the community chip strip would just duplicate it.
  final bool showChips;

  /// Bumped by CommunityScreen's header JOIN button (the Join button moves
  /// up there while the Streaks tab is switched off) — opens this tab's own
  /// join popover, which is where the joining logic lives.
  final ValueListenable<int>? openJoin;

  /// False when the header carries the JOIN button instead, so the chip
  /// strip gets its full width back.
  final bool showJoinInChips;

  final String? communityId;
  final String? communityName;
  final List<CommunityOption> communities;
  final ValueChanged<String> onSelectCommunity;
  final VoidCallback onCommunitiesChanged;

  @override
  State<CommunityAnnouncementsTab> createState() => _CommunityAnnouncementsTabState();
}

class _CommunityAnnouncementsTabState extends State<CommunityAnnouncementsTab> {
  bool _joinOpen = false;

  bool _priorityLoading = true;
  String? _priorityError;
  List<CommunityPriorityItem> _priorityItems = const [];

  bool _feedLoading = true;
  String? _feedError;
  List<CommunityPost> _feedPosts = const [];

  String? _myUsersId;
  RealtimeChannel? _postsChannel;

  void _onOpenJoin() {
    if (mounted) setState(() => _joinOpen = true);
  }

  @override
  void initState() {
    super.initState();
    widget.openJoin?.addListener(_onOpenJoin);
    _loadAll();
    CurrentUserService.instance.resolveId().then((id) {
      if (mounted) setState(() => _myUsersId = id);
    }).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant CommunityAnnouncementsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.communityId != widget.communityId) {
      _unsubscribe();
      _loadAll();
    }
  }

  @override
  void dispose() {
    widget.openJoin?.removeListener(_onOpenJoin);
    _unsubscribe();
    super.dispose();
  }

  void _unsubscribe() {
    _postsChannel?.unsubscribe();
    _postsChannel = null;
  }

  Future<void> _loadAll() async {
    final id = widget.communityId;
    if (id == null) {
      setState(() {
        _priorityLoading = false;
        _feedLoading = false;
        _priorityItems = const [];
        _feedPosts = const [];
      });
      return;
    }
    setState(() {
      _priorityLoading = true;
      _feedLoading = true;
      _priorityError = null;
      _feedError = null;
    });
    try {
      final items = await CommunityFeedService.instance.fetchPriorityItems(id);
      if (mounted) {
        setState(() {
          _priorityItems = items;
          _priorityLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _priorityError = "Couldn't load announcements.";
          _priorityLoading = false;
        });
      }
    }
    try {
      final posts = await CommunityFeedService.instance.fetchPosts(id);
      if (mounted) {
        setState(() {
          _feedPosts = posts;
          _feedLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedError = "Couldn't load the feed.";
          _feedLoading = false;
        });
      }
    }
    _subscribe(id);
  }

  void _subscribe(String communityId) {
    _postsChannel = CommunityFeedService.instance.subscribePosts(communityId, (_) {
      // A small per-community list — cheap enough to refetch wholesale on
      // any change rather than hand-rolling a partial insert (which would
      // also need to re-fetch documents/author info anyway).
      CommunityFeedService.instance.fetchPosts(communityId).then((posts) {
        if (mounted) setState(() => _feedPosts = posts);
      }).catchError((_) {});
    });
  }

  /// Someone was blocked from a post's "…": reload so everything of theirs
  /// (anonymous posts included) drops out of the feed immediately.
  Future<void> _onAuthorBlocked() async {
    final id = widget.communityId;
    if (id == null) return;
    final posts = await CommunityFeedService.instance.fetchPosts(id);
    if (mounted) setState(() => _feedPosts = posts);
  }

  /// "+" → My posts: the existing composer screen, opened on its My Posts
  /// view (see and delete what you posted). Refreshes the feed on return in
  /// case something was deleted there.
  Future<void> _openMyPosts() async {
    final id = widget.communityId;
    final name = widget.communityName;
    if (id == null || name == null) return;
    await Navigator.of(context).push<CommunityPost>(
      MaterialPageRoute(
        builder: (_) => CommunityComposerScreen(
          communityId: id,
          communityName: name,
          startInMyPosts: true,
        ),
      ),
    );
    if (!mounted) return;
    final posts = await CommunityFeedService.instance.fetchPosts(id);
    if (mounted) setState(() => _feedPosts = posts);
  }

  Future<void> _vote(String feedItemId, String optionId) async {
    final id = widget.communityId;
    if (id == null) return;
    try {
      await CommunityFeedService.instance.votePoll(feedItemId: feedItemId, optionId: optionId);
      final items = await CommunityFeedService.instance.fetchPriorityItems(id);
      if (mounted) setState(() => _priorityItems = items);
    } catch (_) {
      if (mounted) showGlassToast(context, "Couldn't record your vote — try again.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showChips)
              _ChipScrollerRow(
                communities: widget.communities,
                selectedId: widget.communityId,
                onSelect: widget.onSelectCommunity,
                onManage: () => setState(() => _joinOpen = !_joinOpen),
                showJoin: widget.showJoinInChips,
              ),
            Expanded(
              child: widget.communityId == null
                  ? _NoCommunitySelected(onManage: () => setState(() => _joinOpen = true))
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      child: ListView(
                        // Both Socio tabs stay mounted in CommunityScreen's
                        // IndexedStack; without primary:false they both
                        // attached to the one PrimaryScrollController (iOS),
                        // which is what "unable to scroll in Socio" traced
                        // to. AlwaysScrollable so a short feed still drags
                        // and pull-to-refresh still triggers.
                        primary: false,
                        physics: const AlwaysScrollableScrollPhysics(),
                        // Bottom room for the message box + tab bar.
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 190),
                        children: [
                          _PriorityHeader(count: _priorityItems.length),
                          const SizedBox(height: 11),
                          _buildPrioritySection(),
                          const SizedBox(height: 26),
                          const _FeedHeader(),
                          const SizedBox(height: 11),
                          _buildFeedSection(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
        // WhatsApp-style message box (replaces the old pink "+" button).
        // MainShell shrinks this page above the keyboard and hides the tab
        // bar while typing, so the box sits just above the tab bar normally
        // and at the bottom edge while the keyboard is up.
        if (widget.communityId != null && widget.communityName != null)
          _KeyboardAwareBottom(
            noTabBar: !widget.showChips,
            child: CommunityMessageBar(
              communityId: widget.communityId!,
              communityName: widget.communityName!,
              // The live-update refetch can land before this does and
              // already include the new post, so add it only if missing
              // (it showed twice otherwise).
              onPosted: (post) => setState(() => _feedPosts = [
                    post,
                    ..._feedPosts.where((p) => p.id != post.id),
                  ]),
              onOpenMyPosts: _openMyPosts,
            ),
          ),
        if (_joinOpen)
          CommunityJoinPopover(
            onClose: () => setState(() => _joinOpen = false),
            onChanged: widget.onCommunitiesChanged,
          ),
      ],
    );
  }

  Widget _buildPrioritySection() {
    if (_priorityLoading) return const _SectionSkeleton(count: 1);
    if (_priorityError != null) return _SectionError(message: _priorityError!, onRetry: _loadAll);
    if (_priorityItems.isEmpty) return const _EmptyState(text: 'No priority notices yet.');
    return Column(
      children: [
        for (var i = 0; i < _priorityItems.length; i++) ...[
          _PriorityCard(item: _priorityItems[i], onVote: _vote),
          if (i != _priorityItems.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _buildFeedSection() {
    if (_feedLoading) return const _SectionSkeleton(count: 2);
    if (_feedError != null) return _SectionError(message: _feedError!, onRetry: _loadAll);
    if (_feedPosts.isEmpty) return const _EmptyState(text: 'No posts yet — be the first.');
    return Column(
      children: [
        for (var i = 0; i < _feedPosts.length; i++) ...[
          _FeedPostCard(post: _feedPosts[i], myUsersId: _myUsersId, onBlocked: _onAuthorBlocked),
          if (i != _feedPosts.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

// ── Chip strip ──────────────────────────────────────────────────────────

class _ChipScrollerRow extends StatelessWidget {
  const _ChipScrollerRow({required this.communities, required this.selectedId, required this.onSelect, required this.onManage, this.showJoin = true});
  final List<CommunityOption> communities;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onManage;
  final bool showJoin;

  @override
  Widget build(BuildContext context) {
    // Was `height: 50` with `padding: fromLTRB(18,16,10,12)` — 22px of
    // child space against a 28px chip (6+16+6 padding+count-badge) plus a
    // 4px dot overhang the ListView then clipped. 62/14 gives 36px, enough
    // for the tallest chip content with slack on both sides.
    return SizedBox(
      height: 62,
      child: Row(
        children: [
          Expanded(
            child: communities.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text("You haven't joined a community yet", style: CommunityType.chipInactive),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                    children: [
                      for (final c in communities) ...[
                        _CommunityChip(community: c, active: c.id == selectedId, onTap: () => onSelect(c.id)),
                        const SizedBox(width: 7),
                      ],
                    ],
                  ),
          ),
          if (showJoin)
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 18, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0x000B0B0E), CommunityColors.screenBg], stops: [0, 0.6]),
              ),
              child: CommunityJoinButton(onTap: onManage),
            ),
        ],
      ),
    );
  }
}

class _CommunityChip extends StatelessWidget {
  const _CommunityChip({required this.community, required this.active, required this.onTap});
  final CommunityOption community;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? CommunityColors.textPrimary : null,
          border: active ? null : Border.all(color: CommunityColors.chipBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          community.name.trim(),
          style: active ? CommunityType.chipActive : CommunityType.chipInactive,
        ),
      ),
    );
  }
}

class _NoCommunitySelected extends StatelessWidget {
  const _NoCommunitySelected({required this.onManage});
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Join a community to see its announcements and feed.', textAlign: TextAlign.center, style: CommunityType.pollMeta.copyWith(color: CommunityColors.textSecondary)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onManage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: CommunityColors.pink, borderRadius: BorderRadius.circular(10)),
                child: const Text('Browse communities', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared loading/error/empty scaffolding ────────────────────────────

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          Container(height: 90, decoration: BoxDecoration(color: CommunityColors.cardBg, borderRadius: BorderRadius.circular(13))),
          if (i != count - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text(message, style: CommunityType.pollMeta),
          const SizedBox(height: 6),
          TextButton(onPressed: onRetry, child: Text('Retry', style: CommunityType.pollCta)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(text, style: CommunityType.pollMeta),
    );
  }
}

// ── Section headers ────────────────────────────────────────────────────

class _PriorityHeader extends StatelessWidget {
  const _PriorityHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text('PRIORITY', style: CommunityType.sectionLabel(CommunityColors.pink)),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0x66FA2D64), Color(0x0AFA2D64)]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('$count PINNED', style: CommunityType.sectionMeta),
        ],
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('THE FEED', style: CommunityType.sectionLabel(CommunityColors.textSecondary)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: CommunityColors.cardBorder)),
        const SizedBox(width: 10),
        Text('NEWEST', style: CommunityType.sectionMeta),
      ],
    );
  }
}

// ── Priority (dashboard-authored) cards ────────────────────────────────

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

class _DocumentChipRow extends StatelessWidget {
  const _DocumentChipRow({required this.documents});
  final List<CommunityPostDocument> documents;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final d in documents) _DocumentChip(doc: d)],
      ),
    );
  }
}

class _DocumentChip extends StatelessWidget {
  const _DocumentChip({required this.doc});
  final CommunityPostDocument doc;

  String _sizeLabel(int? bytes) {
    if (bytes == null) return '';
    final kb = bytes / 1024;
    if (kb < 1024) return ' · ${kb.toStringAsFixed(0)} KB';
    return ' · ${(kb / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(doc.fileUrl);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showGlassToast(context, "Couldn't open ${doc.fileName}.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: CommunityColors.cardBg2, border: Border.all(color: CommunityColors.chipBorder), borderRadius: BorderRadius.circular(9)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_rounded, size: 15, color: Color(0xFFE0607F)),
            const SizedBox(width: 6),
            Flexible(child: Text('${doc.fileName}${_sizeLabel(doc.fileSize)}', style: CommunityType.joinRowMeta, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.item, required this.onVote});
  final CommunityPriorityItem item;
  final void Function(String feedItemId, String optionId) onVote;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Container(
        decoration: BoxDecoration(
          color: CommunityColors.priorityCardBg,
          border: Border.all(color: CommunityColors.priorityCardBorder),
          borderRadius: BorderRadius.circular(13),
        ),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        child: Stack(
          children: [
            Positioned(
              left: -14,
              top: -13,
              bottom: -12,
              width: 3,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [CommunityColors.amber, CommunityColors.amberDark]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
                              decoration: BoxDecoration(color: const Color(0x24F5B13D), borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 10, color: CommunityColors.amber),
                                  const SizedBox(width: 3),
                                  Text('PRIORITY', style: CommunityType.priorityBadge),
                                ],
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(child: Text(item.authorName, style: CommunityType.priorityHandle, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                      Text(_relativeTime(item.createdAt), style: CommunityType.priorityTime),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(item.title, style: CommunityType.priorityBody),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.body!, style: CommunityType.postBody),
                  ],
                  if (item.itemType == 'poll' && item.pollOptions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _PriorityPoll(item: item, onVote: onVote),
                  ],
                  _DocumentChipRow(documents: item.documents),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityPoll extends StatelessWidget {
  const _PriorityPoll({required this.item, required this.onVote});
  final CommunityPriorityItem item;
  final void Function(String feedItemId, String optionId) onVote;

  @override
  Widget build(BuildContext context) {
    final options = item.pollOptions;
    final total = options.fold<int>(0, (s, o) => s + o.voteCount);
    final leadCount = options.fold<int>(0, (m, o) => o.voteCount > m ? o.voteCount : m);
    final voted = item.myVoteOptionId != null;

    return Column(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          _PollOptionRow(
            name: options[i].label,
            pct: total == 0 ? 0 : (options[i].voteCount / total * 100).round(),
            isTop: total > 0 && options[i].voteCount == leadCount,
            chosen: item.myVoteOptionId == options[i].id,
            voted: voted,
            onTap: voted ? null : () {
              HapticFeedback.selectionClick();
              onVote(item.id, options[i].id);
            },
          ),
          if (i != options.length - 1) const SizedBox(height: 7),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$total VOTES', style: CommunityType.pollMeta),
            if (!voted) Text('TAP TO VOTE', style: CommunityType.pollCta) else Text('VOTED', style: CommunityType.pollVoted),
          ],
        ),
      ],
    );
  }
}

// ── Feed (member) cards ─────────────────────────────────────────────────

class _PostHeaderRow extends StatelessWidget {
  const _PostHeaderRow({required this.post, required this.myUsersId, this.onBlocked});
  final CommunityPost post;
  final String? myUsersId;
  final VoidCallback? onBlocked;

  @override
  Widget build(BuildContext context) {
    // isMine comes from the server, so an anonymous post (no user_id sent)
    // still reads as mine to its author.
    final isOwn = post.isMine || (myUsersId != null && myUsersId == post.userId);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              _AuthorAvatar(
                photoUrl: post.authorPhotoUrl,
                anonymous: post.isAnonymous,
                name: post.authorName,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(post.authorName, style: CommunityType.postHandle, overflow: TextOverflow.ellipsis)),
              // Own posts are tagged so it's obvious at a glance which ones
              // are yours — manage/delete them from "My Posts" in the "+"
              // composer, not from here (see the "..." note below).
              if (isOwn) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(color: CommunityColors.lime, borderRadius: BorderRadius.circular(4)),
                  child: Text('YOU', style: CommunityType.streakRowYouTag),
                ),
              ],
              const SizedBox(width: 6),
              Text(_relativeTime(post.createdAt), style: CommunityType.postTime),
            ],
          ),
        ),
        // The "..." menu is Report/Block ONLY (see community_post_menu.dart)
        // — neither applies to your own post, so it's simply not shown
        // there rather than opening an empty or Delete-only sheet. Delete
        // for an own post lives in "My Posts" (community_composer_screen
        // .dart), reached via the "+" FAB, not from the feed card itself.
        if (!isOwn)
          // 40x40 tap target around a small glyph — the icon stays visually
          // subtle (this app's house style for a card's overflow trigger,
          // matching MoreMenuDropdown/PV2MenuItem elsewhere) while still
          // meeting a comfortable minimum touch size.
          GestureDetector(
            onTap: () async {
              final blocked = await showCommunityPostMenu(
                context,
                communityPostId: post.id,
                isAnonymousPost: post.isAnonymous,
                authorUsersId: post.isAnonymous ? null : post.userId,
              );
              if (blocked) onBlocked?.call();
            },
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.more_horiz_rounded, size: 18, color: CommunityColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({required this.post, required this.myUsersId, this.onBlocked});
  final CommunityPost post;
  final String? myUsersId;
  final VoidCallback? onBlocked;

  /// Reads like a chat message: who, the text, then what's attached
  /// underneath (photos, then documents).
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: CommunityColors.cardBg, border: Border.all(color: CommunityColors.cardBorder), borderRadius: BorderRadius.circular(13)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PostHeaderRow(post: post, myUsersId: myUsersId, onBlocked: onBlocked),
          if (post.body != null && post.body!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(post.body!, style: CommunityType.postBody),
          ],
          if (post.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: PostPhotoCarousel(photoUrls: post.photoUrls, aspectRatio: 16 / 10, borderRadius: 0, showScrim: false),
            ),
          ],
          _DocumentChipRow(documents: post.documents),
        ],
      ),
    );
  }
}

// ── Poll option row (shared visual, real data) ─────────────────────────

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.name,
    required this.pct,
    required this.isTop,
    required this.chosen,
    required this.voted,
    required this.onTap,
  });

  final String name;
  final int pct;
  final bool isTop;
  final bool chosen;
  final bool voted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fillColor = isTop ? CommunityColors.pollFillLead : CommunityColors.pollFillOther;
    final edgeColor = isTop ? CommunityColors.lime : CommunityColors.pollEdgeOther;
    final textColor = isTop ? const Color(0xFFE4E5EA) : const Color(0xFFA8A9B4);
    final pctColor = isTop ? CommunityColors.lime : CommunityColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: CommunityColors.cardBg2, border: Border.all(color: CommunityColors.pollOptionBorder), borderRadius: BorderRadius.circular(9)),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: CommunityCurves.pollFillDuration,
                    curve: Curves.easeOutCubic,
                    width: voted ? constraints.maxWidth * (pct / 100) : 0,
                    decoration: BoxDecoration(color: fillColor, border: Border(right: BorderSide(color: edgeColor, width: 1.5))),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(name, style: CommunityType.pollOption(textColor), overflow: TextOverflow.ellipsis)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (chosen)
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.5, end: 1),
                          duration: CommunityCurves.voteRingDuration,
                          curve: Curves.easeOutCubic,
                          builder: (context, t, child) => Transform.scale(scale: t, child: child),
                          child: Container(
                            width: 15,
                            height: 15,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(color: CommunityColors.lime, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded, size: 9, color: CommunityColors.screenBg),
                          ),
                        ),
                      if (voted) ...[
                        if (chosen) const SizedBox(width: 6),
                        Text('$pct%', style: CommunityType.pollPct(pctColor)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The poster's picture beside their name. An anonymous post shows the
/// author's ANON avatar (or a mask), never their real photo: the feed
/// already sends only the anon avatar for someone else's anonymous post.
class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.photoUrl, required this.anonymous, required this.name});
  final String? photoUrl;
  final bool anonymous;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: anonymous ? const Color(0x33FA2D64) : CommunityColors.cardBg2,
      alignment: Alignment.center,
      child: anonymous
          ? const Icon(Icons.theater_comedy_rounded, size: 14, color: CommunityColors.pinkHover)
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: CommunityType.postHandle.copyWith(color: CommunityColors.textPrimary),
            ),
    );
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: anonymous ? const Color(0x80FA2D64) : CommunityColors.chipBorder),
      ),
      child: ClipOval(
        child: (photoUrl ?? '').isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 84,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Keeps the message box where it belongs: just above the tab bar normally,
/// and right on top of the keyboard while it's open (MainShell hides the tab
/// bar then). Rebuilds on every keyboard change itself: reading the insets
/// once at build time left the box stranded with a tab-bar-sized gap above
/// the keyboard on iPhone.
class _KeyboardAwareBottom extends StatefulWidget {
  const _KeyboardAwareBottom({required this.child, this.noTabBar = false});
  final Widget child;

  /// Opened as a single chat (the tab bar is hidden) — sit at the bottom
  /// edge instead of above where the bar would be.
  final bool noTabBar;

  @override
  State<_KeyboardAwareBottom> createState() => _KeyboardAwareBottomState();
}

class _KeyboardAwareBottomState extends State<_KeyboardAwareBottom>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = View.of(context).viewInsets.bottom > 0;
    return Positioned(
      left: 12,
      right: 12,
      bottom: keyboardOpen
          ? 8
          : widget.noTabBar
          ? MediaQuery.of(context).padding.bottom + 10
          : kTabBarHeight + kTabBarBottomOffset + 10,
      child: widget.child,
    );
  }
}
