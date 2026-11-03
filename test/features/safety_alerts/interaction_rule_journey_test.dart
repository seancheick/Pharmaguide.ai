import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

import 'interaction_rule_journey.dart';

void main() {
  final feedBytes = File(
    'test/fixtures/safety_alerts/interaction_rule_feed.json',
  ).readAsBytesSync();
  final baseBytes = File(
    'test/fixtures/safety_alerts/interaction_rule_base_feed.json',
  ).readAsBytesSync();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a new contraindication appears when the connection returns', (
    tester,
  ) async {
    await runInteractionRuleJourney(
      tester,
      baseBytes: baseBytes,
      feedBytes: feedBytes,
      settle: () => settle(tester),
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

  testWidgets('a pregnancy rule reaches someone taking no medication', (
    tester,
  ) async {
    await runInteractionRuleJourney(
      tester,
      baseBytes: baseBytes,
      feedBytes: feedBytes,
      pregnant: true,
      // A widget test's clock can't wait on the asset bundle; the provider's own
      // test and the simulator journey use the bundled taxonomy.
      extraOverrides: [
        evaluatorProfileFlagsProvider.overrideWith(
          (ref) async => const {'pregnant'},
        ),
      ],
      settle: () => settle(tester),
      onStep: (step) async {
        if (step != 'after_reconnect') return;
        for (final part in [
          'Fakeroot (fictional)',
          'Applies to: Pregnancy',
          'not for use during pregnancy',
          'Worth a conversation with your doctor',
        ]) {
          expect(find.textContaining(part), findsWidgets, reason: part);
        }
        expect(find.text('View source'), findsOneWidget);
      },
    );
  });
}
