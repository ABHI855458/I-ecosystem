import '../core/supabase_config.dart';
import '../shared/time_ago.dart' show parsePostgresTimestamp;
import 'current_user_service.dart';

// ---------------------------------------------------------------------------
// PingService — real persistence for person, group, and anonymous pings.
//
// Group and anonymous pings used to be entirely fake: pingGroupMembers()
// wrote plain `pings` rows with no way to tell N of them were one logical
// ping (no group wall, nobody saw anyone else's reply), and an anonymous
// send was skipped client-side before it ever reached the database. See
// supabase/migrations/20260906000000_ping_threads_group_wall_and_anonymity.sql
// for the schema/RLS this method set assumes: every ping now belongs to a
// `ping_threads` row (one thread = one logical ping, however many `pings`
// rows it fans out to), and every read goes through a SECURITY DEFINER RPC
// rather than a raw `.from('pings').select(...)` — that's what makes an
// anonymous sender's identity actually unrecoverable by the client, not just
// unlabeled in the UI. notify-ping / notify-ping-reply are NOT wired to any
// trigger on the live DB — no push fires on send/reply, same as most of this
// app's other notify_webhook hooks (see project memory on schema.sql drift).
// ---------------------------------------------------------------------------

/// One reply I sent to an inbound ping, with how many likes it got — the
/// server-side record behind the "📷 Photo sent" receipt rows (ping_inbox's
/// my_replies).
class MyPingReply {
  const MyPingReply({
    required this.isPhoto,
    required this.body,
    required this.likes,
    this.id,
  });

  /// `ping_replies.id` — what the RealMoji reactions on MY reply are keyed
  /// by, so the Ping page can show who reacted to a photo I sent (added
  /// 20261004020000_ping_inbox_my_reply_id.sql). Null on older payloads.
  final String? id;
  final bool isPhoto;
  final String? body;
  final int likes;

  factory MyPingReply.fromJson(Map<String, dynamic> m) => MyPingReply(
    id: m['id'] as String?,
    isPhoto: m['kind'] == 'photo',
    body: m['body'] as String?,
    likes: (m['likes'] as num?)?.toInt() ?? 0,
  );
}

class InboundPingRow {
  const InboundPingRow({
    required this.id,
    required this.threadId,
    required this.kind,
    required this.senderId,
    required this.senderName,
    required this.senderAvatarUrl,
    required this.prompt,
    required this.sentAt,
    required this.windowHours,
    this.closesAt,
    required this.isAnon,
    required this.groupId,
    required this.groupName,
    required this.groupSize,
    this.photoUrl,
    this.seenAt,
    this.photoOpenedAt,
    this.myReplies = const [],
  });

  /// My replies to this ping, oldest first, each with its like count.
  final List<MyPingReply> myReplies;

  /// `pings.seen_at` — when the RECEIVER held to reveal this ping, written
  /// by mark_ping_seen (PingService.markSeen, called from
  /// PingPage.finishHold). Null means never revealed.
  ///
  /// This is what makes a reveal survive a relaunch: PingPage's `revealed`
  /// map is in-memory only, so without a server-side record every app
  /// start re-blurred pings the user had already opened.
  final DateTime? seenAt;

  /// A photo the asker attached to the ping itself (`pings.photo_url`).
  /// Null for a text-only ping, which is every ping sent before the
  /// ping_photo migration.
  final String? photoUrl;

  /// `pings.photo_opened_at` — when I (the receiver) burned my one-time view
  /// of [photoUrl] (mark_ping_photo_opened, called the instant the full-
  /// screen photo viewer opens). Null means never opened — the photo is
  /// still a live, viewable tease. Non-null means it's gone for good: the
  /// card shows a locked "photo viewed" placeholder instead, same one-time
  /// contract a reply's photo already has.
  final DateTime? photoOpenedAt;

  final String id;
  final String threadId;

  /// 'person' | 'group'.
  final String kind;

  /// Null when [isAnon] — that absence IS the masking; there is no real id
  /// to resolve on the client for an anonymous ping.
  final String? senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String prompt;
  final DateTime sentAt;
  final int windowHours;

  /// `pings.expires_at` — when this ping CLOSES: 6h after it was opened, or
  /// 24h after it was sent if it never was. Server-generated, so the client
  /// no longer derives expiry from windowHours (which stopped describing
  /// the close time when the lifecycle changed).
  final DateTime? closesAt;
  final bool isAnon;
  final String? groupId;
  final String? groupName;
  final int groupSize;

  bool get isGroup => kind == 'group';

  /// Server value when present; the old windowHours rule only as a fallback
  /// for a row fetched before the column existed.
  DateTime get expiresAt =>
      closesAt ?? sentAt.add(Duration(hours: windowHours));
  bool get expired => DateTime.now().isAfter(expiresAt);
}

class OutboundPingRow {
  const OutboundPingRow({
    required this.id,
    required this.receiverId,
    required this.receiverName,
    required this.receiverAvatarUrl,
    required this.prompt,
    required this.sentAt,
    required this.seenAt,
    required this.replied,
    this.receiverHidden = false,
    this.threadId,
    this.isGroup = false,
    this.groupId,
  });

  final String id;
  final String receiverId;

