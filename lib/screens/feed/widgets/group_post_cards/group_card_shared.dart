import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants.dart';
import '../../../../features/groups/design_preview/widgets/avatar.dart';

// ---------------------------------------------------------------------------
// Real data model for the 4 group-post collage cards (Float/Mosaic/Stack/
// Strip) — see group_post_card.dart for how this gets loaded from
// GroupService. No fabricated fields: no streak/fire count, no location,
// no comment/reaction data, since group_posts has no schema backing any of
// those (see design_handoff_group_post_cards/README.md's spec vs. what's
// actually real — this app drops what isn't).
// ---------------------------------------------------------------------------

class GroupCardMember {
  const GroupCardMember({required this.id, required this.name, this.avatarUrl});
  final String id;
  final String name;
  final String? avatarUrl;
}

class GroupCardPost {
  const GroupCardPost({
    required this.id,
    required this.photoUrl,
    required this.userId,
    this.caption,
    this.createdAt,
  });
  final String id;
  final String photoUrl;
  final String userId;
  final String? caption;
  final DateTime? createdAt;
}

class GroupCardData {
  const GroupCardData({
    required this.groupId,
    required this.groupName,
    required this.members,
    required this.posts,
    required this.mainPhotoUrl,
    this.mainCaption,
    this.mainCreatedAt,
  });

  final String groupId;
  final String groupName;

  /// Real group_members roster (any role), admins-first per
  /// GroupService.fetchMembers's own ordering.
  final List<GroupCardMember> members;

  /// Real group_posts for this group, newest-first, ROTATED so the feed
  /// item's own post (the one that made this card appear in the feed at
  /// all) is index 0 — see group_post_card.dart. Always has >=1 entry.
  final List<GroupCardPost> posts;

  /// The feed item's own photo — same as posts.first.photoUrl, kept as a
  /// separate field so Float/Mosaic/Strip (which only ever show ONE "main"
  /// photo, not the full cycling deck Stack uses) don't need to reach into
  /// the posts list at all.
  final String mainPhotoUrl;
  final String? mainCaption;
  final DateTime? mainCreatedAt;
}

// ---------------------------------------------------------------------------
// Relative time — compact form matching the design spec's "2h" / "45m"
// style. No shared formatter existed elsewhere in this codebase to reuse
// (grepped: every other feed screen just hardcodes its own display string).
// ---------------------------------------------------------------------------

String groupCardTimeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}

// ---------------------------------------------------------------------------
// Member avatar — real photo when available, else the same deterministic
// gradient+initial fallback the group-profile screens already use
// (Avatar.gradientFor, features/groups/design_preview/widgets/avatar.dart —
// already reused by real production screens like group_roster_screen.dart
// despite its own directory name, so reusing it here too rather than
// duplicating the palette).
// ---------------------------------------------------------------------------

class GroupCardMemberCircle extends StatelessWidget {
  const GroupCardMemberCircle({
    super.key,
    required this.member,
    this.size = 34,
    this.borderColor,
    this.borderWidth = 0,
  });

  final GroupCardMember member;
  final double size;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    if (member.avatarUrl == null) {
      return Avatar(id: member.id, label: member.name, size: size, borderColor: borderColor, borderWidth: borderWidth);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderWidth > 0 ? Border.all(color: borderColor ?? Colors.black, width: borderWidth) : null,
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: member.avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, _) => Avatar(id: member.id, label: member.name, size: size),
          errorWidget: (_, _, _) => Avatar(id: member.id, label: member.name, size: size),
        ),
      ),
    );
  }
}

/// Rectangular (not circular) member tile for Float's floating selfie tiles
/// — real photo cover-fit, or the same gradient+initial fallback in a
/// rounded-rect instead of a circle.
class GroupCardMemberTile extends StatelessWidget {
  const GroupCardMemberTile({super.key, required this.member, this.radius = 14, this.initialFontSize = 22});

  final GroupCardMember member;
  final double radius;
  final double initialFontSize;

  @override
  Widget build(BuildContext context) {
    if (member.avatarUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: member.avatarUrl!,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _fallback(),
        ),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: _fallback());
  }

  Widget _fallback() {
    final colors = Avatar.gradientFor(member.id);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(
        member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
        style: GoogleFonts.spaceGrotesk(fontSize: initialFontSize, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header row — shared by all 4 cards: overlapping avatar stack (real
// members, up to 3), group name, "N members · Nh" meta line (no fire/streak
// count — not real data), "···" menu (visual only, no real group-options
// sheet wired here).
// ---------------------------------------------------------------------------

class GroupCardHeader extends StatelessWidget {
  const GroupCardHeader({super.key, required this.data});
  final GroupCardData data;

  @override
  Widget build(BuildContext context) {
    final shown = data.members.take(3).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (shown.isNotEmpty) _AvatarStack(members: shown),
        if (shown.isNotEmpty) const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.16,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${data.members.length} member${data.members.length == 1 ? '' : 's'}'
                '${data.mainCreatedAt == null ? '' : ' · ${groupCardTimeAgo(data.mainCreatedAt)}'}',
                style: GoogleFonts.ibmPlexMono(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Text(
          '···',
          style: GoogleFonts.spaceGrotesk(fontSize: 20, letterSpacing: 1, height: 1, color: AppColors.textMuted.withValues(alpha: 0.75)),
        ),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<GroupCardMember> members;

  static const double size = 34;
  static const double overlap = 12;

  @override
  Widget build(BuildContext context) {
    const step = size - overlap;
    final width = size + step * (members.length - 1);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < members.length; i++)
            Positioned(
              left: i * step,
              child: GroupCardMemberCircle(member: members[i], size: size, borderColor: AppColors.cardSurface, borderWidth: 2),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bell/smiley icon button pair — visual only (no real ping/reaction wiring
// specified for these cards; EveryonePostCard's own real reaction system is
// keyed off `posts.id`, which group_posts rows don't have).
// ---------------------------------------------------------------------------

class GroupCardIconButtons extends StatelessWidget {
  const GroupCardIconButtons({super.key, this.vertical = true, this.size = 44, this.flat = false});

  final bool vertical;
  final double size;

  /// Strip's variant is flat (no blur, solid dark fill) per spec.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final children = [_button('🔔'), SizedBox(width: vertical ? 0 : 10, height: vertical ? 10 : 0), _button('😊')];
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _button(String emoji) {
    final content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: flat ? const Color(0xFF15151A) : const Color.fromRGBO(10, 12, 18, 0.62),
        border: Border.all(color: flat ? const Color(0xFF23232B) : Colors.white.withValues(alpha: 0.12)),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: TextStyle(fontSize: size * 0.38)),
    );
    if (flat) return content;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: content,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton — shown briefly while a card's own member/post fetch is
// in flight (the outer feed has already loaded by this point). Static, no
// shimmer loop — this is a short-lived per-card state, not the feed's own
// initial-load placeholder (see everyone_feed_screen.dart's _LoadingList).
// ---------------------------------------------------------------------------

class GroupCardSkeleton extends StatelessWidget {
  const GroupCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 460,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(26),
      ),
    );
  }
}

/// Card shell — background/border/radius/padding common to all 4 variants.
class GroupCardShell extends StatelessWidget {
  const GroupCardShell({super.key, required this.data, required this.body});
  final GroupCardData data;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroupCardHeader(data: data),
          const SizedBox(height: 14),
          body,
        ],
      ),
    );
  }
}
