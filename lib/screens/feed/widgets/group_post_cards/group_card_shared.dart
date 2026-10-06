import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants.dart';
import '../../../../features/groups/design_preview/widgets/avatar.dart';
import '../../../../features/ping/ping_prompt_sheet.dart' show PingContext;
import '../../../../features/profile_v2/profile_navigation.dart';
import '../../../../services/post_service.dart';
import '../../../../services/presence_service.dart';
import '../../../../services/reaction_preset_service.dart';
import '../../../../services/realmoji_service.dart';
import '../post_card_shared.dart';
import '../../../../features/profile_v2/profile_v2_tokens.dart' show PV2;

// ---------------------------------------------------------------------------
// Real data model for the 4 group-post collage cards (Float/Mosaic/Stack/
// Strip) — see group_post_card.dart for how this gets loaded from
// GroupService. Still no fabricated location/comment/reaction data — those
// have no schema backing (see design_handoff_group_post_cards/README.md's
// spec vs. what's actually real — this app drops what isn't). `streaks` IS
// real, though: DipService.streaksForGroup, backed by
// group_ping_member_streak_map() — each member's own reply streak to their
// group's daily ping (BLUE 3 of STREAK SYSTEM v4). The per-group Dip streak
// this used to show was removed with the Dip streak mechanic itself.
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
    this.aspectRatio,
    this.note,
    this.place,
    this.takenAt,
  });
  final String id;
  final String photoUrl;
  final String userId;
  final String? caption;
  final DateTime? createdAt;

  /// This post's own `group_posts.aspect_ratio` — the frame ITS poster
  /// picked at compose time (PostSizePresetPicker), never a viewer
  /// preference. Parse with parseStoredAspectRatio.
  final String? aspectRatio;

  /// Body text shown below the photo — separate from [caption], which
  /// doubles as the card's header title. Same `group_posts.note` column
  /// GroupProfilePostCard reads.
  final String? note;

  /// Location label for the footer pill, falling back to the poster's name
  /// when unset — same `group_posts.place` column GroupProfilePostCard reads.
  final String? place;

  /// When the memory actually happened, vs [createdAt] (when it was
  /// posted) — same `group_posts.taken_at` column GroupProfilePostCard
  /// prefers for its date badge.
  final DateTime? takenAt;
}

/// '9:40 pm' — matches the design's header subtitle. Shared by
/// DesignGroupCard (feed) and GroupProfilePostCard (group profile) so both
/// format a post's date identically.
String groupCardClockTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'pm' : 'am'}';
}

const List<String> kGroupCardWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> kGroupCardMonths = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

class GroupCardData {
  const GroupCardData({
    required this.groupId,
    required this.groupName,
    this.groupIconUrl,
    required this.members,
    required this.posts,
    required this.mainPhotoUrl,
    this.mainPhotoUrls,
    this.mainVideoUrl,
    this.mainVideoMs,
    this.mainCaption,
    this.mainCreatedAt,
    this.streaks = const {},
    this.locked = false,
    this.groupIsPublic = false,
    this.sharedVia,
  });

  final String groupId;
  final String groupName;

  /// Whose share put this post in the viewer's feed (FeedItem.
  /// groupSharedVia) — the group profile opens via this person.
  final String? sharedVia;

  /// A private group's post seen only through a shared community
  /// (FeedItem.groupPostLocked): shown in full layout, photos after the
  /// first blurred, and opening anything says "Be a friend to see it".
  final bool locked;

  /// This group has `visibility = 'public'` (FeedItem.groupIsPublic) —
  /// self-joinable from the group's own screen, so DesignGroupCard skips
  /// the feed's "Accept" pill for it even when [locked] is false.
  final bool groupIsPublic;

  /// The group's own DP, once any member has set one — falls back to the
  /// letter-glyph initial (see DesignGroupCard's own render) when null.
  final String? groupIconUrl;

  /// Real group_members roster (any role), admins-first per
  /// GroupService.fetchMembers's own ordering.
  final List<GroupCardMember> members;

  /// Per-member GROUP-PING REPLY streak, keyed by `users.id`
  /// (DipService.streaksForGroup). STREAK SYSTEM v4: this used to be the
  /// per-user Dip streak, which no longer exists — see that method's doc.
  /// A member absent from this map has never Dipped in this group — treat as
  /// 0, same as a missing key elsewhere in this file's reaction/ping data.
  final Map<String, int> streaks;

  /// Real group_posts for this group, newest-first, ROTATED so the feed
  /// item's own post (the one that made this card appear in the feed at
  /// all) is index 0 — see group_post_card.dart. Always has >=1 entry.
  final List<GroupCardPost> posts;

  /// The feed item's own cover photo — same as posts.first.photoUrl.
  final String mainPhotoUrl;

  /// The feed item's full photo list when it's a multi-photo post
  /// (`group_posts.photo_urls`). Null/empty means single-photo — read
  /// [mainPhotoUrl]. Prefer [photoUrls], which resolves the fallback.
  final List<String>? mainPhotoUrls;