  /// A group ping's per-member row — its replies belong on the Group Wall,
  /// so it is never folded into a multi-person card.
  final bool isGroup;

  /// `pings.group_id` for a group ping, else null. Lets the Ping page tell
  /// WHICH group a still-open ping of mine belongs to, so that group's chip
  /// can drop out of the strip until the window closes.
  final String? groupId;

  /// `pings.thread_id`. Pings from one multi-person send share it (see
  /// [PingService.sendMulti]); the Ping page groups them into one card.
  final String? threadId;

  /// What to SHOW for the recipient. Already masked where it has to be —
  /// see [receiverHidden]; the real name never reaches this field in that
  /// case, so no render site has to remember to check.
  final String receiverName;
  final String? receiverAvatarUrl;
  final String prompt;
  final DateTime sentAt;
  final DateTime? seenAt;
  final bool replied;

  /// `pings.receiver_hidden` — this ping went to an anonymous post's author
  /// via ping_post_author(), so the sender is not entitled to their real
  /// identity. [receiverName]/[receiverAvatarUrl] carry the recipient's
  /// anon persona instead.
  final bool receiverHidden;

  bool get seen => seenAt != null;
}

/// How long the "Ping back" CTA stays on an Open Loops row after the reply
/// was viewed (explicit request, 2026-10-03). Shared by
/// [ReceivedReplyRow.pingBackAvailable] and the Ping page's own countdown
/// label, so the button and the time it shows can never disagree.
const kPingBackWindow = Duration(hours: 48);

class ReceivedReplyRow {
  const ReceivedReplyRow({
    required this.replyId,
    required this.pingId,
    required this.replierId,
    required this.replierName,
    required this.replierAvatarUrl,
    required this.prompt,
    required this.kind,
    required this.body,
    required this.photoUrl,
    required this.createdAt,
    required this.viewed,
    required this.viewedAt,
    this.isAnon = false,
    this.groupName,
    this.selfieUrl,
    this.pingedBack = false,
    this.reactionCount = 0,
    this.myReaction = false,
    this.threadId,
  });

  final String replyId;
  final String pingId;

  /// The replied-to ping's `thread_id` — places this reply in its
  /// multi-person card's slot on the Ping page.
  final String? threadId;

  /// Real, resolvable even when the ORIGINAL ping (below) was anonymous —
  /// replying always identifies the replier to the ping's sender. Only the
  /// sender's identity can ever be hidden in this app's anonymity model,
  /// never the replier's, so "ping them back" from a received reply is
  /// always a normal, real-identity send.
  final String replierId;
  final String replierName;
  final String? replierAvatarUrl;
  final String prompt;
  final String kind; // 'photo' | 'text'
  final String? body;
  final String? photoUrl;

  /// The front-camera half of a dual capture (see PingCameraScreen,
  /// ping_reveal_screen.dart) — null for an album-picked photo or a
  /// text-only reply, which is what tells the top-left inset render sites
  /// not to show one at all.
  final String? selfieUrl;
  final DateTime createdAt;
  final bool viewed;
  final DateTime? viewedAt;

  /// True when the ORIGINAL PING (not this reply) was sent anonymously —
  /// the reply itself always identifies its author to the ping's sender
  /// (that's what "replying" means), this only affects how the row that
  /// prompted it should be labeled.
  final bool isAnon;
  final String? groupName;

  /// `pings.pinged_back_at IS NOT NULL` — this specific original ping has
  /// already been pinged back once, ever. Durable (survives an app
  /// restart), unlike the old purely in-memory tracking that let the
  /// button show as available again the moment the screen remounted. See
  /// 20260921020000_ping_back_once_only.sql: the server now enforces this
  /// as the real one-time gate; this field is what lets the button agree
  /// with it from a fresh load instead of a stale local guess.
  final bool pingedBack;

  /// Ping-back CTA is live for 48 HOURS after the reply was viewed, and
  /// only once per original ping (explicit request, 2026-10-03: "let the
  /// ping back button be there for 48 hrs under open loops"). It was 24h,
  /// then 5 days to match ping_back_anonymous()'s server window
  /// (20260907010000_pingback_window_5_days.sql) — 48h is stricter than
  /// that server gate, so the anonymous path still can't outlive what the
  /// server allows; it just closes the loop sooner.
  bool get pingBackAvailable {
    if (pingedBack) return false;
    final v = viewedAt;
    if (v == null) return false;
    return DateTime.now().difference(v) < kPingBackWindow;
  }

  /// Total hearts on this reply — from `ping_reply_reactions`, unified
  /// across 1:1 and group walls (see toggle_ping_reply_reaction's own doc).
  /// For a 1:1 reply this is 0 or 1 forever: only the ping's sender may ever
  /// react, and that's who's reading this row.
  final int reactionCount;

  /// Whether I (the caller, i.e. the ping's sender) am one of the reactors.
  /// Only ever true from my own read of my own inbox.
  final bool myReaction;
}

/// One member's slot on a Group Wall (see `get_group_wall` RPC).
class WallSlot {
  const WallSlot({
    required this.memberId,
    required this.memberName,
    required this.memberAvatarUrl,
    required this.isMe,
    required this.answered,
    required this.replyId,
    required this.replyKind,
    required this.replyBody,
    required this.photoUrl,
    required this.repliedAt,
    required this.opened,
    this.selfieUrl,
    this.reactionCount = 0,
    this.myReaction = false,
  });

