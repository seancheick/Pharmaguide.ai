// Dual-reader widget tests for the ScoreBreakdown section adapter.
//
//   * v4: a blob with `quality_pillars_v4` renders the SIX v4 pillars and
//     suppresses the stale v3 four-section labels.
//   * v3 fallback: no `quality_pillars_v4` → the original four pillars.
//   * malformed v4 map → falls back to v3 (never renders an empty card).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Map<String, dynamic> _v4Pillars() => {
  'formulation': {'score': 17.6, 'max': 20, 'reason': 'Well formulated.'},
  'dose': {'score': 20.0, 'max': 20, 'reason': 'Clinically studied dose.'},
  'evidence': {'score': 18.9, 'max': 20, 'reason': 'Backed by human trials.'},
  'transparency': {
    'score': 13.5,
    'max': 15,
    'reason': 'No proprietary blends.',
  },
  'verification': {'score': 15.0, 'max': 15, 'reason': 'Third-party tested.'},
  'safety_hygiene': {'score': 9.0, 'max': 10, 'reason': 'No banned additives.'},
};

const _v4Labels = [
  'Formulation',
  'Dose',
  'Evidence',
  'Transparency',
  'Verification',
  'Safety Hygiene',
];

void main() {
  nativeScaleTests();
  testWidgets('v4: renders the six pillars from quality_pillars_v4', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          ingredientQuality: 99,
          safetyPurity: 99,
          evidenceResearch: 99,
          brandTrust: 99,
          hasThirdPartyTesting: true,
          isTrustedManufacturer: false,
          heroScore: 95,
          mappedCoverage: 0.9,
          qualityPillarsV4: _v4Pillars(),
        ),
      ),
    );

    for (final label in _v4Labels) {
      expect(
        find.text(label),
        findsOneWidget,
        reason: 'missing v4 pillar: $label',
      );
    }
    // The stale v3 section labels must NOT appear when v4 pillars are present.
    expect(find.text('Ingredient Quality'), findsNothing);
    expect(find.text('Safety & Purity'), findsNothing);
    expect(find.text('Why this scored 95'), findsOneWidget);
  });

  testWidgets('v3 fallback: no quality_pillars_v4 → four v3 pillars', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          ingredientQuality: 20,
          safetyPurity: 28,
          evidenceResearch: 15,
          brandTrust: 4,
          hasThirdPartyTesting: false,
          isTrustedManufacturer: true,
          heroScore: 80,
          mappedCoverage: 0.5,
          qualityPillarsV4: null,
        ),
      ),
    );

    expect(find.text('Ingredient Quality'), findsOneWidget);
    expect(find.text('Safety & Purity'), findsOneWidget);
    expect(find.text('Evidence & Research'), findsOneWidget);
    expect(find.text('Transparency & Verification'), findsOneWidget);
    for (final label in _v4Labels) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('malformed quality_pillars_v4 falls back to v3 (no empty card)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          ingredientQuality: 20,
          safetyPurity: 28,
          evidenceResearch: 15,
          brandTrust: 4,
          hasThirdPartyTesting: false,
          isTrustedManufacturer: false,
          heroScore: 70,
          mappedCoverage: null,
          qualityPillarsV4: const {'garbage': 'not a pillar map'},
        ),
      ),
    );

    expect(find.text('Ingredient Quality'), findsOneWidget);
    expect(find.text('Formulation'), findsNothing);
  });
}

// ---------------------------------------------------------------------------
// v4 native-scale display contract (2026-06): pillars render their REAL
// score/max — NOT normalized /10 — and the card closes with a "= N/100"
// sum line, because quality_score_v4_100 IS the pillar sum.
// ---------------------------------------------------------------------------

Widget _v4Section({Map<String, dynamic>? pillars, double? heroScore = 94}) =>
    buildScoreBreakdownSection(
      ingredientQuality: 99,
      safetyPurity: 99,
      evidenceResearch: 99,
      brandTrust: 99,
      hasThirdPartyTesting: false,
      isTrustedManufacturer: false,
      heroScore: heroScore,
      mappedCoverage: 0.9,
      qualityPillarsV4: pillars ?? _v4Pillars(),
    );

void nativeScaleTests() {
  testWidgets('v4: pillars render native score/max, not /10', (tester) async {
    await tester.pumpWidget(_wrap(_v4Section()));

    expect(find.text('17.6/20'), findsOneWidget); // formulation, decimal kept
    expect(find.text('20/20'), findsOneWidget); // dose, integral → bare
    expect(find.text('13.5/15'), findsOneWidget); // transparency
    expect(find.text('9/10'), findsOneWidget); // safety_hygiene native /10
    expect(find.textContaining('/10 '), findsNothing);
  });

  testWidgets('v4: sum line shows exact pillar sum out of 100', (tester) async {
    await tester.pumpWidget(_wrap(_v4Section()));

    // 17.6 + 20 + 18.9 + 13.5 + 15 + 9 = 94
    expect(find.text('= 94/100'), findsOneWidget);
    expect(
      find.text('Six pillars, out of 100 — they add up to the score.'),
      findsOneWidget,
    );
  });

  testWidgets('v4: sum line hidden when any pillar lacks a score', (
    tester,
  ) async {
    final pillars = _v4Pillars();
    (pillars['dose'] as Map<String, dynamic>).remove('score');
    await tester.pumpWidget(_wrap(_v4Section(pillars: pillars)));

    expect(find.textContaining('= '), findsNothing);
    expect(find.text('No data'), findsOneWidget);
  });

  testWidgets('v3 fallback: keeps the normalized /10 display', (tester) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          ingredientQuality: 20, // /25 → 8/10
          safetyPurity: 30, // /30 → 10/10
          evidenceResearch: 10, // /20 → 5/10
          brandTrust: 4, // /5 → 8/10
          hasThirdPartyTesting: false,
          isTrustedManufacturer: false,
          heroScore: 73,
          mappedCoverage: 0.9,
          qualityPillarsV4: null,
        ),
      ),
    );

    expect(find.text('8/10'), findsNWidgets(2));
    expect(find.text('10/10'), findsOneWidget);
    expect(find.text('5/10'), findsOneWidget);
    expect(find.textContaining('= '), findsNothing); // no sum line on v3
    expect(find.text('Tap any pillar to see what drives it.'), findsOneWidget);
  });
}