  /// A video group post (2026-10-06) — the card plays this instead of the
  /// photo carousel.
  final String? mainVideoUrl;
  final int? mainVideoMs;

  final String? mainCaption;
  final DateTime? mainCreatedAt;

  /// Every photo of THIS feed item, in display order, cover first.
  List<String> get photoUrls =>
      (mainPhotoUrls != null && mainPhotoUrls!.isNotEmpty)
          ? mainPhotoUrls!
          : [mainPhotoUrl];
}

// ---------------------------------------------------------------------------
// Relative time — compact form matching the design spec's "2h" / "45m"
// style. No shared formatter existed elsewhere in this codebase to reuse
// (grepped: every other feed screen just hardcodes its own display string).
// ---------------------------------------------------------------------------

/// Resolves the display name for whichever post GroupCardEngagementButtons/
/// Ping should target — the feed item's own post (posts.first, per
/// GroupPostCard's rotation), matched against the real member roster.
String groupCardPosterName(GroupCardData data) {
  if (data.posts.isEmpty) return 'someone';
  final userId = data.posts.first.userId;
  for (final m in data.members) {
    if (m.id == userId) return m.name;
  }
  return 'someone';
}

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
              memCacheWidth: 1080,
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

// ---------------------------------------------------------------------------
// Member streak row — horizontally scrollable avatars + group-ping streak,
// under the group card header. No names in the resting state (spec): a
// streak-only badge, tap-through to the profile for the name. Streak comes
// from DipService.streaksForGroup (group_ping_member_streak_map()) — each
// member's own consecutive-days streak of answering their group's ping.
// ---------------------------------------------------------------------------

class GroupMemberStreakRow extends StatelessWidget {
  const GroupMemberStreakRow({super.key, required this.members, required this.streaks});

  final List<GroupCardMember> members;
  final Map<String, int> streaks;

  static const double _rowHeight = 48; // avatarSize + flame badge overhang
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: _rowHeight,
      child: ScrollConfiguration(
        behavior: const _NoScrollbarBehavior(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: members.length,
          separatorBuilder: (_, _) => const SizedBox(width: _gap),
          itemBuilder: (_, i) {
            final member = members[i];
            return _MemberStreakAvatar(member: member, streak: streaks[member.id] ?? 0);
          },
        ),
      ),
    );
  }
}

class _MemberStreakAvatar extends StatelessWidget {
  const _MemberStreakAvatar({required this.member, required this.streak});

  final GroupCardMember member;
  final int streak;

  static const double _avatarSize = 34;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openProfile(context, member.id),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        // Room for the 1A ring, which sits OUTSIDE the avatar circle now
        // rather than a badge merely overlapping its edge.
        width: _avatarSize + 6,
        height: GroupMemberStreakRow._rowHeight,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Variant 1A's decorative ring, floating outside the photo —
            // amber when the member has an active streak (their own
            // "captured" state), the spec's neutral #2e2e33 otherwise. Same
            // shape language as the RealMoji chips elsewhere in the app —
            // explicit request: "in 1A design as such" — applied here to
            // the OTHER thing this app already draws in that language.
            Container(
              width: _avatarSize + 6,
              height: _avatarSize + 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  // BLUE when there's a live streak — this is BLUE 3, the
                  // member's own group-ping reply streak, and every
                  // relationship streak in the app is blue (see
                  // PV2.streakBlue). Was orange-red, which read as the
                  // personal anon streak's colour.
                  // Always neutral now, and no flame badge: this row is on
                  // a FEED card, where the whole audience saw each member's
                  // ping streak. Explicit request, 2026-10-06: "remove the
                  // ping streak visible to everyone in friends feed".
                  // [streak] is still passed in, unused, so re-showing it
                  // somewhere private is a one-line change.
                  color: const Color(0xFF2E2E33),
                  width: 1.5,
                ),
              ),
            ),
            GroupCardMemberCircle(member: member, size: _avatarSize),
          ],
        ),
      ),
    );
  }
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
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
              memCacheWidth: 1080,
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
  const GroupCardHeader({super.key, required this.data, this.trailing});
  final GroupCardData data;

  /// Overrides the trailing "···" menu — GroupCardShell passes a
  /// LivePresencePill here (post_card_shared.dart), matching PersonalPostCard's
  /// identical header-trailing slot (post_card.dart's _AuthorRow).
  final Widget? trailing;

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
        if (trailing != null)
          trailing!
        else
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
// Ping + RealMoji buttons — REAL wiring now (group_post_id migration adds
// group-post support to reactions/post_realmoji_reactions, see
// supabase/schema.sql). Self-contained StatefulWidget (its own
// PostReactions-mixin State) rather than reading state from an ancestor,
// since each of the 4 layout files (float/mosaic/stack/strip) instantiates
// this independently at its own position — same PostPingButton/
// PostReactionCorner pair PersonalPostCard uses, same tray-opening style,
// just keyed on groupPostId instead of postId. Replaces the old
// GroupCardIconButtons (bell/smiley, visual-only).
// ---------------------------------------------------------------------------

