import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_video.dart';

import '../../../features/profile_v2/group_profile_v2_screen.dart';
import '../../../features/profile_v2/profile_v2_icons.dart';
import '../../../features/profile_v2/profile_v2_tokens.dart';
import '../../../features/profile_v2/profile_v2_widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../features/moderation/post_actions_menu.dart';

import '../../../core/glass.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../services/current_user_service.dart';
import '../../../services/post_size_prefs_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/dip_service.dart';
import '../../../services/group_service.dart';
import '../../../services/post_author_pin_service.dart';
import '../../../services/post_service.dart';
import '../../../services/presence_service.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
import 'group_post_cards/group_card_shared.dart'
    show
        GroupCardData,
        GroupCardMember,
        GroupCardPost,
        GroupMemberStreakRow,
        groupCardClockTime,
        groupCardTimeAgo,
        kGroupCardMonths,
        kGroupCardWeekdays;
import '../../../shared/widgets/avatar_peek.dart';
import 'post_card_shared.dart';
import '../single_post_detail_screen.dart';
import 'post_photo_carousel.dart';

// ---------------------------------------------------------------------------
// DesignGroupCard — pixel-faithful port of the GROUP CARD section of the
// live Claude Design file, replacing GroupPostCard/GroupCardFloat/Mosaic/
// Stack/Strip (an older, unrelated design system per this session's own
// audit). Same 4-layout deterministic hash as the widget it replaces
// (postId.hashCode.abs() % 4), same real GroupCardData loading (member
// roster + group posts via GroupService), same real backend wiring
// (PostReactions mixin, PostCommentCard) as DesignSoloCard.
//
// Graceful degradation: collage/deck need 2-3 real photos; when a group has
// fewer real posts than a layout wants, this cycles through the available
// ones (postAt(i)) rather than leaving a slot blank or crashing — a group
// with only 1 real post shows that same photo in every slot a layout needs.
// ---------------------------------------------------------------------------

class DesignGroupCard extends StatefulWidget {
  const DesignGroupCard({super.key, required this.item});
  final FeedItem item;

  @override
  State<DesignGroupCard> createState() => _DesignGroupCardState();
}

class _DesignGroupCardState extends State<DesignGroupCard> {
  /// Loaded card data per group post, kept across rebuilds. The feed's
  /// ListView disposes cards that scroll off-screen, so without this every
  /// return trip re-fetched from zero and the card was rebuilt at ZERO
  /// height, then expanded when the data landed — shoving everything below
  /// it. That pop-in was the feed's "glitching several times" while
  /// scrolling back up. A revisited card now builds at full size instantly.
  static final Map<String, GroupCardData> _cache = {};

  late final Future<GroupCardData?> _future = _cachedLoad();

  Future<GroupCardData?> _cachedLoad() async {
    final data = await _load();
    if (data != null) _cache[widget.item.postId] = data;
    return data;
  }

