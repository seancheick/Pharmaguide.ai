// v4 widget tests for the ScoreBreakdown section adapter.
//
//   * v4: a blob with `quality_pillars_v4` renders the SIX v4 pillars and
//     suppresses the stale v3 four-section labels.
//   * missing/malformed v4 map → unavailable state, never stale v3 math.

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
  gapLineTests();
  deepLinkTests();
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

  testWidgets('no quality_pillars_v4 → unavailable state, not v3 math', (
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

    expect(find.text('Score breakdown unavailable'), findsOneWidget);
    expect(find.text('Ingredient Quality'), findsNothing);
    expect(find.text('Safety & Purity'), findsNothing);
    expect(find.text('Evidence & Research'), findsNothing);
    expect(find.text('Transparency & Verification'), findsNothing);
    for (final label in _v4Labels) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('malformed quality_pillars_v4 shows unavailable state', (
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

    expect(find.text('Score breakdown unavailable'), findsOneWidget);
    expect(find.text('Ingredient Quality'), findsNothing);
    expect(find.text('Formulation'), findsNothing);
  });

  testWidgets('SHIP RULE: partial blob (4/6 pillars) shows unavailable state — '
      'never a partial native-scale sum under the hero', (tester) async {
    final partial = _v4Pillars();
    partial.remove('verification');
    partial.remove('safety_hygiene');

    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          ingredientQuality: 20,
          safetyPurity: 28,
          evidenceResearch: 15,
          brandTrust: 4,
          hasThirdPartyTesting: false,
          isTrustedManufacturer: false,
          heroScore: 98.1,
          mappedCoverage: 0.9,
          qualityPillarsV4: partial,
        ),
      ),
    );

    // Unavailable state rendered — NOT four v4 pillars with a "= 70/100"
    // sum line contradicting the 98.1 hero, and not stale v3 section math.
    expect(find.text('Score breakdown unavailable'), findsOneWidget);
    expect(find.text('Ingredient Quality'), findsNothing);
    expect(find.text('Formulation'), findsNothing);
    expect(find.textContaining('= '), findsNothing);
  });

  testWidgets('tolerant parsing: numeric-string scores and max<=0 render '
      'via spec fallback, never throw', (tester) async {
    final pillars = _v4Pillars();
    (pillars['formulation'] as Map<String, dynamic>)['score'] = '17.6';
    (pillars['dose'] as Map<String, dynamic>)['max'] = 0; // → fallback 20
    await tester.pumpWidget(_wrap(_v4Section(pillars: pillars)));

    expect(find.text('17.6/20'), findsOneWidget); // string score parsed
    expect(find.text('20/20'), findsOneWidget); // dose against fallback max
    expect(find.text('= 94/100'), findsOneWidget); // all six still sum
  });

  testWidgets('sum line matches the 0.1-rounded values the rows display', (
    tester,
  ) async {
    // Raw values whose unrounded sum (93.38 → "93.4") disagrees with the
    // sum of the displayed 0.1-rounded row values
    // (17.5 + 20 + 18.5 + 13.5 + 15 + 9 = 93.5).
    final pillars = _v4Pillars();
    (pillars['formulation'] as Map<String, dynamic>)['score'] = 17.46;
    (pillars['evidence'] as Map<String, dynamic>)['score'] = 18.46;
    (pillars['transparency'] as Map<String, dynamic>)['score'] = 13.46;
    await tester.pumpWidget(_wrap(_v4Section(pillars: pillars)));

    expect(find.text('17.5/20'), findsOneWidget);
    expect(find.text('18.5/20'), findsOneWidget);
    expect(find.text('13.5/15'), findsOneWidget);
    // The sum line must reproduce the arithmetic a user can do from the
    // visible rows — 93.5, not the raw 93.4.
    expect(find.text('= 93.5/100'), findsOneWidget);
    expect(find.text('= 93.4/100'), findsNothing);
  });
}

// ---------------------------------------------------------------------------
// v4 native-scale display contract (2026-06): pillars render their REAL
// score/max — NOT normalized /10 — and the card closes with a "= N/100"
// sum line, because quality_score_v4_100 IS the pillar sum.
// ---------------------------------------------------------------------------

