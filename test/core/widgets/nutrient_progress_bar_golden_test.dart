// Golden-image tests for [NutrientProgressBar] — one per [NutrientTier].
// To regenerate: flutter test --update-goldens test/core/widgets/nutrient_progress_bar_golden_test.dart
//
// These tests guard against future color tier regressions (e.g. someone
// accidentally changing the exceedsUl color from red to orange).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_progress_bar.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

NutrientStatus _status({
  required NutrientTier tier,
  double? pctOfRda,
  double? pctOfUl,
  String? warning,
}) {
  return NutrientStatus(
    total: const NutrientTotal(
      canonicalId: 'test_nutrient',
      displayName: 'Test Nutrient',
      totalAmount: 200,
      unit: 'mg',
      contributions: [],
    ),
    tier: tier,
    pctOfRda: pctOfRda,
    pctOfUl: pctOfUl,
    warning: warning,
  );
}

Widget _wrap(NutrientStatus status) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: NutrientProgressBar(status: status),
        ),
      ),
    );

void main() {
  testWidgets('golden: exceedsUl tier', (tester) async {
    await tester.pumpWidget(_wrap(_status(
      tier: NutrientTier.exceedsUl,
      pctOfRda: 450,
      pctOfUl: 180,
      warning: 'Exceeds upper limit',
    )));
    await tester.pump();
    await expectLater(
      find.byType(NutrientProgressBar),
      matchesGoldenFile('goldens/nutrient_progress_bar_exceedsUl.png'),
    );
  });

  testWidgets('golden: approachingUl tier', (tester) async {
    await tester.pumpWidget(_wrap(_status(
      tier: NutrientTier.approachingUl,
      pctOfRda: 320,
      pctOfUl: 90,
      warning: 'Approaching upper limit',
    )));
    await tester.pump();
    await expectLater(
      find.byType(NutrientProgressBar),
      matchesGoldenFile('goldens/nutrient_progress_bar_approachingUl.png'),
    );
  });

  testWidgets('golden: aboveTypical tier', (tester) async {
    await tester.pumpWidget(_wrap(_status(
      tier: NutrientTier.aboveTypical,
      pctOfRda: 280,
      pctOfUl: 65,
    )));
    await tester.pump();
    await expectLater(
      find.byType(NutrientProgressBar),
      matchesGoldenFile('goldens/nutrient_progress_bar_aboveTypical.png'),
    );
  });

  testWidgets('golden: abundant tier', (tester) async {
    await tester.pumpWidget(_wrap(_status(
      tier: NutrientTier.abundant,
      pctOfRda: 150,
    )));
    await tester.pump();
    await expectLater(
      find.byType(NutrientProgressBar),
      matchesGoldenFile('goldens/nutrient_progress_bar_abundant.png'),
    );
  });

  testWidgets('golden: adequate tier', (tester) async {
    await tester.pumpWidget(_wrap(_status(
      tier: NutrientTier.adequate,
      pctOfRda: 90,
    )));
    await tester.pump();
    await expectLater(
      find.byType(NutrientProgressBar),
      matchesGoldenFile('goldens/nutrient_progress_bar_adequate.png'),
    );
  });

  testWidgets('golden: underFifty tier', (tester) async {
    await tester.pumpWidget(_wrap(_status(
      tier: NutrientTier.underFifty,
      pctOfRda: 30,
    )));
    await tester.pump();
    await expectLater(
      find.byType(NutrientProgressBar),
      matchesGoldenFile('goldens/nutrient_progress_bar_underFifty.png'),
    );
  });

  testWidgets('golden: noRda tier', (tester) async {
    await tester.pumpWidget(_wrap(_status(tier: NutrientTier.noRda)));
    await tester.pump();
    await expectLater(
      find.byType(NutrientProgressBar),
      matchesGoldenFile('goldens/nutrient_progress_bar_noRda.png'),
    );
  });
}
