import 'dart:math' as math;
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/glass.dart' show showGlassToast, showPingToast;
import '../../core/supabase_config.dart';
import '../ping/ping_page.dart' show groupWallAnswerRequest;
import '../../screens/feed/single_post_detail_screen.dart';
import '../../services/current_user_service.dart';
import '../../services/dip_service.dart';
import '../../services/feed_service.dart' show FeedItem;
import '../../services/group_service.dart';
import '../../services/ping_service.dart';
import '../../shared/time_ago.dart';
import '../../shared/widgets/avatar_peek.dart';
import '../composer/composer_screen.dart' show openCameraRoute;
import '../groups/group_member_picker_screen.dart';
import 'audience_picker_sheet.dart';
import 'group_profile_post_card.dart';
import 'profile_navigation.dart' show openProfile;
import '../qr/my_qr_sheet.dart';
import 'profile_v2_create_flows.dart' show GroupPostScreen;
import 'profile_v2_data.dart';
import 'profile_v2_icons.dart';
import 'profile_v2_menus.dart';
import 'profile_v2_sections.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

/// A group's profile.
///
/// The group's two content sections are deliberately opposed and should not be
/// collapsed into one feed: **Dip** is light, member-only and expires within a
/// day, so it is rendered as scattered, tilted cards with a countdown; and
/// **Memories** is permanent and date-organised, so it is rendered as neat
/// collages hung off a date spine. The visual difference is the feature.
class GroupProfileV2Screen extends StatefulWidget {
  const GroupProfileV2Screen({
    super.key,
    this.group = PV2Data.group,
    this.groupId,
    this.backdropIndex = 1,
    this.showBackButton = true,
    this.extraBottomInset = 0,
    this.viaUserId,
  });

  /// Whose profile (or whose share, from the feed) the viewer came through.
  /// A NON-member sees only the posts THIS person shared to them — a post
  /// someone else shared to them shows when they go through that other
  /// person instead (group_profile_posts_for_viewer's p_via_user). Null =
  /// only community-wide posts (public group / locked preview). Members
  /// always see everything regardless.
  final String? viaUserId;

  /// Used only while [groupId] is null — the design-gallery/mock preview.
  final GroupProfile group;

  /// A real group to load and render instead of [group]. Null keeps every
  /// existing caller (profile_v2_gallery.dart, and any my/their-profile row
  /// backed by mock PV2Data, which has no real id to give) on the mock path
  /// unchanged; a caller with a real id switches the whole screen to it.
  final String? groupId;

  final int backdropIndex;
  final bool showBackButton;

  /// Space to reserve below the content for chrome the host floats over the
  /// page — the app shell's nav pill, for instance.
  final double extraBottomInset;

  @override
  State<GroupProfileV2Screen> createState() => _GroupProfileV2ScreenState();
}

/// One real group's loaded data — group row, members, posts, live dips, and
/// the caller's own role/id (the last two drive per-post delete
/// permission). Only ever populated for an actual member: [_loadReal]
/// checks GroupService.myRole first and routes a null role to
/// [_PublicGroupData] instead, so `myRole` here is always 'admin' or
/// 'member', never null.
class _RealGroupData {
  const _RealGroupData({
    required this.group,
    required this.members,
    required this.posts,
    required this.myRole,
    required this.myUserId,
    required this.dips,
    required this.viewCount,
  });

  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> posts;
  final String myRole;
  final String myUserId;
  final List<Map<String, dynamic>> dips;

  /// Real all-time distinct-viewer count (group_profile_views) — explicit
  /// request: profile context shows an all-time count, unlike the feed's
  /// own 3h live-presence window (PresenceService), which is unrelated and
  /// untouched.
  final int viewCount;
}

/// Non-member data: identity, roster, each member's streak, and ONLY the
/// posts this viewer is permitted to see ([posts], from
/// group_profile_posts_for_viewer — shared-to-them posts in full, private-
/// group posts first-photo-only). Never dips. `group_public_profile` itself
/// never selects from `dips` or `group_posts`.
class _PublicGroupData {
  const _PublicGroupData({
    required this.name,
    required this.iconUrl,
    required this.memberCount,
    required this.members,
    this.posts = const [],
  });

  _PublicGroupData withPosts(List<Map<String, dynamic>> posts) =>
      _PublicGroupData(
        name: name,
        iconUrl: iconUrl,
        memberCount: memberCount,
        members: members,
        posts: posts,
      );

