import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// NotificationFeedService — the real, persisted inbox (`notifications`
// table, supabase/migrations/20260907020000_notifications.sql). Five
// server-written types: reaction, ping, friend_request, friend_accepted,
// branch_view — each inserted by a SECURITY DEFINER trigger on the event's
// own table (reactions/pings/us_albums/group_invites/profile_views), never by the
// client. The client's only writes here are read_at (via markRead/
// markAllRead) — the table's RLS has no INSERT/DELETE policy for
// authenticated, and a BEFORE UPDATE trigger (lock_notification_fields)
// forces every other column back to its previous value even if a client
// tried to change it.
//
// Distinct from the pre-existing local/ephemeral banner+glass-toast system
// in notifications_screen.dart (NotifState's fire* methods) — that one is
// product-decided in-session UX (streak reminders, FOMO nudges, rank
// alerts) with no server backing and is untouched by this service.
// ---------------------------------------------------------------------------

class NotificationRow {
  const NotificationRow({
    required this.id,
    required this.type,
    required this.actorId,
    required this.tier,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.dedupeKey,
    this.actorName,
    this.revealedAt,
    this.postId,
    this.data = const {},
  });

  factory NotificationRow.fromMap(Map<String, dynamic> r) => NotificationRow(
        id: r['id'] as String,
        type: r['type'] as String,
        actorId: r['actor_id'] as String?,
        tier: r['tier'] as String,
        title: r['title'] as String,
        body: r['body'] as String?,
        isRead: r['read_at'] != null,
        createdAt: DateTime.parse(r['created_at'] as String),
        dedupeKey: r['dedupe_key'] as String?,
        // actor_id is a bare uuid on the row; the embed below resolves it
        // to a human name. Null whenever actor_id is null — which for a
        // ping is exactly the anonymous case (notify_ping() nulls actor_id
        // when pings.anonymous, so an anonymous sender is unresolvable by
        // construction rather than by client-side discipline).
        actorName: (r['actor'] as Map<String, dynamic>?)?['name'] as String?,
        revealedAt: r['revealed_at'] == null
            ? null
            : DateTime.parse(r['revealed_at'] as String),
        postId: r['post_id'] as String?,
        data: (r['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  final String id;
  final String type; // reaction | ping | us_album_invite | group_invite | branch_view | …

  /// The row's `data` jsonb (screen routing + ids, e.g. album_id / group_id
  /// / invite_id for the two invite types).
  final Map<String, dynamic> data;
  final String? actorId;
  final String tier; // minor | standard | major
  final String title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;

  /// `'ping:<pings.id>'` for a ping/photoReply notification (set by
  /// notify_ping(), supabase/migrations/20260907020000_notifications.sql) —
  /// the only way to recover which `pings` row a notification is about,
  /// since the row itself carries no separate ping_id column. Null for
  /// every other notification type.
  final String? dedupeKey;

  /// The actor's display name, resolved through the actor_id FK. Null when
  /// there is no actor (system notification) or the actor was deliberately
  /// withheld (anonymous ping).
  final String? actorName;

  /// When the recipient hold-revealed [actorName] on this notification.
  /// Null means still blurred. See notifications.revealed_at.
  final DateTime? revealedAt;

  bool get isRevealed => revealedAt != null;

  /// The post this notification is ABOUT, when there is one — reactions,
  /// comments, moment activity. FK is ON DELETE SET NULL, so a deleted
  /// post leaves this null rather than dangling, which is exactly the
  /// signal the tap handler needs to fall back to the feed.
  final String? postId;
}

class NotificationFeedService {
  NotificationFeedService._();
  static final instance = NotificationFeedService._();

  final _sb = Supabase.instance.client;

  Future<List<NotificationRow>> fetchPage({int limit = 50}) async {
    final rows = await _sb
        .from('notifications')
        // actor:users!... — the FK must be named explicitly. `notifications`
        // has TWO foreign keys into users (actor_id and recipient_id), and
        // an unqualified `users(...)` embed is rejected outright with
        // PGRST201 ("more than one relationship found") rather than picking
        // one. Naming the constraint is the disambiguation PostgREST wants.
        .select('id, type, actor_id, tier, title, body, read_at, revealed_at, '
            'created_at, dedupe_key, data, '
            'actor:users!notifications_actor_id_fkey(name)')
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(const Duration(seconds: 8));
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(NotificationRow.fromMap)
        .toList();
  }

  Future<int> fetchUnreadCount() async {
    final rows = await _sb
        .from('notifications')
        .select('id')
        .isFilter('read_at', null)
        .timeout(const Duration(seconds: 8));
    return (rows as List).length;
  }

  Future<void> markRead(String id) async {
    await _sb.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  /// Records that the recipient unblurred this notification's actor name.
  /// Fails soft: a lost write just means the name is blurred again next
  /// time, which is the safe direction — it never reveals something that
  /// should not be revealed.
  Future<void> markRevealed(String id) async {
    try {
      await _sb
          .from('notifications')
          .update({'revealed_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    await _sb.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).isFilter('read_at', null);
  }

  /// Marks exactly these rows read — backs NotifState.markPingsRead, which
  /// clears the Ping tab's badge without touching other notification types.
  Future<void> markManyRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _sb
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', ids);
  }

  /// Realtime stream of this user's notifications, most-recent-first —
  /// same idiom as the community realtime subscriptions in
  /// 20260904020000_community_realtime.sql. RLS already scopes this to the
  /// signed-in user's own rows.
  Stream<List<NotificationRow>> watch() {
    return _sb
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(NotificationRow.fromMap).toList());
  }
}
