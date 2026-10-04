import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/postgrest_search.dart';
import '../core/supabase_config.dart';
import 'block_service.dart';
import 'current_user_service.dart';
import 'storage_service.dart';

/// Real user-created groups: a name + icon, an admin/member roster, and a
/// shared photo album (`group_posts`). Distinct from `communities`
/// (moderator-only creation, no roles) and from the old GroupService
/// placeholder (renamed to CommunityPhotosService — see that file), which
/// reads community-scoped posts and has nothing to do with named groups.
///
/// Role rules (enforced both here and, redundantly but authoritatively, by
/// the RLS policies in supabase/schema.sql):
///  - admin: add/remove members, delete any post, edit group info, delete
///    the group.
///  - member: post to the group, delete their own posts, leave.
class GroupService {
  /// Read timeout, matching every other service in this app.
  ///
  /// This file had NONE. The group profile awaits six of these calls
  /// with no deadline, so one stalled request left the screen on its
  /// spinner forever — no error, and therefore no Retry button either,
  /// since that only renders once _loadError is set.
  static const _kRead = Duration(seconds: 10);

  GroupService._();
  static final instance = GroupService._();

  static const _adminRole = 'admin';

  // ---------------------------------------------------------------------------
  // Group lifecycle
  // ---------------------------------------------------------------------------

