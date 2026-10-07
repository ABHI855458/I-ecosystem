import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i/features/ping/ping_turns.dart';
import 'package:i/features/ping/reply_story_viewer.dart';
import 'package:i/services/ping_service.dart';

/// The story a REPLIES face opens into: it starts on that person's LATEST
/// reply, goes back through the earlier ones, plays the next person's, and
/// closes after the last. A reply is reported as opened only once it is on
/// screen. Everything that would touch the network goes through
/// [ReplyStoryDelegate], faked here.
class _FakeDelegate extends ReplyStoryDelegate {
  final viewed = <String>[];
  final hearts = <String>[];

  /// Photo urls that "fail to load".
  final broken = <String>{};

  @override
  Future<void> markViewed(String replyId) async => viewed.add(replyId);

  @override
  Future<bool> toggleHeart(String replyId) async {
    hearts.add(replyId);
    return true;
  }

  @override
  Future<double?> loadPhoto(BuildContext context, String url) async =>
      broken.contains(url) ? null : 0.75;

  @override
  Widget buildPhoto(BuildContext context, String url) =>
      Center(child: Text('photo:${url.split('/').last}'));

  @override
  Widget buildSelfie(BuildContext context, String url) =>
      const SizedBox.shrink();
}

void main() {
  const step = Duration(milliseconds: 600);
  final now = DateTime.now();

  ReceivedReplyRow reply(
    String id, {
    required String from,
    bool viewed = false,
    String? words,
  }) => ReceivedReplyRow(
    replyId: id,
    pingId: 'p-$from',
    replierId: from,
    replierName: from,
    replierAvatarUrl: null,
    prompt: '',
    kind: words == null ? 'photo' : 'text',
    body: words,
    photoUrl: words == null ? 'https://example.invalid/$id' : null,
    createdAt: now,
    viewed: viewed,
    viewedAt: null,
  );

  /// Opens the viewer from a button; returns a getter for what it handed
  /// back (null while still open).
  Future<Set<String>? Function()> open(
    WidgetTester tester,
    List<ReceivedReplyRow> rows,
    _FakeDelegate delegate,
  ) async {
    Set<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await Navigator.of(context).push<Set<String>>(
                    MaterialPageRoute<Set<String>>(
                      builder: (_) => ReplyStoryViewer(
                        stories: replyStories(rows),
                        delegate: delegate,
                        itemDuration: step,
                      ),
                    ),
                  );
                  result = r ?? const {};
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Route transition, then the first reply loads and its timer starts.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return () => result;
  }

  /// Lets one reply's time run out (a timer only reports done on the first
  /// tick AFTER its duration, hence the extra ticks).
  Future<void> advance(WidgetTester tester, Duration d) async {
    const tick = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < d + tick * 3; t += tick) {
      await tester.pump(tick);
    }
    await tester.pump();
  }

  testWidgets('opens on the latest, goes back through the earlier ones, '
      'then the next person, then closes', (tester) async {
    final delegate = _FakeDelegate();
    // Newest first, as PingService.fetchReplies returns them.
    final result = await open(tester, [
      reply('a2', from: 'asha'),
      reply('r1', from: 'ravi'),
      reply('a1', from: 'asha'),
    ], delegate);

    expect(find.text('photo:a2'), findsOneWidget, reason: 'latest first');
    expect(find.textContaining('Latest'), findsOneWidget);
    await advance(tester, step);
    expect(find.text('photo:a1'), findsOneWidget, reason: 'then the earlier');
    expect(find.textContaining('Earlier'), findsOneWidget);
    await advance(tester, step);
    expect(find.text('photo:r1'), findsOneWidget, reason: 'next person');
    expect(result(), isNull, reason: 'still playing');
    await advance(tester, step);
    await tester.pumpAndSettle();

    expect(find.text('photo:r1'), findsNothing);
    expect(result(), {'a2', 'a1', 'r1'});
    expect(delegate.viewed, ['a2', 'a1', 'r1']);
  });

  testWidgets('the edges move; an already-opened reply is not reported '
      'again', (tester) async {
    final delegate = _FakeDelegate();
    final result = await open(tester, [
      reply('a2', from: 'asha'),
      reply('a1', from: 'asha', viewed: true),
    ], delegate);

    expect(find.text('photo:a2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reply-story-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('photo:a1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reply-story-prev')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('photo:a2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reply-story-close')));
    await tester.pumpAndSettle();
    expect(result(), {'a2'});
    expect(delegate.viewed, ['a2']);
  });

  testWidgets('a reply that will not load is not counted as opened', (
    tester,
  ) async {
    final delegate = _FakeDelegate()..broken.add('https://example.invalid/a1');
    final result = await open(tester, [reply('a1', from: 'asha')], delegate);

    expect(find.text("Couldn't load this one"), findsOneWidget);
    await advance(tester, step);
    await tester.pumpAndSettle();
    expect(result(), isEmpty);
    expect(delegate.viewed, isEmpty);
  });

  testWidgets('words and a plain ping back have their own cards; the heart '
      'toggles', (tester) async {
    final delegate = _FakeDelegate();
    await open(tester, [
      reply('a2', from: 'asha', words: 'on my way'),
      reply('a1', from: 'asha', words: kPingBackBody),
    ], delegate);

    expect(find.text('on my way'), findsOneWidget);
    expect(find.text('Love it'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reply-story-heart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Loved'), findsOneWidget);
    expect(delegate.hearts, ['a2']);

    await tester.tap(find.byKey(const ValueKey('reply-story-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('asha pinged you back'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reply-story-close')));
    await tester.pumpAndSettle();
  });
}
