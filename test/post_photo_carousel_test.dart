import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i/screens/feed/widgets/post_photo_carousel.dart';

/// Verifies the two rendering paths of the post photo area added when the
/// collage layouts were removed: one photo renders as a plain image (no
/// pager, no dots — identical to the pre-carousel behavior), several render
/// as a swipeable PageView with dot indicators and a counter.
void main() {
  Widget host(List<String> urls) => MaterialApp(
        home: Scaffold(body: PostPhotoCarousel(photoUrls: urls)),
      );

  testWidgets('single photo renders no pager and no dots', (tester) async {
    await tester.pumpWidget(host(const ['https://example.com/a.jpg']));

    expect(find.byType(PageView), findsNothing);
    // No counter pill for a single photo.
    expect(find.text('1/1'), findsNothing);
  });

  testWidgets('multiple photos render a pager with a counter', (tester) async {
    await tester.pumpWidget(host(const [
      'https://example.com/a.jpg',
      'https://example.com/b.jpg',
      'https://example.com/c.jpg',
    ]));

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('swiping advances the page and updates the counter', (tester) async {
    await tester.pumpWidget(host(const [
      'https://example.com/a.jpg',
      'https://example.com/b.jpg',
      'https://example.com/c.jpg',
    ]));

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('empty list renders nothing', (tester) async {
    await tester.pumpWidget(host(const []));
    expect(find.byType(PageView), findsNothing);
  });

  group('resolvePostPhotos', () {
    test('prefers photo_urls when non-empty', () {
      expect(
        resolvePostPhotos(photoUrls: const ['a', 'b'], singleUrl: 'cover'),
        ['a', 'b'],
      );
    });

    test('falls back to the legacy single column', () {
      expect(resolvePostPhotos(photoUrls: null, singleUrl: 'cover'), ['cover']);
      expect(resolvePostPhotos(photoUrls: const [], singleUrl: 'cover'), ['cover']);
    });

    test('empty when neither is present', () {
      expect(resolvePostPhotos(photoUrls: null, singleUrl: null), isEmpty);
      expect(resolvePostPhotos(photoUrls: const [], singleUrl: ''), isEmpty);
    });
  });
}
