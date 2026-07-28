// Widget contract for PGDepletionCard after the B1.1 factual-copy rewrite.
// The card must not author a coverage verdict ("covered"/"adequate") or render
// affirmation copy ("you're already taking…"); it states what the stack
// supplies, surfaces the relationship type, and never implies sufficiency.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_depletion_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

DepletionMatch _dep({
  required String type,
  required String nutrient,
  required String drug,
  String id = 'DEP_X',
  CoverageLevel coverage = CoverageLevel.none,
  num? detectedAmount,
  String? detectedUnit,
  num? adequacyMcg,
}) => DepletionMatch(
  depletionId: id,
  drugDisplayName: drug,
  drugClassId: 'class:x',
  nutrientName: nutrient,
  nutrientCanonicalId: nutrient.toLowerCase(),
  depletionType: type,
  severity: 'significant',
  mechanism: 'mech',
  recommendation: 'rec',
  detectedAmount: detectedAmount,
  detectedUnit: detectedUnit,
  adequacyThresholdMcg: adequacyMcg,
  coverageLevel: coverage,
);

Future<void> _pump(WidgetTester tester, List<DepletionMatch> deps) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverList.list(children: [PGDepletionCard(depletions: deps)]),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets('factual header, no "covered" verdict', (tester) async {
    await _pump(tester, [
      _dep(type: 'depletion', nutrient: 'Vitamin B12', drug: 'Metformin'),
    ]);
    expect(find.textContaining('Nutrients to monitor'), findsOneWidget);
    expect(find.textContaining('covered'), findsNothing);
    expect(find.textContaining('already taking'), findsNothing);
  });

  testWidgets('surfaces relationship label + factual no-source body', (
    tester,
  ) async {
    await _pump(tester, [
      _dep(type: 'depletion', nutrient: 'Vitamin B12', drug: 'Metformin'),
    ]);
    expect(
      find.textContaining('ASSOCIATED NUTRIENT TO MONITOR'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No Vitamin B12 source detected'),
      findsOneWidget,
    );
  });

  testWidgets('meets-comparison row makes no sufficiency/covered claim', (
    tester,
  ) async {
    await _pump(tester, [
      _dep(
        type: 'depletion',
        nutrient: 'Vitamin B12',
        drug: 'Metformin',
        coverage: CoverageLevel.adequate,
        detectedAmount: 250,
        detectedUnit: 'mcg',
        adequacyMcg: 100,
      ),
    ]);
    expect(
      find.textContaining('contains 250 mcg of Vitamin B12 per day'),
      findsOneWidget,
    );
    expect(
      find.textContaining('This meets the comparison amount'),
      findsOneWidget,
    );
    expect(find.textContaining('covered'), findsNothing);
    expect(find.textContaining('adequate'), findsNothing);
  });

  testWidgets('functional antagonism is not framed as depletion', (
    tester,
  ) async {
    await _pump(tester, [
      _dep(
        type: 'functional_antagonism',
        nutrient: 'Magnesium',
        drug: 'Furosemide',
      ),
    ]);
    expect(
      find.textContaining('may affect how the body uses Magnesium'),
      findsOneWidget,
    );
    expect(find.textContaining('MAY AFFECT NUTRIENT FUNCTION'), findsOneWidget);
  });

  testWidgets('unavailable card is an explicit not-all-clear state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverList.list(children: const [PGDepletionUnavailableCard()]),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Check unavailable'), findsOneWidget);
    expect(find.textContaining('not an all-clear'), findsOneWidget);
    // Must not read as a clean state.
    expect(find.textContaining('No '), findsNothing);
  });
}
