// Widget tests for [NutrientAccumulationPanel].
//
// We override [stackNutrientStatusesProvider] with synthetic data so
// the test never touches the database, Supabase, or asset bundles.
// Each test asserts one panel state: loading, error, empty, single
// warning, multiple warnings.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_accumulation_panel.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required AsyncValue<List<NutrientStatus>> override,
    bool incomplete = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stackNutrientStatusesProvider.overrideWith((ref) async {
            // Translate the AsyncValue test fixture into a Future.
            return override.when(
              data: (d) =>
                  StackNutrientStatuses(statuses: d, incomplete: incomplete),
              loading: () => _neverComplete<StackNutrientStatuses>(),
              error: (e, _) => Future<StackNutrientStatuses>.error(e),
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NutrientAccumulationPanel()),
        ),
      ),
    );
    await tester.pump(); // settle the FutureProvider
  }

  testWidgets('loading state shows progress indicator', (tester) async {
    await pumpPanel(
      tester,
      override: const AsyncValue<List<NutrientStatus>>.loading(),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('empty stack collapses to nothing', (tester) async {
    await pumpPanel(
      tester,
      override: const AsyncValue<List<NutrientStatus>>.data([]),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrient-accumulation-card')), findsNothing);
    expect(find.text('Stack Nutrient Totals'), findsNothing);
  });

  testWidgets('error state says totals are unavailable, never blank', (
    tester,
  ) async {
    // Regression: this panel IS the upper-limit surface. A silent shrink
    // reads as "no UL concerns" — exactly what a failed check cannot
    // promise. The previous test asserted findsNothing and so locked in
    // the false all-clear.
    await pumpPanel(
      tester,
      override: AsyncValue<List<NutrientStatus>>.error(
        Exception('boom'),
        StackTrace.current,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nutrient-totals-unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('not an all-clear'), findsOneWidget);
  });

  testWidgets('partial totals carry a hedge above the numbers', (tester) async {
    // Regression: a skipped stack item makes the sum an under-report, so a
    // UL comparison drawn from it can read "within limit" when the true
    // total is unknown. The number must not stand unqualified.
    const status = NutrientStatus(
      total: NutrientTotal(
        canonicalId: 'zinc',
        displayName: 'Zinc',
        totalAmount: 12,
        unit: 'mg',
        contributions: [],
      ),
      tier: NutrientTier.adequate,
      rda: 11,
      ul: 40,
      pctOfRda: 109.0,
      pctOfUl: 30.0,
    );
    await pumpPanel(
      tester,
      override: const AsyncValue<List<NutrientStatus>>.data([status]),
      incomplete: true,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nutrient-totals-partial-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('lower than your full intake'), findsOneWidget);
  });

  testWidgets('complete totals carry no hedge', (tester) async {
    const status = NutrientStatus(
      total: NutrientTotal(
        canonicalId: 'zinc',
        displayName: 'Zinc',
        totalAmount: 12,
        unit: 'mg',
        contributions: [],
      ),
      tier: NutrientTier.adequate,
      rda: 11,
      ul: 40,
      pctOfRda: 109.0,
      pctOfUl: 30.0,
    );
    await pumpPanel(
      tester,
      override: const AsyncValue<List<NutrientStatus>>.data([status]),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nutrient-totals-partial-notice')),
      findsNothing,
    );
  });

  testWidgets('every stack item skipped still says so rather than hiding', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      override: const AsyncValue<List<NutrientStatus>>.data([]),
      incomplete: true,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nutrient-totals-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('single warning renders header + alert badge + bar', (
    tester,
  ) async {
    const status = NutrientStatus(
      total: NutrientTotal(
        canonicalId: 'zinc',
        displayName: 'Zinc',
        totalAmount: 52,
        unit: 'mg',
        contributions: [],
      ),
      tier: NutrientTier.exceedsUl,
      rda: 11,
      ul: 40,
      pctOfRda: 472.7,
      pctOfUl: 130.0,
      warning: 'Exceeds Upper Limit — risk of copper depletion',
    );

    await pumpPanel(
      tester,
      override: const AsyncValue<List<NutrientStatus>>.data([status]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stack Nutrient Totals'), findsOneWidget);
    expect(find.text('1 alert'), findsOneWidget);
    expect(find.text('Zinc'), findsOneWidget);
    expect(find.textContaining('copper depletion'), findsOneWidget);
    expect(find.byKey(const Key('warn-zinc')), findsOneWidget);
  });

  testWidgets('multiple warnings render with plural label', (tester) async {
    final statuses = [
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'zinc',
          displayName: 'Zinc',
          totalAmount: 52,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.exceedsUl,
        rda: 11,
        ul: 40,
        pctOfRda: 472.7,
        pctOfUl: 130.0,
        warning: 'Exceeds Upper Limit — risk of copper depletion',
      ),
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'iron',
          displayName: 'Iron',
          totalAmount: 50,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.exceedsUl,
        rda: 8,
        ul: 45,
        pctOfRda: 625,
        pctOfUl: 111,
        warning: 'Exceeds Upper Limit — risk of GI toxicity',
      ),
    ];

    await pumpPanel(
      tester,
      override: AsyncValue<List<NutrientStatus>>.data(statuses),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 alerts'), findsOneWidget);
    expect(find.byKey(const Key('warn-zinc')), findsOneWidget);
    expect(find.byKey(const Key('warn-iron')), findsOneWidget);
  });

  testWidgets('safety warnings stay ahead of non-warning UL rows', (
    tester,
  ) async {
    final statuses = [
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_d',
          displayName: 'Vitamin D',
          totalAmount: 25,
          unit: 'mcg',
          contributions: [],
        ),
        tier: NutrientTier.adequate,
        rda: 15,
        ul: 100,
        pctOfRda: 166.7,
        pctOfUl: 25,
      ),
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'zinc',
          displayName: 'Zinc',
          totalAmount: 35,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.approachingUl,
        rda: 11,
        ul: 40,
        pctOfRda: 318.2,
        warning: 'Approaching the upper limit',
      ),
    ];

    await pumpPanel(
      tester,
      override: AsyncValue<List<NutrientStatus>>.data(statuses),
    );
    await tester.pumpAndSettle();

    final warningTop = tester.getTopLeft(find.byKey(const Key('warn-zinc'))).dy;
    final regularTop = tester
        .getTopLeft(find.byKey(const Key('row-vitamin_d')))
        .dy;
    expect(warningTop, lessThan(regularTop));
  });

  testWidgets('non-warning rows render under "X tracked" header', (
    tester,
  ) async {
    final statuses = [
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'magnesium',
          displayName: 'Magnesium',
          totalAmount: 200,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.adequate,
        rda: 400,
        ul: 350,
        pctOfRda: 50,
        pctOfUl: 57.1,
      ),
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_c',
          displayName: 'Vitamin C',
          totalAmount: 500,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.abundant,
        rda: 90,
        ul: 2000,
        pctOfRda: 555.5,
        pctOfUl: 25,
      ),
    ];

    await pumpPanel(
      tester,
      override: AsyncValue<List<NutrientStatus>>.data(statuses),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 tracked'), findsOneWidget);
    expect(find.text('Magnesium'), findsOneWidget);
    expect(find.text('Vitamin C'), findsOneWidget);
    // No alert badge for non-warning rows.
    expect(find.textContaining('alert'), findsNothing);
  });

  testWidgets(
    'separates upper limits, intake targets without ULs, and label amounts',
    (tester) async {
      final statuses = [
        const NutrientStatus(
          total: NutrientTotal(
            canonicalId: 'vitamin_d',
            displayName: 'Vitamin D',
            totalAmount: 25,
            unit: 'mcg',
            contributions: [],
          ),
          tier: NutrientTier.adequate,
          rda: 15,
          ul: 100,
          pctOfRda: 166.7,
          pctOfUl: 25,
        ),
        const NutrientStatus(
          total: NutrientTotal(
            canonicalId: 'vitamin_b12',
            displayName: 'Vitamin B12',
            totalAmount: 5,
            unit: 'mcg',
            contributions: [],
          ),
          tier: NutrientTier.aboveAdequateNoUl,
          rda: 2.4,
          pctOfRda: 208.3,
        ),
        const NutrientStatus(
          total: NutrientTotal(
            canonicalId: 'lycopene',
            displayName: 'Lycopene',
            totalAmount: 10,
            unit: 'mg',
            contributions: [],
          ),
          tier: NutrientTier.noRda,
        ),
      ];

      await pumpPanel(
        tester,
        override: AsyncValue<List<NutrientStatus>>.data(statuses),
      );
      await tester.pumpAndSettle();

      expect(find.text('Safety limits'), findsOneWidget);
      expect(find.text('Intake targets — no UL'), findsOneWidget);
      expect(find.text('Label amounts'), findsOneWidget);
      expect(
        find.textContaining(
          'Above 100% of a target is not automatically unsafe',
        ),
        findsOneWidget,
      );
      expect(find.text('Vitamin D'), findsOneWidget);
      expect(find.text('Vitamin B12'), findsOneWidget);

      // Raw label amounts stay compact until the user asks to see them.
      expect(find.text('Lycopene'), findsNothing);
      await tester.tap(find.text('Show 1 label amount'));
      await tester.pumpAndSettle();
      expect(find.text('Lycopene'), findsOneWidget);
      expect(find.text('Hide label amounts'), findsOneWidget);
    },
  );
}

/// Returns a future that never completes, used to keep the panel in
/// its loading state for as long as the test wants.
Future<T> _neverComplete<T>() {
  final completer = Completer<T>();
  return completer.future;
}
