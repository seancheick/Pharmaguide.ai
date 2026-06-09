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
  'transparency': {'score': 13.5, 'max': 15, 'reason': 'No proprietary blends.'},
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
