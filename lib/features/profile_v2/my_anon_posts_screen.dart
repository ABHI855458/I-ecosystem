import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../screens/feed/single_post_detail_screen.dart';
import '../../screens/feed/widgets/post_card_shared.dart' show showPostCommentsSheet;
import '../../services/feed_service.dart';
import '../../services/post_service.dart';
import '../../services/reaction_service.dart';
import '../../shared/time_ago.dart';
import 'profile_v2_data.dart' show kFaceSwatches;
import 'profile_v2_tokens.dart';

/// Your own anonymous posts — owner-only (what the profile's old Anon tab
/// showed): open one, see its reactions and comments, delete it. Reached
/// from the "+" chooser's Anon option.
class MyAnonPostsScreen extends StatefulWidget {
  const MyAnonPostsScreen({super.key});

  @override
  State<MyAnonPostsScreen> createState() => _MyAnonPostsScreenState();
}

class _MyAnonPostsScreenState extends State<MyAnonPostsScreen> {
  List<FeedItem>? _posts;
  Map<String, int> _counts = const {};
  Map<String, List<LikeReactor>> _reactors = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await FeedService.instance.fetchMyAnonPosts();
    if (!mounted) return;
    setState(() => _posts = items);
    if (items.isEmpty) return;
    final results = await Future.wait([
      Future.wait(items.map((i) => ReactionService.instance.fetchSummary(i.postId))),
      Future.wait(items.map((i) => ReactionService.instance.fetchRecentReactors(i.postId))),
    ]);
    final summaries = results[0] as List<ReactionSummary>;
    final reactors = results[1] as List<List<LikeReactor>>;
    if (!mounted) return;
    setState(() {
      _counts = {
        for (var i = 0; i < items.length; i++) items[i].postId: summaries[i].totalReactionCount,
      };
      _reactors = {
        for (var i = 0; i < items.length; i++) items[i].postId: reactors[i],
      };
    });
  }

  Future<void> _delete(FeedItem post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text('Delete this post?', style: PV2.body(size: 17, weight: FontWeight.w700)),
        content: Text(
          'It disappears from the anon feed for everyone.',
          style: PV2.body(size: 13.5, color: PV2.inkBio),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: PV2.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final before = _posts;
    setState(() => _posts = [for (final p in _posts ?? const <FeedItem>[]) if (p.postId != post.postId) p]);
    try {
      await PostService.instance.deletePost(post.postId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _posts = before);
      showGlassToast(context, "Couldn't delete that post.", isError: true);
    }
  }

  Future<void> _menu(FeedItem post) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141417),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
              title: Text('Reactions & comments', style: PV2.body(size: 15)),
              onTap: () => Navigator.pop(c, 'comments'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: PV2.danger),
              title: Text('Delete post', style: PV2.body(size: 15, color: PV2.danger)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (pick == 'delete') await _delete(post);
    if (pick == 'comments') _openComments(post);
  }

  void _openComments(FeedItem post) => showPostCommentsSheet(
    context,
    postId: post.postId,
    isGroup: false,
    reactors: _reactors[post.postId] ?? const [],
    reactionCount: _counts[post.postId] ?? 0,
  );

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return Scaffold(
      backgroundColor: PV2.page,
      appBar: AppBar(
        backgroundColor: PV2.page,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Your anon posts', style: PV2.display(size: 19)),
      ),
      body: posts == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: PV2.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(PV2.pad, 4, PV2.pad, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded, size: 15, color: Colors.white),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Only you can see this list. Nobody can tell these posts are yours.',
                            style: PV2.body(size: 11.5, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.66)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'No anonymous posts yet.\nAnswer a prompt in the anon feed to post one.',
                          textAlign: TextAlign.center,
                          style: PV2.body(size: 13, color: PV2.inkByline),
                        ),
                      ),
                    )
                  else
                    for (final p in posts) ...[
                      _row(p),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }

  Widget _row(FeedItem post) {
    final count = _counts[post.postId] ?? 0;
    final reactors = _reactors[post.postId] ?? const <LikeReactor>[];
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SinglePostDetailScreen(item: post)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PV2.raised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PV2.hairlinePanel),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 60,
                height: 75,
                child: post.photoUrl == null
                    ? ColoredBox(color: kFaceSwatches[post.postId.hashCode.abs() % kFaceSwatches.length])
                    : CachedNetworkImage(imageUrl: post.photoUrl!, memCacheWidth: 300, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (post.caption ?? '').trim().isEmpty
                        ? 'Anonymous post'
                        : post.caption!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PV2.body(size: 13.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openComments(post),
                    child: Row(
                      children: [
                        _faces(reactors),
                        if (reactors.isNotEmpty) const SizedBox(width: 6),
                        Text(
                          count == 0 ? 'No reactions yet' : '$count reaction${count == 1 ? '' : 's'} · comments',
                          style: PV2.body(size: 11, weight: FontWeight.w600, color: PV2.inkMember),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(formatRelativeTime(post.createdAt), style: PV2.mono(size: 10, color: PV2.inkStamp)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _menu(post),
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _faces(List<LikeReactor> reactors) {
    final shown = reactors.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    const d = 18.0, step = 12.0;
    return SizedBox(
      width: step * (shown.length - 1) + d,
      height: d,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kFaceSwatches[shown[i].id.hashCode.abs() % kFaceSwatches.length],
                  border: Border.all(color: PV2.raised, width: 1.5),
                ),
                child: ClipOval(
                  child: shown[i].displayPhotoUrl == null
                      ? const SizedBox.shrink()
                      : CachedNetworkImage(imageUrl: shown[i].displayPhotoUrl!, memCacheWidth: 96, fit: BoxFit.cover),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
