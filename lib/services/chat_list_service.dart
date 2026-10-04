import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// ChatListService — the Community tab's WhatsApp-style list of every
// community I've joined and every group I'm in (explicit request,
// 2026-10-02/03), backed by the my_chat_list() RPC
// (20261003010000_my_chat_list.sql): one row per chat with its newest
// message + time.
//
// Unread / priority are worked out HERE, against a per-chat "last opened"
// timestamp kept on the device — the server keeps no read state for these.
// ---------------------------------------------------------------------------

enum ChatKind { community, group }

class ChatSummary {
  const ChatSummary({
    required this.kind,
    required this.id,
    required this.name,
    this.iconUrl,
    this.lastText,
    this.lastAt,
    this.priorityAt,
    this.memberCount = 0,
    this.lastOpenedAt,
    this.memberAvatars = const [],
  });

  /// Groups only: up to 3 member photos — drawn stacked when the group has
  /// no DP of its own ([iconUrl]), same as the Ping page's group chips.
  final List<String> memberAvatars;

  final ChatKind kind;
  final String id;
  final String name;
  final String? iconUrl;
  final String? lastText;
  final DateTime? lastAt;

  /// Community: newest priority notice (last 7 days). Group: newest group
  /// ping still waiting on my answer.
  final DateTime? priorityAt;
  final int memberCount;
  final DateTime? lastOpenedAt;

  String get key => '${kind.name}:$id';

  /// Something new since I last opened it.
  bool get unread =>
      lastAt != null && (lastOpenedAt == null || lastAt!.isAfter(lastOpenedAt!));

  /// Goes in the PRIORITY section: a COMMUNITY priority notice I haven't
  /// opened the chat since. Groups never do (explicit request, 2026-10-03:
  /// "group chat shall not have priority ... communities shall").
  bool get isPriority {
    if (kind == ChatKind.group) return false;
    final p = priorityAt;
    if (p == null) return false;
    return lastOpenedAt == null || p.isAfter(lastOpenedAt!);
  }
}

class ChatListService {
  ChatListService._();
  static final instance = ChatListService._();

  static const _prefPrefix = 'chat_last_opened:';

  Future<List<ChatSummary>> fetch() async {
    final rows = await supabase
        .rpc('my_chat_list')
        .timeout(const Duration(seconds: 10)) as List;
    final prefs = await SharedPreferences.getInstance();
    DateTime? ts(Object? v) =>
        v == null ? null : DateTime.tryParse(v as String)?.toUtc();
    final out = <ChatSummary>[];
    for (final r in rows.cast<Map<String, dynamic>>()) {
      final kind = r['kind'] == 'group' ? ChatKind.group : ChatKind.community;
      final id = r['id'] as String;
      final opened = prefs.getString('$_prefPrefix${kind.name}:$id');
      out.add(
        ChatSummary(
          kind: kind,
          id: id,
          name: (r['name'] as String?)?.trim().isNotEmpty == true
              ? r['name'] as String
              : (kind == ChatKind.group ? 'Group' : 'Community'),
          iconUrl: r['icon_url'] as String?,
          lastText: r['last_text'] as String?,
          lastAt: ts(r['last_at']),
          priorityAt: ts(r['priority_at']),
          memberCount: (r['member_count'] as num?)?.toInt() ?? 0,
          lastOpenedAt: opened == null ? null : DateTime.tryParse(opened),
          memberAvatars: [
            for (final u in (r['member_avatars'] as List?) ?? const [])
              if (u is String && u.isNotEmpty) u,
          ],
        ),
      );
    }
    // Newest activity first; chats with nothing yet sink, by name.
    out.sort((a, b) {
      final x = a.lastAt, y = b.lastAt;
      if (x == null && y == null) return a.name.compareTo(b.name);
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return out;
  }

  Future<void> markOpened(ChatSummary c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefPrefix${c.key}',
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}
