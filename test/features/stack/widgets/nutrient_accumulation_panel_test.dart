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
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stackNutrientStatusesProvider.overrideWith((ref) async {
            // Translate the AsyncValue test fixture into a Future.
            return override.when(
              data: (d) => d,
              loading: () => _neverComplete<List<NutrientStatus>>(),
              error: (e, _) => Future<List<NutrientStatus>>.error(e),
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

  testWidgets('error state collapses silently', (tester) async {
    await pumpPanel(
      tester,
      override: AsyncValue<List<NutrientStatus>>.error(
        Exception('boom'),
        StackTrace.current,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrient-accumulation-card')), findsNothing);
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
}

/// Returns a future that never completes, used to keep the panel in
/// its loading state for as long as the test wants.
Future<T> _neverComplete<T>() {
  final completer = Completer<T>();
  return completer.future;
}
