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
  'Testing & Brand',
  'Safety Hygiene',
];

void main() {
  nativeScaleTests();
  namedActionTests();
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
// Named pillar actions — the three navigable pillars (evidence, verification,
// transparency) render a named action inside their expanded reveal when a
// destination callback is wired. Formulation, Dose, and Safety Hygiene are
// explained in place and NEVER render an action (no dead scroll links), even
// when a callback is supplied for them. Replaces the retired "See details →"
// deep link and the removed "Biggest opportunity" gap line.
// ---------------------------------------------------------------------------

void namedActionTests() {
  testWidgets('named action: a wired eligible pillar renders its action and '
      'invokes the callback only when expanded', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(_v4Section(onPillarTap: {'evidence': () => tapped++})),
    );

    // Collapsed: the action is not in the tree.
    expect(find.text('View clinical evidence'), findsNothing);

    // Expanding the row must NOT fire the action.
    await tester.tap(find.text('Evidence'));
    await tester.pumpAndSettle();
    expect(tapped, 0);

    // The wired eligible pillar renders its named action, which fires on tap.
    expect(find.text('View clinical evidence'), findsOneWidget);
    await tester.tap(find.text('View clinical evidence'));
    expect(tapped, 1);
  });

  testWidgets('named action: Formulation and Dose never render an action, even '
      'when a callback is supplied (no dead scroll links)', (tester) async {
    await tester.pumpWidget(
      _wrap(_v4Section(onPillarTap: {'formulation': () {}, 'dose': () {}})),
    );

    await tester.tap(find.text('Formulation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('View '), findsNothing);

    // Single-open accordion: tapping Dose collapses Formulation, opens Dose.
    await tester.tap(find.text('Dose'));
    await tester.pumpAndSettle();
    expect(find.textContaining('View '), findsNothing);
  });
}
