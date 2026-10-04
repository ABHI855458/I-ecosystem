import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// AnonIdentityService — wraps the live `get_thread_handle` /
// `get_thread_handles` RPCs (see supabase/migrations/
// 20260905030000_thread_handles_batch_rpc.sql), which mint and resolve a
// stable per-post pseudonym ("quiet_owl42") so anon-post comments can show
// WHO said something without ever revealing real identity. Nothing in this
// app called either RPC before this — the anon comment sheet previously
// rendered hardcoded fake names (kAnonComments) instead.
//
// IMPORTANT: both RPCs are keyed on the raw Supabase Auth id (`auth.uid()`,
// = `profiles.id` — a separate legacy identity table this app barely
// touches), NOT this app's own `users.id` that CommentService/comments.user_id
// use everywhere else. Never pass a `users.id` here — resolve it to
// `users.auth_id` first (CommentService.fetchRecentAnon does this via the
// `users(auth_id)` embed).
// ---------------------------------------------------------------------------

class AnonIdentityService {
  AnonIdentityService._();
  static final instance = AnonIdentityService._();

  final _sb = Supabase.instance.client;

  /// The CALLER's own stable pseudonym for [postId] — minted on first call.
  /// Only ever resolves your own identity (RLS on post_thread_handles
  /// blocks reading anyone else's row directly); use [handlesFor] to
  /// resolve other people's, via the SECURITY DEFINER batch RPC.
  Future<String?> myHandle(String postId) async {
    try {
      final res = await _sb.rpc('get_thread_handle', params: {'p_post': postId});
      return res as String?;
    } catch (_) {
      return null;
    }
  }

  /// Batch-resolves pseudonyms for [authIds] (raw Supabase Auth ids, NOT
  /// `users.id`) on [postId]. Returns a map from authId to handle; ids that
  /// fail to resolve (shouldn't happen for a real signed-in user, but the
  /// RPC swallows nothing given it's meant to run for every commenter) are
  /// simply absent from the result — callers fall back to a generic label.
  Future<Map<String, String>> handlesFor(String postId, Iterable<String> authIds) async {
    final ids = authIds.toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _sb.rpc(
        'get_thread_handles',
        params: {'p_post': postId, 'p_user_ids': ids},
      );
      final out = <String, String>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        out[r['user_id'] as String] = r['handle'] as String;
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
