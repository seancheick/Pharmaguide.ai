// v4 widget tests for the ScoreBreakdown section adapter.
//
//   * v4: a blob with `quality_pillars_v4` renders the SIX v4 pillars and
//     suppresses the stale v3 four-section labels.
//   * missing/malformed v4 map → unavailable state, never stale v3 math.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/evidence_section.dart';
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
  'Formula & quality checks',
];

void main() {
  nativeScaleTests();
  namedActionTests();
  evidenceScopeReconciliationTests();
  testWidgets('v4: renders the six pillars from quality_pillars_v4', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          heroScore: 95,
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

  testWidgets(
    'category cap renders as an explicit adjustment after pre-cap pillars',
    (tester) async {
      final pillars = _v4Pillars();
      pillars['safety_hygiene'] = {
        'score': 9.0,
        'max': 10,
        'reason': 'No banned additives.',
        'components': {'score_before_public_cap': 10.0},
      };

      await tester.pumpWidget(
        _wrap(
          buildScoreBreakdownSection(
            heroScore: 94,
            qualityPillarsV4: pillars,
            qualityScoreCapV4: const {
              'applied': true,
              'score_before_cap': 95.0,
              'score_after_cap': 94.0,
            },
          ),
        ),
      );

      expect(find.text('Pillar subtotal'), findsOneWidget);
      expect(find.text('95/100'), findsOneWidget);
      expect(find.text('Category calibration'), findsOneWidget);
      expect(find.text('−1'), findsOneWidget);
      expect(find.text('Final score'), findsOneWidget);
      expect(find.text('94/100'), findsOneWidget);
    },
  );

  testWidgets('category cap is hidden when pillars cannot reproduce it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          heroScore: 94,
          qualityPillarsV4: _v4Pillars(),
          qualityScoreCapV4: const {
            'applied': true,
            'score_before_cap': 99.0,
            'score_after_cap': 94.0,
          },
        ),
      ),
    );

    expect(find.text('Category calibration'), findsNothing);
    expect(find.text('Pillar subtotal'), findsNothing);
  });

  testWidgets('no quality_pillars_v4 suppresses the optional score section', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(buildScoreBreakdownSection(heroScore: 80, qualityPillarsV4: null)),
    );

    expect(find.byType(PGScoreBreakdownCard), findsNothing);
    expect(find.text('Ingredient Quality'), findsNothing);
    expect(find.text('Safety & Purity'), findsNothing);
    expect(find.text('Evidence & Research'), findsNothing);
    expect(find.text('Transparency & Verification'), findsNothing);
    expect(find.text('How PG Score works'), findsNothing);
    expect(find.text('How scoring works'), findsNothing);
    for (final label in _v4Labels) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('malformed quality_pillars_v4 suppresses the score section', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(
          heroScore: 70,
          qualityPillarsV4: const {'garbage': 'not a pillar map'},
        ),
      ),
    );

    expect(find.byType(PGScoreBreakdownCard), findsNothing);
    expect(find.text('Ingredient Quality'), findsNothing);
    expect(find.text('Formulation'), findsNothing);
  });

  testWidgets('SHIP RULE: partial blob (4/6 pillars) is suppressed — '
      'never a partial native-scale sum under the hero', (tester) async {
    final partial = _v4Pillars();
    partial.remove('verification');
    partial.remove('safety_hygiene');

    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(heroScore: 98.1, qualityPillarsV4: partial),
      ),
    );

    // No maintenance state and no partial sum contradicting the hero.
    expect(find.byType(PGScoreBreakdownCard), findsNothing);
    expect(find.text('Score breakdown unavailable'), findsNothing);
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

  testWidgets('consumer total matches the rounded hero score', (tester) async {
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
    // Pillars retain their useful decimal precision, while the consumer total
    // uses the same whole-number presentation as the hero.
    expect(find.text('= 94/100'), findsOneWidget);
    expect(find.text('= 93.5/100'), findsNothing);
    expect(find.text('= 93.4/100'), findsNothing);
  });
}