  Future<GroupCardData?> _load() async {
    final groupId = widget.item.groupId;
    final photoUrl = widget.item.photoUrl;
    if (groupId == null || photoUrl == null || photoUrl.isEmpty) return null;

    final locked = widget.item.groupPostLocked;
    // A locked viewer isn't a member, so group_members/group_posts RLS hides
    // both; the roster comes from group_card_members() (which re-checks the
    // viewer may see this post) and the post itself is this feed item.
    final results = await Future.wait([
      locked
          ? GroupService.instance.fetchCardMembers(widget.item.postId)
          : GroupService.instance.fetchMembers(groupId),
      // Locked: only THIS post, via group_card_post() (RLS hides the
      // row itself) — note/place/taken_at for the profile-card layout.
      locked
          ? GroupService.instance.fetchCardPost(widget.item.postId)
          : GroupService.instance.fetchPosts(groupId),
    ]);
    final memberRows = results[0];
    final postRows = results[1];

    final members = memberRows.map((r) {
      final u = r['users'] as Map?;
      return GroupCardMember(
        id: r['user_id'] as String? ?? '',
        name: (u?['name'] as String?) ?? 'Member',
        avatarUrl: u?['profile_photo_url'] as String?,
      );
    }).toList();

    // Dip streaks — separate table from group_posts/members above, so this
    // is its own round trip rather than folded into the Future.wait; a
    // failure here degrades to an all-zero map (DipService.streaksForGroup)
    // rather than blocking the card.
    final streaks = await DipService.instance.streaksForGroup(
      groupId,
      members.map((m) => m.id).toList(),
    );

    var posts = postRows
        .map(
          (r) => GroupCardPost(
            id: r['id'] as String? ?? '',
            photoUrl: r['photo_url'] as String? ?? '',
            userId: r['user_id'] as String? ?? '',
            caption: r['caption'] as String?,
            createdAt: r['created_at'] != null
                ? DateTime.tryParse(r['created_at'] as String)
                : null,
            aspectRatio: r['aspect_ratio'] as String?,
            note: r['note'] as String?,
            place: r['place'] as String?,
            takenAt: r['taken_at'] != null
                ? DateTime.tryParse(r['taken_at'] as String)
                : null,
          ),
        )
        .where((p) => p.photoUrl.isNotEmpty)
        .toList();

    final idx = posts.indexWhere((p) => p.id == widget.item.postId);
    if (idx > 0) {
      posts = [...posts.sublist(idx), ...posts.sublist(0, idx)];
    } else if (idx == -1) {
      posts = [
        GroupCardPost(
          id: widget.item.postId,
          photoUrl: photoUrl,
          userId: widget.item.userId,
          caption: widget.item.caption,
          createdAt: widget.item.createdAt,
          aspectRatio: widget.item.aspectRatio,
        ),
        ...posts,
      ];
    }

    return GroupCardData(
      groupId: groupId,
      groupName: widget.item.groupName ?? 'Group',
      groupIconUrl: widget.item.groupIconUrl,
      members: members,
      posts: posts,
      mainPhotoUrl: photoUrl,
      mainPhotoUrls: widget.item.photos,
      mainVideoUrl: widget.item.videoUrl,
      mainVideoMs: widget.item.videoMs,
      mainCaption: widget.item.caption,
      mainCreatedAt: widget.item.createdAt,
      streaks: streaks,
      locked: locked,
      groupIsPublic: widget.item.groupIsPublic,
      sharedVia: widget.item.groupSharedVia,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GroupCardData?>(
      future: _future,
      // Cached data renders on the very first frame — no zero-height gap.
      initialData: _cache[widget.item.postId],
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          // Still loading for the first time: hold the card's real height
          // (header + members + its photo at the post's own stored ratio +
          // footer/comments) instead of 0, so its arrival doesn't push the
          // feed. A load that ends with no data collapses once, as before.
          if (snap.connectionState == ConnectionState.done) {
            return const SizedBox.shrink();
          }
          return LayoutBuilder(
            builder: (context, c) => SizedBox(
              height:
                  // group-name row + members row + date header
                  84 + 58 + 70 +
                  c.maxWidth /
                      parseStoredAspectRatio(widget.item.aspectRatio) +
                  // footer well + comment block below the card
                  62 + 150,
            ),
          );
        }
        // One body for every group post — the old hash-picked single/
        // collage/deck layouts are gone (see _layoutBody).
        return _GroupCardBody(
          data: data,
          onOpenPost: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SinglePostDetailScreen(item: widget.item),
            ),
          ),
        );
      },
    );
  }
}

class _GroupCardBody extends StatefulWidget {
  const _GroupCardBody({required this.data, required this.onOpenPost});
  final GroupCardData data;

  /// Opens this post's own screen — what every tap on a LOCKED card does
  /// (no pop-up: the post opens like any other, photos 2+ still blurred).
  final VoidCallback onOpenPost;

  @override
  State<_GroupCardBody> createState() => _GroupCardBodyState();
}

