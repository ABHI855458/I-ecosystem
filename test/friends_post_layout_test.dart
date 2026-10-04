import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i/features/composer/dual_photo_compositor.dart';
import 'package:i/screens/feed/widgets/dual_photo_view.dart';

/// Locks the friends post frame and its dual-camera inset to the measured
/// reference: a 402pt-wide full-bleed photo is 536pt tall (3:4), and the
/// inset is a 121x161 bubble sitting 12pt in from the top-left corner.
///
/// Measured off the reference screenshot at 3x (1206x2622), so every
/// expectation below is that measurement divided by three.
void main() {
  const screenWidth = 402.0;

  Widget host({bool insetOnRight = false}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: screenWidth,
            child: DualPhotoView(
              backgroundUrl: 'https://example.com/back.jpg',
              insetUrl: 'https://example.com/front.jpg',
              insetOnRight: insetOnRight,
            ),
          ),
        ),
      );

  testWidgets('outer frame is 3:4 at full width', (tester) async {
    await tester.pumpWidget(host());

    final frame = tester.getSize(find.byType(AspectRatio));
    expect(frame.width, closeTo(402, 0.5));
    expect(frame.height, closeTo(536, 0.5));
  });

  testWidgets('inset sits 12pt from the top-left at 121x161', (tester) async {
    await tester.pumpWidget(host());

    final frame = tester.getRect(find.byType(AspectRatio));
    final inset = tester.getRect(find.byType(GestureDetector).first);

    expect(inset.left - frame.left, closeTo(12, 0.5));
    expect(inset.top - frame.top, closeTo(12, 0.5));
    expect(inset.width, closeTo(121, 0.5));
    expect(inset.height, closeTo(161, 0.5));
  });

  testWidgets('inset corner radius resolves to ~9pt', (tester) async {
    await tester.pumpWidget(host());

    final inset = tester.getSize(find.byType(GestureDetector).first);
    final radius = inset.width * FriendsDualInsetGeometry.radiusRatio;
    expect(radius, closeTo(9, 0.5));
  });

  testWidgets('insetOnRight mirrors it to the right margin', (tester) async {
    await tester.pumpWidget(host(insetOnRight: true));

    final frame = tester.getRect(find.byType(AspectRatio));
    final inset = tester.getRect(find.byType(GestureDetector).first);

    expect(frame.right - inset.right, closeTo(12, 0.5));
    expect(inset.top - frame.top, closeTo(12, 0.5));
  });
}
