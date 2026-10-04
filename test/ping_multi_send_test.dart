import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i/features/ping/ping_prompt_sheet.dart';

/// The prompt-first, then "Send to…" multi-ping flow in PingPromptSheet:
/// write a prompt → Next → tick people/groups → "Send to N" delivers the
/// prompt with exactly the ticked recipients, pre-selection included.
void main() {
  const recipients = [
    PingRecipient(id: 'u1', name: 'akhil'),
    PingRecipient(id: 'u2', name: 'shreyas'),
    PingRecipient(id: 'u3', name: 'manmohan'),
    PingRecipient(id: 'g1', name: 'FUN IN BLOOD', isGroup: true),
  ];

  Future<List<Object?>?> run(
    WidgetTester tester, {
    Set<String> preselect = const {},
    required List<String> tapNames,
    bool send = true,
  }) async {
    List<Object?>? got;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showPingPromptSheet(
                context,
                targetName: 'people',
                pingContext: PingContext.pingPage,
                showScoreReward: false,
                recipients: recipients,
                initialSelected: preselect,
                onSendMany: (prompt, to, {photoUrl}) {
                  got = [prompt, to.map((r) => r.id).toList(), photoUrl];
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Step 1: prompt. "Next", not "Send".
    expect(find.text('Ping someone'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Show us your desk');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: Send to…, prompt pinned on top.
    expect(find.text('Send to…'), findsOneWidget);
    expect(find.text('“Show us your desk”'), findsOneWidget);
    expect(find.text('people'), findsOneWidget);
    expect(find.text('groups'), findsOneWidget);

    for (final n in tapNames) {
      await tester.tap(find.text(n));
      await tester.pump();
    }
    final total = {...preselect, ...tapNames}.length;
    if (total == 0 || !send) {
      expect(
        find.text(total > 0 ? 'Send to $total' : 'Pick someone'),
        findsOneWidget,
      );
      return got;
    }
    await tester.tap(find.text('Send to $total'));
    await tester.pumpAndSettle();
    return got;
  }

  testWidgets('sends one prompt to several people and a group', (tester) async {
    final got = await run(tester, tapNames: ['akhil', 'manmohan', 'FUN IN BLOOD']);
    expect(got, isNotNull);
    expect(got![0], 'Show us your desk');
    expect(got[1], ['u1', 'u3', 'g1']);
    expect(got[2], isNull);
    // Sheet closed after sending.
    expect(find.text('Send to…'), findsNothing);
  });

  testWidgets('tapping a face pre-ticks that person', (tester) async {
    // Pre-ticked: "Send to 1" is live without touching the grid.
    final got = await run(tester, preselect: {'u2'}, tapNames: const []);
    expect(got, ['Show us your desk', ['u2'], null]);
  });

  testWidgets('untick all → send disabled; Back returns to prompt', (tester) async {
    await run(tester, preselect: {'u2'}, tapNames: const [], send: false);
    await tester.tap(find.text('shreyas')); // untick
    await tester.pump();
    expect(find.text('Pick someone'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('search filters the grid', (tester) async {
    await run(tester, tapNames: const []);
    await tester.enterText(find.byType(TextField).last, 'shr');
    await tester.pump();
    expect(find.text('shreyas'), findsOneWidget);
    expect(find.text('akhil'), findsNothing);
    expect(find.text('FUN IN BLOOD'), findsNothing);
  });
}