  final String memberId;
  final String memberName;
  final String? memberAvatarUrl;
  final bool isMe;
  final bool answered;

  /// Every field below is null while the caller hasn't unlocked the wall
  /// yet (server-enforced by get_group_wall, not just hidden client-side) —
  /// even for a member who HAS answered.
  final String? replyId;
  final String? replyKind;
  final String? replyBody;
  final String? photoUrl;

  /// The front-camera half of a dual capture — see
  /// [ReceivedReplyRow.selfieUrl]'s own doc, same null-means-no-inset rule.
  final String? selfieUrl;
  final DateTime? repliedAt;
  final bool opened;

  /// Hearts on this member's reply, from `ping_reply_reactions` — visible to
  /// any member who has answered the thread (that's what unlocks the wall),
  /// not just this slot's own owner. 0/false (never gated) for a locked
  /// wall — get_group_wall zeroes both server-side, same as every other
  /// reply field.
  final int reactionCount;

  /// Whether I (the caller) am one of the reactors on THIS slot's reply.
  final bool myReaction;
}

/// One active group ping thread (see `my_group_walls` RPC) — the card-level
/// data `ping_page.dart` needs to render one Group Wall per thread.
class WallThread {
  const WallThread({
    required this.threadId,
    required this.groupId,
    required this.groupName,
    required this.prompt,
    required this.createdAt,
    required this.windowHours,
    required this.anonymous,
    required this.askedBy,
    required this.myPingId,
    required this.unlocked,
    required this.answered,
    required this.total,
    this.photoUrl,
    this.groupIconUrl,
  });

  /// The group's own DP (`groups.icon_url`). Null when the group has no
  /// photo set — the wall header then falls back to the overlapping
  /// member stack, same as it always did. Added to my_group_walls in
  /// 20260921010000; older clients simply don't read the column.
  final String? groupIconUrl;

  /// The photo the asker attached (`ping_threads.photo_url`), null for a
  /// text-only ask.
  final String? photoUrl;

  final String threadId;
  final String groupId;
  final String groupName;
  final String prompt;
  final DateTime createdAt;
  final int windowHours;
  final bool anonymous;
  final String askedBy;

  /// The ping row the caller replies to. Null only for the named (non-
  /// anonymous) asker themselves — they didn't get a fan-out row, since
  /// everyone already knows they asked.
  final String? myPingId;
  final bool unlocked;
  final int answered;
  final int total;
}

class PingLimitExceeded implements Exception {
  const PingLimitExceeded();
  @override
  String toString() => 'Ping limit reached (5 per 24h).';
}

/// The group has no one but you in it yet (everyone else is still only
/// invited) — send_group_ping refuses to ping it.
class PingGroupWaitingForMembers implements Exception {
  const PingGroupWaitingForMembers();
  @override
  String toString() => 'Waiting for members to join this group.';
}

/// You already have a live ping sitting with this person.
///
/// One open ping per pair — a ping closes 6h after they open it, or 24h if
/// they never do (pings.expires_at, generated). Only then can the same
/// person be pinged again. Raised by send_ping as
/// `PING_ALREADY_OPEN:<iso8601>`.
class PingAlreadyOpen implements Exception {
  const PingAlreadyOpen(this.opensAt);

  /// When the existing ping closes, so the message can say when rather than
  /// just no.
  final DateTime? opensAt;

  @override
  String toString() {
    final at = opensAt;
    if (at == null) return 'You already have an open ping with them.';
    final left = at.difference(DateTime.now());
    if (left.isNegative) return 'You already have an open ping with them.';
    if (left.inHours >= 1) {
      return 'You already pinged them — you can ping again in ${left.inHours}h.';
    }
    return 'You already pinged them — you can ping again in ${left.inMinutes}m.';
  }
}

/// Pinging your own post — send_ping's own direct self-ping guard, and
/// ping_post_author's own version of it for the anon/friends "ping the
/// author" path. Reacting is still fine; only pinging yourself is blocked.
class PingSelfNotAllowed implements Exception {
  const PingSelfNotAllowed();
  @override
  String toString() => 'You cannot ping yourself.';
}

/// A block exists between the two people, either direction. send_ping
/// already raises 'Cannot ping this user.' for this (see that RPC's own
/// "THE FIX." comment) — this maps that server text into a typed exception
/// the same way the other three are, so the UI can show a specific message
/// instead of the generic fallback every unrecognized error gets.
class PingBlocked implements Exception {
  const PingBlocked();
  @override
  String toString() => "You can't send a ping to this person.";
}

/// This specific original ping has already been pinged back once — see
/// ping_back_anonymous's own doc (20260921020000_ping_back_once_only.sql)
/// on the durable server-side guard this maps. A stale UI (a reply row
/// fetched before this ping was pinged back from another device, say)
/// hitting this is expected and not a bug; the fresh fetch that follows
/// will show the button correctly disabled going forward.
class PingBackAlreadyUsed implements Exception {
  const PingBackAlreadyUsed();
  @override
  String toString() => 'You already pinged back on this.';
}

