import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/time_ago.dart' show parsePostgresTimestamp;
import 'current_user_service.dart';

// ---------------------------------------------------------------------------
// CommentService — real reads/writes against the `comments` table (schema
// already live, see supabase/schema.sql — post_id FK, comments_select/
// comments_insert/comments_delete_own RLS). Nothing in the app previously
// wrapped this table in a service; every card only ever showed a
// commentCount + a "view comments" link that opened a detail screen with no
// comment UI of its own. This is the first real comment read/write path.
//
// [groupPostId] routes at a group_posts row instead of a posts row
// (mutually exclusive with [postId] — see the group_post_id migration on
// comments). Exactly one of the two must be non-null on every call.
// ---------------------------------------------------------------------------

class Comment {
  const Comment({
    required this.id,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.body,
    required this.createdAt,
    this.isAnonymous = false,
    this.anonName,
    this.anonAvatarUrl,
  });

  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String body;
  final DateTime createdAt;

  /// True when this was posted via the composer's "Comment anonymously"
  /// toggle — BUG FIX: that toggle used to be purely cosmetic
  /// (CommentService.post() never received it), so every "anonymous"
  /// comment still rendered under the real name/photo. [displayName]/
  /// [displayAvatarUrl] are what every render site should actually show;
  /// [name]/[avatarUrl] stay the real identity for anyone who needs it
  /// (e.g. moderation), never rendered directly when [isAnonymous].
  final bool isAnonymous;
  final String? anonName;
  final String? anonAvatarUrl;

  String get displayName => isAnonymous ? (anonName ?? 'anonymous') : name;
  String? get displayAvatarUrl => isAnonymous ? anonAvatarUrl : avatarUrl;
}

/// One comment on an ANONYMOUS post — deliberately carries no `userId`,
/// real name, or photo. [handle] is the commenter's stable per-post
/// pseudonym (AnonIdentityService / get_thread_handles), the only identity
/// marker anon threads are allowed to show. Render its DP via
/// `AnonPersona.of(handle)` (anon_feed_models.dart) — a deterministic
/// glyph+color, same visual language the anon post card itself already
/// uses for its own author avatar, not a photo.
class AnonThreadComment {
  const AnonThreadComment({
    required this.id,
    required this.handle,
    required this.avatarUrl,
    required this.body,
    required this.createdAt,
    this.isMine = false,
  });

  /// `comments.id` — needed only so the row can be removed. Carrying it
  /// reveals nothing: it maps to no identity on its own.
  final String id;

  /// Whether the signed-in person wrote this one. Resolved inside the
  /// service by comparing the already-selected auth_id against the current
  /// session, so the real id never leaves the service.
  final bool isMine;

  /// The commenter's anonymous display name: their own persona
  /// (`users.anon_name` — the same identity the anon post card shows for a
  /// post's author), falling back to the per-post thread pseudonym from
  /// get_thread_handles. Never a real name.
  final String handle;

  /// `users.anon_photo_url` — the persona DP, never profile_photo_url.
  /// Null when the person hasn't set one; the row then draws its
  /// deterministic glyph instead.
  final String? avatarUrl;

  final String body;
  final DateTime createdAt;
}

class CommentService {
  CommentService._();
  static final instance = CommentService._();

  final _sb = Supabase.instance.client;

