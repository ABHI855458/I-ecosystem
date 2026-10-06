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

/// One of MY ping replies that somebody reacted to — the "reactions on your
/// replies" row in the Ping page. Survives the ping itself: a ping expires 6
/// hours after it's sent, which used to take the only view of its reactions
/// with it (reported 2026-10-04).
class MyReplyReactions {
  const MyReplyReactions({
    required this.replyId,
    required this.kind,
    required this.otherName,
    required this.isGroup,
    required this.reactions,
    this.photoUrl,
    this.body,
  });

  final String replyId;
  final String kind;
  final String otherName;
  final bool isGroup;
  final String? photoUrl;
  final String? body;
  final List<PingRealmoji> reactions;

  bool get isPhoto => kind == 'photo';

  factory MyReplyReactions.fromRow(Map<String, dynamic> r) => MyReplyReactions(
    replyId: r['reply_id'] as String,
    kind: (r['kind'] as String?) ?? 'text',
    otherName: (r['other_name'] as String?) ?? 'Someone',
    isGroup: r['is_group'] == true,
    photoUrl: r['photo_url'] as String?,
    body: r['body'] as String?,
    reactions: [
      for (final x in (r['reactions'] as List? ?? const []))
        PingRealmoji.fromRow(Map<String, dynamic>.from(x as Map)),
    ],
  );
}

extension MyReplyReactionsApi on PingRealmojiService {
  /// Reactions on the replies I sent, newest first (my_ping_reply_reactions).
  Future<List<MyReplyReactions>> fetchMyReplyReactions() async {
    try {
      final rows = await supabase
          .rpc('my_ping_reply_reactions')
          .timeout(const Duration(seconds: 8)) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(MyReplyReactions.fromRow)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