class _GroupCardBodyState extends State<_GroupCardBody>
    with PostReactions<_GroupCardBody> {
  bool _showLiveDropdown = false;
  bool _showMoreMenu = false;
  String? _mySelfieUrl;
  List<PresenceUser> _present = const [];

  /// Whether the VIEWER is already in this group. Null while resolving —
  /// the Accept pill stays hidden until we actually know, so a member never
  /// sees a flash of "Accept" for their own group.
  bool? _isMember;
  bool _joining = false;

  // TapRegion groupIds pairing each trigger with its own panel (spec §C:
  // "outside-tap closes it") — suffixed with the group's own post id since
  // many group cards are mounted at once in a scrolling feed.
  late final String _liveGroupId = 'grouplive-${widget.data.groupId}';

  ScrollPosition? _scrollPosition;

  String? get _groupPostId =>
      widget.data.posts.isNotEmpty ? widget.data.posts.first.id : null;

  @override
  void initState() {
    super.initState();
    // Re-fetch the "here" list on any pin change so an open dropdown's
    // PINNED section updates immediately (PostAuthorPinService.changes).
    PostAuthorPinService.instance.changes.addListener(_onPinsChanged);
    unawaited(_resolveMembership());
    final gpid = _groupPostId;
    if (gpid != null) {
      loadReactionSummary(null, groupPostId: gpid);
      unawaited(loadMyRealmojiReaction(null, groupPostId: gpid));
      unawaited(PresenceService.instance.touch(groupPostId: gpid));
      // The PERMANENT view record, distinct from the heartbeat above —
      // same pairing DesignSoloCard already does for personal posts. Only
      // the group PROFILE card wrote these, so a group post seen in the
      // FEED left group_post_views empty: the seen/pinned merge in the
      // presence pill had nothing to read, and (as of Phase 2) the
      // pinned-viewer notification could not fire either.
      unawaited(PostService.instance.recordGroupPostView(gpid));
      unawaited(_loadPresence());
    }
  }

  /// Resolved against the roster the card already carries — no extra
  /// round trip. GroupCardData.members is the real group_members list.
  Future<void> _resolveMembership() async {
    try {
      final me = await CurrentUserService.instance.resolveId();
      if (!mounted) return;
      setState(() => _isMember = widget.data.members.any((m) => m.id == me));
    } catch (_) {
      // Unknown — leave null so the pill stays hidden rather than
      // offering "Accept" to someone who may already be a member.
    }
  }

  /// "Accept" -> join the group this post came from. The gate lives
  /// server-side (join_group_from_shared_post): seeing the post is the
  /// invitation, and the RPC re-checks that independently of this UI.
  Future<void> _acceptGroup() async {
    final gpid = _groupPostId;
    if (gpid == null || _joining) return;
    setState(() => _joining = true);
    try {
      await GroupService.instance.joinFromSharedPost(gpid);
      if (!mounted) return;
      setState(() {
        _isMember = true;
        _joining = false;
      });
      showGlassToast(context, 'Joined ${widget.data.groupName}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      // The RPC's own message ("This group post was not shared with you")
      // is more useful than a generic failure, so it is surfaced as-is.
      final msg = e is PostgrestException
          ? e.message
          : 'Couldn\'t join that group.';
      showGlassToast(context, msg, isError: true);
    }
  }

  Future<void> _loadPresence() async {
    final gpid = _groupPostId;
    if (gpid == null) return;
    final entries = await PresenceService.instance.fetchPresence(
      groupPostId: gpid,
    );
    if (!mounted) return;
    setState(() => _present = entries.map(PresenceUser.fromEntry).toList());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (newPosition != _scrollPosition) {
      _scrollPosition?.removeListener(_onAncestorScroll);
      _scrollPosition = newPosition;
      _scrollPosition?.addListener(_onAncestorScroll);
    }
  }

  void _onAncestorScroll() {
    if (_showLiveDropdown || _showMoreMenu || showPresetTray) {
      _hideMoreMenuOverlay();
      if (showPresetTray) closePresetTray();
      setState(() {
        _showLiveDropdown = false;
      });
    }
  }

  void _onPinsChanged() {
    if (mounted && _groupPostId != null) unawaited(_loadPresence());
  }

  @override
  void dispose() {
    PostAuthorPinService.instance.changes.removeListener(_onPinsChanged);
    _scrollPosition?.removeListener(_onAncestorScroll);
    _moreMenuEntry?.remove();
    super.dispose();
  }

  // Mutual exclusion (spec §C: "only one of each open per card") — every
  // trigger's onTap calls this before opening its own panel.
  void _closeAllPanels() {
    _showLiveDropdown = false;
    _showMoreMenu = false;
    if (showPresetTray) closePresetTray();
    _hideMoreMenuOverlay();
  }

  // More (⋯) menu — ported verbatim from DesignSoloCard (same OverlayEntry
  // pattern, same Block/Report no-op actions: no backend for either exists
  // anywhere in this codebase for personal posts either). Group posts had
  // this before the GroupPostCard→DesignGroupCard rewrite; the rewrite's
  // own header row just never re-added the trigger.
  final _moreMenuKey = GlobalKey();
  OverlayEntry? _moreMenuEntry;

  void _toggleMoreMenu() {
    if (_moreMenuEntry != null) {
      _hideMoreMenuOverlay();
      return;
    }
    _closeAllPanels();
    final box = _moreMenuKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context);
    if (box == null || overlayState == null) return;
    final topLeft = box.localToGlobal(Offset.zero);

    _moreMenuEntry = OverlayEntry(
      builder: (overlayContext) {
        final screen = MediaQuery.of(overlayContext).size;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideMoreMenuOverlay,
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned(
              right: screen.width - (topLeft.dx + box.size.width),
              top: topLeft.dy + box.size.height + 4,
              child: Material(
                color: Colors.transparent,
                // Was toast-only on both actions, writing nothing — see
                // design_solo_card.dart's note. Same real sheet now.
                child: MoreMenuDropdown(
                  onBlock: () {
                    _hideMoreMenuOverlay();
                    _openRealMenu();
                  },
                  onReport: () {
                    _hideMoreMenuOverlay();
                    _openRealMenu();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(_moreMenuEntry!);
    setState(() => _showMoreMenu = true);
  }

  /// The real Report(+reason) / Block sheet — see design_solo_card.dart's
  /// _openRealMenu for why the toast-only version had to go.
  ///
  /// Uses the GROUP-POST menu, not the ordinary post one: this card is a
  /// `group_posts` row, and showPostActionsMenu targets `posts`. Pointing it
  /// at the wrong table would have made Report file against a post id that
  /// doesn't exist and Remove soft-delete nothing.
  Future<void> _openRealMenu() async {
    final groupPostId = _groupPostId;
    if (groupPostId == null) return; // nothing concrete to report
    await showGroupPostActionsMenu(
      context,
      groupPostId: groupPostId,
      // The poster of the group post being reported — Block targets the
      // person, not the group.
      authorUsersId: widget.data.posts.first.userId.isEmpty
          ? null
          : widget.data.posts.first.userId,
    );
  }

  void _hideMoreMenuOverlay() {
    _moreMenuEntry?.remove();
    _moreMenuEntry = null;
    if (_showMoreMenu) _showMoreMenu = false;
  }

  @override
  Future<void> selectPreset(
    String? postId,
    ReactionPreset preset, {
    String? groupPostId,
  }) async {
    await super.selectPreset(postId, preset, groupPostId: groupPostId);
    unawaited(_refreshMySelfie());
  }

  @override
  Future<void> captureRealmojiAndReact(
    String? postId,
    ReactionPresetCategory category,
    RealmojiType type, {
    String? groupPostId,
  }) async {
    await super.captureRealmojiAndReact(
      postId,
      category,
      type,
      groupPostId: groupPostId,
    );
    unawaited(_refreshMySelfie());
  }

  Future<void> _refreshMySelfie() async {
    final type = myRealmojiReaction;
    if (type == null) {
      setState(() => _mySelfieUrl = null);
      return;
    }
    final url = await RealmojiService.instance.savedSelfieUrl(
      feedScope: ReactionPresetCategory.everyone.wire,
      emojiType: type,
    );
    if (!mounted) return;
    setState(() => _mySelfieUrl = url);
  }

  /// Opens the group's own profile — its photos, roster and Dips.
  bool get _locked => widget.data.locked;

  /// A locked post's taps just open the post (see _GroupCardBody.onOpenPost).
  void _showLocked() => widget.onOpenPost();

  void _openGroupProfile() {
    // Opens for locked viewers too — the profile itself only shows them the
    // posts they're permitted to see (group_profile_posts_for_viewer), so
    // there is nothing to gate here any more. Explicit request: tapping the
    // group from the friends feed opens its profile.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupProfileV2Screen(
          groupId: widget.data.groupId,
          // Opens via whoever's share put this post in my feed.
          viaUserId: widget.data.sharedVia,
        ),
      ),
    );
  }

  String get _groupInitial => widget.data.groupName.isNotEmpty
      ? widget.data.groupName[0].toUpperCase()
      : 'G';

  /// Date badge source — taken_at (when the memory happened) over
  /// created_at (when it was posted), same preference GroupProfilePostCard
  /// gives its own date badge. Falls back to the feed item's own
  /// createdAt for the synthesized-post path (idx == -1 in _load), which
  /// never carries taken_at.
  DateTime? get _headerDate => widget.data.posts.isEmpty
      ? widget.data.mainCreatedAt
      : (widget.data.posts.first.takenAt ??
            widget.data.posts.first.createdAt ??
            widget.data.mainCreatedAt);

  /// Header title — the post's own caption, same as GroupProfilePostCard's
  /// title. Falls back to the group's name rather than a poster's name:
  /// unlike the profile card (always a member viewing a known group), a
  /// feed card may be shown to a non-member who hasn't resolved a name for
  /// the poster yet.
  String get _headerTitle {
    final caption = widget.data.posts.isEmpty
        ? null
        : widget.data.posts.first.caption;
    if (caption != null && caption.isNotEmpty) return caption;
    return '${widget.data.groupName}’s post';
  }

  /// Body text below the photo — same `note` column GroupProfilePostCard
  /// reads. Null for the synthesized-post path (idx == -1 in _load), which
  /// has no note to show.
  String? get _headerNote =>
      widget.data.posts.isEmpty ? null : widget.data.posts.first.note;

  /// Footer location label — same `place` column GroupProfilePostCard
  /// reads, falling back to the poster's name (see [_posterName]) when unset.
  String? get _headerPlace =>
      widget.data.posts.isEmpty ? null : widget.data.posts.first.place;

  GroupCardMember? get _posterMember {
    if (widget.data.posts.isEmpty) return null;
    final userId = widget.data.posts.first.userId;
    for (final m in widget.data.members) {
      if (m.id == userId) return m;
    }
    return null;
  }

  String? get _posterAvatarUrl => _posterMember?.avatarUrl;

  String get _posterName => _posterMember?.name ?? 'member';

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();
    final gpid = _groupPostId;

    // ---- Group name row (above the card) ----
    // Explicit request: keep the group's DP + name visible (matching a
    // personal post's own avatar+name+time header, per the reference
    // screenshot) in the same row as the Live-presence pill and "···"
    // menu — the same quartet the old in-card header carried — just
    // sitting above the restyled card now instead of inside it, since the
    // card's own header is the post's date badge/caption/time now (see
    // below).
    final groupNameRow = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _openGroupProfile,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3DDC97), Color(0xFF10B981)],
                      ),
                    ),
                    alignment: Alignment.center,
                    // The group's real DP, once any member has set one —
                    // falls back to the gradient + letter glyph when
                    // null, same as every other avatar fallback here.
                    child: (widget.data.groupIconUrl ?? '').isEmpty
                        ? Text(
                            _groupInitial,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          )
                        // Press-and-hold to see the group DP big.
                        : AvatarPeek(
                          imageUrl: widget.data.groupIconUrl,
                          child: CachedNetworkImage(
                            memCacheWidth: 132,
                            imageUrl: widget.data.groupIconUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => Text(
                              _groupInitial,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.data.groupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.nunito(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            '${widget.data.members.length} member${widget.data.members.length == 1 ? '' : 's'}'
                            '${widget.data.mainCreatedAt == null ? '' : ' · ${groupCardTimeAgo(widget.data.mainCreatedAt)}'}',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The "Accept"/join pill used to sit here — removed outright
          // (explicit request, 2026-10-02: "in friends feed on group post
          // ... it showing join no one can join like that remove that join
          // button"). _acceptGroup/_isMember/_joining are kept (harmless if
          // unused) rather than ripped out, since _isMember also gates
          // nothing else risky here.
          TapRegion(
            groupId: _liveGroupId,
            child: LivePresencePill(
              present: _present,
              maxAvatars: 2,
              // Faces only, the same reduced pill Duo posts use — explicit
              // request to shrink the "not seen yet" pill on group posts
              // "same like how it's in duo album".
              avatarsOnly: true,
              onTap: () {
                setState(() {
                  final next = !_showLiveDropdown;
                  _closeAllPanels();
                  _showLiveDropdown = next;
                });
                if (_showLiveDropdown) unawaited(_loadPresence());
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: _moreMenuKey,
            onTap: _toggleMoreMenu,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.more_horiz, size: 22, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    // The dropdown used to be nested inside groupNameRow's own Stack, which
    // meant it painted BEFORE (i.e. underneath) the NeuCard below it in the
    // outer Column — any part of the dropdown taller than the row's own
    // padding was covered by the card. Hoisted to the outer Stack below so
    // it paints last, on top of the whole card, same fix pattern as every
    // other dropdown/tray in this file.
    final liveDropdownOverlay = _showLiveDropdown
        ? Positioned(
            top: 62,
            right: 14,
            child: TapRegion(
              groupId: _liveGroupId,
              onTapOutside: (_) => setState(() => _showLiveDropdown = false),
              child: LivePresenceDropdown(
                present: _present,
                width: 180,
                borderRadius: 14,
              ),
            ),
          )
        : null;

    // Same NeuCard shell GroupProfilePostCard uses, so the feed card reads
    // as one rounded unit — neither this card nor DesignSoloCard had an
    // outer card background before, so this is new chrome, not a double-up.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            groupNameRow,
            // ---- Group members ----
            // OUTSIDE the card again, between the group-name row and the
            // card — explicit request: "keep the dp outside the blob". The
            // card itself is now exactly GroupProfilePostCard's contents.
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GroupMemberStreakRow(
                members: widget.data.members,
                streaks: widget.data.streaks,
              ),
            ),
            // The member row used to sit here, between the group name and
            // the card. Moved INSIDE the card, directly under the date/
            // title header — explicit request ("let the member be inside
            // below the date thing in post"). See its new call site below.
            // Attached to the screen edges (explicit request) — group posts
            // only; the same in the group profile's post list.
            Padding(
              padding: EdgeInsets.zero,
              child: NeuCard(
                radius: 24,
                clip: true,
                // Reverted to NeuCard's own default fill, matching
                // GroupProfilePostCard — explicit request to carry the
                // group profile's (pre-today) card look into the friends
                // feed too, so the same post reads identically in both
                // places. The kGroupCardBody/kGroupCardPanel panelled
                // treatment added today is gone from both cards now.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- Header + members ----
                    // No darker kGroupCardBody block behind these any more —
                    // explicit request to make the feed's group post read
                    // "ditto" like the group profile's GroupProfilePostCard,
                    // where the header sits on the card's own ground.
                    // ---- Header ----
                    // Date-badge style ported from GroupProfilePostCard (the group's
                    // own profile already looked like this; the feed card didn't) —
                    // NeuWell day/month badge + caption-as-title + weekday·time
                    // subtitle, replacing the old DP + group-name + member-count row.
                    // The group's own name/Live-pill/menu moved above the card (see
                    // groupNameRow) — this row is just the post's own date/caption now.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                      // Reverted: this header briefly sat in its own lighter
                      // kGroupCardPanel well. Explicit request to match the
                      // group profile's card, where it's a plain row on the
                      // card's own ground.
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _openGroupProfile,
                                  child: NeuWell(
                                    width: 46,
                                    height: 46,
                                    radius: 14,
                                    shadows: PV2.insetStd,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _headerDate == null
                                              ? '--'
                                              : _headerDate!.day
                                                    .toString()
                                                    .padLeft(2, '0'),
                                          style: PV2.display(
                                            size: 17,
                                            height: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          _headerDate == null
                                              ? ''
                                              : kGroupCardMonths[_headerDate!
                                                        .month -
                                                    1],
                                          style: PV2.caps(
                                            size: 8,
                                            tracking: 0.14,
                                            color: PV2.inkCount,
                                            weight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  // Tapping the title/subtitle opens the group's profile —
                                  // the same affordance the old DP/name row had. It was
                                  // inert, so a group post was a dead end.
                                  child: GestureDetector(
                                    onTap: _openGroupProfile,
                                    behavior: HitTestBehavior.opaque,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _headerTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: PV2.body(
                                            size: 15.5,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _headerDate == null
                                              ? groupCardTimeAgo(
                                                  widget.data.mainCreatedAt,
                                                )
                                              : '${kGroupCardWeekdays[_headerDate!.weekday - 1]} · ${groupCardClockTime(_headerDate!)}',
                                          style: PV2.body(
                                            size: 12,
                                            color: PV2.inkCount,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ),
                    _layoutBody(reactions, gpid),

                    // ---- Caption body + footer ----
                    // Ported from GroupProfilePostCard: the caption is the header's
                    // title now (not repeated here), but a separate `note` still
                    // renders below the photo as the post's body text when there is
                    // one, and a place/poster-identity pill closes out the card.
                    if (_headerNote != null && _headerNote!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
                        child: Text(
                          _headerNote!,
                          style: PV2.body(
                            size: 13,
                            color: PV2.inkBio,
                            height: 1.4,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                      child: NeuWell(
                        radius: 13,
                        shadows: PV2.insetStd,
                        // Reverted to NeuWell's default fill — see the
                        // card's own revert note above.
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        width: double.infinity,
                        child: Row(
                          children: [
                            ClipOval(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: _posterAvatarUrl == null
                                    ? const ColoredBox(
                                        color: PV2.recessed,
                                        child: Icon(
                                          Icons.person,
                                          size: 11,
                                          color: Colors.white38,
                                        ),
                                      )
                                    : CachedNetworkImage(
                                        memCacheWidth: 1080,
                                        imageUrl: _posterAvatarUrl!,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                            // Only the poster's avatar — "only one logo", same as
                            // GroupProfilePostCard's footer. Presence lives on
                            // the group-name row above the card.
                            const SizedBox(width: 8),
                            if (_headerPlace != null &&
                                _headerPlace!.isNotEmpty) ...[
                              PV2Icons.place(
                                13,
                                Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _headerPlace!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PV2.body(
                                    size: 12.5,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ] else
                              Flexible(
                                child: Text(
                                  _posterName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PV2.body(
                                    size: 12.5,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  ],
                ),
              ),
            ),
            // ---- Comments ----
            // OUTSIDE the post card's own boundary — explicit request
            // ("let comment section not be included in the post
            // boundary"). It used to be the last child INSIDE the
            // NeuCard, so the card's rounded edge wrapped around it;
            // now the card ends at the poster/location strip and the
            // comments sit below it on the page ground.
            // Back under every group post (explicit request: "why
            // isn't there a comment section below each post").
            // Locked posts get a quiet line instead of a composer
            // the server would refuse.
            if (gpid != null && _locked)
              GestureDetector(
                onTap: _showLocked,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: PV2.recessed,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_rounded,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Be a friend to comment',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (gpid != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PostCommentCard(
                  groupPostId: gpid,
                  isGroup: true,
                  reactionCount: reactions.totalReactionCount,
                ),
              ),
          ],
        ),
        ?liveDropdownOverlay,
      ],
    );
  }

  /// One body for every group post — the same swipeable photo area personal
  /// posts use, with this card's own overlays layered on top. Replaces the
  /// old 3-way single/collage/deck switch: group posts are no longer a
  /// different KIND of card, just a post whose photos happen to come from a
  /// group.
  Widget _layoutBody(ReactionSummary reactions, String? gpid) {
    // Edge to edge inside the rounded card, no frame of its own — copied
    // from GroupProfilePostCard (explicit request).
    return Padding(
      padding: EdgeInsets.zero,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Was a separate, smaller 20pt — now unified with
          // kFriendsPostRadius (see that constant's own doc) so group
          // and personal posts curve identically in the merged feed.
          //
          // The FRAME was a third value too: this carousel was passed no
          // aspectRatio at all, so it fell back to PostPhotoCarousel's own
          // 4:5 default while personal posts ran at 2:3. Now reads THIS
          // post's own stored ratio — its poster's compose-time choice
          // (PostSizePresetPicker), never a viewer preference. posts.first
          // is always the post that made this card appear (see _load's
          // rotate-to-front), so its aspectRatio is the one to use.
          // A VIDEO group post plays here in place of the carousel
          // (2026-10-06). A locked post still never reveals it.
          if ((widget.data.mainVideoUrl ?? '').isNotEmpty && !_locked)
            AspectRatio(
              aspectRatio: parseStoredAspectRatio(
                widget.data.posts.first.aspectRatio,
              ),
              child: AppVideo(
                url: widget.data.mainVideoUrl,
                durationMs: widget.data.mainVideoMs,
                fit: BoxFit.cover,
              ),
            )
          else
            PostPhotoCarousel(
              photoUrls: widget.data.photoUrls,
              borderRadius: 0,
              aspectRatio: parseStoredAspectRatio(
                widget.data.posts.first.aspectRatio,
              ),
              blurFromIndex: _locked ? 1 : null,
            ),
          // Reactions are only VIEWABLE on the group's own profile —
          // explicit request: "group posts reactions in group profile".
          // The chip still previews them here, but a tap points at the
          // group profile (same toast DesignSoloCard gives personal posts)
          // instead of opening the reactor list in the feed.
          Positioned(
            left: 14,
            bottom: 14,
            child: ReactionPreviewChip(
              count: reactions.totalEmojiCount + reactions.faceReactions.length,
              faces: reactions.faceReactions,
              emojiCounts: reactions.emojiCounts,
              onTap: () => _locked
                  ? _showLocked()
                  : showGlassToast(
                      context,
                      'Visit the group profile to view reactions in this post',
                    ),
            ),
          ),

          // Bottom-right: the SAME Ping + RealMoji pair personal posts use
          // (PostPingButton / PostReactionCorner from post_card_shared),
          // stacked HORIZONTALLY — group posts get a Row here (unlike
          // DesignSoloCard's personal-post rail, which stays a vertical
          // Column; the contrast is intentional, matching the group
          // profile's own post cards, see group_profile_post_card.dart).
          // Replaces the old decorative _WaveButton — which had no onTap at
          // all, so group posts had no working Ping — and the bespoke
          // _GroupRealMojiButton + inline picker.
          Positioned(
            right: 13,
            bottom: 14,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // No Ping button on group posts in the feed (explicit ask):
                // a group is pinged only by its own members, from the group
                // itself or the Ping page, never from a shared feed card.
                PostReactionCorner(
                  size: 34,
                  allowFaceReactions: true,
                  myFaceReaction: null,
                  myEmoji: myRealmojiReaction?.glyph,
                  mySelfieUrl: _mySelfieUrl,
                  uploading: uploadingFaceReaction,
                  onTap: () {
                    // TEMP PROBE — remove after diagnosing.
                    debugPrint('[GCARD] reaction tap locked=$_locked gpid=$gpid');
                    if (_locked) {
                      _showLocked();
                    } else {
                      openReactionTray();
                    }
                  },
                  onClose: closePresetTray,
                  showTray: showPresetTray,
                  category: ReactionPresetCategory.everyone,
                  onSelect: (preset) =>
                      selectPreset(null, preset, groupPostId: gpid),
                  onAddNew: () => openAddPresetFlow(
                    null,
                    allowFaceReactions: true,
                    groupPostId: gpid,
                  ),
                  onCaptureRealmoji: (type) => captureRealmojiAndReact(
                    null,
                    ReactionPresetCategory.everyone,
                    type,
                    groupPostId: gpid,
                  ),
                  // Default ❤️ like, first in the tray.
                  onHeart: () => toggleHeart(null, groupPostId: gpid),
                  heartLiked: heartLiked,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