class PingService {
  PingService._();
  static final instance = PingService._();

  Never _mapLimitError(Object e) {
    final text = e.toString();
    if (text.contains('Ping limit reached')) {
      throw const PingLimitExceeded();
    }
    if (text.contains('Waiting for members to join')) {
      throw const PingGroupWaitingForMembers();
    }
    if (text.contains('Cannot ping yourself') ||
        text.contains('You cannot ping yourself')) {
      throw const PingSelfNotAllowed();
    }
    if (text.contains('Cannot ping this user')) {
      throw const PingBlocked();
    }
    if (text.contains('You already pinged back on this')) {
      throw const PingBackAlreadyUsed();
    }
    // send_ping raises PING_ALREADY_OPEN:<iso8601> when the sender still has
    // a live ping with this person — see PingAlreadyOpen.
    final marker = text.indexOf('PING_ALREADY_OPEN:');
    if (marker != -1) {
      final tail = text.substring(marker + 'PING_ALREADY_OPEN:'.length);
      final stamp = RegExp(
        r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z',
      ).firstMatch(tail)?.group(0);
      throw PingAlreadyOpen(
        stamp == null ? null : DateTime.tryParse(stamp)?.toLocal(),
      );
    }
    throw e;
  }

  /// Sends a single person-to-person ping, real or anonymous. Throws
  /// [PingLimitExceeded] if the sender has already sent 5 logical pings
  /// (thread_id-deduped, so a group fan-out costs 1, not N) in the last 24h.
  Future<void> send({
    required String receiverId,
    required String prompt,
    bool anonymous = false,
    String? photoUrl,
  }) async {
    try {
      await supabase.rpc(
        'send_ping',
        params: {
          'p_receiver_id': receiverId,
          'p_prompt': prompt,
          'p_anonymous': anonymous,
          if (photoUrl != null) 'p_photo_url': photoUrl,
        },
      );
    } on Object catch (e) {
      _mapLimitError(e);
    }
  }

  /// A ping sent as an answer to someone who pinged me or replied to me —
  /// same send_ping underneath, but flags the row so notify_ping titles it
  /// "X pinged you back" instead of the ordinary greeting (explicit
  /// request, 2026-10-02). Same 5-per-24h quota as [send].
  Future<void> sendPingBack(String receiverId) async {
    try {
      await supabase.rpc(
        'send_ping_back',
        params: {'p_receiver_id': receiverId},
      );
    } on Object catch (e) {
      _mapLimitError(e);
    }
  }

  /// Sends ONE ping to several people at once — a single shared thread
  /// (send_ping_multi), so it costs 1 of the 5-per-24h quota and every
  /// reply lands in one card on the sender's Ping page. Each reply stays
  /// private between the sender and that recipient. People who are
  /// blocked or already hold an open ping from me are skipped, not fatal.
  Future<
    ({int sent, int alreadyOpen, int blocked, List<String> alreadyOpenNames})
  >
  sendMulti({
    required List<String> receiverIds,
    required String prompt,
    bool anonymous = false,
    String? photoUrl,
  }) async {
    try {
      final res =
          await supabase.rpc(
                'send_ping_multi',
                params: {
                  'p_receiver_ids': receiverIds,
                  'p_prompt': prompt,
                  'p_anonymous': anonymous,
                  if (photoUrl != null) 'p_photo_url': photoUrl,
                },
              )
              as Map<String, dynamic>;
      return (
        sent: (res['sent'] as num?)?.toInt() ?? 0,
        alreadyOpen: (res['already_open'] as num?)?.toInt() ?? 0,
        blocked: (res['blocked'] as num?)?.toInt() ?? 0,
        alreadyOpenNames: [
          for (final n in (res['already_open_names'] as List?) ?? const [])
            '$n',
        ],
      );
    } on Object catch (e) {
      _mapLimitError(e);
    }
  }

  /// Pings every member of [groupId] (all of them, if [anonymous] — see the
  /// migration's own doc on why the asker answers their own prompt in that
  /// case; everyone but the sender otherwise). Returns the recipient count
  /// for the "Pinged N members" toast.
  Future<int> pingGroupMembers({
    required String groupId,
    required String prompt,
    bool anonymous = false,
    String? photoUrl,
  }) async {
    try {
      final rows = await supabase.rpc(
        'send_group_ping',
        params: {
          'p_group_id': groupId,
          'p_prompt': prompt,
          'p_anonymous': anonymous,
          if (photoUrl != null) 'p_photo_url': photoUrl,
        },
      );
      final row = (rows as List).cast<Map<String, dynamic>>().first;
      return (row['recipients'] as num?)?.toInt() ?? 0;
    } on Object catch (e) {
      _mapLimitError(e);
    }
  }