Widget _v4Section({
  Map<String, dynamic>? pillars,
  double? heroScore = 94,
  Map<String, VoidCallback>? onPillarTap,
}) => buildScoreBreakdownSection(
  ingredientQuality: 99,
  safetyPurity: 99,
  evidenceResearch: 99,
  brandTrust: 99,
  hasThirdPartyTesting: false,
  isTrustedManufacturer: false,
  heroScore: heroScore,
  mappedCoverage: 0.9,
  qualityPillarsV4: pillars ?? _v4Pillars(),
  onPillarTap: onPillarTap,
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

  testWidgets('missing v4 pillars never renders normalized v3 /10 display', (
    tester,
  ) async {
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

    expect(find.text('Score breakdown unavailable'), findsOneWidget);
    expect(find.text('8/10'), findsNothing);
    expect(find.text('10/10'), findsNothing);
    expect(find.text('5/10'), findsNothing);
    expect(find.textContaining('= '), findsNothing);
    expect(find.text('Tap any pillar to see what drives it.'), findsNothing);
  });
}

// ---------------------------------------------------------------------------
// "Biggest opportunity" gap line — shown only when total < 95 AND the
// largest (max − score) gap is ≥ 3 points. Calm explanation, not a judgment.
// ---------------------------------------------------------------------------

void gapLineTests() {
  testWidgets('gap line: shown with pillar label + reason when gap ≥ 3', (
    tester,
  ) async {
    final pillars = _v4Pillars();
    // formulation 15/20 → gap 5 is the largest; sum 91.4 (< 95).
    (pillars['formulation'] as Map<String, dynamic>)['score'] = 15.0;
    await tester.pumpWidget(_wrap(_v4Section(pillars: pillars)));

    expect(
      find.textContaining('Biggest opportunity: Formulation — '),
      findsOneWidget,
    );
  });

  testWidgets('gap line: hidden when largest gap < 3', (tester) async {
    // Default fixture sums to 94 (< 95) but largest gap is 2.4 (formulation).
    await tester.pumpWidget(_wrap(_v4Section()));

    expect(find.textContaining('Biggest opportunity'), findsNothing);
  });

  testWidgets('gap line: hidden when total ≥ 95 (no nitpicking)', (
    tester,
  ) async {
    final pillars = _v4Pillars();
    // dose stays 20/20; raise the rest so sum = 95.4 with a 4-pt gap.
    (pillars['formulation'] as Map<String, dynamic>)['score'] = 16.0;
    (pillars['evidence'] as Map<String, dynamic>)['score'] = 20.0;
    (pillars['transparency'] as Map<String, dynamic>)['score'] = 15.0;
    (pillars['verification'] as Map<String, dynamic>)['score'] = 15.0;
    (pillars['safety_hygiene'] as Map<String, dynamic>)['score'] = 9.4;
    await tester.pumpWidget(_wrap(_v4Section(pillars: pillars)));

    expect(find.textContaining('Biggest opportunity'), findsNothing);
  });

  testWidgets('gap line: hidden when v4 pillars are unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          ingredientQuality: 10,
          safetyPurity: 12,
          evidenceResearch: 5,
          brandTrust: 1,
          hasThirdPartyTesting: false,
          isTrustedManufacturer: false,
          heroScore: 40,
          mappedCoverage: 0.9,
          qualityPillarsV4: null,
        ),
      ),
    );

    expect(find.textContaining('Biggest opportunity'), findsNothing);
  });
}

// ---------------------------------------------------------------------------
// Pillar deep-links — "See details →" appears inside the expanded reveal
// only for pillars with a wired callback; row tap just expands.
// ---------------------------------------------------------------------------

void deepLinkTests() {
  testWidgets('deep-link: See details invokes the wired callback', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(_v4Section(onPillarTap: {'evidence': () => tapped++})),
    );

    // Collapsed: the reveal (and its link) is faded out — not tappable.
    expect(find.text('See details →').hitTestable(), findsNothing);

    // Expanding the row must NOT fire the deep-link callback.
    await tester.tap(find.text('Evidence'));
    await tester.pumpAndSettle();
    expect(tapped, 0);

    // Only the wired pillar renders a tappable link.
    expect(find.text('See details →').hitTestable(), findsOneWidget);
    await tester.tap(find.text('See details →').hitTestable());
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('deep-link: unwired pillars render no link (no dead links)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_v4Section(onPillarTap: {'evidence': () {}})),
    );

    await tester.tap(find.text('Dose'));
    await tester.pumpAndSettle();
    // The expanded Dose reveal has no link; the only link in the tree is
    // the (collapsed, opacity-0) Evidence one, which is not tappable.
    expect(find.text('See details →').hitTestable(), findsNothing);
  });
}
