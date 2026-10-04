import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../services/block_service.dart';
import '../../services/comment_service.dart';
import '../../services/post_service.dart';
import '../../services/report_service.dart';
import '../../services/us_album_service.dart';

// ---------------------------------------------------------------------------
// The "..." menu for a `posts` row — Moments included.
//
// A sibling of community_post_menu.dart, which does the same job for
// `community_posts`. Kept separate rather than generalised: the two target
// different tables, different report columns and different delete paths, so
// one menu with a discriminator would be a bigger tangle than two small
// files.
//
// Rows depend on WHOSE post it is:
//   your own       -> Remove (soft delete, deleted_at)
//   someone else's -> Report, and Block unless the post is anonymous
//
// Block is hidden on an anonymous post on purpose, for the same reason the
// community menu hides it: blocking an anonymous author would let the
// blocker learn "these two anonymous posts share an author" by diffing the
// feed before and after. Don't add it without re-reading that policy.
// ---------------------------------------------------------------------------

enum _Action { report, block, delete }

const _reportReasons = ['Spam', 'Harassment', 'NSFW', 'Misinformation', 'Other'];

const _bg = Color(0xFF16151A);
const _border = Color(0x1FFFFFFF);
const _card = Color(0xFF201F26);
const _text = Color(0xFFF2F2F4);
const _muted = Color(0xFF9A9AA5);
const _danger = Color(0xFFE0607F);

/// Opens the menu and performs whatever was chosen.
///
/// [onDeleted] fires only after the delete actually succeeded, so a caller
/// can pop or refresh without assuming it worked.
Future<void> showPostActionsMenu(
  BuildContext context, {
  required String postId,
  required bool isOwnPost,
  bool isAnonymousPost = false,
  String? authorUsersId,
  VoidCallback? onDeleted,
  String title = 'THIS POST',
}) async {
  final action = await showModalBottomSheet<_Action>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MenuSheet(
      isOwnPost: isOwnPost,
      canBlock: !isAnonymousPost && authorUsersId != null,
      title: title,
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _Action.report:
      await _showReportReasons(context, postId: postId);
    case _Action.block:
      if (authorUsersId != null) {
        await _confirmBlock(context, authorUsersId: authorUsersId);
      }
    case _Action.delete:
      await _confirmDelete(context, postId: postId, onDeleted: onDeleted);
  }
}

/// The same menu for a `group_posts` row (the Friends feed's collage cards).
///
/// No Remove, even on your own: `group_posts` has no `deleted_at` column and
/// no moderator UPDATE policy, so nothing here could actually take one down —
/// and a Remove that silently does nothing is worse than no Remove. Report
/// and Block both work.
Future<void> showGroupPostActionsMenu(
  BuildContext context, {
  required String groupPostId,
  String? authorUsersId,
}) async {
  final action = await showModalBottomSheet<_Action>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MenuSheet(
      isOwnPost: false,
      canBlock: authorUsersId != null,
      title: 'THIS GROUP POST',
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _Action.report:
      await _showReportReasons(context, groupPostId: groupPostId);
    case _Action.block:
      if (authorUsersId != null) {
        await _confirmBlock(context, authorUsersId: authorUsersId);
      }
    case _Action.delete:
      break; // unreachable: isOwnPost is false, so no Remove row is drawn
  }
}

/// The menu for one photo inside a Duo.
///
/// Remove is offered to EITHER member (us_album_photos_delete_member), since
/// a Duo is jointly owned — a photo of the two of you should not be
/// removable only by whoever happened to upload it. Report and Block appear
/// alongside it on someone else's photo rather than instead of it.
Future<void> showAlbumPhotoActionsMenu(
  BuildContext context, {
  required String photoId,
  required bool isMine,
  String? uploaderUsersId,
  VoidCallback? onDeleted,
}) async {
  final action = await showModalBottomSheet<_Action>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MenuSheet(
      isOwnPost: isMine,
      // Either member can remove — the album is jointly owned, and this
      // viewer is only reachable from an album you are a party to.
      canRemove: true,
      canBlock: !isMine && uploaderUsersId != null,
      title: 'THIS PHOTO',
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _Action.report:
      await _showReportReasons(context, duoPhotoId: photoId);
    case _Action.block:
      if (uploaderUsersId != null) {
        await _confirmBlock(context, authorUsersId: uploaderUsersId);
      }
    case _Action.delete:
      final confirmed = await _confirm(
        context,
        title: 'Remove this photo?',
        body: 'It comes out of the album for both of you, and for anyone who '
            'could see it. This cannot be undone.',
        confirmLabel: 'Remove',
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await DuoService.instance.deletePhoto(photoId);
        if (context.mounted) showGlassToast(context, 'Photo removed.');
        onDeleted?.call();
      } catch (_) {
        if (context.mounted) {
          showGlassToast(context, "Couldn't remove that — try again.",
              isError: true);
        }
      }
  }
}