  Future<List<Comment>> fetchRecent({
    String? postId,
    String? groupPostId,
    int limit = 20,
  }) async {
    try {
      var query = _sb
          .from('comments')
          .select(
            'id, user_id, content, created_at, is_anonymous, '
            'users(name, profile_photo_url, anon_name, anon_photo_url)',
          );
      query = groupPostId != null
          ? query.eq('group_post_id', groupPostId)
          : query.eq('post_id', postId!);
      final rows = await query
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 8));

      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final user = r['users'] as Map?;
        return Comment(
          id: r['id'] as String,
          userId: r['user_id'] as String,
          name: (user?['name'] as String?) ?? 'someone',
          avatarUrl: user?['profile_photo_url'] as String?,
          body: r['content'] as String,
          createdAt: parsePostgresTimestamp(r['created_at'] as String),
          isAnonymous: r['is_anonymous'] as bool? ?? false,
          anonName: user?['anon_name'] as String?,
          anonAvatarUrl: user?['anon_photo_url'] as String?,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// [isAnonymousPost] routes to anon_post_comment_count() instead of a
  /// direct table read. comments_select denies anon-post rows (see
  /// 20260921050000), so the plain query below returns 0 for them — which
  /// would silently report "no comments" on every anonymous post rather
  /// than failing loudly.
  Future<int> fetchCount({
    String? postId,
    String? groupPostId,
    bool isAnonymousPost = false,
  }) async {
    try {
      if (isAnonymousPost && postId != null) {
        final n = await _sb
            .rpc('anon_post_comment_count', params: {'p_post_id': postId})
            .timeout(const Duration(seconds: 8));
        return (n as num?)?.toInt() ?? 0;
      }
      var query = _sb.from('comments').select('id');
      query = groupPostId != null
          ? query.eq('group_post_id', groupPostId)
          : query.eq('post_id', postId!);
      final rows = await query
          .isFilter('deleted_at', null)
          .timeout(const Duration(seconds: 8));
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> post({
    String? postId,
    String? groupPostId,
    required String body,
    bool anonymous = false,
  }) async {
    final userId = await CurrentUserService.instance.resolveId();
    // `comments` carries a `comments_post_xor_group_post` CHECK — exactly
    // one of post_id/group_post_id, never both — matching this method's own
    // exactly-one-of contract. group_post_id landed live in
    // 20260903030000_comments_group_post_id.sql (confirmed against the live
    // DB, not schema.sql, which is stale here) — group-post comments write
    // and read correctly now (the read side needed its own fix, see
    // 20260905020000_fix_comments_select.sql's doc).
    //
    // is_anonymous: BUG FIX — the composer's "Comment anonymously" toggle
    // used to reach only as far as this method's caller (its own preview
    // avatar), never persisted. See Comment.isAnonymous's own doc for the
    // display-side half of this fix.
    await _sb.from('comments').insert({
      if (postId != null) 'post_id': postId,
      if (groupPostId != null) 'group_post_id': groupPostId,
      'user_id': userId,
      'content': body,
      'is_anonymous': anonymous,
    });
  }

  /// Posts a comment on an ANONYMOUS post — same insert as [post], but also
  /// tags the row in `anonymous_comment_authors` so any future
  /// identity-aware consumer (moderation, say) can tell it apart from a
  /// named-post comment without inspecting the post's own visibility. The
  /// tag uses the raw Supabase Auth id (`anonymous_comment_authors.author_id`
  /// FKs to `profiles`, not `users` — see AnonIdentityService's own doc),
  /// not `users.id`.
  ///
  /// Best-effort on the tag: a failed tag insert does not undo or fail the
  /// comment post itself — worst case that one row falls back to
  /// fetchRecentAnon's generic "someone" label if its own handle lookup
  /// somehow also fails, never a lost comment.
  Future<void> postAnon({required String postId, required String body}) async {
    final userId = await CurrentUserService.instance.resolveId();
    final row = await _sb
        .from('comments')
        .insert({'post_id': postId, 'user_id': userId, 'content': body})
        .select('id')
        .single();

    final authId = _sb.auth.currentUser?.id;
    if (authId == null) return;
    try {
      await _sb.from('anonymous_comment_authors').insert({
        'comment_id': row['id'] as String,
        'author_id': authId,
      });
    } catch (_) {
      // Non-fatal — see doc above.
    }
  }

  /// Removes one comment. Allowed for the person who wrote it and for the
  /// owner of the post it sits under — the rule lives in the
  /// `delete_comment` RPC, not here, so every surface enforces the same one
  /// and a client can't widen it.
  ///
  /// Soft delete: the row stays, `deleted_at` is set, and every read path
  /// already filters on it. Throws with the server's own message on a
  /// refusal so the caller can show it.
  Future<void> deleteComment(String commentId) async {
    await _sb.rpc<dynamic>(
      'delete_comment',
      params: {'p_comment_id': commentId},
    );
  }

  /// Whether the signed-in person owns the post this comment surface is
  /// showing — i.e. whether they may remove OTHER people's comments on it.
  ///
  /// One boolean from the server rather than an ownership flag threaded
  /// through every call site, and it deliberately returns nothing else, so
  /// asking it on an anonymous post reveals no author identity.
  ///
  /// Fails closed: an error means "no", which only ever hides a Remove
  /// affordance the RPC would have honoured.
  Future<bool> iOwnPost({String? postId, String? groupPostId}) async {
    try {
      final v = await _sb.rpc<dynamic>(
        'i_own_post',
        params: {'p_post_id': postId, 'p_group_post_id': groupPostId},
      );
      return v == true;
    } catch (_) {
      return false;
    }
  }

  /// Recent comments on an ANONYMOUS post — deliberately never selects
  /// `users.name`/`profile_photo_url` (that's the leak the anon comment
  /// sheet used to be blocked on: comments_select's row-visibility hid
  /// these entirely from non-owners; now that it doesn't, this method must
  /// mask identity itself instead). Each commenter's real `user_id` is
  /// resolved only as far as `users.auth_id` (needed to call the handle
  /// RPCs — see AnonIdentityService's own doc on why), never returned to
  /// the caller.
  Future<List<AnonThreadComment>> fetchRecentAnon(String postId, {int limit = 20}) async {
    try {
      // anon_name/anon_photo_url, NOT name/profile_photo_url — the anon
      // persona is a real, stable identity in this app (it's what the post
      // card already renders for a post's own author), so a comment on an
      // anon post shows the commenter's persona and its DP. Real name and
      // real photo are still never selected here.
      // SECURITY: goes through anon_post_comments(), NOT a direct table
      // read. This used to select `users(auth_id, ...)`, and `users` is
      // readable by any authenticated caller — so every client received an
      // identifier that resolved the persona straight back to a real
      // account, no RLS bug required. The RPC never returns user_id or
      // auth_id at all, and resolves the per-post handle and "is this mine"
      // server-side, so there is nothing identifying left to hand over.
      //
      // comments_select also denies anon-post rows outright now (see
      // 20260921050000), so this RPC is the ONLY read path for them. Do not
      // "optimise" it back into a .from('comments') query.
      final rows = await _sb.rpc(
        'anon_post_comments',
        params: {'p_post_id': postId, 'p_limit': limit},
      ).timeout(const Duration(seconds: 8));

      final list = (rows as List).cast<Map<String, dynamic>>();

      return list.map((r) {
        final persona = (r['anon_name'] as String?)?.trim();
        final handle = (r['thread_handle'] as String?)?.trim();
        return AnonThreadComment(
          id: r['id'] as String,
          isMine: r['is_mine'] as bool? ?? false,
          // Persona first, per-post pseudonym as the fallback — unchanged
          // behaviour, both now resolved server-side.
          handle: (persona != null && persona.isNotEmpty)
              ? persona
              : ((handle != null && handle.isNotEmpty) ? handle : 'anonymous'),
          avatarUrl: r['anon_photo_url'] as String?,
          body: r['content'] as String,
          createdAt: parsePostgresTimestamp(r['created_at'] as String),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
