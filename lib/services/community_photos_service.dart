import '../core/supabase_config.dart';

/// Backs the profile's "Groups" TAB (the grid of photos — not the new
/// group-circles row or GroupProfileScreen, which are a different feature;
/// see group_service.dart). No group-photo-album system existed anywhere in
/// this codebase when this was written — it reads the closest existing real
/// data: community-scoped posts (`posts.visibility = 'community'`) for
/// communities the user has joined via `community_members`.
///
/// Formerly named GroupService — renamed when the real group system
/// (named groups, admin/member roles, group_posts) was built, so that name
/// wouldn't collide with the actual "group" feature. This class's behavior
/// is unchanged; only the name moved.
///
/// `user_communities` (the table this used to read) was dropped 2026-09-04 —
/// it was a dead duplicate with 0 live rows, fully superseded by
/// `community_members`, which is keyed on the raw auth uid rather than
/// `users.id` (see community_service.dart's KEYSPACE FIX note).
class CommunityPhotosService {
  CommunityPhotosService._();
  static final instance = CommunityPhotosService._();

  Future<List<Map<String, dynamic>>> myGroupPhotos() async {
    final authId = supabase.auth.currentUser?.id;
    if (authId == null) return [];

    final memberships = await supabase
        .from('community_members')
        .select('community_id')
        .eq('user_id', authId);
    final communityIds = (memberships as List)
        .map((m) => (m as Map)['community_id'] as String)
        .toList();
    if (communityIds.isEmpty) return [];

    final rows = await supabase
        .from('posts_feed')
        .select()
        .eq('visibility', 'community')
        .inFilter('community_id', communityIds)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
