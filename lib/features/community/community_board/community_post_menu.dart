import 'package:flutter/material.dart';

import '../../../core/glass.dart' show showGlassToast;
import '../../../services/block_service.dart';
import '../../../services/community_feed_service.dart';
import '../../../services/report_service.dart';
import 'community_tokens.dart';

// ---------------------------------------------------------------------------
// The "..." menu on a community feed post card — Report / Block ONLY.
// Deleting your own post moved out of this menu entirely: it now lives in
// the "My Posts" view reached from the composer's own header toggle (see
// community_composer_screen.dart), via [confirmDeleteCommunityPost] below,
// which this file still owns since both places need the identical confirm
// dialog + delete call.
//
// This menu is therefore never shown on your own post at all — the caller
// (_PostHeaderRow in community_announcements_tab.dart) hides the "..."
// trigger when isOwnPost, since Report/Block on yourself makes no sense.
//
// Row set depends on anonymity:
//   named post     -> Report, Block
//   anonymous post -> Report only. Block is hidden on purpose: blocking an
//     anonymous author would let the blocker learn "these two anonymous
//     posts share an author" by diffing before/after — the exact identity
//     leak community_posts_block_filter's `is_anonymous OR` carve-out
//     (20260904000000_community_posts.sql) exists to prevent. Don't add a
//     Block row here without re-reading that policy first.
//
// Styling follows anon_feed_screen.dart's _AnonMenuSheet (eyebrow label,
// rows with a subtitle, full-width Cancel pill) — the best-looking existing
// Report/Block pattern in this app — reskinned onto CommunityColors/
// CommunityType for visual consistency with the rest of this screen.
// ---------------------------------------------------------------------------

/// Report or block from a post's "…". Returns true when the author was
/// blocked, so the caller can drop their posts from the feed right away.
Future<bool> showCommunityPostMenu(
  BuildContext context, {
  required String communityPostId,
  required bool isAnonymousPost,
  String? authorUsersId,
}) async {
  final action = await showModalBottomSheet<_MenuAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PostMenuSheet(isAnonymousPost: isAnonymousPost),
  );
  if (action == null || !context.mounted) return false;

  switch (action) {
    case _MenuAction.report:
      await _showReportReasons(context, communityPostId: communityPostId);
      return false;
    case _MenuAction.block:
      return _confirmBlock(
        context,
        communityPostId: communityPostId,
        isAnonymousPost: isAnonymousPost,
      );
  }
}

enum _MenuAction { report, block }

class _PostMenuSheet extends StatelessWidget {
  const _PostMenuSheet({required this.isAnonymousPost});
  final bool isAnonymousPost;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          decoration: BoxDecoration(
            color: CommunityColors.popoverBg,
            border: Border.all(color: CommunityColors.popoverBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('THIS POST', style: CommunityType.popoverTitle),
              const SizedBox(height: 12),
              _MenuRow(
                icon: Icons.outlined_flag_rounded,
                iconColor: const Color(0xFFE0607F),
                title: 'Report content',
                subtitle: 'Reviewed by campus moderators.',
                onTap: () => Navigator.pop(context, _MenuAction.report),
              ),
              // Offered on anonymous posts too: the block happens server-side
              // by post, so you never learn who the anonymous poster is.
              const SizedBox(height: 8),
              _MenuRow(
                icon: Icons.block_rounded,
                iconColor: CommunityColors.textSecondary,
                title: isAnonymousPost ? 'Block this anonymous poster' : 'Block this person',
                subtitle: isAnonymousPost
                    ? "You won't see them again. Their identity stays hidden."
                    : "You won't see their posts again.",
                onTap: () => Navigator.pop(context, _MenuAction.block),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CommunityColors.cardBg2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text('Cancel', style: CommunityType.joinRowName.copyWith(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: CommunityColors.cardBg2,
          border: Border.all(color: CommunityColors.chipBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: CommunityType.joinRowName.copyWith(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: CommunityType.joinRowMeta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared delete-confirm + delete call for one of the caller's own
/// community posts. Used by the "My Posts" view (community_composer_screen
/// .dart) — the only place a delete action is offered now that the feed's
/// "..." menu is report/block-only. Returns true if the post was deleted
/// (so the caller can remove it from its own list), false otherwise.
Future<bool> confirmDeleteCommunityPost(
  BuildContext context, {
  required String communityPostId,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF16151A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Delete this post?', style: CommunityType.cardTitle),
      content: Text('This removes it for everyone in the community.', style: CommunityType.pollMeta.copyWith(color: CommunityColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete', style: TextStyle(color: Color(0xFFE0607F))),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await CommunityFeedService.instance.deletePost(communityPostId);
    return true;
  } catch (_) {
    if (context.mounted) showGlassToast(context, "Couldn't delete — try again.", isError: true);
    return false;
  }
}

const _reportReasons = ['Spam', 'Harassment', 'NSFW', 'Misinformation', 'Other'];

Future<void> _showReportReasons(BuildContext context, {required String communityPostId}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          decoration: BoxDecoration(
            color: CommunityColors.popoverBg,
            border: Border.all(color: CommunityColors.popoverBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WHY ARE YOU REPORTING THIS?', style: CommunityType.popoverTitle),
              const SizedBox(height: 12),
              for (final r in _reportReasons) ...[
                GestureDetector(
                  onTap: () => Navigator.pop(context, r),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                    decoration: BoxDecoration(color: CommunityColors.cardBg2, borderRadius: BorderRadius.circular(12)),
                    child: Text(r, style: CommunityType.joinRowName.copyWith(fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  if (reason == null || !context.mounted) return;

  try {
    await ReportService.instance.reportCommunityPost(communityPostId, reason: reason);
    if (context.mounted) showGlassToast(context, 'Reported — thanks for letting us know.');
  } on AlreadyReportedException {
    if (context.mounted) showGlassToast(context, 'You already reported this.');
  } catch (_) {
    if (context.mounted) showGlassToast(context, "Couldn't report — try again.", isError: true);
  }
}

/// Blocks the post's author by POST id (block_community_post_author), so it
/// works for an anonymous post too without the app ever learning who wrote it.
Future<bool> _confirmBlock(
  BuildContext context, {
  required String communityPostId,
  required bool isAnonymousPost,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF16151A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isAnonymousPost ? 'Block this anonymous poster?' : 'Block this person?',
        style: CommunityType.cardTitle,
      ),
      content: Text(
        isAnonymousPost
            ? "You won't see anything from them again, and they won't see yours. "
                  "You still won't find out who they are, and they aren't told."
            : "They won't be able to see your posts or profile, and you won't see theirs.",
        style: CommunityType.pollMeta.copyWith(color: CommunityColors.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Block', style: TextStyle(color: Color(0xFFE0607F))),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await BlockService.instance.blockCommunityPostAuthor(communityPostId);
    if (context.mounted) showGlassToast(context, 'Blocked.');
    return true;
  } catch (_) {
    if (context.mounted) showGlassToast(context, "Couldn't block — try again.", isError: true);
    return false;
  }
}
