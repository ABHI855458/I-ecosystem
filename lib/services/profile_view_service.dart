import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/time_ago.dart' show parsePostgresTimestamp;
import 'current_user_service.dart';

// ---------------------------------------------------------------------------
// ProfileViewService — real reads/writes against the live `profile_views`
// table (viewer_id, viewed_user_id, is_anonymous, created_at — already in
// supabase/schema.sql, RLS already correct: a viewer can only insert their
// own row, and only the viewed user can read theirs). Nothing in the app
// wrote to or read from this table before; this is the "Viewed by" feature.
// ---------------------------------------------------------------------------

/// "someone" for a non-pinned viewer with no branch on file (a gmail/admin
/// account, or a real rvce.edu.in signup whose branch parse never landed);
/// "someone in CS"/"someone in EC"/"someone in CV" etc. otherwise — the
/// branch itself is never masked (see my_profile_viewers/my_post_viewers'
/// own doc: it's the same fact already shown in public profile headers),
/// only WHO they are stays hidden until pinned.
String _anonLabel(String? branch) {
  final b = branch?.trim();
  if (b == null || b.isEmpty) return 'someone';
  return 'someone in ${b.toUpperCase()}';
}

class ProfileViewer {
  const ProfileViewer({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isPinned,
    required this.viewedAt,
  });

  factory ProfileViewer.fromRow(Map<String, dynamic> row) {
    final username = (row['username'] as String?)?.trim();
    final name = (row['name'] as String?)?.trim();
    return ProfileViewer(
      userId: (row['user_id'] as String?) ?? 'k:${row['viewer_key']}',
      // Server already returns null for both unless this viewer is pinned
      // (my_profile_viewers) — the branch-based label is the anonymous
      // fallback now, not a client-side masking decision (the masking
      // itself still happens server-side; this just picks what to print
      // for the masked case).
      name: (username != null && username.isNotEmpty)
          ? username
          : (name != null && name.isNotEmpty ? name : ((row['anon_label'] as String?) ?? _anonLabel(row['branch'] as String?))),
      avatarUrl:
          (row['avatar_url'] as String?) ?? row['anon_avatar_url'] as String?,
      isPinned: row['is_pinned'] as bool? ?? false,
      viewedAt: parsePostgresTimestamp(row['viewed_at'] as String),
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;

  /// Pinned by YOU — the only reason [name]/[avatarUrl] are real rather
  /// than the anonymous fallback. See my_profile_viewers().
  final bool isPinned;
  final DateTime viewedAt;
}

/// Someone who has opened one of YOUR posts — a row of `my_post_viewers`.
class PostViewerPerson {
  const PostViewerPerson({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isPinned,
    required this.viewedAt,
  });

  factory PostViewerPerson.fromRow(Map<String, dynamic> row) {
    final username = (row['username'] as String?)?.trim();
    final name = (row['name'] as String?)?.trim();
    return PostViewerPerson(
      userId: (row['user_id'] as String?) ?? 'k:${row['viewer_key']}',
      name: (username != null && username.isNotEmpty)
          ? username
          : (name != null && name.isNotEmpty ? name : ((row['anon_label'] as String?) ?? _anonLabel(row['branch'] as String?))),
      avatarUrl:
          (row['avatar_url'] as String?) ?? row['anon_avatar_url'] as String?,
      isPinned: row['is_pinned'] as bool? ?? false,
      viewedAt: row['viewed_at'] != null
          ? DateTime.tryParse(row['viewed_at'] as String)
          : null,
    );
  }

  final String userId;
  final String name;
  final String? avatarUrl;

  /// Pinned by YOU. These sort to the top of the list.
  final bool isPinned;
  final DateTime? viewedAt;
}

class ProfileViewService {
  ProfileViewService._();
  static final instance = ProfileViewService._();

  final _sb = Supabase.instance.client;

  /// Records that the current user viewed [viewedUserId]'s profile. No-op
  /// on your own id (visiting your own profile isn't a "view"), and
  /// collapsed to at most one row per viewer per hour so the list reads as
  /// distinct people, not distinct pageloads — checked with a read before
  /// the insert since there's no unique constraint to upsert against.
  Future<void> record(String viewedUserId) async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      if (myId == viewedUserId) return;

      final recent = await _sb
          .from('profile_views')
          .select('id')
          .eq('viewer_id', myId)
          .eq('viewed_user_id', viewedUserId)
          .gte(
            'created_at',
            DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
          )
          .limit(1)
          .timeout(const Duration(seconds: 8));
      if ((recent as List).isNotEmpty) return;

      await _sb.from('profile_views').insert({
        'viewer_id': myId,
        'viewed_user_id': viewedUserId,
      });
    } catch (_) {
      // Non-critical — a missed view record shouldn't disrupt navigation.
    }
  }

  /// Who has opened the caller's own POSTS — pinned people first, then most
  /// recent. This is a different question from [fetchViewers], which is
  /// about profile visits.
  ///
  /// An RPC because post_views' only SELECT policy is self-only
  /// (`viewer_id = me`), so a post's author cannot read their own post's
  /// viewers directly. my_post_viewers (20260906200000) is scoped to
  /// `p.user_id = me`, so it can only ever return viewers of your own
  /// content. Fails soft to an empty list.
  Future<List<PostViewerPerson>> fetchMyPostViewers({int limit = 60}) async {
    try {
      final rows = await _sb
          .rpc('my_post_viewers', params: {'p_limit': limit})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          PostViewerPerson.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Who viewed the current user's profile, most recent first, deduped to
  /// one entry per viewer (their most recent view).
  ///
  /// Goes through my_profile_viewers() rather than a direct
  /// `.from('profile_views')` join — that raw join used to return every
  /// viewer's real name/username/photo unconditionally, with no notion of
  /// pinning at all. "Apart from pinned people, no other name shall be
  /// shown here" is enforced server-side now: the RPC returns null
  /// name/username/avatar_url for anyone the caller hasn't pinned, the same
  /// masking my_post_viewers() already did for the Your Posts tab.
  Future<List<ProfileViewer>> fetchViewers({int limit = 50}) async {
    try {
      final rows = await _sb
          .rpc('my_profile_viewers', params: {'p_limit': limit})
          .timeout(const Duration(seconds: 8));
      return [
        for (final r in (rows as List))
          ProfileViewer.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }
}
