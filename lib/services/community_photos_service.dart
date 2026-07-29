import '../core/supabase_config.dart';
import 'current_user_service.dart';

/// Backs the profile's "Groups" TAB (the grid of photos — not the new
/// group-circles row or GroupProfileScreen, which are a different feature;
/// see group_service.dart). No group-photo-album system existed anywhere in
/// this codebase when this was written — it reads the closest existing real
/// data: community-scoped posts (`posts.visibility = 'community'`) for
/// communities the user has joined via `user_communities`.
///
/// Formerly named GroupService — renamed when the real group system
/// (named groups, admin/member roles, group_posts) was built, so that name
/// wouldn't collide with the actual "group" feature. This class's behavior
/// is unchanged; only the name moved.
class CommunityPhotosService {
  CommunityPhotosService._();
  static final instance = CommunityPhotosService._();

  Future<List<Map<String, dynamic>>> myGroupPhotos() async {
    final userId = await CurrentUserService.instance.resolveId();

    final memberships = await supabase
        .from('user_communities')
        .select('community_id')
        .eq('user_id', userId);
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
