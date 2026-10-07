import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i/features/highlights/highlight_models.dart';
import 'package:i/features/highlights/highlight_story_viewer.dart';
import 'package:i/services/post_service.dart' show PostViewer;
import 'package:i/services/reaction_service.dart' show ReactionSummary;

/// The story a polaroid opens into: each photo moves on by itself, the
/// edges skip, the next highlight plays when one ends, and it closes after
/// the last. Everything that would touch the network goes through
/// [HighlightStoryDelegate], faked here.
class _FakeDelegate extends HighlightStoryDelegate {
  static const myId = 'me';
  final seen = <String>[];
  final views = <String>[];
  final reactions = <String>[];

  @override
  bool isMine(Highlight h) => h.ownerId == myId;

  @override
  Future<void> markSeen(Highlight h) async => seen.add(h.id);

  @override
  Future<void> recordView(String postId) async => views.add(postId);

  @override
  Future<ReactionSummary?> fetchSummary(String postId) async => null;

  @override
  Future<void> react(String postId, String emoji) async =>
      reactions.add('$postId:$emoji');

  @override
  Future<void> unreact(String postId) async => reactions.add('$postId:-');

  @override
  Future<List<PostViewer>> fetchViewers(String postId) async => const [];

  @override
  Future<void> preload(BuildContext context, String url) async {}

  @override
  Widget buildPhoto(BuildContext context, HighlightPhoto photo) =>
      Center(child: Text('photo:${photo.postId}'));
}

void main() {
  const step = Duration(seconds: 4);

  Highlight highlight(String id, List<String> photoIds, {String owner = 'friend'}) =>
      Highlight(
        id: id,
        ownerId: owner,
        title: id,
        updatedAt: '2026-10-07T10:00:00',
        ownerName: owner,
        photos: [
          for (final p in photoIds)
            HighlightPhoto(postId: p, url: 'https://example.invalid/$p.jpg'),
        ],
      );

  /// Opens the viewer from a button and returns a getter for how it closed
  /// (null while still open; true = played to the end).
  Future<bool? Function()> open(
    WidgetTester tester,
    List<Highlight> highlights,
    _FakeDelegate delegate,
  ) async {
    bool? result;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => HighlightStoryViewer(
                        highlights: highlights,
                        delegate: delegate,
                        photoDuration: step,
                      ),
                    ),
                  );
                  result = r ?? false;
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Route transition, then the first photo's timer starts.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return () => closed ? result : null;
  }

  /// Lets one photo's time run out: [d] plus a little, in small steps so
  /// the status callback and the async start of the next photo all get to
  /// run. (The "little" matters: a timer only reports done on the first
  /// tick AFTER its duration, never on the exact boundary.)
  Future<void> advance(WidgetTester tester, Duration d) async {
    const tick = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < d + tick * 3; t += tick) {
      await tester.pump(tick);
    }
    await tester.pump();
  }

  testWidgets('photos move on by themselves, then the next highlight plays, '
      'then it closes', (tester) async {
    final delegate = _FakeDelegate();
    final result = await open(tester, [
      highlight('A', ['a1', 'a2']),
      highlight('B', ['b1']),
    ], delegate);

    expect(find.text('photo:a1'), findsOneWidget);
    await advance(tester, step);
    expect(find.text('photo:a2'), findsOneWidget);
    await advance(tester, step);
    expect(find.text('photo:b1'), findsOneWidget);
    expect(result(), isNull, reason: 'still playing');
    await advance(tester, step);
    await tester.pumpAndSettle();

    expect(find.text('photo:b1'), findsNothing);
    expect(result(), isTrue, reason: 'played through to the end');
    expect(delegate.seen, ['A', 'B']);
    // One view per opened highlight, recorded on its FIRST photo.
    expect(delegate.views, ['a1', 'b1']);
  });

  testWidgets('tapping the right edge skips, the left edge goes back',
      (tester) async {
    final delegate = _FakeDelegate();
    await open(tester, [
      highlight('A', ['a1', 'a2', 'a3']),
    ], delegate);

    await tester.tap(find.byKey(const ValueKey('story-next')));
    await tester.pump();
    expect(find.text('photo:a2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-next')));
    await tester.pump();
    expect(find.text('photo:a3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-prev')));
    await tester.pump();
    expect(find.text('photo:a2'), findsOneWidget);

    // Close it so no timer outlives the test.
    await tester.tap(find.byKey(const ValueKey('story-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('closing part-way reports "not finished"', (tester) async {
    final delegate = _FakeDelegate();
    final result = await open(tester, [
      highlight('A', ['a1', 'a2']),
    ], delegate);

    await tester.tap(find.byKey(const ValueKey('story-close')));
    await tester.pumpAndSettle();

    expect(result(), isFalse);
    expect(find.text('photo:a1'), findsNothing);
  });

  testWidgets("reacting goes to the photo on screen; my own highlight has no "
      'react bar and records no view', (tester) async {
    final delegate = _FakeDelegate();
    await open(tester, [
      highlight('A', ['a1', 'a2']),
    ], delegate);

    await tester.tap(find.byKey(const ValueKey('story-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('story-react-❤️')));
    await tester.pump();
    expect(delegate.reactions, ['a2:❤️']);
    // Let the burst animation finish, then close.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('story-close')));
    await tester.pumpAndSettle();

    final mine = _FakeDelegate();
    await open(tester, [
      highlight('M', ['m1'], owner: 'me'),
    ], mine);
    expect(find.byKey(const ValueKey('story-react-❤️')), findsNothing);
    expect(find.textContaining('Seen by'), findsOneWidget);
    expect(mine.views, isEmpty);
    await tester.tap(find.byKey(const ValueKey('story-close')));
    await tester.pumpAndSettle();
  });
}
