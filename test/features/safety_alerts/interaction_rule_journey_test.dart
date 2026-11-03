import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'interaction_rule_journey.dart';

void main() {
  testWidgets('a new contraindication appears when the connection returns', (
    tester,
  ) async {
    final feedBytes = File(
      'test/fixtures/safety_alerts/interaction_rule_feed.json',
    ).readAsBytesSync();

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await runInteractionRuleJourney(
      tester,
      feedBytes: feedBytes,
      settle: settle,
      onStep: (step) async {
        if (step != 'after_reconnect') return;
        for (final part in [
          'Fakeroot (fictional)',
          'Testoprilex (fictional)',
          'can raise Testoprilex levels',
          'Worth a conversation with your doctor',
        ]) {
          expect(find.textContaining(part), findsWidgets, reason: part);
        }
        expect(find.text('View source'), findsOneWidget);
      },
    );
  });
}