class GroupCardEngagementButtons extends StatefulWidget {
  const GroupCardEngagementButtons({
    super.key,
    required this.groupPostId,
    required this.posterName,
  });

  final String groupPostId;
  final String posterName;

  @override
  State<GroupCardEngagementButtons> createState() => _GroupCardEngagementButtonsState();
}

class _GroupCardEngagementButtonsState extends State<GroupCardEngagementButtons>
    with PostReactions<GroupCardEngagementButtons> {
  @override
  void initState() {
    super.initState();
    unawaited(loadMyRealmojiReaction(null, groupPostId: widget.groupPostId));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PostPingButton(onTap: () => openPing(pingContext: PingContext.everyone, targetName: widget.posterName)),
        const SizedBox(width: 14),
        PostReactionCorner(
          // §2: 34dp per spec — see PersonalPostCard's identical note.
          size: 34,
          allowFaceReactions: true,
          myFaceReaction: null,
          myEmoji: myRealmojiReaction?.glyph,
          uploading: uploadingFaceReaction,
          onTap: openReactionTray,
          onClose: closePresetTray,
          showTray: showPresetTray,
          category: ReactionPresetCategory.everyone,
          onSelect: (preset) => selectPreset(null, preset, groupPostId: widget.groupPostId),
          onAddNew: () {},
          onCaptureRealmoji: (type) => captureRealmojiAndReact(
            null,
            ReactionPresetCategory.everyone,
            type,
            groupPostId: widget.groupPostId,
          ),
        ),
      ],
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
/// Also owns the Live-presence pill/dropdown (header-adjacent) and the
/// comment card (below body) — the two engagement pieces that don't vary
/// per layout, mirroring PersonalPostCard's identical use of the same
/// shared widgets (post_card_shared.dart) for parity between group and
/// personal posts. The Ping+RealMoji buttons DO vary in position per
/// layout, so those stay embedded in each layout's own `body`
/// (GroupCardEngagementButtons, above).
class GroupCardShell extends StatefulWidget {
  const GroupCardShell({super.key, required this.data, required this.body});
  final GroupCardData data;
  final Widget body;

  @override
  State<GroupCardShell> createState() => _GroupCardShellState();
}

class _GroupCardShellState extends State<GroupCardShell> {
  bool _showLiveDropdown = false;
  List<PresenceUser> _present = const [];

  String? get _groupPostId =>
      widget.data.posts.isNotEmpty ? widget.data.posts.first.id : null;

  @override
  void initState() {
    super.initState();
    _touchAndLoadPresence();
  }

  @override
  void didUpdateWidget(GroupCardShell old) {
    super.didUpdateWidget(old);
    final oldGpid = old.data.posts.isNotEmpty ? old.data.posts.first.id : null;
    if (oldGpid != _groupPostId) _touchAndLoadPresence();
  }

  void _touchAndLoadPresence() {
    final gpid = _groupPostId;
    if (gpid == null) return;
    unawaited(PresenceService.instance.touch(groupPostId: gpid));
    // Permanent view record — see the same call in DesignGroupCard.
    unawaited(PostService.instance.recordGroupPostView(gpid));
    unawaited(_loadPresence());
  }

  Future<void> _loadPresence() async {
    final gpid = _groupPostId;
    if (gpid == null) return;
    final entries = await PresenceService.instance.fetchPresence(groupPostId: gpid);
    if (!mounted) return;
    setState(() => _present = entries.map(PresenceUser.fromEntry).toList());
  }

  @override
  Widget build(BuildContext context) {
    final groupPostId = _groupPostId;

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
          Stack(
            clipBehavior: Clip.none,
            children: [
              GroupCardHeader(
                data: widget.data,
                trailing: LivePresencePill(
                  present: _present,
                  compact: true,
                  onTap: () {
                    setState(() => _showLiveDropdown = !_showLiveDropdown);
                    if (_showLiveDropdown) unawaited(_loadPresence());
                  },
                ),
              ),
              if (_showLiveDropdown)
                Positioned(
                  top: 44,
                  right: 0,
                  child: LivePresenceDropdown(present: _present, width: 180, borderRadius: 14),
                ),
            ],
          ),
          const SizedBox(height: 14),
          widget.body,
          // reactors/reactionCount left at defaults (hides the mini RealMoji
          // rail) — GroupCardShell has no reactor list in scope; reaction
          // data here lives per-layout in GroupCardEngagementButtons'
          // PostReactions mixin instance, not centrally on this shell. Wire
          // through if/when that data gets lifted up.
          if (groupPostId != null) PostCommentCard(groupPostId: groupPostId, isGroup: true),
        ],
      ),
    );
  }
}
