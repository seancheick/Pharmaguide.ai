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
  String? alertHeadline,
  String? alertBody,
  String? monitoringTip,
  String clinicalImpact = 'Low status can cause symptoms.',
  String mechanism = 'Detailed mechanism.',
  String recommendation = 'Discuss monitoring with your clinician.',
  List<DepletionSource> sources = const [],
}) => DepletionMatch(
  depletionId: id,
  drugDisplayName: drug,
  drugClassId: 'class:x',
  nutrientName: nutrient,
  nutrientCanonicalId: nutrient.toLowerCase(),
  depletionType: type,
  severity: 'significant',
  mechanism: mechanism,
  recommendation: recommendation,
  clinicalImpact: clinicalImpact,
  sources: sources,
  alertHeadline: alertHeadline,
  alertBody: alertBody,
  monitoringTipShort: monitoringTip,
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
    expect(find.text('Medication & nutrients'), findsOneWidget);
    expect(find.textContaining('covered'), findsNothing);
    expect(find.textContaining('already taking'), findsNothing);
  });

  testWidgets('surfaces relationship label + factual no-source body', (
    tester,
  ) async {
    await _pump(tester, [
      _dep(type: 'depletion', nutrient: 'Vitamin B12', drug: 'Metformin'),
    ]);
    expect(find.text('MEDICATION/NUTRIENT GUIDANCE'), findsOneWidget);
    expect(
      find.textContaining('No Vitamin B12 source detected'),
      findsOneWidget,
    );
  });

  testWidgets('metformin row uses plain supply copy and reviewed guidance', (
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
        alertHeadline: 'Long-term metformin can lower vitamin B12',
        alertBody:
            'With long-term use, the chance of low B12 rises with higher '
            'doses and other B12 factors.',
        monitoringTip:
            'Consider B12 testing with long-term use, symptoms, or other '
            'risk factors.',
      ),
    ]);
    expect(
      find.text('Long-term metformin can lower vitamin B12'),
      findsOneWidget,
    );
    expect(
      find.textContaining('provides 250 mcg/day of Vitamin B12'),
      findsOneWidget,
    );
    expect(
      find.textContaining('does not confirm your blood level'),
      findsOneWidget,
    );
    expect(find.text('What to monitor'), findsOneWidget);
    expect(find.textContaining('comparison amount'), findsNothing);
    expect(find.textContaining('covered'), findsNothing);
    expect(find.textContaining('adequate'), findsNothing);
  });

  testWidgets('warfarin row is an interaction using reviewed consistency copy', (
    tester,
  ) async {
    await _pump(tester, [
      _dep(
        type: 'functional_antagonism',
        nutrient: 'Vitamin K',
        drug: 'Warfarin',
        alertHeadline: 'Warfarin is sensitive to vitamin K changes',
        alertBody:
            'Keep vitamin K intake consistent. Sudden diet or supplement '
            'changes can affect how strongly warfarin works.',
        monitoringTip:
            'Keep vitamin K intake steady day to day; discuss changes with '
            'your prescriber.',
      ),
    ]);
    expect(
      find.text('Warfarin is sensitive to vitamin K changes'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Sudden diet or supplement changes can affect how strongly warfarin works',
      ),
      findsOneWidget,
    );
    expect(find.text('MEDICATION/NUTRIENT GUIDANCE'), findsOneWidget);
    expect(find.text('Why this matters'), findsOneWidget);
    expect(find.textContaining('keep intake steady'), findsNothing);
    expect(find.textContaining('may affect how the body uses'), findsNothing);
  });

  testWidgets('the full relationship card opens its focused detail sheet', (
    tester,
  ) async {
    await _pump(tester, [
      _dep(
        type: 'depletion',
        nutrient: 'Vitamin B12',
        drug: 'Metformin (type 2 diabetes medication)',
        alertHeadline: 'Long-term metformin can lower vitamin B12',
        sources: const [
          DepletionSource(
            sourceType: 'reference',
            label: 'MHRA',
            url: 'https://www.gov.uk/example',
          ),
        ],
      ),
    ]);

    await tester.tap(find.text('Long-term metformin can lower vitamin B12'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Metformin & Vitamin B12'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.text('WHAT CAN HAPPEN', skipOffstage: false), findsOneWidget);
    expect(find.text('WHY', skipOffstage: false), findsOneWidget);
    expect(find.text('WHAT TO DO', skipOffstage: false), findsOneWidget);
    expect(find.text('MHRA', skipOffstage: false), findsOneWidget);
    expect(find.text('FROM FOOD', skipOffstage: false), findsNothing);
  });

  testWidgets('detail sheet survives small screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    // The production app intentionally caps Dynamic Type at 1.4x.
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await _pump(tester, [
      _dep(type: 'depletion', nutrient: 'Vitamin B12', drug: 'Metformin'),
    ]);
    await tester.ensureVisible(find.text('Vitamin B12'));
    await tester.tap(find.text('Vitamin B12'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
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
