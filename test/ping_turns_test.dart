import 'package:flutter_test/flutter_test.dart';
import 'package:i/features/ping/ping_turns.dart';
import 'package:i/services/ping_service.dart';

/// "Whose turn is it?" — the two readers of the ping inbox:
///  * yourTurnPings      -> the Friends feed's YOUR TURN row
///  * sendScreenPingers  -> the camera send screen's "pinged you" tiles
/// Both take the inbox newest-first, exactly as PingService.fetchToReply
/// returns it.
///
/// And the reader of replies I've received:
///  * replyStories       -> the Friends feed's REPLIES row, one face (and
///                          one story) per person
void main() {
  final now = DateTime.now();

  InboundPingRow ping(
    String id, {
    String? sender,
    String name = 'someone',
    bool group = false,
    String? groupId,
    bool anon = false,
    bool expired = false,
    int replies = 0,
  }) => InboundPingRow(
    id: id,
    threadId: 't-$id',
    kind: group ? 'group' : 'person',
    senderId: anon ? null : sender,
    senderName: name,
    senderAvatarUrl: null,
    prompt: '',
    sentAt: now.subtract(const Duration(hours: 1)),
    windowHours: 6,
    closesAt: expired
        ? now.subtract(const Duration(minutes: 1))
        : now.add(const Duration(hours: 5)),
    isAnon: anon,
    groupId: groupId,
    groupName: group ? name : null,
    groupSize: group ? 4 : 0,
    myReplies: [
      for (var i = 0; i < replies; i++)
        const MyPingReply(isPhoto: true, body: '', likes: 0),
    ],
  );

  group('yourTurnPings', () {
    test('keeps open, unanswered pings in inbox order', () {
      final got = yourTurnPings([
        ping('a', sender: 'u1'),
        ping('b', sender: 'u2'),
      ], myId: 'me');
      expect(got.map((p) => p.id), ['a', 'b']);
    });

    test('drops expired and already-answered pings', () {
      final got = yourTurnPings([
        ping('gone', sender: 'u1', expired: true),
        ping('done', sender: 'u2', replies: 1),
        ping('open', sender: 'u3'),
      ], myId: 'me');
      expect(got.map((p) => p.id), ['open']);
    });

    test('one face per person: their newest unanswered ping', () {
      final got = yourTurnPings([
        ping('new-answered', sender: 'u1', replies: 1),
        ping('older-open', sender: 'u1'),
        ping('oldest-open', sender: 'u1'),
      ], myId: 'me');
      expect(got.map((p) => p.id), ['older-open']);
    });

    test('never offers a group ping I sent myself', () {
      final got = yourTurnPings([
        ping('mine', sender: 'me', group: true, groupId: 'g1', name: 'Hostel'),
        ping('theirs', sender: 'u2', group: true, groupId: 'g2', name: 'Fest'),
      ], myId: 'me');
      expect(got.map((p) => p.id), ['theirs']);
    });

    test('anonymous pings are never merged with each other', () {
      final got = yourTurnPings([
        ping('anon-1', anon: true),
        ping('anon-2', anon: true),
      ], myId: 'me');
      expect(got.map((p) => p.id), ['anon-1', 'anon-2']);
    });
  });

  group('sendScreenPingers', () {
    test('a person stays after being answered; an answered group does not', () {
      final got = sendScreenPingers([
        ping('p', sender: 'u1', replies: 2),
        ping('g', sender: 'u2', group: true, groupId: 'g1', replies: 1),
      ]);
      expect(got.map((p) => p.id), ['p']);
    });

    test('the ping still waiting on a reply represents the sender', () {
      final got = sendScreenPingers([
        ping('new-answered', sender: 'u1', replies: 1),
        ping('older-open', sender: 'u1'),
      ]);
      expect(got.map((p) => p.id), ['older-open']);
    });

    test('keeps the sender in the place their newest ping put them', () {
      final got = sendScreenPingers([
        ping('u1-new-answered', sender: 'u1', replies: 1),
        ping('u2-open', sender: 'u2'),
        ping('u1-older-open', sender: 'u1'),
      ]);
      expect(got.map((p) => p.id), ['u1-older-open', 'u2-open']);
    });

    test('people, anonymous and groups come as one list, newest first', () {
      final got = sendScreenPingers([
        ping('group', sender: 'u9', group: true, groupId: 'g1', name: 'Fest'),
        ping('anon', anon: true),
        ping('person', sender: 'u1'),
        ping('expired', sender: 'u2', expired: true),
      ]);
      expect(got.map((p) => p.id), ['group', 'anon', 'person']);
    });

    test('agrees with YOUR TURN on which ping a face stands for', () {
      final inbox = [
        ping('u1-new-answered', sender: 'u1', replies: 1),
        ping('u1-older-open', sender: 'u1'),
        ping('u2-open', sender: 'u2'),
      ];
      final turn = yourTurnPings(inbox, myId: 'me').map((p) => p.id).toSet();
      final tiles = sendScreenPingers(inbox).map((p) => p.id).toSet();
      // Every YOUR TURN face must be a tile the send screen can tick.
      expect(tiles.containsAll(turn), isTrue);
    });
  });

  group('replyStories', () {
    ReceivedReplyRow reply(
      String id, {
      required String from,
      String ping = 'p1',
      bool viewed = false,
      int minutesAgo = 1,
    }) => ReceivedReplyRow(
      replyId: id,
      pingId: ping,
      replierId: from,
      replierName: 'Name of $from',
      replierAvatarUrl: null,
      prompt: '',
      kind: 'photo',
      body: null,
      photoUrl: 'https://example.invalid/$id.jpg',
      createdAt: now.subtract(Duration(minutes: minutesAgo)),
      viewed: viewed,
      viewedAt: null,
    );

    test('one story per person, across pings, newest reply first', () {
      // Newest first, as PingService.fetchReplies returns them.
      final got = replyStories([
        reply('a3', from: 'asha', ping: 'p2', minutesAgo: 1),
        reply('r1', from: 'ravi', minutesAgo: 2),
        reply('a2', from: 'asha', ping: 'p1', minutesAgo: 5),
        reply('a1', from: 'asha', ping: 'p1', minutesAgo: 9),
      ]);
      expect(got.map((s) => s.replierId), ['asha', 'ravi']);
      expect(got.first.replies.map((r) => r.replyId), ['a3', 'a2', 'a1']);
      expect(got.first.newest.replyId, 'a3');
      expect(got.first.unseen, 3);
      expect(got.last.unseen, 1);
    });

    test('a person with nothing unopened is not in the row', () {
      final got = replyStories([
        reply('a1', from: 'asha', viewed: true),
        reply('r1', from: 'ravi'),
      ]);
      expect(got.map((s) => s.replierId), ['ravi']);
    });

    test('earlier replies already opened stay in the story, uncounted', () {
      final got = replyStories([
        reply('a2', from: 'asha'),
        reply('a1', from: 'asha', viewed: true),
      ]);
      expect(got.single.replies.map((r) => r.replyId), ['a2', 'a1']);
      expect(got.single.unseen, 1);
    });

    test('replies opened on this device count as opened at once', () {
      final rows = [
        reply('a2', from: 'asha'),
        reply('a1', from: 'asha'),
        reply('r1', from: 'ravi'),
      ];
      final got = replyStories(rows, opened: {'a2', 'r1'});
      expect(got.map((s) => s.replierId), ['asha']);
      expect(got.single.unseen, 1);
      expect(replyStories(rows, opened: {'a2', 'a1', 'r1'}), isEmpty);
    });
  });
}