  /// People who have pinged me 1:1 (named, not anonymous) in the last 30
  /// days, most recent first — the PEOPLE half of the "Send to…" picker.
  /// `(id, name, avatarUrl)`; empty on failure.
  Future<List<(String, String, String?)>> fetchPeopleWhoPingedMe() async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final since = DateTime.now().toUtc().subtract(const Duration(days: 30));
      final rows = await supabase
          .from('pings')
          .select(
            'sender_id, created_at, sender:users!pings_sender_id_fkey(name, profile_photo_url)',
          )
          .eq('receiver_id', myId)
          .isFilter('group_id', null)
          .eq('anonymous', false)
          .neq('sender_id', myId)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: false)
          .limit(200)
          .timeout(const Duration(seconds: 8));
      final seen = <String>{};
      return [
        for (final r in rows as List)
          if (seen.add(r['sender_id'] as String))
            (
              r['sender_id'] as String,
              ((r['sender'] as Map?)?['name'] as String?) ?? 'someone',
              (r['sender'] as Map?)?['profile_photo_url'] as String?,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Alias kept for call-site clarity — group-ping entry points read better
  /// calling `sendGroupPing` than the historically-named `pingGroupMembers`.
  Future<int> sendGroupPing({
    required String groupId,
    required String prompt,
    bool anonymous = false,
    String? photoUrl,
  }) => pingGroupMembers(
    groupId: groupId,
    prompt: prompt,
    anonymous: anonymous,
    photoUrl: photoUrl,
  );

  /// Pings sent TO me that I haven't replied to yet and are still inside
  /// their reply window — person and group, real-identity and anonymous,
  /// all through the one masked `ping_inbox()` RPC so an anonymous sender's
  /// real id/name/avatar never reaches the client at all.
  ///
  /// Returns `null` on failure (network timeout, no session) rather than an
  /// empty list — an empty list means "genuinely nothing to reply to" and a
  /// caller that can't tell the difference will happily overwrite a real,
  /// still-valid inbox with nothing the moment one request drops a packet.
  /// [PingPage] relies on this: it keeps the previous list on `null` instead
  /// of blanking the screen.
  ///
  /// Deliberately does NOT filter to `status == 'pending'` — a ping stays
  /// answerable, and its card stays visible, for its whole reply window even
  /// after the first reply lands (multiple replies within the window are
  /// allowed); [InboundPingRow.expired] is what actually retires a card.
  Future<List<InboundPingRow>?> fetchToReply() async {
    try {
      final rows = await supabase
          .rpc('ping_inbox')
          .timeout(const Duration(seconds: 8));

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map((r) {
            return InboundPingRow(
              id: r['ping_id'] as String,
              threadId: r['thread_id'] as String,
              kind: r['kind'] as String? ?? 'person',
              senderId: r['sender_id'] as String?,
              senderName: (r['sender_name'] as String?) ?? 'someone',
              senderAvatarUrl: r['sender_avatar'] as String?,
              prompt: r['prompt'] as String,
              sentAt: parsePostgresTimestamp(r['created_at'] as String),
              windowHours: (r['window_hours'] as num?)?.toInt() ?? 6,
              closesAt: r['expires_at'] != null
                  ? DateTime.tryParse(r['expires_at'] as String)?.toLocal()
                  : null,
              isAnon: r['anonymous'] as bool? ?? false,
              groupId: r['group_id'] as String?,
              groupName: r['group_name'] as String?,
              groupSize: (r['group_size'] as num?)?.toInt() ?? 0,
              photoUrl: r['photo_url'] as String?,
              seenAt: r['seen_at'] != null
                  ? parsePostgresTimestamp(r['seen_at'] as String)
                  : null,
              photoOpenedAt: r['photo_opened_at'] != null
                  ? DateTime.tryParse(r['photo_opened_at'] as String)?.toLocal()
                  : null,
              myReplies: [
                for (final m in (r['my_replies'] as List? ?? const []))
                  MyPingReply.fromJson(Map<String, dynamic>.from(m as Map)),
              ],
            );
          })
          .where((p) => !p.expired)
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Pings I sent — both still-pending ("Sent") and already-replied-to
  /// ("Replies", see [fetchReplies]) share this one query; callers split on
  /// [OutboundPingRow.replied]. Returns `null` on failure — see
  /// [fetchToReply]'s doc on why that's not the same as an empty list.
  /// A sent ping falls off this list 48h after it was sent — explicit
  /// report ("the ping sent shall disappear after 48 hrs"). Filtered
  /// server-side (same `created_at > cutoff` idiom FeedService.anonCutoff
  /// uses for the anon feed's 24h window) rather than client-side, so a
  /// ping that's aged out never round-trips at all.
  static const sentVisibleWindow = Duration(hours: 48);

  static String _sentCutoff() =>
      DateTime.now().toUtc().subtract(sentVisibleWindow).toIso8601String();

  Future<List<OutboundPingRow>?> fetchSent() async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final rows = await supabase
          .from('pings')
          .select(
            'id, thread_id, group_id, receiver_id, prompt, created_at, seen_at, status, receiver_hidden, expires_at, '
            'users!pings_receiver_id_fkey(name, profile_photo_url, anon_name, anon_photo_url)',
          )
          .eq('sender_id', myId)
          // A ping leaves the SENDER's UI the moment it closes — 6h after
          // the recipient opened it, or 24h if they never did. That is also
          // exactly when the sender is free to ping them again, so the row
          // disappearing and the ability returning are the same event.
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .gt('created_at', _sentCutoff())
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        final receiver = r['users'] as Map?;
        // A ping aimed at an anonymous post's author must read back as that
        // author's PERSONA, never their real name — ping_post_author()
        // deliberately resolves the target server-side so the sender never
        // learns who it was, and echoing users.name here handed exactly
        // that back. See 20260906160000_ping_receiver_hidden.sql.
        final hidden = r['receiver_hidden'] as bool? ?? false;
        final persona = (receiver?['anon_name'] as String?)?.trim();
        return OutboundPingRow(
          id: r['id'] as String,
          threadId: r['thread_id'] as String?,
          isGroup: r['group_id'] != null,
          groupId: r['group_id'] as String?,
          receiverId: r['receiver_id'] as String,
          receiverHidden: hidden,
          receiverName: hidden
              ? ((persona != null && persona.isNotEmpty)
                    ? persona
                    : 'anonymous')
              : ((receiver?['name'] as String?) ?? 'someone'),
          receiverAvatarUrl: hidden
              ? (receiver?['anon_photo_url'] as String?)
              : (receiver?['profile_photo_url'] as String?),
          prompt: r['prompt'] as String,
          sentAt: parsePostgresTimestamp(r['created_at'] as String),
          seenAt: r['seen_at'] != null
              ? parsePostgresTimestamp(r['seen_at'] as String)
              : null,
          replied: r['status'] == 'replied',
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  /// Replies to pings I sent — one row per `ping_replies` entry, EXCEPT a
  /// photo reply is delivered at most once per (ping, replier). Replying is
  /// still unlimited within the window (see PingService.reply's own doc,
  /// and the composer copy at ping_page.dart's 'unlimited within the
  /// window — send more anytime') — a recipient can send as many replies as
  /// they like, but the pinger only ever sees the FIRST photo any one
  /// replier sent for a given ping. There is no server-side guard for this
  /// (no unique index, no notification to dedupe) — see this method's own
  /// investigation notes — so it's collapsed here, client-side, on read.
  /// A later text-only reply is not a duplicate image and always passes
  /// through untouched.
  ///
  /// Returns `null` on failure — see [fetchToReply]'s doc on why that's not
  /// the same as an empty list.
  Future<List<ReceivedReplyRow>?> fetchReplies() async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final rows = await supabase
          .from('ping_replies')
          .select(
            'id, ping_id, replier_id, kind, body, photo_url, selfie_url, created_at, viewed, viewed_at, '
            // ping_reply_reactions has a NARROW select policy (reactor_id =
            // current_user_id() only — see the migration's own doc on why a
            // permissive one would de-anonymize an anonymous sender). For a
            // 1:1 reply the sender is the ONLY possible reactor, so that
            // restricted embed is still a COMPLETE result set here: 0 or 1
            // rows, which doubles correctly as both "did I react" and the
            // true total count.
            'ping_reply_reactions(reactor_id), '
            'replier:replier_id(name, profile_photo_url), '
            'pings!inner(prompt, thread_id, sender_id, anonymous, group_id, expires_at, pinged_back_at, groups(name))',
          )
          .eq('pings.sender_id', myId)
          // BUG FIX ("the ended pings shall not be seen on the screen"):
          // this had NO time filter at all, unlike fetchToReply/fetchSent
          // right above (both gate on `expires_at`), so a reply card
          // outlived its ping's closed window indefinitely — the ping
          // itself vanished from Sent/To Reply while its reply stayed
          // pinned to the top of Replies forever. `!inner` makes `pings`
          // required rather than left-joined, which is what lets a filter
          // on the embedded table's own column apply here.
          .gt('pings.expires_at', DateTime.now().toUtc().toIso8601String())
          // 1:1 REPLIES ONLY. A group reply belongs on the Group Wall —
          // it renders as a hold-to-reveal tile there, which is the whole
          // point of the wall. Without this filter every group reply ALSO
          // landed in the Replies section, because sendGroupPing writes one
          // `pings` row per member with sender_id = the asker, so the
          // `pings.sender_id = me` filter above matches all of them.
          //
          // It also fixes a worse symptom: a group ping deliberately
          // includes its own sender as a recipient, so replying on your own
          // group thread produced a row where sender_id = replier_id = you
          // — and your own name appeared in your own Replies list, as if
          // you had received a reply from yourself. Verified in live data:
          // the only group rows reaching this query were exactly that
          // self-reply case. Same root cause as the self-push guarded in
          // notify-ping-reply and the self-ping-back filtered in
          // ping_page.dart's open-loop derivation.
          .isFilter('pings.group_id', null)
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      // Rows arrive newest-first. Walking oldest-first and keeping the
      // first photo seen per (ping_id, replier_id) means "first" is the
      // earliest one actually sent, not merely the earliest in this page.
      final ascending = (rows as List).cast<Map<String, dynamic>>().reversed;
      final seenPhotoKeys = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final r in ascending) {
        if (r['photo_url'] != null) {
          final key = '${r['ping_id']}:${r['replier_id']}';
          if (!seenPhotoKeys.add(key)) continue; // already delivered
        }
        deduped.add(r);
      }

      return deduped.reversed.map((r) {
        final ping = r['pings'] as Map?;
        final replier = r['replier'] as Map?;
        final group = ping?['groups'] as Map?;
        final reactions = (r['ping_reply_reactions'] as List?) ?? const [];
        return ReceivedReplyRow(
          replyId: r['id'] as String,
          pingId: r['ping_id'] as String,
          threadId: ping?['thread_id'] as String?,
          replierId: r['replier_id'] as String,
          replierName: (replier?['name'] as String?) ?? 'someone',
          replierAvatarUrl: replier?['profile_photo_url'] as String?,
          prompt: (ping?['prompt'] as String?) ?? '',
          kind: r['kind'] as String,
          body: r['body'] as String?,
          photoUrl: r['photo_url'] as String?,
          selfieUrl: r['selfie_url'] as String?,
          createdAt: parsePostgresTimestamp(r['created_at'] as String),
          viewed: r['viewed'] as bool? ?? false,
          viewedAt: r['viewed_at'] != null
              ? parsePostgresTimestamp(r['viewed_at'] as String)
              : null,
          isAnon: ping?['anonymous'] as bool? ?? false,
          groupName: group?['name'] as String?,
          pingedBack: ping?['pinged_back_at'] != null,
          reactionCount: reactions.length,
          myReaction: reactions.isNotEmpty,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  /// Replies to [pingId] with a photo, a caption, or both — mirrors
  /// ping_replies_insert's own requirement that only the ping's RECEIVER
  /// may reply. Exactly one of [photoUrl]/[body] must be non-null for a
  /// text-only reply; a photo reply may carry both.
  Future<void> reply({
    required String pingId,
    String? photoUrl,
    String? selfieUrl,
    String? body,
  }) async {
    final replierId = await CurrentUserService.instance.resolveId();
    await supabase.from('ping_replies').insert({
      'ping_id': pingId,
      'replier_id': replierId,
      'kind': photoUrl != null ? 'photo' : 'text',
      if (photoUrl != null) 'photo_url': photoUrl,
      // Only ever set alongside photoUrl — a camera reply's front-lens
      // shot (see PingCameraScreen's dual capture). Null for an album pick
      // or a text-only reply, which is exactly what tells every render
      // site not to show the selfie inset for those.
      if (selfieUrl != null) 'selfie_url': selfieUrl,
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
    });
  }

  /// Replies to a Group Wall ping — same write as [reply], kept as its own
  /// name only for clarity at the wall composer's call site.
  Future<void> replyToWall({
    required String pingId,
    String? photoUrl,
    String? selfieUrl,
    String? body,
  }) => reply(
    pingId: pingId,
    photoUrl: photoUrl,
    selfieUrl: selfieUrl,
    body: body,
  );

  /// Marks a ping as seen by its receiver — called the instant the
  /// recipient reveals it (PingPage.finishHold's isPing branch), the same
  /// moment PingFeedEntry.revealedAt gets set on the sibling unused model.
  /// Goes through the mark_ping_seen() RPC rather than a direct table
  /// update: pings_update_receiver excludes anonymous rows from the
  /// receiver's own UPDATE policy (an UPDATE...WHERE also evaluates SELECT
  /// policies to find the row), so a direct update would silently no-op for
  /// exactly the pings anonymity matters most for. Best-effort: a missed
  /// write just means the sender's "seen" indicator lags, never a crash.
  Future<void> markSeen(String pingId) async {
    try {
      await supabase.rpc('mark_ping_seen', params: {'p_ping_id': pingId});
    } catch (_) {
      // Non-critical — see doc above.
    }
  }

  /// Burns the ping's attached photo's one-time view — called the instant
  /// the receiver opens the full-screen viewer (PingPage._openPingPhoto).
  /// Best-effort, same posture as markSeen right above: a missed write only
  /// means the photo stays re-openable a bit longer, never a crash. The real
  /// one-time guarantee is server-side (mark_ping_photo_opened's own
  /// idempotent, receiver-only UPDATE), not this call succeeding.
  Future<void> markPingPhotoOpened(String pingId) async {
    try {
      await supabase.rpc(
        'mark_ping_photo_opened',
        params: {'p_ping_id': pingId},
      );
    } catch (_) {
      // Non-critical — see doc above.
    }
  }

  /// Marks a reply as viewed by the original sender — called the instant
  /// they reveal it (PingPage.finishHold's non-ping branch), starting the
  /// 24h ping-back window (ReceivedReplyRow.pingBackAvailable).
  Future<void> markViewed(String replyId) async {
    try {
      await supabase
          .from('ping_replies')
          .update({
            'viewed': true,
            'viewed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', replyId)
          .eq('viewed', false);
    } catch (_) {
      // Non-critical — see doc above.
    }
  }

  /// Hearts (or un-hearts) a reply — unified across 1:1 and group walls.
  /// Server-side authorization (toggle_ping_reply_reaction) differs by
  /// shape: for a 1:1 reply only the ORIGINAL PING'S SENDER may react; for a
  /// group wall reply, anyone who has ANSWERED that thread may react to
  /// anyone else's tile (never their own). Both throw for a disallowed
  /// caller. Returns the new (liked, count) so the caller's optimistic UI
  /// can be corrected if it guessed wrong. Unlike markSeen/markViewed above
  /// this is NOT swallowed on failure — a like the UI shows as landed but
  /// the server rejected is worse than a visible error, same posture as
  /// every other real ping write.
  Future<(bool liked, int count)> toggleReaction(String replyId) async {
    final rows =
        await supabase.rpc(
              'toggle_ping_reply_reaction',
              params: {'p_reply_id': replyId},
            )
            as List;
    final row = Map<String, dynamic>.from(rows.first as Map);
    return (row['liked'] as bool, (row['reaction_count'] as num).toInt());
  }

  /// My current ping streak with every person I have ping history with,
  /// keyed by their `users.id`. A streak counts consecutive days on which
  /// an exchange between us actually CLOSED (they replied, or I did) — an
  /// ignored ping doesn't extend it. Computed server-side from
  /// ping/ping_replies history (see the ping_streaks migration), so it
  /// needs no backfill and can't drift.
  Future<Map<String, int>> fetchStreaks() async {
    try {
      final rows = await supabase
          .rpc('my_ping_streaks')
          .timeout(const Duration(seconds: 8));
      return {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          r['other_id'] as String: (r['streak'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Active Group Wall threads I'm a member of. Returns `null` on failure —
  /// see [fetchToReply]'s doc on why that's not the same as an empty list.
  Future<List<WallThread>?> fetchWalls() async {
    try {
      final rows = await supabase
          .rpc('my_group_walls')
          .timeout(const Duration(seconds: 8));
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        return WallThread(
          threadId: r['thread_id'] as String,
          groupId: r['group_id'] as String,
          groupName: (r['group_name'] as String?) ?? 'Group',
          prompt: r['prompt'] as String,
          createdAt: parsePostgresTimestamp(r['created_at'] as String),
          windowHours: (r['window_hours'] as num?)?.toInt() ?? 6,
          anonymous: r['anonymous'] as bool? ?? false,
          askedBy: (r['asked_by'] as String?) ?? 'someone',
          myPingId: r['my_ping_id'] as String?,
          unlocked: r['unlocked'] as bool? ?? false,
          answered: (r['answered'] as num?)?.toInt() ?? 0,
          total: (r['total'] as num?)?.toInt() ?? 0,
          photoUrl: r['photo_url'] as String?,
          groupIconUrl: r['group_icon_url'] as String?,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  /// One Group Wall's member slots. Locked slots come back with every
  /// reply-payload field null — enforced by get_group_wall itself, not
  /// hidden client-side — so there's no path where the client ever holds a
  /// photo it isn't supposed to show yet. Returns `null` on failure — see
  /// [fetchToReply]'s doc on why that's not the same as an empty list.
  Future<List<WallSlot>?> fetchWall(String threadId) async {
    try {
      final rows = await supabase
          .rpc('get_group_wall', params: {'p_thread_id': threadId})
          .timeout(const Duration(seconds: 8));
      return (rows as List).cast<Map<String, dynamic>>().map((r) {
        return WallSlot(
          memberId: r['member_id'] as String,
          memberName: (r['member_name'] as String?) ?? 'someone',
          memberAvatarUrl: r['member_avatar'] as String?,
          isMe: r['is_me'] as bool? ?? false,
          answered: r['answered'] as bool? ?? false,
          replyId: r['reply_id'] as String?,
          replyKind: r['reply_kind'] as String?,
          replyBody: r['reply_body'] as String?,
          photoUrl: r['reply_photo'] as String?,
          selfieUrl: r['reply_selfie'] as String?,
          repliedAt: r['replied_at'] != null
              ? parsePostgresTimestamp(r['replied_at'] as String)
              : null,
          opened: r['opened'] as bool? ?? false,
          reactionCount: (r['reaction_count'] as num?)?.toInt() ?? 0,
          myReaction: r['my_reaction'] as bool? ?? false,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  /// Records that I've revealed a wall reply — the per-viewer counterpart
  /// to [markViewed], since a wall reply has N viewers rather than one.
  Future<void> markWallReplyOpened(String replyId) async {
    try {
      await supabase.rpc(
        'mark_wall_reply_opened',
        params: {'p_reply_id': replyId},
      );
    } catch (_) {
      // Non-critical — see markSeen's doc above.
    }
  }

  /// Ping-backs the sender of an anonymous ping I already replied to,
  /// without ever learning who they are — the server resolves the target
  /// from [pingId] and re-checks the same 24h/already-replied gate
  /// [ReceivedReplyRow.pingBackAvailable] mirrors client-side.
  Future<void> pingBackAnonymous({
    required String pingId,
    required String prompt,
    bool anonymous = true,
  }) async {
    try {
      await supabase.rpc(
        'ping_back_anonymous',
        params: {
          'p_ping_id': pingId,
          'p_prompt': prompt,
          'p_anonymous': anonymous,
        },
      );
    } on Object catch (e) {
      _mapLimitError(e);
    }
  }

  /// Pings the author of an anonymous post without the caller ever learning
  /// who wrote it — powers the anon feed's ping button.
  Future<void> pingPostAuthor({
    required String postId,
    required String prompt,
    bool anonymous = true,
  }) async {
    try {
      await supabase.rpc(
        'ping_post_author',
        params: {
          'p_post_id': postId,
          'p_prompt': prompt,
          'p_anonymous': anonymous,
        },
      );
    } on Object catch (e) {
      _mapLimitError(e);
    }
  }
}