  /// Creates a group, makes the caller its admin, and adds [memberUserIds]
  /// (if any) as regular members. Returns the new group's id.
  ///
  /// Two inserts, not one — Postgres can't atomically insert into `groups`
  /// and `group_members` together without a database function, and this
  /// app doesn't otherwise use RPC functions (grepped: none exist). The
  /// `group_members_insert_first_admin` RLS policy is what makes the
  /// creator's own admin row insertable even though no admin row exists
  /// yet to satisfy the normal "an admin added you" check.
  ///
  /// The id is generated client-side rather than read back via
  /// `.select().single()` (which sends `Prefer: return=representation`).
  /// Requesting the row back on INSERT makes Postgres also enforce the
  /// table's SELECT policy on the new row, not just the INSERT policy's
  /// WITH CHECK — and `groups_select` requires an existing `group_members`
  /// row, which by design doesn't exist until the *next* insert below. That
  /// was a real, confirmed-live bug (belt-and-suspenders fix here even
  /// though the RLS policy itself has also been corrected server-side).
  Future<String> createGroup({
    required String name,
    File? iconFile,
    List<String> memberUserIds = const [],
    // Blurred Group Teaser feature: 'public' groups can be self-joined by
    // any community member (see self_join_public_group RLS policy);
    // 'private' — the default, matching every group created before this
    // column existed — can only ever gain a member via an existing member
    // or admin adding them.
    String visibility = 'private',
  }) async {
    assert(visibility == 'public' || visibility == 'private');
    final creatorId = await CurrentUserService.instance.resolveId();

    // Blurred Group Teaser (group_posts_teaser_for_community) joins on
    // groups.community_id and was never set anywhere — every group made
    // through this method had it NULL, so the teaser silently matched zero
    // rows for every group regardless of visibility. The function itself
    // has no visibility check at all (teaser is not a public-groups-only
    // thing, unlike the QR/self-join), so the ONLY gap was this column
    // never being populated. Earliest-joined community is an assumption
    // (most creators belong to exactly one), not a real "primary community"
    // concept — revisit if a creator ever needs to pick explicitly.
    //
    // community_members.user_id is the AUTH id (auth.uid()), not
    // users.id — confirmed live (every row's user_id matched
    // supabase.auth.currentUser?.id, not the resolved app-side creatorId
    // above). Filtering by creatorId here silently matched nothing.
    //
    // Must exclude soft-deleted communities (communities.deleted_at) —
    // confirmed live this was the actual reason the very first backfill
    // attempt at this feature produced a group nobody could ever discover:
    // "earliest joined" landed on old deactivated test communities almost
    // every time (deleted_at IS NOT NULL), and the CLIENT's own "my
    // communities" list (fetchJoinedCommunities) correctly filters those
    // out — so a group pointed at one was invisible to the teaser fetch
    // even though the RPC itself doesn't check deleted_at and would have
    // happily returned rows for it if anything had ever asked.
    final authId = supabase.auth.currentUser?.id;
    final myCommunities = authId == null
        ? const <Map<String, dynamic>>[]
        : await supabase
              .from('community_members')
              .select('community_id, communities!inner(deleted_at)')
              .eq('user_id', authId)
              .isFilter('communities.deleted_at', null)
              .order('joined_at')
              .limit(1);
    final communityId = myCommunities.isEmpty
        ? null
        : myCommunities.first['community_id'] as String?;
    // Server-side backstop for CreateGroupScreen's own check — "minimum
    // criteria for making a group is 2 members." The creator is always
    // added as the 1st member below, so this is what makes at least 2 true;
    // checked against the filtered set (creatorId excluded), same as the
    // insert loop below uses, so a caller that accidentally includes their
    // own id doesn't get a false pass. Enforced here too so no other/
    // future call site can silently create a group of one.
    if (memberUserIds.where((id) => id != creatorId).isEmpty) {
      throw StateError('A group needs at least one other member.');
    }
    final groupId = const Uuid().v4();

    await supabase.from('groups').insert({
      'id': groupId,
      'name': name,
      'created_by': creatorId,
      'visibility': visibility,
      'community_id': communityId,
    });

    if (iconFile != null) {
      final url = await StorageService.uploadGroupIcon(
        file: iconFile,
        groupId: groupId,
      );
      if (url != null) {
        await supabase
            .from('groups')
            .update({'icon_url': url})
            .eq('id', groupId);
      }
    }

    await supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': creatorId,
      'role': _adminRole,
    });

    // Nobody is put into a group any more: everyone else gets an invite
    // (group_invites, notified as 'group_invite') and only becomes a member
    // by accepting it — see 20260926000000_circles_replace_friendships.sql.
    final others = memberUserIds.where((id) => id != creatorId).toSet();
    await inviteMembers(groupId, others);

    return groupId;
  }

  /// Joins the group that posted [groupPostId], for a viewer who isn't a
  /// member yet — the "accept" affordance on a shared group post.
  ///
  /// Goes through the join_group_from_shared_post RPC rather than a direct
  /// insert because every INSERT policy on group_members requires the
  /// caller to already BE a member/admin/creator; a non-member has no
  /// self-join path otherwise. The RPC carries the gate: you may only join
  /// a group that actually shared a post into a surface you qualified for
  /// (friends-of-the-poster, or a community you're in) — seeing the post is
  /// the invitation.
  ///
  /// Returns true if this call added the membership, false if you were
  /// already in the group (a double tap is a quiet no-op, not an error).
  /// Throws with the server's own message when the post wasn't shared with
  /// you, so the caller can surface that rather than a generic failure.
  Future<bool> joinFromSharedPost(String groupPostId) async {
    final res = await supabase.rpc(
      'join_group_from_shared_post',
      params: {'p_group_post_id': groupPostId},
    ).timeout(_kRead);
    return res == true;
  }

  /// Groups the current user is a member of, newest-created first — backs
  /// the profile's group-circles row.
  /// Per group I'm in: my ping streak with it and how active it's been
  /// (pings + replies + posts, last 7 days) — my_group_ping_overview, most
  /// active first. Keyed by group id; empty on failure (ordering/badges only).
  Future<Map<String, ({int streak, int activity, int rank})>>
      fetchMyGroupPingOverview() async {
    try {
      final rows = await supabase.rpc('my_group_ping_overview') as List;
      return {
        for (var i = 0; i < rows.length; i++)
          (rows[i] as Map)['group_id'] as String: (
            streak: ((rows[i] as Map)['my_streak'] as num?)?.toInt() ?? 0,
            activity: ((rows[i] as Map)['activity'] as num?)?.toInt() ?? 0,
            rank: i,
          ),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyGroups() async {
    final userId = await CurrentUserService.instance.resolveId();

    final rows = await supabase
        .from('group_members')
        .select('groups(*)')
        .eq('user_id', userId)
            .timeout(_kRead);

    final groups = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final g = (r as Map)['groups'] as Map?;
      if (g == null) {
        continue; // group deleted out from under this membership row
      }
      groups.add(Map<String, dynamic>.from(g));
    }
    groups.sort(
      (a, b) => (b['created_at'] as String? ?? '').compareTo(
        a['created_at'] as String? ?? '',
      ),
    );
    return groups;
  }

  /// Groups [userId] is a member of, newest-created first — for
  /// TheirProfileScreen's own group-circles row, which needs someone
  /// ELSE's groups, not the caller's own (fetchMyGroups above is
  /// hardcoded to CurrentUserService.resolveId()). Relies on
  /// group_members_select_friend/groups_select_friend_member (see
  /// migration 20260904180000) — the caller only sees rows for groups
  /// where they're an accepted friend of [userId] (or a fellow member);
  /// a non-friend querying this simply gets an empty list back, not an
  /// error, matching this app's usual silent-RLS-narrowing convention.
  Future<List<Map<String, dynamic>>> fetchGroupsForUser(String userId) async {
    final rows = await supabase
        .from('group_members')
        .select('groups(*)')
        .eq('user_id', userId)
            .timeout(_kRead);

    final groups = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final g = (r as Map)['groups'] as Map?;
      if (g == null) continue;
      groups.add(Map<String, dynamic>.from(g));
    }
    groups.sort(
      (a, b) => (b['created_at'] as String? ?? '').compareTo(
        a['created_at'] as String? ?? '',
      ),
    );
    return groups;
  }

  /// Fetches a single group's metadata. Returns null if it doesn't exist,
  /// is deleted, or isn't visible under RLS (not a member).
  Future<Map<String, dynamic>?> fetchGroup(String groupId) async {
    final row = await supabase
        .from('groups')
        .select()
        .eq('id', groupId)
        .maybeSingle()
            .timeout(_kRead);
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// Rename and/or replace the icon/banner. The icon is open to ANY group
  /// member (explicit follow-up: "anyone can change the dp") — routed
  /// through the update_group_icon RPC, not the plain table update below,
  /// because groups_update_admin (RLS) restricts UPDATE on `groups` to
  /// admins/creator, which is right for the NAME and banner but was also
  /// silently blocking a non-admin member's icon upload. Name/banner stay
  /// admin-only, unchanged.
  Future<void> updateGroupInfo(
    String groupId, {
    String? name,
    File? iconFile,
    File? bannerFile,
  }) async {
    if (iconFile != null) {
      final url = await StorageService.uploadGroupIcon(
        file: iconFile,
        groupId: groupId,
      );
      // THROW rather than skip. uploadGroupIcon swallows its own
      // StorageException and returns null, so `if (url != null)` quietly
      // dropped the update and this method still returned normally — the
      // picker looked like it worked and the photo never changed. Every
      // caller already shows the error it catches.
      if (url == null) {
        throw StateError("Couldn't upload that photo. Check your connection.");
      }
      await supabase.rpc('update_group_icon', params: {
        'p_group_id': groupId,
        'p_icon_url': url,
      }).timeout(_kRead);
    }

    final updates = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) updates['name'] = name.trim();
    if (bannerFile != null) {
      final url = await StorageService.uploadGroupBanner(
        file: bannerFile,
        groupId: groupId,
      );
      if (url == null) {
        throw StateError("Couldn't upload that banner. Check your connection.");
      }
      updates['banner_url'] = url;
    }
    if (updates.isEmpty) return;
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

    // .select() so a row actually comes back. Without it an RLS refusal is
    // indistinguishable from success: PostgREST reports no error, zero rows
    // change, and the app reloads the unchanged group. That is exactly how
    // the group photo failed silently for every group whose creator had no
    // group_members row (see 20260907250000).
    final rows = await supabase
        .from('groups')
        .update(updates)
        .eq('id', groupId)
        .select('id')
            .timeout(_kRead);
    if ((rows as List).isEmpty) {
      throw StateError(
        'Only a group admin can change this group.',
      );
    }
  }

  /// Admin-only: permanently deletes the group. BUG FIX — this used to
  /// write `deleted_at`, a column that never existed on `groups` (unlike
  /// posts/comments/reports, which really do soft-delete); every call
  /// silently failed with a Postgres error. `groups` has no soft-delete
  /// column and a real DELETE policy (groups_delete_admin) instead — every
  /// FK into it (group_members, group_posts, pings, ping_threads, dips,
  /// group_streaks) is ON DELETE CASCADE, so this genuinely removes
  /// everything the group owned, not just the group row.
  ///
  /// `.select()` PROVES it landed, same reasoning as
  /// my_profile_screen.dart's _saveProfileImageUrl: a write RLS refuses
  /// returns zero rows and NO error on this project. Without it a
  /// non-admin's destroy did nothing server-side while the caller popped
  /// the screen as though the group were gone.
  Future<void> deleteGroup(String groupId) async {
    final rows =
        await supabase.from('groups').delete().eq('id', groupId).select('id');
    if (rows.isEmpty) {
      throw StateError('only an admin can delete this group');
    }
  }

  // ---------------------------------------------------------------------------
  // Membership
  // ---------------------------------------------------------------------------

  /// Members with their role and user info, admins first (role sorts
  /// 'admin' before 'member' alphabetically — no secondary sort needed).
  Future<List<Map<String, dynamic>>> fetchMembers(String groupId) async {
    final rows = await supabase
        .from('group_members')
        // Explicit columns, not users(*): birth_date/is_minor are REVOKEd
        // from `authenticated` (see 20260918000000_user_birth_date.sql), and
        // a wildcard embed asks for every column — which fails outright
        // rather than silently omitting the ones it can't read. Only these
        // four are ever consumed by any caller.
        .select('role, user_id, users(id, name, profile_photo_url, anon_name)')
        .eq('group_id', groupId)
        .order('role')
            .timeout(_kRead);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// A group's roster for a feed card the viewer may see but isn't a member
  /// of (a locked private-group post). Same row shape as [fetchMembers].
  Future<List<Map<String, dynamic>>> fetchCardMembers(String groupPostId) async {
    final rows = await supabase
        .rpc('group_card_members', params: {'p_group_post': groupPostId})
        .timeout(_kRead);
    return [
      for (final r in rows as List)
        {
          'role': (r as Map)['role'],
          'user_id': r['user_id'],
          'users': {
            'id': r['user_id'],
            'name': r['name'],
            'profile_photo_url': r['profile_photo_url'],
          },
        },
    ];
  }

  /// One group post's row for a feed card the viewer may see but can't read
  /// directly (a locked private-group post) — same keys [fetchPosts] rows
  /// carry that the card uses (caption/note/place/taken_at/aspect_ratio).
  Future<List<Map<String, dynamic>>> fetchCardPost(String groupPostId) async {
    final rows = await supabase
        .rpc('group_card_post', params: {'p_group_post': groupPostId})
        .timeout(_kRead);
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  }

  /// The current user's role in [groupId], or null if not a member.
  Future<String?> myRole(String groupId) async {
    final userId = await CurrentUserService.instance.resolveId();
    final row = await supabase
        .from('group_members')
        .select('role')
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .maybeSingle()
            .timeout(_kRead);
    return row?['role'] as String?;
  }

  /// Invites people into [groupId] (any member may invite). They join only
  /// by accepting — see [respondInvite]. Already-members and already-invited
  /// people are skipped server-side; returns how many new invites went out.
  Future<int> inviteMembers(String groupId, Iterable<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return 0;
    final n = await supabase.rpc('invite_to_group', params: {
      'p_group': groupId,
      'p_user_ids': ids,
    });
    return (n as num?)?.toInt() ?? 0;
  }

  /// Pending group invites addressed to me, newest first, with the group's
  /// name/icon and the inviter's name for the row.
  Future<List<GroupInvite>> fetchMyGroupInvites() async {
    final myId = await CurrentUserService.instance.resolveId();
    final rows = await supabase
        .from('group_invites')
        .select('id, group_id, invited_by, created_at, '
            'groups(name, icon_url), inviter:users!group_invites_invited_by_fkey(name)')
        .eq('invitee_id', myId)
        .order('created_at', ascending: false)
        .timeout(_kRead);
    return [for (final r in rows) GroupInvite.fromRow(r)];
  }

  /// Accept ([accept] = true) joins the group; decline just drops the
  /// invite. Returns the group id either way.
  Future<String> respondInvite(String inviteId, {required bool accept}) async {
    final groupId = await supabase.rpc('respond_group_invite', params: {
      'p_invite': inviteId,
      'p_accept': accept,
    });
    return groupId as String;
  }

  /// Shares someone's group post onward to MY audience (any member may).
  /// Replaces what I shared before. Empty [circleIds] = my Friends circle,
  /// the same default every audience picker uses. However many members
  /// share one post, a viewer still gets one card — the feed returns
  /// group_posts rows, not audience rows.
  Future<void> sharePost(
    String groupPostId, {
    required Set<String> circleIds,
    required Set<String> communityIds,
  }) async {
    await supabase.rpc('share_group_post', params: {
      'p_group_post': groupPostId,
      'p_include_friends': circleIds.isEmpty,
      'p_circle_ids': circleIds.toList(),
      'p_community_ids': communityIds.toList(),
    });
  }

  /// What I've already shared [groupPostId] to, for pre-filling the sheet.
  Future<({Set<String> circleIds, Set<String> communityIds})> myShare(String groupPostId) async {
    final rows = await supabase.rpc('my_group_post_share', params: {'p_group_post': groupPostId});
    final circles = <String>{};
    final communities = <String>{};
    for (final r in rows as List) {
      final m = r as Map;
      if (m['circle_id'] != null) circles.add(m['circle_id'] as String);
      if (m['community_id'] != null) communities.add(m['community_id'] as String);
    }
    return (circleIds: circles, communityIds: communities);
  }

  /// Accept/decline by group, for notification rows whose payload predates
  /// carrying an invite id. No-op if no invite is pending.
  Future<String?> respondInviteForGroup(String groupId, {required bool accept}) async {
    final myId = await CurrentUserService.instance.resolveId();
    final row = await supabase
        .from('group_invites')
        .select('id')
        .eq('group_id', groupId)
        .eq('invitee_id', myId)
        .maybeSingle();
    if (row == null) return null;
    return respondInvite(row['id'] as String, accept: accept);
  }

  /// Admin-only (enforced by RLS): removes another member.
  /// Admin-only: removes SOMEONE ELSE from the group. Goes through
  /// remove_group_member rather than a direct delete so the admin check,
  /// the "use Leave instead" guard and the last-admin guard are enforced
  /// server-side and come back as a message worth showing.
  Future<void> removeMember(String groupId, String userId) async {
    await supabase.rpc('remove_group_member', params: {
      'p_group_id': groupId,
      'p_user_id': userId,
    }).timeout(_kRead);
  }

  /// Admin-only: renames the group. Explicit request — "in group profiles
  /// give option to rename the group... by the admin only".
  Future<void> renameGroup(String groupId, String name) async {
    await supabase.rpc('rename_group', params: {
      'p_group_id': groupId,
      'p_name': name,
    }).timeout(_kRead);
  }

  /// Any member (including admins) can remove themselves. Deletes directly
  /// rather than via [removeMember] — that path is admin-only and refuses
  /// self-removal outright, which is exactly the case this handles.
  /// `.select()` proves the delete landed — see [deleteGroup]'s own note on
  /// silent RLS refusals.
  Future<void> leaveGroup(String groupId) async {
    final userId = await CurrentUserService.instance.resolveId();
    final rows = await supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .select('user_id');
    if (rows.isEmpty) {
      throw StateError("couldn't leave this group — try again");
    }
  }

  /// Groups [userId] belongs to, WITH real member/post counts already
  /// attached — one request via `groups_with_counts_for_user`, replacing
  /// the old fetchMyGroups() + per-group fetchMembers()/fetchPosts() fan-out
  /// (2N+1 requests for N groups) that made the profile page's own doc
  /// literally ask "why does this load so much." Same authorization the
  /// RPC re-checks server-side: your own groups always, anyone else's only
  /// if you're a friend of theirs.
  Future<List<Map<String, dynamic>>> fetchGroupsWithCounts(String userId) async {
    final rows = await supabase.rpc(
      'groups_with_counts_for_user',
      params: {'p_user_id': userId},
    )
        .timeout(_kRead);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// The group's SHARED ping streak (BLUE 2) plus today's live progress.
  ///
  /// All-or-nothing by design: any member opens the day by sending the
  /// group's daily ping, and EVERY member has to reply before the IST day
  /// ends or the shared number resets to zero for the whole group. A day
  /// where nobody pings at all is a no-op, not a break — see
  /// resolve_group_ping_day (migration 20260914030000_streak_system_v4).
  ///
  /// [todayReplied]/[todayTotal] are the live in-progress counts, which is
  /// what makes the rule legible BEFORE midnight rather than only after the
  /// resolver has already punished a miss.
  ///
  /// Returns null when there's nothing to show (not a member, or the RPC
  /// failed) — the caller renders no flame rather than a misleading zero.
  Future<GroupPingStreak?> fetchGroupPingStreak(String groupId) async {
    try {
      final rows = await supabase
          .rpc<dynamic>('group_ping_streak', params: {'p_group_id': groupId})
          .timeout(_kRead);
      final list = (rows as List);
      if (list.isEmpty) return null;
      final r = Map<String, dynamic>.from(list.first as Map);
      return GroupPingStreak(
        current: (r['current_streak'] as num?)?.toInt() ?? 0,
        longest: (r['longest_streak'] as num?)?.toInt() ?? 0,
        todayReplied: (r['today_replied'] as num?)?.toInt() ?? 0,
        todayTotal: (r['today_total'] as num?)?.toInt() ?? 0,
        todayOpen: r['today_open'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Up to 3 real member DPs per group, for the small overlapping-circles
  /// preview on a group row. BUG FIX (explicit report — "in the group
  /// preview from the profile, the circles shall show the real DPs of both
  /// the members"): [fetchGroupsWithCounts] only ever returned a member
  /// COUNT, so the preview had no photo to show and fell back to a
  /// hardcoded 3-swatch palette (kFaceSwatches) that had nothing to do
  /// with who was actually in the group.
  ///
  /// One batched query for every group on the row, not one per group —
  /// same "no N+1 fan-out" discipline [fetchGroupsWithCounts] documents
  /// above. `group_members_select` already lets a member read their own
  /// group's roster (see the RLS policy), so no new grant is needed.
  /// Ordering isn't guaranteed by the query; each group's own list is
  /// capped to 3 client-side after grouping, so which 3 show is whichever
  /// 3 the server happened to return first — acceptable for a decorative
  /// preview, not something a caller should rely on being stable.
  /// Every listed group's shared streak (BLUE 2) and each member's own
  /// group-ping streak (BLUE 3), for the group ROW on the profile — so the
  /// numbers are visible without opening the group. Explicit request: "on
  /// group [show] the overall group streak which we discussed, and as well
  /// under each person's dp."
  ///
  /// Two RPCs per group is acceptable here because the profile lists a
  /// handful of groups, not a feed of them; both are member-gated
  /// server-side and fail soft, so a group you can't read simply has no
  /// flame rather than an error.
  Future<Map<String, ({int shared, Map<String, int> members})>>
      fetchGroupStreakBundle(List<String> groupIds) async {
    final out = <String, ({int shared, Map<String, int> members})>{};
    for (final id in groupIds) {
      try {
        final results = await Future.wait([
          fetchGroupPingStreak(id),
          supabase
              .rpc<dynamic>('group_ping_member_streak_map',
                  params: {'p_group_id': id})
              .timeout(_kRead),
        ]);
        final shared = results[0] as GroupPingStreak?;
        final rows = (results[1] as List).cast<Map<String, dynamic>>();
        out[id] = (
          shared: shared?.current ?? 0,
          members: {
            for (final r in rows)
              r['user_id'] as String: (r['streak'] as num?)?.toInt() ?? 0,
          },
        );
      } catch (_) {
        // Decorative — never block the group list on a streak lookup.
      }
    }
    return out;
  }

  /// Member ids for the faces [fetchMemberAvatars] last returned, same
  /// order and same 3-face cap — so the group row can pair each circle with
  /// that member's own streak. Populated as a side effect of the call
  /// above rather than as a second query.
  final Map<String, List<String>> memberIdsByGroup = {};

  Future<Map<String, List<String?>>> fetchMemberAvatars(
    List<String> groupIds,
  ) async {
    if (groupIds.isEmpty) return const {};
    try {
      // user_id comes back too — the group row draws each member's own
      // streak flame under their circle, which needs the id to line the
      // streak up with the right face.
      final rows = await supabase
          .from('group_members')
          .select('group_id, user_id, users(profile_photo_url)')
          .inFilter('group_id', groupIds)
          .timeout(_kRead);
      final out = <String, List<String?>>{};
      // Reset only the groups THIS call is responsible for, never the whole
      // map. It used to .clear() everything: this is a singleton, so two
      // screens loading at once (MyProfileScreen and a pushed
      // GroupProfileV2Screen, say) had the second call wipe the first's
      // entries out from under it. The first screen's later read at
      // my_profile_screen.dart then found nothing and fell through its
      // `?? []`, silently dropping every per-member streak flame from its
      // group rows. Scoping the reset to groupIds makes concurrent callers
      // independent — each owns its own keys.
      for (final gid in groupIds) {
        memberIdsByGroup[gid] = [];
      }
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final gid = r['group_id'] as String;
        final list = out.putIfAbsent(gid, () => []);
        final ids = memberIdsByGroup.putIfAbsent(gid, () => []);
        if (list.length >= 3) continue;
        final user = r['users'] as Map?;
        list.add(user?['profile_photo_url'] as String?);
        ids.add(r['user_id'] as String);
      }
      return out;
    } catch (_) {
      // Decorative-only — a failed fetch here should never block the
      // group list itself from rendering.
      return const {};
    }
  }

  /// Real search for the add-members picker — ilike over name/anon_name,
  /// excluding the caller and anyone in [excludeIds] (already-added picks
  /// or existing members). No dedicated user-search endpoint existed
  /// anywhere in this codebase (grepped: only mock data in
  /// profile_screen.dart's _SearchScreen) — this is the first real one.
  Future<List<Map<String, dynamic>>> searchUsers(
    String query, {
    Set<String> excludeIds = const {},
  }) async {
    final q = sanitizeSearchTerm(query);
    if (q == null) return [];
    final userId = await CurrentUserService.instance.resolveId();
    // See PeopleService.searchPeople's own note: blocks aren't
    // filtered by RLS on `users` itself, so it's done client-side here too.
    final blockedIds = await BlockService.instance.blockedUserIds();

    final rows = await supabase
        .from('users')
        .select('id, name, anon_name, username, profile_photo_url, department, deleted_at')
        .or('name.ilike.%$q%,anon_name.ilike.%$q%,username.ilike.%$q%')
        .limit(50)
            .timeout(_kRead);

    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where(
          (u) =>
              u['id'] != userId &&
              u['deleted_at'] == null &&
              !excludeIds.contains(u['id']) &&
              !blockedIds.contains(u['id']),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Group posts (shared album)
  // ---------------------------------------------------------------------------

  /// Newest post photo per group, for highlight covers. Groups with no
  /// posts are absent.
  Future<Map<String, String>> fetchLatestPostPhotos(List<String> groupIds) async {
    if (groupIds.isEmpty) return const {};
    final rows = await supabase
        .from('group_posts')
        .select('group_id, photo_url, created_at')
        .inFilter('group_id', groupIds)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(300)
        .timeout(_kRead);
    final out = <String, String>{};
    for (final r in rows as List) {
      final url = r['photo_url'] as String?;
      if (url != null) out.putIfAbsent(r['group_id'] as String, () => url);
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> fetchPosts(String groupId) async {
    final rows = await supabase
        .from('group_posts')
        // users!group_posts_user_id_fkey, not a bare users(...): the
        // group_post_views table (viewer_id -> users) added a SECOND
        // relationship path between group_posts and users, so PostgREST
        // refuses the ambiguous embed with PGRST201 and the whole group
        // screen fails to load. Naming the FK resolves it explicitly.
        .select('*, users!group_posts_user_id_fkey(name, profile_photo_url)')
        .eq('group_id', groupId)
        // Explicit, not left to RLS: this is the group's own album view and
        // a soft-deleted post must not reappear in it.
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
            .timeout(_kRead);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// The group's posts a NON-member may see on its profile — the ones
  /// shared to them ('open') and, for a private group in one of their
  /// communities, the first-photo-only 'locked' ones (flagged `locked`,
  /// photos 2+ withheld server-side). Same row shape as [fetchPosts].
  /// See group_profile_posts_for_viewer (20260927170000).
  ///
  /// [viaUserId] = whose profile/share the viewer came through: a personal
  /// share only shows through the person who made it (20260927210000).
  Future<List<Map<String, dynamic>>> fetchVisiblePosts(
    String groupId, {
    String? viaUserId,
  }) async {
    final rows = await supabase
        .rpc(
          'group_profile_posts_for_viewer',
          params: {
            'p_group_id': groupId,
            if (viaUserId != null) 'p_via_user': viaUserId,
          },
        )
        .timeout(_kRead);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Any member can post — the group's shared album, not a personal one.
  /// Posts one or more photos to a group. [photoFiles] order IS display
  /// order — the first is the cover.
  ///
  /// Writes BOTH columns by design: `photo_url` (still NOT NULL, and what
  /// every pre-multi-photo reader uses) gets the cover photo, and
  /// `photo_urls` gets the full ordered list. See migration
  /// 20260831000000_multi_photo_posts.sql for why this stays additive
  /// rather than replacing the single column.
  Future<void> addPost({
    required String groupId,
    required List<File> photoFiles,
    // The un-flattened dual pair. When set, photoFiles.first is the
    // BACKGROUND and this is the inset — same two-layer model the friends
    // feed uses (see FeedItem.secondaryPhotoUrl), stored in the columns
    // group_posts already carries for it. Null keeps an ordinary
    // single/multi-photo group post, unchanged.
    File? secondaryPhoto,
    bool insetOnRight = false,
    String? caption,
    DateTime? takenAt,
    String? note,
    String? place,
    // Friends/community audience — same combined, non-exclusive model
    // PostService.addPost uses for personal posts (C1), but group_posts
    // has no visibility column of its own to encode 'friends' on, so BOTH
    // pieces are explicit group_post_audiences rows here (see that
    // table's own doc). Untouched by default: no rows, group post stays
    // visible only the way it always was (to the group's own members via
    // FeedService.fetchGroupFeed).
    bool includeFriends = false,
    List<String> audienceCommunityIds = const [],
    // Specific circles of the poster's (Close Friends, Family, ...) — the
    // group composer had no circle option at all before.
    List<String> audienceCircleIds = const [],
    // Members-only: never shown outside the group (not on a public group's
    // profile, not shareable). Audience args are ignored when set.
    bool isPrivate = false,
    // The poster's own compose-time size choice (PostSizePresetPicker) —
    // width/height, stored as text same as posts.aspect_ratio. Null keeps
    // whatever default the reading side falls back to (parseStoredAspectRatio).
    double? aspectRatio,
  }) async {
    if (photoFiles.isEmpty) {
      throw StateError('At least one photo is required');
    }
    final userId = await CurrentUserService.instance.resolveId();

    // Sequential, not Future.wait: uploadGroupPhoto derives its object path
    // from DateTime.now().millisecondsSinceEpoch, so concurrent uploads can
    // collide on the same path and overwrite each other (upsert: true).
    final urls = <String>[];
    for (final file in photoFiles) {
      final url = await StorageService.uploadGroupPhoto(
        file: file,
        groupId: groupId,
        userId: userId,
      );
      if (url == null) {
        throw StateError('Photo upload failed');
      }
      urls.add(url);
    }

    // Inset uploads after the cover, and fails soft: a group post with a
    // background but no inset is a valid single-photo post, whereas losing
    // the whole post over the second layer is not a trade worth making.
    String? secondaryUrl;
    if (secondaryPhoto != null) {
      try {
        secondaryUrl = await StorageService.uploadGroupPhoto(
          file: secondaryPhoto,
          groupId: groupId,
          userId: userId,
        );
      } catch (e) {
        debugPrint('[GroupService.addPost] inset upload failed, '
            'saving as single photo: $e');
      }
    }

    final row = await supabase
        .from('group_posts')
        .insert({
          'group_id': groupId,
          'user_id': userId,
          'photo_url': urls.first,
          'photo_urls': urls,
          if (secondaryUrl != null) 'photo_url_secondary': secondaryUrl,
          if (secondaryUrl != null) 'inset_on_right': insetOnRight,
          if (caption != null && caption.isNotEmpty) 'caption': caption,
          if (takenAt != null) 'taken_at': takenAt.toUtc().toIso8601String(),
          if (note != null && note.isNotEmpty) 'note': note,
          if (place != null && place.isNotEmpty) 'place': place,
          if (aspectRatio != null) 'aspect_ratio': aspectRatio.toString(),
          if (isPrivate) 'is_private': true,
        })
        .select('id')
        .single()
            .timeout(_kRead);

    // Same fail-closed contract as PostService.addPost's own
    // post_audiences write: the group post itself already succeeded, so a
    // failed audience insert only narrows who can additionally see it
    // (never widens/leaks), and is logged rather than rethrown.
    //
    // Through share_group_post — the same call a member uses to share
    // someone else's post — rather than raw inserts: it is the one path that
    // writes circle audiences (checking each circle is really the poster's)
    // and stamps shared_by, so the poster's audience and every other
    // member's are stored the same way.
    if (!isPrivate &&
        (includeFriends ||
            audienceCommunityIds.isNotEmpty ||
            audienceCircleIds.isNotEmpty)) {
      final groupPostId = row['id'] as String;
      try {
        await supabase.rpc('share_group_post', params: {
          'p_group_post': groupPostId,
          'p_include_friends': includeFriends,
          'p_circle_ids': audienceCircleIds,
          'p_community_ids': audienceCommunityIds,
        });
      } catch (e, st) {
        debugPrint(
          '[GroupService] group_post_audiences insert FAILED for post $groupPostId: $e\n$st',
        );
      }
    }
  }

  /// Hard-deletes a post — allowed for the post's own author or the
  /// group's admin (both paths are RLS-enforced via the `delete_group_posts`
  /// policy; this method doesn't need to know which one applies to the
  /// caller). This used to be a soft-delete (`.update({'deleted_at': ...})`)
  /// but `group_posts.deleted_at` was confirmed (2026-09-02, live DB) to
  /// never have existed, and there was never an UPDATE policy on this
  /// table either — every call silently failed with a 42703/RLS error,
  /// which is why the group profile's post delete button did nothing.
  /// `fetchPosts` never filtered on `deleted_at`, so no read-side change
  /// is needed.
  /// Removes a group post — soft delete, via `remove_group_post`.
  ///
  /// An RPC rather than a direct update: every SELECT policy on group_posts
  /// requires `deleted_at IS NULL`, so an UPDATE that sets it can't use
  /// PostgREST's `.select()` (which compiles to RETURNING) — the new row is
  /// no longer visible and the whole statement is refused. The RPC does the
  /// authorisation check itself and returns a real boolean, so a refusal is
  /// never mistaken for success.
  ///
  /// Permitted for the author, a group admin, or a global moderator.
  Future<void> deletePost(String postId) async {
    final ok = await supabase.rpc<dynamic>(
      'remove_group_post',
      params: {'p_post_id': postId},
    );
    if (ok != true) {
      throw StateError("Couldn't remove that post.");
    }
  }

  /// Real group posts for the Everyone/Friends feed (not a single group's
  /// own album view) — every group_posts row from a group the caller
  /// belongs to, newest first. Backs FeedService.fetchGroupFeed, which
  /// replaces the DemoContent.demoGroupPosts placeholders that previously
  /// filled this slot in everyone_feed_screen.dart.
  Future<List<Map<String, dynamic>>> fetchFeedPosts({
    int limit = 30,
    int offset = 0,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    final memberRows = await supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId)
            .timeout(_kRead);
    final groupIds = (memberRows as List)
        .map((r) => (r as Map)['group_id'] as String)
        .toSet()
        .toList();

    // Group posts shared OUT of their group by GroupPostScreen's "Also show
    // to" pills — to the author's friends, or to a community's members.
    // group_post_audiences' own SELECT policy is gated on being able to see
    // the underlying group_post, and group_posts_select_shared_audience
    // (20260906130000) is what now makes those posts visible, so this query
    // returns exactly the shared posts this viewer is entitled to and
    // nothing else. Rows for groups the viewer is already in come back too;
    // the OR below dedupes them naturally.
    var sharedIds = const <String>[];
    try {
      final audienceRows = await supabase
          .from('group_post_audiences')
          .select('group_post_id')
              .timeout(_kRead);
      sharedIds = (audienceRows as List)
          .map((r) => (r as Map)['group_post_id'] as String)
          .toSet()
          .toList();
    } catch (e, st) {
      // Never fatal: worst case the viewer sees only their own groups'
      // posts, which is the behaviour that shipped before sharing existed.
      debugPrint('[GroupService.fetchFeedPosts] shared-audience lookup failed: $e\n$st');
    }

    if (groupIds.isEmpty && sharedIds.isEmpty) return [];

    // ONE query with an OR rather than two merged pages — merging would
    // break `range` (each half would need its own offset) and re-sorting
    // client-side can't page correctly across the boundary.
    final clauses = [
      if (groupIds.isNotEmpty) 'group_id.in.(${groupIds.join(',')})',
      if (sharedIds.isNotEmpty) 'id.in.(${sharedIds.join(',')})',
    ];
    final rows = await supabase
        .from('group_posts')
        // Same PGRST201 disambiguation as fetchPosts above.
        .select('*, groups(name, icon_url), users!group_posts_user_id_fkey(name, username, profile_photo_url)')
        .or(clauses.join(','))
        // Belt and braces alongside RLS — same reason fetchPosts filters it.
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1)
            .timeout(_kRead);
    return List<Map<String, dynamic>>.from(rows as List);
  }
}

/// One group's shared ping streak — see GroupService.fetchGroupPingStreak.
class GroupPingStreak {
  const GroupPingStreak({
    required this.current,
    required this.longest,
    required this.todayReplied,
    required this.todayTotal,
    required this.todayOpen,
  });

  final int current;
  final int longest;

  /// How many of the roster have answered today's group ping so far.
  final int todayReplied;
  final int todayTotal;

  /// Whether today's group ping has been sent at all yet. False means the
  /// streak is NOT at risk today — nobody has opened the day.
  final bool todayOpen;

  /// Everyone who was asked has answered, so today is already safe.
  bool get todayComplete => todayOpen && todayTotal > 0 && todayReplied >= todayTotal;
}

/// A pending invite into a group album, addressed to the current user.
class GroupInvite {
  const GroupInvite({
    required this.id,
    required this.groupId,
    required this.groupName,
    this.groupIconUrl,
    required this.inviterName,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String? groupIconUrl;
  final String inviterName;
  final DateTime createdAt;

  factory GroupInvite.fromRow(Map<String, dynamic> r) => GroupInvite(
        id: r['id'] as String,
        groupId: r['group_id'] as String,
        groupName: (r['groups']?['name'] as String?) ?? 'a group',
        groupIconUrl: r['groups']?['icon_url'] as String?,
        inviterName: (r['inviter']?['name'] as String?) ?? 'Someone',
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