void evidenceScopeReconciliationTests() {
  testWidgets('limited formula evidence and strong Vitamin D ingredient evidence '
      'render together without changing the formula score', (tester) async {
    final pillars = _v4Pillars();
    pillars['evidence'] = {
      'score': 6.8,
      'max': 20,
      'reason': 'Limited human evidence for these ingredients.',
    };

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            buildScoreBreakdownSection(
              heroScore: 84.4,
              qualityPillarsV4: pillars,
            ),
            buildEvidenceSection(
              evidenceData: const {
                'match_count': 1,
                'clinical_matches': [
                  {
                    'ingredient': 'Vitamin D3',
                    'evidence_level': 'ingredient-human',
                    'study_type': 'systematic_review_meta',
                    'effect_direction': 'positive_strong',
                    'references_structured': [
                      {'pmid': '30293909', 'title': 'Vitamin D review'},
                      {'pmid': '28202713', 'title': 'Vitamin D meta-analysis'},
                    ],
                  },
                ],
              },
            ),
          ],
        ),
      ),
    );

    expect(find.text('6.8/20'), findsOneWidget);
    expect(
      find.text('Ingredient evidence: STRONG · 2 studies · meta-analysis'),
      findsOneWidget,
    );
    expect(
      find.text('Vitamin D3: strong ingredient evidence · 2 human studies'),
      findsOneWidget,
    );
    expect(find.textContaining('Product evidence: STRONG'), findsNothing);

    await tester.tap(find.text('Evidence'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Formula-wide evidence reflects the full ingredient profile, not one strongly supported ingredient. Limited human evidence for these ingredients.',
      ),
      findsOneWidget,
    );
    expect(find.text('Analysis metadata'), findsNothing);
    expect(find.textContaining('analysis coverage'), findsNothing);
    expect(find.textContaining('matched evidence record'), findsNothing);
  });

  testWidgets('exact-product evidence is claimed only for product-human data', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        buildEvidenceSection(
          evidenceData: const {
            'match_count': 1,
            'clinical_matches': [
              {
                'ingredient': 'Studied Product',
                'evidence_level': 'product-human',
                'references_structured': [
                  {'pmid': '12345', 'title': 'Finished product trial'},
                ],
              },
            ],
          },
        ),
      ),
    );

    expect(
      find.text('Exact-product evidence: identified in this evidence record.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Exact-product evidence: identified in this evidence record.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _wrap(
        buildEvidenceSection(
          evidenceData: const {
            'match_count': 1,
            'clinical_matches': [
              {
                'ingredient': 'Vitamin D3',
                'evidence_level': 'ingredient-human',
                'references_structured': [
                  {'pmid': '67890', 'title': 'Ingredient trial'},
                ],
              },
            ],
          },
        ),
      ),
    );

    expect(find.textContaining('Exact-product evidence:'), findsNothing);
    expect(find.textContaining('Product evidence:'), findsNothing);
  });

  testWidgets(
    'ranked ingredient evidence does not hide a mixed product-human match',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          buildEvidenceSection(
            evidenceData: const {
              'match_count': 2,
              'clinical_matches': [
                {
                  'ingredient': 'Finished Product',
                  'evidence_level': 'product-human',
                  'effect_direction': 'mixed',
                  'references_structured': [
                    {'pmid': '111', 'title': 'Finished product study'},
                  ],
                },
                {
                  'ingredient': 'Vitamin D3',
                  'evidence_level': 'ingredient-human',
                  'study_type': 'systematic_review_meta',
                  'effect_direction': 'positive_strong',
                  'references_structured': [
                    {'pmid': '222', 'title': 'Vitamin D review'},
                    {'pmid': '333', 'title': 'Vitamin D meta-analysis'},
                  ],
                },
              ],
            },
          ),
        ),
      );

      expect(
        find.text('Ingredient evidence: STRONG · 2 studies · meta-analysis'),
        findsOneWidget,
      );
      expect(
        find.text('Vitamin D3: strong ingredient evidence · 2 human studies'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Exact-product evidence: 1 human study identified in this evidence record; results may be mixed.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Exact-product evidence: 1 human study identified in this evidence record; results may be mixed\.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Product evidence: STRONG'), findsNothing);
      expect(find.textContaining('· 3 studies'), findsNothing);
    },
  );

  testWidgets(
    'a product-human record downgraded to ingredient scope never claims '
    'exact-product evidence',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          buildEvidenceSection(
            evidenceData: const {
              'match_count': 1,
              'clinical_matches': [
                {
                  'ingredient': 'Vitamin D3',
                  'evidence_level': 'product-human',
                  'ui_evidence_scope': 'ingredient',
                  'effect_direction': 'positive_strong',
                  'references_structured': [
                    {'pmid': '444', 'title': 'Ingredient-scoped review'},
                  ],
                },
              ],
            },
          ),
        ),
      );

      expect(
        find.text('Ingredient evidence: STRONG · 1 study'),
        findsOneWidget,
      );
      expect(find.textContaining('Exact-product evidence:'), findsNothing);
      expect(find.textContaining('Product evidence:'), findsNothing);
    },
  );

  testWidgets(
    'same-tier product and ingredient studies keep separate scoped counts',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          buildEvidenceSection(
            evidenceData: const {
              'match_count': 2,
              'clinical_matches': [
                {
                  'ingredient': 'Finished Product',
                  'evidence_level': 'product-human',
                  'effect_direction': 'positive_strong',
                  'references_structured': [
                    {'pmid': '555', 'title': 'Finished product trial'},
                  ],
                },
                {
                  'ingredient': 'Vitamin D3',
                  'evidence_level': 'ingredient-human',
                  'study_type': 'systematic_review_meta',
                  'effect_direction': 'positive_strong',
                  'references_structured': [
                    {'pmid': '666', 'title': 'Vitamin D review'},
                    {'pmid': '777', 'title': 'Vitamin D meta-analysis'},
                  ],
                },
              ],
            },
          ),
        ),
      );

      expect(find.text('Product evidence: STRONG · 1 study'), findsOneWidget);
      expect(
        find.textContaining(
          'Vitamin D3: strong ingredient evidence · 2 human studies',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Product evidence: STRONG · 3'), findsNothing);
      expect(
        find.textContaining(
          'Product evidence: STRONG · 1 study · meta-analysis',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('score semantics exclude internal coverage diagnostics', (
    tester,
  ) async {
    final pillars = _v4Pillars();
    pillars['evidence'] = {
      'score': 6.8,
      'max': 20,
      'reason': 'Limited formula evidence.',
    };

    await tester.pumpWidget(
      _wrap(
        buildScoreBreakdownSection(heroScore: 80, qualityPillarsV4: pillars),
      ),
    );

    await tester.tap(find.text('Evidence'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp(r'Evidence.*6\.8/20')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'coverage')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'mapped')), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'matched evidence')), findsNothing);
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
  heroScore: heroScore,
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
      _wrap(buildScoreBreakdownSection(heroScore: 73, qualityPillarsV4: null)),
    );

    expect(find.byType(PGScoreBreakdownCard), findsNothing);
    expect(find.text('Score breakdown unavailable'), findsNothing);
    expect(find.text('8/10'), findsNothing);
    expect(find.text('10/10'), findsNothing);
    expect(find.text('5/10'), findsNothing);
    expect(find.textContaining('= '), findsNothing);
    expect(find.text('Tap any pillar to see what drives it.'), findsNothing);
  });
}

// ---------------------------------------------------------------------------
// Named pillar actions — evidence and verification render a named action when
// a real destination callback is wired. Transparency is already represented by
// the visible label ledger; Formulation, Dose, and Formula & quality checks are explained
// in place and never render an action. Replaces dead/redundant deep links.
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