/// The "..." menu for one COMMENT, on any surface that shows comments —
/// friends feed, anonymous feed, group feed and group profile, Duo.
///
/// Remove is offered to two people: whoever wrote the comment, and whoever
/// owns the post it sits under ("give option for the commentor to remove the
/// comment, and as well for the poster to remove the comment"). [canRemove]
/// is that combined test, resolved by the caller — the server re-checks it
/// in `delete_comment` regardless, so a stale true here is refused rather
/// than honoured.
///
/// Report/Block are deliberately NOT offered on an anonymous comment
/// ([isAnonymous]): Block needs a real identity to act on, and the anon
/// thread is the one place the app must not hand one out.
Future<void> showCommentActionsMenu(
  BuildContext context, {
  required String commentId,
  required bool isMine,
  required bool canRemove,
  bool isAnonymous = false,
  String? authorUsersId,
  VoidCallback? onDeleted,
}) async {
  final action = await showModalBottomSheet<_Action>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MenuSheet(
      isOwnPost: isMine,
      canRemove: canRemove,
      canBlock: !isMine && !isAnonymous && authorUsersId != null,
      title: 'THIS COMMENT',
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _Action.report:
      await _showReportReasons(context, commentId: commentId);
    case _Action.block:
      if (authorUsersId != null) {
        await _confirmBlock(context, authorUsersId: authorUsersId);
      }
    case _Action.delete:
      final confirmed = await _confirm(
        context,
        title: 'Remove this comment?',
        body: isMine
            ? 'It comes off the post for everyone. This cannot be undone.'
            : "It comes off your post for everyone, including the person who "
                  'wrote it. This cannot be undone.',
        confirmLabel: 'Remove',
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await CommentService.instance.deleteComment(commentId);
        if (context.mounted) showGlassToast(context, 'Comment removed.');
        onDeleted?.call();
      } catch (_) {
        if (context.mounted) {
          showGlassToast(
            context,
            "Couldn't remove that — try again.",
            isError: true,
          );
        }
      }
  }
}

class _MenuSheet extends StatelessWidget {
  const _MenuSheet({
    required this.isOwnPost,
    required this.canBlock,
    required this.title,
    this.canRemove,
  });

  final bool isOwnPost;
  final bool canBlock;
  final String title;

  /// Overrides the usual "Remove only on your own" rule. A Duo photo
  /// can be removed by EITHER member, so a co-owner needs Remove AND Report
  /// on the same sheet — the two are not mutually exclusive there the way
  /// they are on a post.
  final bool? canRemove;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          decoration: BoxDecoration(
            color: _bg,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _eyebrow),
              const SizedBox(height: 12),
              if (canRemove ?? isOwnPost) ...[
                _Row(
                  icon: Icons.delete_outline_rounded,
                  iconColor: _danger,
                  title: 'Remove',
                  subtitle: 'Takes it down for everyone. Cannot be undone.',
                  onTap: () => Navigator.pop(context, _Action.delete),
                ),
                if (!isOwnPost) const SizedBox(height: 8),
              ],
              if (!isOwnPost) ...[
                _Row(
                  icon: Icons.outlined_flag_rounded,
                  iconColor: _danger,
                  title: 'Report content',
                  subtitle: 'Reviewed by campus moderators.',
                  onTap: () => Navigator.pop(context, _Action.report),
                ),
                if (canBlock) ...[
                  const SizedBox(height: 8),
                  _Row(
                    icon: Icons.block_rounded,
                    iconColor: _muted,
                    title: 'Block this person',
                    subtitle: "You won't see their posts again.",
                    onTap: () => Navigator.pop(context, _Action.block),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _text,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle get _eyebrow => GoogleFonts.jetBrainsMono(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.12 * 10.5,
      color: _muted,
    );

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

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
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _card,
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
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11.5, color: _muted),
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

Future<void> _showReportReasons(
  BuildContext context, {
  String? postId,
  String? groupPostId,
  String? duoPhotoId,
  String? commentId,
}) async {
  assert(
    [postId, groupPostId, duoPhotoId, commentId]
            .where((t) => t != null)
            .length ==
        1,
    'exactly one report target',
  );
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
            color: _bg,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WHY ARE YOU REPORTING THIS?', style: _eyebrow),
              const SizedBox(height: 12),
              for (final r in _reportReasons) ...[
                GestureDetector(
                  onTap: () => Navigator.pop(context, r),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      r,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _text,
                      ),
                    ),
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
    if (commentId != null) {
      await ReportService.instance.reportComment(commentId, reason: reason);
    } else if (groupPostId != null) {
      await ReportService.instance.reportGroupPost(groupPostId, reason: reason);
    } else if (duoPhotoId != null) {
      await ReportService.instance
          .reportDuoPhoto(duoPhotoId, reason: reason);
    } else {
      await ReportService.instance.reportPost(postId!, reason: reason);
    }
    if (context.mounted) {
      showGlassToast(context, 'Reported — thanks for letting us know.');
    }
  } on AlreadyReportedException {
    if (context.mounted) showGlassToast(context, 'You already reported this.');
  } catch (_) {
    if (context.mounted) {
      showGlassToast(context, "Couldn't report — try again.", isError: true);
    }
  }
}

Future<void> _confirmDelete(
  BuildContext context, {
  required String postId,
  VoidCallback? onDeleted,
}) async {
  final confirmed = await _confirm(
    context,
    title: 'Remove this post?',
    body: 'It comes down for everyone, including anyone who already replied '
        'to it. This cannot be undone.',
    confirmLabel: 'Remove',
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await PostService.instance.deletePost(postId);
    if (context.mounted) showGlassToast(context, 'Post removed.');
    onDeleted?.call();
  } catch (_) {
    if (context.mounted) {
      showGlassToast(context, "Couldn't remove that — try again.", isError: true);
    }
  }
}

Future<void> _confirmBlock(
  BuildContext context, {
  required String authorUsersId,
}) async {
  final confirmed = await _confirm(
    context,
    title: 'Block this person?',
    body: "You won't see their posts, and they won't see yours.",
    confirmLabel: 'Block',
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await BlockService.instance.block(authorUsersId);
    if (context.mounted) showGlassToast(context, 'Blocked.');
  } catch (_) {
    if (context.mounted) {
      showGlassToast(context, "Couldn't block — try again.", isError: true);
    }
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: _text,
        ),
      ),
      content: Text(
        body,
        style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: _muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('Cancel', style: GoogleFonts.inter(color: _muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.inter(
              color: _danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
