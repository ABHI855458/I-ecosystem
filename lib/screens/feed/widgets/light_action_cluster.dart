import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants.dart';

// ---------------------------------------------------------------------------
// LightActionCluster — heart / comment / send / smiley on a white pill, with
// an optional trailing widget (avatars) and an optional relative-time label
// left-aligned under the heart. Matches design-refs/Screenshot 2026-07-29 at
// 10.36.26 AM.png: only the heart fills/colors on like, everything else
// stays a gray outline, icons sit close together (not the old 16px gap).
// ---------------------------------------------------------------------------

const Color kClusterGray = Color(0xFF8E8E93);
const double kClusterIconSize = 17;
const double kClusterGap = 8;

class LightActionCluster extends StatelessWidget {
  const LightActionCluster({
    super.key,
    required this.liked,
    required this.likeCount,
    required this.onHeartTap,
    this.onHeartLongPress,
    this.heartLoading = false,
    this.commentCount = 0,
    this.onCommentTap,
    required this.onSendTap,
    required this.onSmileyTap,
    this.onSmileyLongPress,
    this.trailing,
    this.timeLabel,
  });

  final bool liked;
  final int likeCount;
  final VoidCallback onHeartTap;
  final VoidCallback? onHeartLongPress;
  final bool heartLoading;

  final int commentCount;
  final VoidCallback? onCommentTap;

  final VoidCallback onSendTap;

  final VoidCallback onSmileyTap;
  final VoidCallback? onSmileyLongPress;

  /// Rendered after the smiley icon — typically an avatar stack.
  final Widget? trailing;

  /// Already-formatted relative time (e.g. "12h ago"); omitted when null/empty.
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final label = timeLabel ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeartTapTarget(
                liked: liked,
                count: likeCount,
                loading: heartLoading,
                onTap: onHeartTap,
                onLongPress: onHeartLongPress,
              ),
              const SizedBox(width: kClusterGap),
              _IconWithCount(
                icon: Icons.mode_comment_outlined,
                count: commentCount,
                onTap: onCommentTap,
              ),
              const SizedBox(width: kClusterGap),
              _PlainIconButton(icon: Icons.send_outlined, onTap: onSendTap),
              const SizedBox(width: kClusterGap),
              _PlainIconButton(
                icon: Icons.tag_faces_outlined,
                onTap: onSmileyTap,
                onLongPress: onSmileyLongPress,
              ),
              if (trailing != null) ...[
                const SizedBox(width: kClusterGap),
                trailing!,
              ],
            ],
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: kClusterGray,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeartTapTarget extends StatelessWidget {
  const _HeartTapTarget({
    required this.liked,
    required this.count,
    required this.loading,
    required this.onTap,
    required this.onLongPress,
  });

  final bool liked;
  final int count;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: loading
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: kClusterGray),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: kClusterIconSize,
                  color: liked ? AppColors.errorRed : kClusterGray,
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: liked ? AppColors.errorRed : kClusterGray,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _IconWithCount extends StatelessWidget {
  const _IconWithCount({required this.icon, required this.count, required this.onTap});
  final IconData icon;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: kClusterIconSize, color: kClusterGray),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kClusterGray,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlainIconButton extends StatelessWidget {
  const _PlainIconButton({required this.icon, required this.onTap, this.onLongPress});
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Icon(icon, size: kClusterIconSize, color: kClusterGray),
    );
  }
}
