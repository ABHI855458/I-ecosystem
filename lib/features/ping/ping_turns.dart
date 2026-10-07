import 'package:flutter/foundation.dart';

import '../../services/ping_service.dart';

// ---------------------------------------------------------------------------
// The person-shaped answers read out of the ping lists, kept in one place
// so the screens that show them can't disagree:
//
//  * who pinged me, for the camera's send screen   -> [sendScreenPingers]
//  * who I can't / can ping right now               -> [openPingReceiverIds],
//                                                      [pingablePeople]
//  * who has replied to me, for the Friends feed's
//    REPLIES row and the story it opens             -> [replyStories]
//
// All pure, so they are tested without a device.
// ---------------------------------------------------------------------------

/// Bumped whenever my pings or the replies to them may have changed: a
/// reply of mine has actually been WRITTEN (not when the send screen
/// closed — the photo is still uploading then), or the Ping page's live
/// channel heard a ping or a reply arrive. The Friends feed's top section
/// reloads on it instead of waiting for a pull-to-refresh.
final pingInboxChanged = ValueNotifier<int>(0);

/// Who a ping is "from", as one key per person or group. An anonymous
/// sender has no id on this side, so each anonymous ping stands alone —
/// grouping them by anything else would be guessing who sent what.
String pingSenderKey(InboundPingRow p) => p.isGroup
    ? 'group:${p.groupId ?? p.threadId}'
    : 'user:${p.senderId ?? p.id}';

/// The send screen's "pinged you" tiles: one open ping per person or group,
/// in inbox order.
///
/// A PERSON stays until their ping expires however many photos you've sent
/// back; a GROUP ping takes one answer, so an answered one is gone. When
/// someone has several open pings, the one still WAITING on a reply is the
/// one that represents them — the photo then answers that ping instead of
/// stacking a second reply on one already answered.
List<InboundPingRow> sendScreenPingers(List<InboundPingRow> inbox) {
  final chosen = <String, InboundPingRow>{};
  for (final p in inbox) {
    if (p.expired) continue;
    if (p.isGroup && p.myReplies.isNotEmpty) continue;
    final who = pingSenderKey(p);
    final had = chosen[who];
    if (had == null || (had.myReplies.isNotEmpty && p.myReplies.isEmpty)) {
      // Re-assigning an existing key keeps its place in the map's order,
      // so the sender stays where their newest ping put them.
      chosen[who] = p;
    }
  }
  return chosen.values.toList();
}

/// People I can't ping right now: I already have a ping out to them that
/// hasn't closed. send_ping refuses a second one until it does — REPLIED OR
/// NOT (20261006010000_ping_once_until_expiry.sql), so `replied` must not
/// be part of this test: it used to be, and someone who had answered came
/// back as pingable only for the tap to fail with "already pinged".
///
/// [sent] is PingService.fetchSent, which only returns unexpired rows.
Set<String> openPingReceiverIds(List<OutboundPingRow> sent) => {
  for (final o in sent)
    if (!o.isGroup) o.receiverId,
};

/// PING SOMEONE: the friends I can ping right now — the ones I keep a
/// streak with first, then A-Z. [friends] are user rows (id, name,
/// profile_photo_url); [streaks] is PingService.fetchStreaks.
List<Map<String, dynamic>> pingablePeople({
  required List<Map<String, dynamic>> friends,
  required List<OutboundPingRow> sent,
  required Map<String, int> streaks,
  required String? myId,
}) {
  final blocked = openPingReceiverIds(sent);
  final out = [
    for (final f in friends)
      if (f['id'] is String && f['id'] != myId && !blocked.contains(f['id']))
        f,
  ];
  String nameOf(Map<String, dynamic> f) =>
      ((f['name'] as String?) ?? '').toLowerCase();
  out.sort((a, b) {
    final s = (streaks[b['id']] ?? 0).compareTo(streaks[a['id']] ?? 0);
    return s != 0 ? s : nameOf(a).compareTo(nameOf(b));
  });
  return out;
}

// ── Replies I've received ───────────────────────────────────────────────

/// The one-tap "Ping back" answer to a promptless ping — an ordinary text
/// reply (so it closes the ping and counts for the streak), which
/// notify_ping_reply words as "X pinged you back 👋"
/// (20260930010000_promptless_pings.sql).
const kPingBackBody = '👋';

/// `pingId:replierId` — one person's replies on one ping.
String replyGroupKey(String pingId, String replierId) => '$pingId:$replierId';

/// UNBLUR ONCE (explicit request, 2026-10-07: "when they get the reply for
/// their ping they shall unblur only once ... after unblurring once they
/// don't need to unblur every time they get reply"). The first reply a
/// person sends on a ping is the hold-to-unblur moment; once one of their
/// replies on that ping has been opened, the rest are ordinary rows — name
/// showing, tap to open.
///
/// Returns the groups (see [replyGroupKey]) already unlocked, given every
/// reply on my open pings and whether each has been opened.
Set<String> unlockedReplyGroups<T>(
  Iterable<T> replies, {
  required String Function(T) pingIdOf,
  required String Function(T) replierIdOf,
  required bool Function(T) isViewed,
}) => {
  for (final r in replies)
    if (isViewed(r)) replyGroupKey(pingIdOf(r), replierIdOf(r)),
};

/// One person's replies to my open pings: a face in the feed's REPLIES
/// row, and the story that face opens into (see ReplyStoryViewer).
///
/// One per PERSON, not per ping: someone I pinged twice, or who sent three
/// photos back, is one face — opening it lands on the latest thing they
/// sent and then goes back through the earlier ones (explicit request,
/// 2026-10-07: "when opened he gets to be on the recent sent and as well
/// see the previous sent").
class ReplyStory {
  const ReplyStory({required this.replies, required this.unseen});

  /// NEWEST FIRST — the order the story plays in. Includes replies I have
  /// already opened, for as long as their ping is still open.
  final List<ReceivedReplyRow> replies;

  /// How many of them I haven't opened yet. Zero = everything here has
  /// been seen; the face stays, to be watched again.
  final int unseen;

  ReceivedReplyRow get newest => replies.first;
  String get replierId => newest.replierId;
  String get name => newest.replierName;
  String? get avatarUrl => newest.replierAvatarUrl;
}

/// REPLIES: everyone who has replied to a ping of mine that is still open.
///
/// They STAY after being opened — "people can review their previous
/// replies, just visible like how highlights is visible ... until the ping
/// session is over they can see their replies again and again" (explicit
/// request, 2026-10-07; the first version dropped a face the moment it was
/// opened). People with something unopened come first, then the ones
/// already seen; within each, whoever replied most recently is first.
///
/// [replies] is PingService.fetchReplies (newest first), which only
/// returns replies on pings that are still open — that is what ends a
/// face's stay. [opened] are ids opened on this device that the server may
/// not have recorded yet, counted as opened here so a face doesn't flash
/// back to "new" for the moment in between.
List<ReplyStory> replyStories(
  List<ReceivedReplyRow> replies, {
  Set<String> opened = const {},
}) {
  final byPerson = <String, List<ReceivedReplyRow>>{};
  for (final r in replies) {
    (byPerson[r.replierId] ??= []).add(r);
  }
  final fresh = <ReplyStory>[];
  final watched = <ReplyStory>[];
  for (final theirs in byPerson.values) {
    final unseen = theirs
        .where((r) => !r.viewed && !opened.contains(r.replyId))
        .length;
    (unseen > 0 ? fresh : watched).add(
      ReplyStory(replies: theirs, unseen: unseen),
    );
  }
  return [...fresh, ...watched];
}
