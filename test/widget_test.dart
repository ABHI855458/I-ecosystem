import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saanvi/main.dart';

void main() {
  testWidgets('shows the campus app shell and navigates tabs', (tester) async {
    await tester.pumpWidget(const IApp());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Home screen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.groups_2_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Communities'), findsWidgets);
    expect(find.text('Communities screen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bolt_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Ping'), findsWidgets);
    expect(find.text('Ping screen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsWidgets);
    expect(find.text('Profile screen'), findsOneWidget);
  });
}
