import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// ReportService — the backend that was missing behind every existing
// "Report" button in this app. `reports` has existed live all along (id,
// post_id, comment_id, ping_id, reporter_id, reason, created_at) with
// exactly one policy — rep_ins, INSERT TO authenticated WITH CHECK
// (reporter_id = auth.uid()) — but nothing ever inserted into it; every
// call site (design_solo_card.dart, design_group_card.dart,
// anon_feed_screen.dart's _AnonMenuSheet, profile_screen.dart) was a toast
// or a Navigator.pop with a comment saying so explicitly.
//
// [myReports] reads the caller's OWN reports through rep_select_own
// (migration 20260913000000). That is NOT the moderation queue: the policy
// is `reporter_id = auth.uid()`, so it can only ever return rows this user
// filed. rep_select_moderator is what grants moderators the wider view and
// is untouched.
//
// Outcomes are written by resolve_report() (SECURITY DEFINER, moderator-
// gated), which also notifies the reporter — see the `status` values below.
//
// community_post_id support (20260904000000_community_posts.sql) added a
// partial UNIQUE index on (reporter_id, community_post_id) — the mechanism
// [reportCommunityPost] uses to detect "you already reported this" via a
// 23505 postgres error code rather than a read the RLS doesn't allow.
// ---------------------------------------------------------------------------

/// Thrown when the caller has already reported this exact target.
class AlreadyReportedException implements Exception {
  const AlreadyReportedException();
  @override
  String toString() => 'You already reported this.';
}

class ReportService {
  ReportService._();
  static final instance = ReportService._();

  final _sb = Supabase.instance.client;

  String get _reporterId {
    final id = _sb.auth.currentUser?.id;
    if (id == null) {
      throw StateError('ReportService called with no signed-in user');
    }
    return id;
  }

  Future<void> _insert(Map<String, dynamic> row) async {
    try {
      await _sb.from('reports').insert({'reporter_id': _reporterId, ...row});
    } on PostgrestException catch (e, st) {
      if (e.code == '23505') throw const AlreadyReportedException();
      debugPrint('[ReportService._insert] failed: $e\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('[ReportService._insert] failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> reportCommunityPost(String communityPostId, {String? reason}) =>
      _insert({'community_post_id': communityPostId, if (reason != null) 'reason': reason});

  Future<void> reportPost(String postId, {String? reason}) =>
      _insert({'post_id': postId, if (reason != null) 'reason': reason});

  Future<void> reportComment(String commentId, {String? reason}) =>
      _insert({'comment_id': commentId, if (reason != null) 'reason': reason});

  /// A `group_posts` row — the Friends feed's collage cards. Recorded and
  /// reviewable, but note the queue cannot take a group post DOWN yet:
  /// group_posts has no deleted_at (see
  /// 20260907130000_reports_group_post.sql).
  Future<void> reportGroupPost(String groupPostId, {String? reason}) =>
      _insert({'group_post_id': groupPostId, if (reason != null) 'reason': reason});

  /// A `us_album_photos` row — a photo inside a Duo.
  Future<void> reportDuoPhoto(String photoId, {String? reason}) =>
      _insert({'us_album_photo_id': photoId, if (reason != null) 'reason': reason});

  Future<void> reportPing(String pingId, {String? reason}) =>
      _insert({'ping_id': pingId, if (reason != null) 'reason': reason});

  /// The caller's own reports, newest first — what they reported, when, and
  /// where it got to.
  ///
  /// `status` is one of 'pending' | 'removed' | 'dismissed' (set by
  /// resolve_report()). Fails closed to an empty list, same contract the
  /// feeds use — a reports list that can't load should read as "nothing to
  /// show", never crash a settings screen.
  Future<List<MyReport>> myReports({int limit = 50}) async {
    try {
      final rows = await _sb
          .from('reports')
          .select('id, post_id, comment_id, ping_id, community_post_id, '
              'reason, status, created_at, resolved_at')
          .order('created_at', ascending: false)
          .limit(limit);
      return [
        for (final r in rows as List)
          MyReport.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
    } catch (e, st) {
      debugPrint('[ReportService.myReports] failed: $e\n$st');
      return [];
    }
  }
}

/// One report the current user filed. Carries NO information about who
/// authored the reported content — by design, and matching what the
/// notification withholds: reporting must never become a way to learn who
/// posted something, least of all on an anonymous post.
class MyReport {
  const MyReport({
    required this.id,
    required this.target,
    required this.status,
    required this.createdAt,
    this.reason,
    this.resolvedAt,
  });

  factory MyReport.fromRow(Map<String, dynamic> r) => MyReport(
        id: r['id'] as String,
        target: r['post_id'] != null
            ? 'Post'
            : r['community_post_id'] != null
                ? 'Community post'
                : r['comment_id'] != null
                    ? 'Comment'
                    : r['ping_id'] != null
                        ? 'Ping'
                        : 'Content',
        reason: (r['reason'] as String?)?.trim(),
        status: (r['status'] as String?) ?? 'pending',
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        resolvedAt: r['resolved_at'] != null
            ? DateTime.tryParse(r['resolved_at'] as String)
            : null,
      );

  final String id;

  /// 'Post' | 'Community post' | 'Comment' | 'Ping' | 'Content'.
  final String target;
  final String? reason;

  /// 'pending' | 'removed' | 'dismissed'.
  final String status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  bool get isPending => status == 'pending';

  String get statusLabel => switch (status) {
        'removed' => 'Removed',
        'dismissed' => 'No action taken',
        _ => 'Under review',
      };
}
