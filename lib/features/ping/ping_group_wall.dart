import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ping_feed_models.dart';
import 'ping_feed_rows.dart' show DottedBorderBox;
import 'ping_hold_reveal.dart';
import 'ping_visual_kit.dart';
import '../profile_v2/profile_v2_icons.dart';
import '../profile_v2/profile_v2_tokens.dart';

// ---------------------------------------------------------------------------
// GROUP WALL — replaces the Replies-row pattern for group pings entirely
// (design doc, "Additional Features" → "Group pings"). One shared moment
// with multiple unfolding parts (a mosaic of member tiles), not N separate
// reply rows. Each group [PingFeedEntry] (origin == group, bucket ==
// toReply, with [PingFeedEntry.groupMembers] populated) gets its own card.
// ---------------------------------------------------------------------------

class GroupWallCard extends StatelessWidget {
  const GroupWallCard({
    super.key,
    required this.entry,
    required this.onMemberRevealed,
    required this.onExpandToReply,
  });

  final PingFeedEntry entry;
  final void Function(GroupMember member) onMemberRevealed;

  /// Tapping the header while the wall is locked opens the same
  /// hold-free photo-reply flow To-Reply rows use (PingExpandedCard) — the
  /// only way to unlock everyone else's answers is to send your own.
  final VoidCallback onExpandToReply;

  @override
  Widget build(BuildContext context) {
    final members = entry.groupMembers ?? const [];
    final answered = members
        .where((m) => m.state != GroupMemberState.hasntAnswered)
        .length;
    final opened = members
        .where((m) => m.state == GroupMemberState.answeredOpened)
        .length;
    final unlocked = entry.wallUnlocked;

    return Container(
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: pingR4(28, 12, 30, 16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        color: const Color(
          0xFF131317,
        ), // surface1 — solid, no blur, no gradient
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'GROUP WALL',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.18 * 11,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              if (entry.groupStreak > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0B0D),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Blue vector flame — see ping_page.dart's own note.
                      PV2Icons.iceFlame(8),
                      const SizedBox(width: 2),
                      Text(
                        '${entry.groupStreak}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8,
                          color: PV2.streakBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            entry.groupName ?? entry.displayName,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unlocked
                ? '$answered of ${members.length} answered · $opened opened'
                : '$answered answered · reply to unlock',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.30),
            ),
          ),
          if (!unlocked) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onExpandToReply,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: pingCtaGradient,
                ),
                child: Text(
                  'Reply to unlock the wall',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0B0B0D),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: members.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, i) => _MemberTile(
              member: members[i],
              unlocked: unlocked,
              onRevealed: () => onMemberRevealed(members[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.unlocked,
    required this.onRevealed,
  });
  final GroupMember member;

  /// Wall-level reciprocity gate (entry.wallUnlocked) — while false, every
  /// answered member (regardless of their own [GroupMemberState]) renders
  /// as the locked/blurred treatment below, not their real state.
  final bool unlocked;
  final VoidCallback onRevealed;

  @override
  Widget build(BuildContext context) {
    if (member.state == GroupMemberState.hasntAnswered) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: DottedBorderBox(
          square: true,
          color: Colors.white.withValues(alpha: 0.16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.name,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "hasn't answered",
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8.5,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Answered but the wall is still locked — blurred hatch + neutral "reply
    // to unlock" caption, not interactive, regardless of the member's own
    // opened/unopened state underneath.
    if (!unlocked) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            HatchedPhoto(tint: member.avatarColor, radius: 0),
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: Container(color: Colors.transparent),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    member.name,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'reply to\nunlock',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8.5,
                      height: 1.3,
                      color: Colors.white.withValues(alpha: 0.40),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    switch (member.state) {
      case GroupMemberState.hasntAnswered:
        return const SizedBox.shrink(); // handled above

      case GroupMemberState.answeredOpened:
        return HatchedPhoto(
          tint: member.avatarColor,
          radius: 14,
          child: Stack(
            children: [
              Positioned(
                top: 9,
                left: 9,
                child: Container(
                  width: 30,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                    gradient: pingAvatarGradient(member.avatarColor),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      member.name,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (member.replyText != null)
                      Text(
                        member.replyText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case GroupMemberState.answeredUnopened:
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: HoldToRevealBlur(
            revealed: false,
            onRevealed: onRevealed,
            ringSize: 36,
            dotOpacity: 0.75,
            child: HatchedPhoto(
              tint: member.avatarColor,
              radius: 0,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    member.name,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }
}
