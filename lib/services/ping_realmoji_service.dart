import '../core/supabase_config.dart';
import 'realmoji_service.dart';

// ---------------------------------------------------------------------------
// PingRealmojiService — RealMoji reactions inside Ping (explicit request,
// 2026-10-03: "make the reactions in ping RealMoji reactions same as the
// friends feed, and create a mechanism to see those reactions").
//
// Same model as the feed: a reaction stores only WHICH emoji, and the
// picture is the reactor's own saved selfie for it (user_realmojis). It just
// targets ping things instead of posts:
//   * replyId — a reply to one of my pings, or a group wall answer
//   * pingId  — a one-to-one ping someone sent me
//
// Server: ping_realmoji_reactions + react_ping_realmoji/unreact_ping_realmoji
// + ping_realmojis_for (20261003100000, 20261003110000). RLS decides who may
// react and who may see; the replier / pinger always sees who reacted.
// ---------------------------------------------------------------------------

class PingRealmoji {
  const PingRealmoji({
    required this.userId,
    required this.name,
    required this.type,
    required this.isMine,
    this.replyId,
    this.pingId,
    this.imageUrl,
  });

  final String? replyId;
  final String? pingId;
  final String userId;
  final String name;
  final RealmojiType type;

  /// The reactor's saved selfie for [type]. Null when they never captured
  /// one for that emoji — the emoji glyph stands in.
  final String? imageUrl;
  final bool isMine;

  factory PingRealmoji.fromRow(Map<String, dynamic> r) => PingRealmoji(
    replyId: r['ping_reply_id'] as String?,
    pingId: r['ping_id'] as String?,
    userId: r['user_id'] as String,
    name: (r['name'] as String?) ?? 'Someone',
    type: realmojiTypeFromWire((r['emoji_type'] as String?) ?? 'like'),
    imageUrl: r['image_url'] as String?,
    isMine: r['is_mine'] == true,
  );
}

class PingRealmojiService {
  PingRealmojiService._();
  static final instance = PingRealmojiService._();

  /// React (or change my reaction) on a reply or a ping.
  Future<void> react({
    String? replyId,
    String? pingId,
    required RealmojiType type,
  }) async {
    await supabase.rpc(
      'react_ping_realmoji',
      params: {'p_reply': replyId, 'p_ping': pingId, 'p_type': type.wire},
    );
  }

  Future<void> unreact({String? replyId, String? pingId}) async {
    await supabase.rpc(
      'unreact_ping_realmoji',
      params: {'p_reply': replyId, 'p_ping': pingId},
    );
  }

  /// Every reaction on these targets the caller may see, newest first.
  Future<List<PingRealmoji>> fetchFor({
    List<String> replyIds = const [],
    List<String> pingIds = const [],
  }) async {
    if (replyIds.isEmpty && pingIds.isEmpty) return const [];
    final rows = await supabase
        .rpc(
          'ping_realmojis_for',
          params: {'p_reply_ids': replyIds, 'p_ping_ids': pingIds},
        )
        .timeout(const Duration(seconds: 8)) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(PingRealmoji.fromRow)
        .toList();
  }
}
