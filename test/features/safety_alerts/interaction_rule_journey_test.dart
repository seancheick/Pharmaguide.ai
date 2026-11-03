import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';

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

  testWidgets('a medication list that could not be fully read says so, and the '
      'warning the profile can find still shows', (tester) async {
    // The list builds lazily, and the notice pushes the banner past a short
    // test window.
    tester.view.physicalSize = const Size(1320, 8000);
    addTearDown(tester.view.reset);
    final banner = find.byKey(const Key('personalized-checks-error-banner'));
    await runInteractionRuleJourney(
      tester,
      baseBytes: baseBytes,
      feedBytes: feedBytes,
      pregnant: true,
      extraOverrides: [
        evaluatorProfileFlagsProvider.overrideWith(
          (ref) async => const {'pregnant'},
        ),
        localMedicationIdentityProvider.overrideWith(
          (ref) async => (ids: const <String>{}, isComplete: false),
        ),
      ],
      settle: () => settle(tester),
      onStep: (step) async {
        if (step == 'before_reconnect') {
          expect(banner, findsOneWidget);
          expect(find.textContaining('No known concerns'), findsNothing);
        }
        if (step != 'after_reconnect') return;
        expect(banner, findsOneWidget);
        expect(find.textContaining('Applies to: Pregnancy'), findsOneWidget);
        expect(
          find.textContaining('Fictional test notice: Fakeroot in pregnancy'),
          findsWidgets,
        );
      },
    );
  });
}