  factory _PublicGroupData.fromRpc(Map<String, dynamic> json) {
    final rawMembers = (json['members'] as List?) ?? const [];
    return _PublicGroupData(
      name: (json['name'] as String?) ?? 'Group',
      iconUrl: json['icon_url'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? rawMembers.length,
      members: [
        for (final m in rawMembers)
          _PublicMember(
            name: (m as Map)['name'] as String? ?? 'member',
            photoUrl: m['profile_photo_url'] as String?,
            streak: (m['streak'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }

  final String name;
  final String? iconUrl;
  final int memberCount;
  final List<_PublicMember> members;
  final List<Map<String, dynamic>> posts;
}

class _PublicMember {
  const _PublicMember({
    required this.name,
    required this.photoUrl,
    required this.streak,
  });

  final String name;
  final String? photoUrl;
  final int streak;
}

class _GroupProfileV2ScreenState extends State<GroupProfileV2Screen> {
  bool _memberMenu = false;

  /// id of the post whose delete menu is open, or null. Separate from
  /// _memberMenu since it's per-item, but _closeMenus below closes both —
  /// only one menu is ever open at a time on this screen.
  String? _openPostMenu;

  _RealGroupData? _real;
  _PublicGroupData? _public;
  String? _loadError;

  /// BLUE 2 — the group's SHARED, all-or-nothing ping streak. Null until it
  /// loads, and stays null for a non-member (the RPC returns nothing), which
  /// is what keeps the flame off a view that shouldn't show it.
  GroupPingStreak? _pingStreak;

  /// BLUE 3 per member (`users.id` -> streak) — the flame under each
  /// member's DP in the Members rail. Loaded with [_loadPingStreak].
  Map<String, int> _memberStreaks = const {};
  bool _bannerUploading = false;
  bool _iconUploading = false;

  bool get _isReal => widget.groupId != null;

  /// True once the real load resolves and this viewer is the group's admin
  /// (its creator, or anyone later promoted). Gates the member-removal
  /// affordance and the group-photo/banner pickers.
  bool get _isGroupAdmin => _real?.myRole == 'admin';

  /// Distinct profile viewers, filled in after the page renders.
  int? _views;

  @override
  void initState() {
    super.initState();
    if (_isReal) {
      _loadReal();
      _loadPingStreak();
    }
  }

  /// Loads the group's shared streak. Deliberately separate from
  /// [_loadReal] rather than folded into it: it fails soft to "no flame"
  /// and must never be able to hold up (or break) the rest of the profile.
  Future<void> _loadPingStreak() async {
    final id = widget.groupId;
    if (id == null) return;
    final results = await Future.wait([
      GroupService.instance.fetchGroupPingStreak(id),
      GroupService.instance.fetchGroupStreakBundle([id]),
    ]);
    if (!mounted) return;
    final bundle =
        results[1] as Map<String, ({int shared, Map<String, int> members})>;
    setState(() {
      _pingStreak = results[0] as GroupPingStreak?;
      _memberStreaks = bundle[id]?.members ?? const {};
    });
  }

  /// Records this visit (once per screen load, no session-level dedupe —
  /// same "just insert, read the real count back" shape as
  /// TheirProfileScreen._recordView) and returns the real all-time
  /// distinct-viewer count for [groupId]. Fails soft to the previous count
  /// (or 0) rather than ever throwing — a view-tracking hiccup shouldn't
  /// block the rest of the group profile from loading.
  Future<int> _recordAndCountViews(String groupId) async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      await supabase.from('group_profile_views').insert({
        'viewer_id': myId,
        'group_id': groupId,
      });
    } catch (_) {
      // Still try to read a count even if the insert failed.
    }
    try {
      final rows = await supabase
          .from('group_profile_views')
          .select('viewer_id')
          .eq('group_id', groupId);
      return {
        for (final r in rows as List) (r as Map)['viewer_id'] as String,
      }.length;
    } catch (_) {
      return _real?.viewCount ?? 0;
    }
  }

  Future<void> _loadReal() async {
    final id = widget.groupId;
    if (id == null) return;
    setState(() => _loadError = null);
    try {
      // BUG FIX (explicit report — group profile load delay): `myRole`
      // used to be awaited BEFORE starting the member-tier batch below,
      // serializing two round trips even though myRole's result only
      // decides which BRANCH to use, not an input to the other 5 calls.
      // Starting all 6 together and awaiting myRole first still lets the
      // member-tier batch run at the same time — real members (the common
      // case) win back a full round trip; the rare non-member/nonexistent
      // case just discards the speculative batch below instead of using
      // it, which RLS already makes cheap (empty/denied, not slow).
      final roleFuture = GroupService.instance.myRole(id);
      final batchFuture = Future.wait([
        GroupService.instance.fetchGroup(id),
        GroupService.instance.fetchMembers(id),
        GroupService.instance.fetchPosts(id),
        CurrentUserService.instance.resolveId(),
        DipService.instance.fetchDips(id),
      ]);
      final viewCountFuture = _recordAndCountViews(id);

      // Membership decides which of the two tiers this viewer gets.
      // GroupService.myRole already returns null both when the caller
      // truly isn't a member and (by RLS construction) when the group
      // doesn't exist at all, so a null role here can't yet distinguish
      // those — group_public_profile below makes that distinction for us
      // by returning null only in the genuinely-nonexistent case.
      final role = await roleFuture.timeout(const Duration(seconds: 12));
      if (role == null) {
        final results = await Future.wait([
          DipService.instance.publicProfile(id),
          // Posts are decoration on this tier — a failure shows the
          // profile without them rather than failing the whole page.
          GroupService.instance
              .fetchVisiblePosts(id, viaUserId: widget.viaUserId)
              .catchError((_) => <Map<String, dynamic>>[]),
        ]);
        final profile = results[0] as Map<String, dynamic>?;
        if (profile == null) {
          throw StateError('Group not found or no longer visible');
        }
        if (!mounted) return;
        setState(() {
          _public = _PublicGroupData.fromRpc(
            profile,
          ).withPosts(results[1] as List<Map<String, dynamic>>);
          _real = null;
        });
        return;
      }

      // Same four-call shape groups/group_profile_screen.dart's own _load()
      // uses — that screen is the reference implementation for this fetch.
      final results = await batchFuture.timeout(const Duration(seconds: 12));
      final group = results[0] as Map<String, dynamic>?;
      if (group == null) {
        throw StateError('Group not found or no longer visible');
      }
      // The view count is decoration: the page shows now and the count
      // fills in when it lands (it used to hold the whole page up to 6s —
      // "clicking on groups it's loading too much").
      unawaited(viewCountFuture.then((v) {
        if (mounted) setState(() => _views = v);
      }));
      if (!mounted) return;
      setState(() {
        _public = null;
        _real = _RealGroupData(
          group: group,
          members: results[1] as List<Map<String, dynamic>>,
          posts: results[2] as List<Map<String, dynamic>>,
          myRole: role,
          myUserId: results[3] as String,
          dips: results[4] as List<Map<String, dynamic>>,
          viewCount: _views ?? 0,
        );
      });
    } on TimeoutException {
      if (!mounted) return;
      // A stall is now an ERROR, not an endless spinner. Every one of the
      // six calls above used to be unbounded (group_service and dip_service
      // were the only services in the app with no timeouts at all), so a
      // single hung request — flaky campus wifi, an expired token whose
      // refresh failed mid-flight — left this screen spinning with no way
      // back. _loadError is what renders the Retry button.
      setState(
        () => _loadError = 'Took too long to load. Check your connection.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  /// Admin-only picker → GroupService.updateGroupInfo's new bannerFile
  /// param. Mirrors group_profile_screen.dart's _changeIcon, the one
  /// existing working reference for this upload → persist → reload shape.
  Future<void> _pickGroupBanner() async {
    final id = widget.groupId;
    if (id == null || _bannerUploading) return;
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (xFile == null || !mounted) return;
    setState(() => _bannerUploading = true);
    try {
      await GroupService.instance.updateGroupInfo(
        id,
        bannerFile: File(xFile.path),
      );
      await _loadReal();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't update the banner: $e")));
    } finally {
      if (mounted) setState(() => _bannerUploading = false);
    }
  }

  /// The group's DP (`groups.icon_url`) — explicit report: Ping QA Group
  /// was stuck showing the generated "P" glyph with no way to replace it,
  /// because only the banner had a picker wired. Same upload → persist →
  /// reload shape as [_pickGroupBanner], squarer crop since it renders in
  /// a circle.
  Future<void> _pickGroupIcon() async {
    final id = widget.groupId;
    if (id == null || _iconUploading) return;
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 88,
    );
    if (xFile == null || !mounted) return;
    setState(() => _iconUploading = true);
    try {
      await GroupService.instance.updateGroupInfo(
        id,
        iconFile: File(xFile.path),
      );
      await _loadReal();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't update the group photo: $e")),
      );
    } finally {
      if (mounted) setState(() => _iconUploading = false);
    }
  }

  /// Admin-only removal of another member — the "group creator authority to
  /// remove the group members" ask. RLS enforces it independently
  /// (group_members_delete_admin), so a non-admin who somehow reached this
  /// path is refused by the server too, not just by the hidden UI.
  /// Admin-only: rename the group. Explicit request — "in group profiles
  /// give option to rename the group... by the admin only". rename_group
  /// re-checks the admin role server-side, so this is a convenience gate,
  /// not the security boundary.
  Future<void> _renameGroup() async {
    final id = widget.groupId;
    if (id == null) return;
    final controller = TextEditingController(
      text: (_real?.group['name'] as String?) ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text(
          'Rename group',
          style: PV2.body(size: 15.5, weight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: PV2.body(size: 14),
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: PV2.body(size: 13.5)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(
              'Rename',
              style: PV2.body(size: 13.5, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await GroupService.instance.renameGroup(id, name);
      if (!mounted) return;
      await _loadReal();
    } catch (e) {
      if (!mounted) return;
      showGlassToast(context, _friendlyError(e), isError: true);
    }
  }

  /// Admin-only: flip an EXISTING group's visibility. The create-flow's own
  /// public/private choice (create_group_screen.dart) only ever applies to
  /// a NEW group — every group made before that feature shipped defaulted
  /// to 'private' (see migration 20260925000000_group_visibility_and_teaser
  /// .sql), with no way to change it afterward. That silently made the
  /// Group QR code (public-groups-only, self_join_public_group RLS) and
  /// the Blurred Group Teaser both permanently unreachable for every
  /// existing group — reported as "there is no group qr" when the actual
  /// cause was every real group still being private, not a broken feature.
  /// groups_update_admin RLS (admin or creator) already permits this
  /// directly; no new RPC needed, same as rename_group's own client-side
  /// convenience-gate-plus-server-reverify shape.
  Future<void> _setGroupVisibility(bool public) async {
    final id = widget.groupId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text(
          public ? 'Make this group public?' : 'Make this group private?',
          style: PV2.body(size: 15.5, weight: FontWeight.w700),
        ),
        content: Text(
          public
              ? 'Anyone who visits the group will see all its posts, except '
                    'ones marked Private. Joining stays invite-only.'
              : 'Only members will see posts. Joining stays invite-only '
                    '(invite or the group QR code).',
          style: PV2.body(size: 13.5, color: PV2.inkBio, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: PV2.body(size: 13.5)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              public ? 'Make Public' : 'Make Private',
              style: PV2.body(size: 13.5, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await supabase
          .from('groups')
          .update({'visibility': public ? 'public' : 'private'})
          .eq('id', id);
      if (!mounted) return;
      await _loadReal();
    } catch (e) {
      if (!mounted) return;
      showGlassToast(context, _friendlyError(e), isError: true);
    }
  }

  /// Postgres raises these as `PostgrestException: <message>`; the message
  /// itself is already written for the user (see rename_group /
  /// remove_group_member), so show that rather than the wrapper.
  String _friendlyError(Object e) {
    final text = e.toString();
    final marker = text.indexOf(': ');
    return marker == -1 ? text : text.substring(marker + 2).split('\n').first;
  }

  Future<void> _confirmRemoveMember(MemberChip member) async {
    final id = widget.groupId;
    final userId = member.userId;
    if (id == null || userId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text(
          'Remove ${member.name}?',
          style: PV2.body(size: 15.5, weight: FontWeight.w700),
        ),
        content: Text(
          'They lose access to this group\'s posts and dips. Anything they already posted stays.',
          style: PV2.body(size: 13.5, color: PV2.inkBio, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: PV2.body(size: 13.5)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: PV2.body(
                size: 13.5,
                weight: FontWeight.w700,
                color: PV2.danger,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await GroupService.instance.removeMember(id, userId);
      await _loadReal();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't remove them: $e")));
    }
  }

  Future<bool> _confirmDestructive({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text(
          title,
          style: PV2.body(size: 15.5, weight: FontWeight.w700),
        ),
        content: Text(
          body,
          style: PV2.body(size: 13.5, color: PV2.inkBio, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: PV2.body(size: 13.5)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmLabel,
              style: PV2.body(
                size: 13.5,
                weight: FontWeight.w700,
                color: PV2.danger,
              ),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmExitGroup() async {
    final id = widget.groupId;
    if (id == null) return;
    final ok = await _confirmDestructive(
      title: 'Leave this group?',
      body:
          "You'll lose access to its posts and dips. Anything you already posted stays.",
      confirmLabel: 'Leave',
    );
    if (!ok || !mounted) return;
    try {
      await GroupService.instance.leaveGroup(id);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't leave the group: $e")));
    }
  }

  Future<void> _confirmDestroyGroup() async {
    final id = widget.groupId;
    if (id == null) return;
    if (!_isGroupAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only a group admin can do that.')),
      );
      return;
    }
    final ok = await _confirmDestructive(
      title: 'Destroy this group?',
      body:
          'This permanently deletes the group for every member — its posts, dips, and ping history go with it. This can\'t be undone.',
      confirmLabel: 'Destroy',
    );
    if (!ok || !mounted) return;
    try {
      await GroupService.instance.deleteGroup(id);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't destroy the group: $e")));
    }
  }

  Future<void> _openAddPost() async {
    final id = widget.groupId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupPostScreen(
          groupId: id,
          groupName: _real?.group['name'] as String?,
          groupIsPublic: _real?.group['visibility'] == 'public',
        ),
      ),
    );
    if (!mounted) return;
    await _loadReal();
  }

  /// Opens straight into dual-camera capture, locked to Dip for this exact
  /// group — no destination pills, no group picker (see composer_screen.
  /// dart's `lockToDipGroupId`). Replaces the previous ImagePicker-direct
  /// implementation: that used the OS's native camera UI, entirely
  /// independent of the app's own camera code, and duplicated the "couldn't
  /// open/couldn't add" error handling the composer already has to get
  /// right for its own camera tab. Reloads on return so a real post shows
  /// up immediately; nothing else to update here — the per-group streak is
  /// entirely server-maintained (the `dips_bump_streak` trigger).
  Future<void> _addDip() async {
    final id = widget.groupId;
    if (id == null) return;
    await Navigator.of(context).push(openCameraRoute(lockToDipGroupId: id));
    if (!mounted) return;
    await _loadReal();
  }

  /// Direct port of GroupProfileCoverScreen's own _addMembers (see
  /// group_profile_cover_screen.dart). Picked people get an invite; they
  /// join only by accepting it.
  Future<void> _addMembers() async {
    final data = _real;
    if (data == null) return;
    final existingIds = data.members.map((m) => m['user_id'] as String).toSet();
    final picked = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute<List<Map<String, dynamic>>>(
        fullscreenDialog: true,
        builder: (_) => GroupMemberPickerScreen(excludeIds: existingIds),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      final n = await GroupService.instance.inviteMembers(widget.groupId!, [
        for (final user in picked) user['id'] as String,
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n == 1 ? 'Invite sent' : '$n invites sent')),
      );
      await _loadReal();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't send those invites: $e")),
      );
    }
  }

  /// Share someone's group post to MY audience. Re-opening pre-fills what I
  /// shared before; a viewer reached through several members still gets
  /// one card (the feed returns group_posts rows, not audience rows).
  /// [own] = the caller wrote this post: same call, worded as editing.
  /// Only the caller's own audience rows change either way.
  Future<void> _sharePost(String postId, {bool own = false}) async {
    try {
      final prev = await GroupService.instance.myShare(postId);
      if (!mounted) return;
      final choice = await showAudiencePickerSheet(
        context,
        title: own ? 'Edit my audience' : 'Share this group post',
        subtitle: own
            ? "Who sees it from your side. Other members' audiences stay as they are."
            : 'Also show it to your own circles or communities.',
        confirmLabel: own ? 'Save' : 'Share',
        initialCircleIds: prev.circleIds,
        initialCommunityIds: prev.communityIds,
      );
      if (choice == null) return;
      await GroupService.instance.sharePost(
        postId,
        circleIds: choice.circleIds,
        communityIds: choice.communityIds,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(own ? 'Your audience is updated' : 'Shared with your audience')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't share: $e")));
    }
  }

  Future<void> _deletePost(String postId) async {
    try {
      await GroupService.instance.deletePost(postId);
      await _loadReal();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn\'t delete: $e')));
    }
  }

  void _closeMenus() {
    if (_memberMenu || _openPostMenu != null) {
      setState(() {
        _memberMenu = false;
        _openPostMenu = null;
      });
    }
  }

  /// Opens the read-only photo + comment-thread view for one group post.
  /// [groupName] must be set — it's what flips
  /// SinglePostDetailScreen._isGroupPost, which routes the reaction fetch
  /// and PostCommentCard at group_post_id instead of post_id.
  void _openGroupPostDetail(
    Map<String, dynamic> row, {
    required String groupName,
    bool locked = false,
  }) {
    final user = row['users'] as Map<String, dynamic>?;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SinglePostDetailScreen(
          item: FeedItem(
            postId: row['id'] as String,
            type: 'single',
            userId: row['user_id'] as String? ?? '',
            username: user?['name'] as String?,
            avatarUrl: user?['profile_photo_url'] as String?,
            caption: row['caption'] as String?,
            photoUrl: row['photo_url'] as String?,
            photos: (row['photo_urls'] as List?)?.cast<String>(),
            createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
            groupName: groupName,
            // Blurs photos 2+ and swaps the composer for "Be a friend to
            // comment" in the detail screen, same as a locked feed card.
            groupPostLocked: locked,
          ),
        ),
      ),
    );
  }

  /// Swipe RIGHT (finger moving left-to-right) pops back to the profile
  /// that opened this screen. Attached at the page level, not on any
  /// individual section, so a drag starting over the horizontal Members
  /// rail is resolved by that rail's own Scrollable first (nearer hit-test
  /// target wins) — this only fires for drags starting elsewhere on the
  /// page.
  void _handleSwipeBack(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 300) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (_isReal) return _buildReal();
    return _buildPage(
      widget.group,
      PV2Data.members,
      _mockPostsSection(widget.group),
    );
  }

  Widget _buildReal() {
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: PV2.page,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Couldn\'t load this group',
                  style: PV2.body(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: PV2.body(size: 11, color: PV2.inkStamp),
                ),
                const SizedBox(height: 14),
                NeuWell(
                  height: 42,
                  radius: 21,
                  shadows: PV2.insetStd,
                  border: PV2.hairlineActive,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  onTap: _loadReal,
                  child: Text(
                    'Retry',
                    style: PV2.body(size: 13, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final public = _public;
    if (public != null) {
      return _buildPublicPage(public);
    }
    final data = _real;
    if (data == null) {
      return const Scaffold(
        backgroundColor: PV2.page,
        body: Center(child: CircularProgressIndicator(color: PV2.accent)),
      );
    }

    final row = data.group;
    final name = (row['name'] as String?) ?? 'Group';
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
    final canDeleteAny = data.myRole == 'admin';
    final group = GroupProfile(
      name: name,
      // groups has no handle column — derived from the real name, same as
      // `initial` below, rather than left blank in a slot the design
      // always fills.
      handle: '@${name.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
      initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
      created: createdAt == null ? '' : _formatMonthYear(createdAt),
      // groups has no bio column — left blank rather than inventing flavor
      // text for a real group, unlike the mock's authored bio.
      bio: '',
      memberCount: data.members.length,
      // "Memories" is a mock-only concept (see class doc); for a real group
      // this stat and the section below it both mean the same thing: how
      // many group_posts exist. Reusing memoryCount for that count keeps
      // _stats untouched other than its label (see _buildPage).
      memoryCount: data.posts.length,
      dipCount: data.dips.length,
      // Real all-time distinct-viewer count (group_profile_views) — was a
      // hardcoded 0. Explicit request: profile context is all-time,
      // unlike the feed's own 3h live-presence badges.
      hereCount: _views ?? data.viewCount,
      iconUrl: row['icon_url'] as String?,
    );
    final dipCards = _dipCardsFromRows(data.dips);
    final members = [
      for (final m in data.members)
        _memberChipFromRow(m, myUserId: data.myUserId),
    ];
    final posts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 4),
          child: Row(
            children: [
              Expanded(
                child: SectionTitle(
                  title: 'Posts',
                  subtitle: '${data.posts.length} in the group',
                ),
              ),
              PillButton(
                label: 'Add',
                icon: PV2Icons.plus(12, Colors.white),
                onTap: _openAddPost,
              ),
            ],
          ),
        ),
        if (data.posts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(PV2.pad, 14, PV2.pad, 0),
            child: Text(
              'No posts yet',
              style: PV2.body(size: 12, color: PV2.inkStamp),
            ),
          )
        else
          Padding(
            // Group posts attached to the screen edges, same as the feed's
            // group cards (explicit request). PV2Page centres everything in
            // a PV2.columnWidth column, so the list breaks out of it to the
            // full screen width rather than sitting a few points in.
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
            child: OverflowBox(
              fit: OverflowBoxFit.deferToChild,
              minWidth: _postsWidth(context),
              maxWidth: _postsWidth(context),
              child: Column(
                children: [
                  for (var i = 0; i < data.posts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 22),
                    GroupProfilePostCard(
                      key: ValueKey(data.posts[i]['id']),
                      row: data.posts[i],
                      groupName: name,
                      canDelete:
                          canDeleteAny ||
                          data.posts[i]['user_id'] == data.myUserId,
                      menuOpen: _openPostMenu == data.posts[i]['id'],
                      onToggleMenu: () => setState(() {
                        final id = data.posts[i]['id'] as String;
                        _openPostMenu = _openPostMenu == id ? null : id;
                        _memberMenu = false;
                      }),
                      onDismissMenu: _closeMenus,
                      onDelete: () {
                        _closeMenus();
                        _deletePost(data.posts[i]['id'] as String);
                      },
                      onTap: () =>
                          _openGroupPostDetail(data.posts[i], groupName: name),
                      // Every member sets their OWN audience; the author
                      // included (they couldn't change theirs after posting).
                      onShare: () {
                        _closeMenus();
                        _sharePost(
                          data.posts[i]['id'] as String,
                          own: data.posts[i]['user_id'] == data.myUserId,
                        );
                      },
                      shareLabel: data.posts[i]['user_id'] == data.myUserId
                          ? 'Edit my audience'
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
    return _buildPage(
      group,
      members,
      posts,
      postsLabel: true,
      dips: dipCards,
      bannerUrl: row['banner_url'] as String?,
    );
  }

  String _formatMonthYear(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  MemberChip _memberChipFromRow(
    Map<String, dynamic> row, {
    required String myUserId,
  }) {
    final user = row['users'] as Map<String, dynamic>?;
    final name = (user?['name'] as String?) ?? 'member';
    // No presence system exists yet — every real member renders without
    // the "here" dot, rather than fabricating who's currently active.
    return MemberChip(
      name: name,
      color: kFaceSwatches[name.hashCode.abs() % kFaceSwatches.length],
      here: false,
      userId: row['user_id'] as String?,
      avatarUrl: user?['profile_photo_url'] as String?,
    );
  }

  Widget _mockPostsSection(GroupProfile group) => _memoriesSection(group);

  /// Converts real `dips` rows (DipService.fetchDips) into the same
  /// [DipCard] shape the mock rail already renders — only the data source
  /// changes, not the visual language (see _dipCard for the photo-vs-color
  /// fallback this enables).
  List<DipCard> _dipCardsFromRows(List<Map<String, dynamic>> rows) {
    return [
      for (final row in rows)
        DipCard(
          color: PV2.amber.withValues(alpha: 0.18),
          byColor:
              kFaceSwatches[((row['user_id'] as String?)?.hashCode.abs() ?? 0) %
                  kFaceSwatches.length],
          by: ((row['users'] as Map?)?['name'] as String?) ?? 'member',
          left: _dipTimeLeft(row['expires_at'] as String?),
          tilt: _dipTilt(row['id'] as String?),
          photoUrl: row['photo_url'] as String?,
          caption: (row['caption'] as String?)?.trim(),
          posterAvatarUrl:
              (row['users'] as Map?)?['profile_photo_url'] as String?,
          postedAgo: formatRelativeTime(
            row['created_at'] != null
                ? DateTime.tryParse(row['created_at'] as String)
                : null,
            withAgo: true,
          ),
        ),
    ];
  }

  /// Countdown from the real `expires_at` column — server truth, unlike
  /// Moments' `momentTimeLeft` (moment_card.dart), which guesses a fixed
  /// 24h from `created_at` with no backing column at all.
  String _dipTimeLeft(String? expiresAtIso) {
    final expiresAt = expiresAtIso == null
        ? null
        : DateTime.tryParse(expiresAtIso);
    if (expiresAt == null) return '';
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return 'ending';
    if (remaining.inHours >= 1) return '${remaining.inHours}h';
    if (remaining.inMinutes >= 1) return '${remaining.inMinutes}m';
    return 'ending';
  }

  /// Deterministic per-row scatter angle so cards don't jump on rebuild.
  double _dipTilt(String? id) {
    final h = (id ?? '').hashCode.abs();
    return ((h % 7) - 3) * 0.9;
  }

  /// Full-screen photo + poster + timestamp, nothing else — no reply/react,
  /// per spec. A Dip has no comment thread of its own (unlike a group post,
  /// see _openGroupPostDetail's SinglePostDetailScreen), so this is a
  /// standalone view rather than a variant of that screen.
  void _openDipDetail(DipCard dip) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _DipDetailScreen(dip: dip)));
  }

  // --- non-member (limited) view --------------------------------------

  /// The entire limited view a non-member sees: identity + roster with
  /// streaks. No Dip section, no Posts section, no add/delete/add-people
  /// actions — those widgets are never built here, not merely hidden, so
  /// there's nothing member-only for a non-member to reach.
  Widget _buildPublicPage(_PublicGroupData data) {
    return GestureDetector(
      onHorizontalDragEnd: _handleSwipeBack,
      behavior: HitTestBehavior.translucent,
      child: PV2Page(
        // Taller banner — explicit request with a reference screenshot showing
        // it filling roughly the top half of the screen. Safe to change on its
        // own: PV2Page's own doc notes backdrop height and panel pull-up are
        // tuned as a PAIR, and growing the height while holding the pull-up
        // keeps the identity panel's overlap constant, so nothing below shifts.
        backdropHeight: 390,
        pullUp: 92,
        gradient: PV2.backdrops[widget.backdropIndex % PV2.backdrops.length],
        washX: 0.22,
        washY: 0.10,
        fadeHeight: 140,
        extraBottomInset: widget.extraBottomInset,
        chrome: [
          if (widget.showBackButton)
            Positioned(
              top: 16,
              left: 16,
              child: ChromeButton(
                icon: PV2Icons.back(24, Colors.white),
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
        ],
        children: [
          IdentityPanel(child: _publicIdentity(data)),
          const SizedBox(height: 19),
          Padding(
            padding: const EdgeInsets.fromLTRB(PV2.gutter, 12, PV2.gutter, 0),
            child: Row(
              children: [
                Expanded(child: _stat('${data.memberCount}', 'MEMBERS')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 12),
            child: SectionTitle(
              title: 'Members',
              // Subtitle removed with the Dip streak it described ("streak
              // resets after a day with no dip") — that mechanic is gone as
              // of migration 20260914030000_streak_system_v4. The group's
              // shared ping streak that replaced it is a MEMBER-only
              // surface, so this non-member view shows no streak line at
              // all rather than a rule that no longer applies.
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 0),
            child: Column(
              children: [
                for (var i = 0; i < data.members.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _publicMemberRow(data.members[i]),
                ],
              ],
            ),
          ),
          // The posts this viewer is permitted to see — shared to them in
          // full, a private group's first photo only (locked). Same card and
          // full-bleed layout members get; no delete/share menu, since a
          // non-member can do neither.
          if (data.posts.isNotEmpty) ...[
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 0),
              child: SectionTitle(
                title: 'Posts',
                subtitle: '${data.posts.length} you can see',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
              child: OverflowBox(
                fit: OverflowBoxFit.deferToChild,
                minWidth: _postsWidth(context),
                maxWidth: _postsWidth(context),
                child: Column(
                  children: [
                    for (var i = 0; i < data.posts.length; i++) ...[
                      if (i > 0) const SizedBox(height: 22),
                      GroupProfilePostCard(
                        key: ValueKey(data.posts[i]['id']),
                        row: data.posts[i],
                        groupName: data.name,
                        canDelete: false,
                        // A visitor, not a member: no seen pill.
                        showSeen: false,
                        menuOpen: false,
                        onToggleMenu: () {},
                        onDismissMenu: () {},
                        onDelete: () {},
                        locked: data.posts[i]['locked'] == true,
                        onTap: () => _openGroupPostDetail(
                          data.posts[i],
                          groupName: data.name,
                          locked: data.posts[i]['locked'] == true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _publicIdentity(_PublicGroupData data) {
    final initial = data.name.isNotEmpty ? data.name[0].toUpperCase() : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                data.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PV2.display(size: 26, letterSpacing: -0.55, height: 1.1),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: kGroupGradients[0],
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x99000000),
                    offset: Offset(0, 8),
                    blurRadius: 20,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.2),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: data.iconUrl == null
                  ? Text(initial, style: PV2.display(size: 25))
                  // Press-and-hold to see the group DP big.
                  : AvatarPeek(
                      imageUrl: data.iconUrl,
                      child: CachedNetworkImage(
                        memCacheWidth: 186,
                        imageUrl: data.iconUrl!,
                        width: 62,
                        height: 62,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        _amberPill(
          height: 24,
          leading: PV2Icons.lock(11, PV2.amber),
          label: 'not a member · dips hidden',
          fontSize: 9.5,
          weight: FontWeight.w700,
        ),
      ],
    );
  }

  Widget _publicMemberRow(_PublicMember member) {
    final initial = member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';
    return NeuCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color:
                  kFaceSwatches[member.name.hashCode.abs() %
                      kFaceSwatches.length],
              shape: BoxShape.circle,
            ),
            child: member.photoUrl == null
                ? Text(
                    initial,
                    style: PV2.body(size: 14, weight: FontWeight.w700),
                  )
                : CachedNetworkImage(
                    memCacheWidth: 120,
                    imageUrl: member.photoUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PV2.body(size: 13.5, weight: FontWeight.w600),
            ),
          ),
          _amberPill(
            height: 22,
            leading: PV2Icons.streak(11, PV2.streakBlue),
            label: '${member.streak}d',
            fontSize: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildPage(
    GroupProfile group,
    List<MemberChip> members,
    Widget postsSection, {
    bool postsLabel = false,
    List<DipCard> dips = PV2Data.dips,
    String? bannerUrl,
  }) {
    return GestureDetector(
      onHorizontalDragEnd: _handleSwipeBack,
      behavior: HitTestBehavior.translucent,
      child: PV2Page(
        // Taller banner — explicit request with a reference screenshot showing
        // it filling roughly the top half of the screen. Safe to change on its
        // own: PV2Page's own doc notes backdrop height and panel pull-up are
        // tuned as a PAIR, and growing the height while holding the pull-up
        // keeps the identity panel's overlap constant, so nothing below shifts.
        backdropHeight: 390,
        pullUp: 92,
        gradient: PV2.backdrops[widget.backdropIndex % PV2.backdrops.length],
        // Mirrored from the person profile's 78%/8% so the two screens don't
        // read as the same surface when you navigate between them.
        washX: 0.22,
        washY: 0.10,
        fadeHeight: 140,
        bannerUrl: bannerUrl,
        extraBottomInset: widget.extraBottomInset,
        // Group posts are attached to the screen edges (see postsSection).
        allowFullBleed: true,
        onScroll: _closeMenus,
        chrome: [
          if (widget.showBackButton)
            Positioned(
              top: 16,
              left: 16,
              child: ChromeButton(
                icon: PV2Icons.back(24, Colors.white),
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          // QR — promoted onto the banner itself (explicit ask: "group qr
          // in its banner as a widget"). Shown on EVERY group now, private
          // included ("qr to join the group ... in each group's banner"):
          // the code carries a members-only join code, checked by
          // join_group_by_code (20260927000000_group_qr_join_codes.sql).
          if (_isReal && widget.groupId != null)
            Positioned(
              top: 16,
              right: 16,
              child: ChromeButton(
                icon: const Icon(
                  Icons.qr_code_2_rounded,
                  size: 20,
                  color: Colors.white,
                ),
                onTap: () => showGroupQrSheet(
                  context,
                  groupId: widget.groupId!,
                  groupName: _real?.group['name'] as String? ?? 'this group',
                ),
              ),
            ),
          if (_isReal)
            Positioned(
              left: 16,
              bottom: 104,
              child: GlassSurface(
                radius: 17,
                height: 34,
                fill: const Color(0x8008080A),
                border: const Color(0x1FFFFFFF),
                padding: const EdgeInsets.only(left: 10, right: 13),
                onTap: _pickGroupBanner,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_bannerUploading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      PV2Icons.camera(14, Colors.white),
                    const SizedBox(width: 7),
                    Text(
                      'Banner',
                      style: PV2.body(size: 11.5, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
        ],
        children: [
          IdentityPanel(child: _identity(group)),
          _stats(group, memoriesLabel: postsLabel ? 'POSTS' : 'MEMORIES'),
          // BLUE 2 — the group's shared, all-or-nothing ping streak. Member
          // view only; a non-member's RPC call returns nothing, so this is
          // absent there by construction rather than by a UI check.
          _sharedStreakCard(),
          const SizedBox(height: 19),
          _membersSection(members, group: group),
          const SizedBox(height: 28),
          // Dip is hidden app-wide for now (explicit request) — the section
          // widget, _addDip, DipService and the rows themselves are all left
          // intact, so restoring it is uncommenting this one line.
          //   _dipSection(group, dips),
          //   const SizedBox(height: 22),
          postsSection,
        ],
      ),
    );
  }

  /// BLUE 2 — the group's shared ping streak, plus today's live progress.
  ///
  /// Blue, not the personal-streak red: the two colours are the whole
  /// vocabulary of this system (red = your own anon streak, blue =
  /// relationship streaks), so the colour alone tells you which kind of
  /// number you're looking at.
  ///
  /// Today's "N/M replied" line is the point of showing this at all. The
  /// streak is all-or-nothing — one member not replying resets it to zero
  /// for everyone — so the group needs to see the shortfall while there's
  /// still time to fix it, not discover it the next morning.
  /// Edge-to-edge width for the attached post list, capped at the page
  /// column. Wider than the column (a >430pt screen) the cards spilled past
  /// their parent's bounds, and Flutter drops taps there — the right-edge
  /// "..." menu couldn't be opened at all.
  double _postsWidth(BuildContext context) =>
      math.min(MediaQuery.sizeOf(context).width, PV2.columnWidth);

  Widget _sharedStreakCard() {
    final s = _pingStreak;
    // Nothing to say yet: not a member, still loading, or a group that has
    // never run a daily ping. Never render a bare 0 — same rule the rest of
    // this app follows for counts.
    if (s == null || (s.current == 0 && !s.todayOpen)) {
      return const SizedBox.shrink();
    }
    final complete = s.todayComplete;
    return Padding(
      padding: const EdgeInsets.fromLTRB(PV2.pad, 14, PV2.pad, 0),
      child: NeuWell(
        radius: 16,
        shadows: PV2.insetStd,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        width: double.infinity,
        child: Row(
          children: [
            // BLUE — a relationship streak. Same pill every other streak
            // in the app uses (StreakFlamePill), so this reads as the same
            // kind of number here as on a profile or the ping page.
            StreakFlamePill(
              count: s.current,
              size: 14,
              label: s.current == 1 ? 'day together' : 'days together',
            ),
            const Spacer(),
            if (s.todayOpen)
              Text(
                complete
                    ? 'today is safe'
                    : '${s.todayReplied}/${s.todayTotal} replied today',
                style: PV2.body(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: complete ? PV2.accent : PV2.amber,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- identity -----------------------------------------------------------

  Widget _identity(GroupProfile group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PV2.display(
                      size: 26,
                      letterSpacing: -0.55,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${group.handle} · since ${group.created}',
                    style: PV2.mono(size: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // The DP itself is the setter — explicit instruction: "the dp
            // setter shall be on the p image as such, not to the banner".
            // The separate "Group photo" chip that used to sit over the
            // banner is gone; tapping the tile picks the photo, and the
            // tile is also the only place the chosen photo was never shown
            // (this rendered group.initial unconditionally, so an uploaded
            // DP was invisible here even though it had saved fine).
            GestureDetector(
              onTap: _isReal ? _pickGroupIcon : null,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      gradient: kGroupGradients[0],
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        const BoxShadow(
                          color: Color(0x99000000),
                          offset: Offset(0, 8),
                          blurRadius: 20,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.2),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: _iconUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : (group.iconUrl == null || group.iconUrl!.isEmpty)
                        ? Text(group.initial, style: PV2.display(size: 25))
                        // Press-and-hold to see the group DP big; a tap
                        // still does what it did (change the DP).
                        : AvatarPeek(
                            imageUrl: group.iconUrl,
                            child: CachedNetworkImage(
                              imageUrl: group.iconUrl!,
                              width: 62,
                              height: 62,
                              fit: BoxFit.cover,
                              memCacheWidth: 186,
                              errorWidget: (_, _, _) => Text(
                                group.initial,
                                style: PV2.display(size: 25),
                              ),
                            ),
                          ),
                  ),
                  // Small camera badge, so the tile reads as editable
                  // rather than as a plain avatar.
                  if (_isReal && !_iconUploading)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xE608080A),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: PV2Icons.camera(12, Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          group.bio,
          style: PV2.body(size: 14.5, color: PV2.inkBio, height: 1.5),
        ),
        const SizedBox(height: 16),
        // The send/more icon buttons that used to sit beside "Add people"
        // were both onTap: () {} no-ops — removed per item #4, not
        // load-bearing. AccentButton now spans the full row on its own.
        Row(
          children: [
            Expanded(
              child: AccentButton(
                label: 'Add people',
                icon: PV2Icons.addPeople(17, Colors.white),
                // Null (inert) on the mock/gallery path — there's no real
                // group to add anyone to there (see GroupProfileV2Screen's
                // own doc on widget.groupId).
                onTap: _isReal ? _addMembers : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- stats --------------------------------------------------------------

  Widget _stats(GroupProfile group, {String memoriesLabel = 'MEMORIES'}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PV2.gutter, 12, PV2.gutter, 0),
      child: Row(
        children: [
          Expanded(child: _stat('${group.memberCount}', 'MEMBERS')),
          const SizedBox(width: 9),
          Expanded(child: _stat('${group.memoryCount}', memoriesLabel)),
          // The amber "DIPS LIVE" tile goes with the rest of Dip while it's
          // hidden — a live-dip counter reading 0 with no way to add one, and
          // no section below it, is worse than no tile. Restored alongside
          // _dipSection when Dip comes back.
          //   const SizedBox(width: 9),
          //   Expanded(
          //     child: _stat(
          //       '${group.dipCount}',
          //       'DIPS LIVE',
          //       valueColor: PV2.amber,
          //       border: PV2.amber.withValues(alpha: 0.16),
          //       glow: PV2.amber.withValues(alpha: 0.05),
          //     ),
          //   ),
        ],
      ),
    );
  }

  Widget _stat(
    String value,
    String label, {
    Color valueColor = Colors.white,
    Color border = PV2.hairline,
    Color? glow,
  }) {
    return NeuCard(
      border: border,
      innerGlow: glow,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: PV2.display(size: 22, color: valueColor, height: 1),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: PV2.caps(size: 8.5, tracking: 0.11),
          ),
        ],
      ),
    );
  }

  // --- members ------------------------------------------------------------

  Widget _membersSection(
    List<MemberChip> members, {
    required GroupProfile group,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ping All heads the members section: pinging the group is the primary
        // thing you come here to do, and it is one action rather than six.
        // Members only: _real is loaded only for a member (non-members get the
        // public tier, _public). send_group_ping refuses non-members anyway;
        // this just stops showing them a button that can't work.
        if (_real != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              // Only real groups have a groupId to fan a ping out to — the
              // mock-data preview path (widget.groupId == null) leaves this
              // inert rather than pretending to send anything.
              onTap: !_isReal
                  ? null
                  // Instant, promptless (2026-09-30) — no prompt sheet.
                  : () async {
                      int count;
                      try {
                        count = await PingService.instance.sendGroupPing(
                          groupId: widget.groupId!,
                          prompt: '',
                        );
                      } on PingGroupWaitingForMembers catch (e) {
                        if (mounted) {
                          showPingToast(context, e.toString(), isError: true);
                        }
                        return;
                      } on PingLimitExceeded catch (e) {
                        if (mounted) {
                          showPingToast(context, e.toString(), isError: true);
                        }
                        return;
                      } catch (_) {
                        if (mounted) {
                          showPingToast(
                            context,
                            "Couldn't send that ping.",
                            isError: true,
                          );
                        }
                        return;
                      }
                      if (!mounted) return;
                      showPingToast(
                        context,
                        count > 0
                            ? 'Pinged ${group.name} ✓'
                            : 'No one else to ping yet',
                      );
                      // Same flow as every group ping: the Ping tab, on
                      // its wall.
                      if (count > 0) {
                        groupWallAnswerRequest.value = widget.groupId;
                      }
                    },
              borderRadius: BorderRadius.circular(23),
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: PV2.accentButton,
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: PV2.accent.withValues(alpha: 0.4),
                      offset: const Offset(0, 6),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PingGlyph(
                      size: 18,
                      color: PV2.onAccent,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'Ping All Members',
                      style: PV2.display(size: 15, color: PV2.onAccent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionTitle(title: 'Members'),
              PV2MenuAnchor(
                open: _memberMenu,
                onDismiss: _closeMenus,
                offset: const Offset(0, 6),
                menu: _memberMenuPanel(),
                child: GestureDetector(
                  onTap: () => setState(() => _memberMenu = !_memberMenu),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: PV2Icons.more(
                      15,
                      Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Rail(
          gap: 13,
          children: [for (final member in members) _memberItem(member)],
        ),
      ],
    );
  }

  /// Group administration. Both leaving and destroying are destructive and sit
  /// below a divider; Destroy Group additionally carries an ADMIN badge, since
  /// it is the one action here that not every member can take.
  Widget _memberMenuPanel() {
    return PV2MenuPanel(
      width: 190,
      border: PV2.menuBorderStrong,
      children: [
        PV2MenuItem(
          icon: Icons.group_add_outlined,
          label: 'Add Member',
          iconSize: 15,
          fontSize: 13,
          gap: 9,
          radius: 11,
          // Was `onTap: _closeMenus` — it dismissed the panel and did
          // nothing else, so this menu entry was purely decorative while
          // the "Add people" button elsewhere on the screen did the real
          // work. Same handler now, same _isReal guard that button uses
          // (a design-preview group has no id to add anyone to).
          onTap: _isReal
              ? () {
                  _closeMenus();
                  _addMembers();
                }
              : _closeMenus,
        ),
        // Group QR Code moved to its own banner-chrome button (top-right,
        // same public-only gate) — see this screen's build() chrome list.
        // It only appears once the group below is actually made public.
        if (_isGroupAdmin)
          PV2MenuItem(
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Rename Group',
            iconSize: 15,
            fontSize: 13,
            gap: 9,
            radius: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            trailing: const PV2AdminBadge(),
            onTap: () {
              _closeMenus();
              _renameGroup();
            },
          ),
        if (_isGroupAdmin)
          PV2MenuItem(
            icon: _real?.group['visibility'] == 'public'
                ? Icons.lock_outline_rounded
                : Icons.public_rounded,
            label: _real?.group['visibility'] == 'public'
                ? 'Make Private'
                : 'Make Public',
            iconSize: 15,
            fontSize: 13,
            gap: 9,
            radius: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            trailing: const PV2AdminBadge(),
            onTap: () {
              _closeMenus();
              _setGroupVisibility(_real?.group['visibility'] != 'public');
            },
          ),
        const PV2MenuDivider(inset: 3),
        PV2MenuItem(
          icon: Icons.logout_rounded,
          label: 'Exit Group',
          iconSize: 15,
          fontSize: 13,
          gap: 9,
          radius: 11,
          destructive: true,
          // Was a dead stub (closed the menu and nothing else) — now really
          // leaves, via the same GroupService.leaveGroup any member is
          // allowed to call (RLS: remove_members, own row).
          onTap: () {
            _closeMenus();
            _confirmExitGroup();
          },
        ),
        PV2MenuItem(
          icon: Icons.delete_outline_rounded,
          label: 'Destroy Group',
          iconSize: 15,
          fontSize: 13,
          gap: 8,
          radius: 11,
          // Tighter horizontal padding than its siblings: this is the only
          // row carrying a trailing badge, and at the panel's width the
          // default padding truncates the label.
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          destructive: true,
          trailing: const PV2AdminBadge(),
          onTap: () {
            _closeMenus();
            _confirmDestroyGroup();
          },
        ),
      ],
    );
  }

  Widget _memberItem(MemberChip member) {
    return GestureDetector(
      // Was a stray Navigator.maybePop() — leftover placeholder behaviour
      // (tapping a member's avatar closed the screen you were on). Real
      // members carry a userId now (see _memberChipFromRow); tapping opens
      // their profile the same way every other avatar in the app does.
      // Mock rows (userId == null) stay inert rather than guessing.
      onTap: member.userId == null
          ? null
          : () => openProfile(context, member.userId!),
      // Admin-only: press and hold a member to remove them from the group.
      // Deliberately long-press rather than a visible X on every tile —
      // removal is destructive and shouldn't sit one stray tap away in a
      // horizontally-scrolling rail.
      onLongPress:
          (!_isGroupAdmin ||
              member.userId == null ||
              member.userId == _real?.myUserId)
          ? null
          : () {
              HapticFeedback.mediumImpact();
              _confirmRemoveMember(member);
            },
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: member.color,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          offset: Offset(4, 4),
                          blurRadius: 11,
                        ),
                      ],
                    ),
                    // The member's real photo. Was a bare coloured disc, so
                    // every member in the roster looked identical.
                    child: (member.avatarUrl ?? '').isEmpty
                        ? Text(
                            member.name.isEmpty
                                ? '?'
                                : member.name[0].toUpperCase(),
                            style: PV2.display(size: 21),
                          )
                        : CachedNetworkImage(
                            memCacheWidth: 174,
                            imageUrl: member.avatarUrl!,
                            fit: BoxFit.cover,
                            width: 58,
                            height: 58,
                            errorWidget: (_, _, _) => Text(
                              member.name.isEmpty
                                  ? '?'
                                  : member.name[0].toUpperCase(),
                              style: PV2.display(size: 21),
                            ),
                          ),
                  ),
                  if (member.here)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: PV2.page, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.7),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Removal used to be long-press ONLY, which meant an
                  // admin had no way to discover it existed. Explicit
                  // request: "give option to... remove members by the admin
                  // only". The long-press still works; this makes it
                  // visible. Admins only, never on your own tile.
                  if (_isGroupAdmin &&
                      member.userId != null &&
                      member.userId != _real?.myUserId)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => _confirmRemoveMember(member),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 19,
                          height: 19,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: PV2.page,
                            shape: BoxShape.circle,
                            border: Border.all(color: PV2.menuBorderStrong),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: PV2.danger,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // BLUE 3, under this member's DP — their own consecutive-days
            // streak of answering the group's daily ping ("here the blue
            // flame under personal dp"). Independent of the group's shared
            // number above: you keep your own run even on a day the group
            // as a whole broke it.
            if ((_memberStreaks[member.userId] ?? 0) > 0) ...[
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PV2Icons.iceFlame(10),
                  const SizedBox(width: 2),
                  Text(
                    '${_memberStreaks[member.userId]}',
                    style: PV2.body(
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: PV2.streakBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
            ] else
              const SizedBox(height: 7),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PV2.body(
                size: 10,
                weight: FontWeight.w600,
                color: PV2.inkMember,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- dip ----------------------------------------------------------------

  // Deliberately kept while Dip is hidden from the UI (see the commented-out
  // call in the body above) so bringing the feature back is uncommenting one
  // line, not rewriting this section. Remove the ignore when it returns.
  // ignore: unused_element
  Widget _dipSection(GroupProfile group, List<DipCard> dips) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Dip',
                          style: PV2.display(size: 18, letterSpacing: -0.2),
                        ),
                        const SizedBox(width: 8),
                        _amberPill(
                          height: 19,
                          leading: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: PV2.amber,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: PV2.amber.withValues(alpha: 0.9),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          label: '${group.dipCount} live',
                          fontSize: 9.5,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Gone in a day · never saved to memories',
                      style: PV2.body(size: 11, color: PV2.inkSub),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _amberPill(
                height: 24,
                leading: PV2Icons.lock(11, PV2.amber),
                label: 'members only',
                fontSize: 9.5,
                weight: FontWeight.w700,
              ),
            ],
          ),
        ),
        Rail(
          gap: 10,
          padding: const EdgeInsets.fromLTRB(PV2.pad, 12, PV2.pad, 8),
          children: [_dipAddTile(), for (final dip in dips) _dipCard(dip)],
        ),
      ],
    );
  }

  Widget _amberPill({
    required double height,
    required Widget leading,
    required String label,
    required double fontSize,
    FontWeight weight = FontWeight.w800,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 6, right: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PV2.amber.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: PV2.amber.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 5),
          Text(
            label,
            style: PV2.body(size: fontSize, weight: weight, color: PV2.amber),
          ),
        ],
      ),
    );
  }

  Widget _dipAddTile() {
    return SizedBox(
      width: 92,
      height: 92 * 4 / 3,
      child: DashedBox(
        radius: 22,
        color: PV2.amber.withValues(alpha: 0.32),
        child: NeuWell(
          radius: 22,
          shadows: PV2.insetDeep,
          // Inert on the mock/gallery path — there's no real group to post
          // a dip into there, same reasoning as "Add people" above.
          onTap: _isReal ? _addDip : null,
          // No local loading state — pushing the composer route replaces
          // this tile's own affordance with the composer's camera/confirm/
          // reward UI, which owns the whole capture-to-upload lifecycle.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              PV2Icons.camera(22, PV2.amber),
              const SizedBox(height: 8),
              Text(
                'drop a dip',
                style: PV2.body(
                  size: 10,
                  weight: FontWeight.w800,
                  color: PV2.amber.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dipCard(DipCard dip) {
    return GestureDetector(
      onTap: () => _openDipDetail(dip),
      child: Tilted(
        degrees: dip.tilt,
        child: SizedBox(
          width: 92,
          height: 92 * 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dip.color,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x8C000000),
                    offset: Offset(5, 7),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  if (dip.photoUrl != null)
                    Positioned.fill(
                      child: CachedNetworkImage(
                        memCacheWidth: 1080,
                        imageUrl: dip.photoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: PV2.tileScrim),
                    ),
                  ),
                  Positioned(
                    top: 7,
                    left: 7,
                    child: GlassSurface(
                      radius: 10,
                      height: 19,
                      blur: 8,
                      fill: const Color(0x9E04070A),
                      border: Colors.transparent,
                      padding: const EdgeInsets.only(left: 6, right: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: PV2.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dip.left,
                            style: PV2.body(
                              size: 9,
                              weight: FontWeight.w800,
                              color: PV2.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: dip.byColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          dip.by,
                          style: PV2.body(
                            size: 9.5,
                            weight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- memories -----------------------------------------------------------

  Widget _memoriesSection(GroupProfile group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 4),
          child: Row(
            children: [
              Expanded(
                child: SectionTitle(
                  title: 'Memories',
                  subtitle: 'Kept forever · ${group.memoryCount} in the box',
                ),
              ),
              PillButton(
                label: 'Add',
                icon: PV2Icons.plus(12, Colors.white),
                onTap: () {},
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 14, PV2.pad, 0),
          child: Column(
            children: [
              for (var i = 0; i < PV2Data.memories.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _memory(PV2Data.memories[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _memory(MemoryCard memory) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date spine — a recessed day/month tile beside the title, so a long
        // list of memories scans by date at a glance.
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(
            children: [
              NeuWell(
                width: 42,
                height: 42,
                radius: 14,
                shadows: PV2.insetStd,
                border: PV2.hairlinePanel,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(memory.day, style: PV2.display(size: 15, height: 1)),
                    const SizedBox(height: 2),
                    Text(
                      memory.month.toUpperCase(),
                      style: PV2.caps(
                        size: 7.5,
                        tracking: 0.12,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      memory.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PV2.body(
                        size: 14.5,
                        weight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${memory.weekday} · ${memory.time}',
                      style: PV2.mono(size: 10.5, color: PV2.inkCount),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        NeuCard(
          radius: 24,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _memoryGrid(memory),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          PV2Icons.place(13, Colors.white),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              memory.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PV2.body(
                                size: 12.5,
                                weight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FaceStack(colors: memory.faces),
                    if (memory.attendees > 0) ...[
                      const SizedBox(width: 7),
                      Text(
                        '${memory.attendees} here',
                        style: PV2.mono(size: 10.5, color: PV2.inkCount),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The four collage arrangements. Each is a distinct shape rather than a
  /// styling variant — see the class doc.
  /// A uniform 2-column photo grid. Replaced the four collage arrangements
  /// (float/mosaic/stack/strip) when collages were removed app-wide —
  /// memories are a browsing surface, so every card reads the same way and
  /// nothing is hidden behind a swipe. Falls back to the mock swatches when
  /// a memory has no real photos yet.
  Widget _memoryGrid(MemoryCard memory) {
    final urls = memory.photoUrls;
    final hasReal = urls != null && urls.isNotEmpty;
    final count = hasReal ? urls.length : memory.swatches.length;

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < count; i++)
          hasReal
              ? CachedNetworkImage(
                  memCacheWidth: 1080,
                  imageUrl: urls[i],
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => ColoredBox(
                    color: memory.swatches[i % memory.swatches.length],
                  ),
                )
              : ColoredBox(color: memory.swatches[i]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dip detail — a clean full-screen viewer: the photo, who posted it, and
// when. No reply/react, no comment thread — a Dip is casual and ephemeral,
// not a place for a discussion the way a group post is.
// ---------------------------------------------------------------------------

class _DipDetailScreen extends StatelessWidget {
  const _DipDetailScreen({required this.dip});
  final DipCard dip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: dip.photoUrl == null
                  ? ColoredBox(color: dip.color)
                  : CachedNetworkImage(
                      memCacheWidth: 1080,
                      imageUrl: dip.photoUrl!,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => ColoredBox(color: dip.color),
                    ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: GlassSurface(
                radius: 22,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipOval(
                      child: dip.posterAvatarUrl == null
                          ? Container(width: 36, height: 36, color: dip.byColor)
                          : CachedNetworkImage(
                              memCacheWidth: 108,
                              imageUrl: dip.posterAvatarUrl!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(
                                width: 36,
                                height: 36,
                                color: dip.byColor,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dip.by,
                            style: PV2.body(
                              size: 14,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (dip.postedAgo != null)
                            Text(
                              dip.postedAgo!,
                              style: PV2.body(
                                size: 11.5,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          // The note typed in the composer's Dip box. Sits
                          // under the byline rather than over the photo so a
                          // long one wraps into the sheet instead of
                          // covering the picture it describes. Expanded so
                          // that wrap has a width to wrap INTO — without it
                          // the Row would let this Column size to its
                          // longest line and overflow.
                          if (dip.caption != null && dip.caption!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                dip.caption!,
                                style: PV2.body(
                                  size: 13,
                                  color: Colors.white.withValues(alpha: 0.86),
                                  height: 1.35,
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
          ],
        ),
      ),
    );
  }
}
