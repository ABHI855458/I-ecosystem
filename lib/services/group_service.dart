import 'dart:io';

import '../core/supabase_config.dart';
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
  GroupService._();
  static final instance = GroupService._();

  static const _adminRole = 'admin';
  static const _memberRole = 'member';

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
  Future<String> createGroup({
    required String name,
    File? iconFile,
    List<String> memberUserIds = const [],
  }) async {
    final creatorId = await CurrentUserService.instance.resolveId();

    final row = await supabase
        .from('groups')
        .insert({'name': name, 'creator_id': creatorId})
        .select('id')
        .single();
    final groupId = row['id'] as String;

    if (iconFile != null) {
      final url = await StorageService.uploadGroupIcon(
        file: iconFile,
        groupId: groupId,
      );
      if (url != null) {
        await supabase.from('groups').update({'icon_url': url}).eq('id', groupId);
      }
    }

    await supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': creatorId,
      'role': _adminRole,
    });

    final others = memberUserIds.where((id) => id != creatorId).toSet();
    for (final userId in others) {
      await supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': userId,
        'role': _memberRole,
      });
    }

    return groupId;
  }

  /// Groups the current user is a member of, newest-created first — backs
  /// the profile's group-circles row.
  Future<List<Map<String, dynamic>>> fetchMyGroups() async {
    final userId = await CurrentUserService.instance.resolveId();

    final rows = await supabase
        .from('group_members')
        .select('groups(*)')
        .eq('user_id', userId);

    final groups = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final g = (r as Map)['groups'] as Map?;
      if (g == null) continue; // group deleted out from under this membership row
      groups.add(Map<String, dynamic>.from(g));
    }
    groups.sort((a, b) =>
        (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? ''));
    return groups;
  }

  /// Fetches a single group's metadata. Returns null if it doesn't exist,
  /// is deleted, or isn't visible under RLS (not a member).
  Future<Map<String, dynamic>?> fetchGroup(String groupId) async {
    final row = await supabase.from('groups').select().eq('id', groupId).maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  /// Admin-only: rename and/or replace the icon.
  Future<void> updateGroupInfo(
    String groupId, {
    String? name,
    File? iconFile,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) updates['name'] = name.trim();
    if (iconFile != null) {
      final url = await StorageService.uploadGroupIcon(file: iconFile, groupId: groupId);
      if (url != null) updates['icon_url'] = url;
    }
    if (updates.isEmpty) return;
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await supabase.from('groups').update(updates).eq('id', groupId);
  }

  /// Admin-only: soft-deletes the group (matches the rest of the schema's
  /// deleted_at convention — see posts/communities).
  Future<void> deleteGroup(String groupId) async {
    await supabase
        .from('groups')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', groupId);
  }

  // ---------------------------------------------------------------------------
  // Membership
  // ---------------------------------------------------------------------------

  /// Members with their role and user info, admins first (role sorts
  /// 'admin' before 'member' alphabetically — no secondary sort needed).
  Future<List<Map<String, dynamic>>> fetchMembers(String groupId) async {
    final rows = await supabase
        .from('group_members')
        .select('role, user_id, users(*)')
        .eq('group_id', groupId)
        .order('role');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// The current user's role in [groupId], or null if not a member.
  Future<String?> myRole(String groupId) async {
    final userId = await CurrentUserService.instance.resolveId();
    final row = await supabase
        .from('group_members')
        .select('role')
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .maybeSingle();
    return row?['role'] as String?;
  }

  /// Admin-only (enforced by RLS): adds a member.
  Future<void> addMember(String groupId, String userId) async {
    await supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': userId,
      'role': _memberRole,
    });
  }

  /// Admin-only (enforced by RLS): removes another member.
  Future<void> removeMember(String groupId, String userId) async {
    await supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  /// Any member (including admins) can remove themselves.
  Future<void> leaveGroup(String groupId) async {
    final userId = await CurrentUserService.instance.resolveId();
    await removeMember(groupId, userId);
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
    final q = query.trim();
    if (q.isEmpty) return [];
    final userId = await CurrentUserService.instance.resolveId();

    final rows = await supabase
        .from('users')
        .select('id, name, anon_name, profile_photo_url, department')
        .or('name.ilike.%$q%,anon_name.ilike.%$q%')
        .limit(30);

    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where((u) => u['id'] != userId && !excludeIds.contains(u['id']))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Group posts (shared album)
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchPosts(String groupId) async {
    final rows = await supabase
        .from('group_posts')
        .select('*, users(name, profile_photo_url)')
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Any member can post — the group's shared album, not a personal one.
  Future<void> addPost({
    required String groupId,
    required File photoFile,
    String? caption,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    final url = await StorageService.uploadGroupPhoto(
      file: photoFile,
      groupId: groupId,
      userId: userId,
    );
    if (url == null) {
      throw StateError('Photo upload failed');
    }
    await supabase.from('group_posts').insert({
      'group_id': groupId,
      'user_id': userId,
      'photo_url': url,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    });
  }

  /// Soft-deletes a post — allowed for the post's own author or the
  /// group's admin (both paths are RLS-enforced; this method doesn't need
  /// to know which one applies to the caller).
  Future<void> deletePost(String postId) async {
    await supabase
        .from('group_posts')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', postId);
  }
}
