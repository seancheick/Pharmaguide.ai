import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';

void main() {
  Widget buildTestWidget({
    double? formulation,
    double? dose,
    double? evidence,
    double? transparency,
    double? verification,
    double? safetyHygiene,
    double? heroScore,
    double? mappedCoverage,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: buildScoreBreakdownSection(
          ingredientQuality: 99,
          safetyPurity: 99,
          evidenceResearch: 99,
          brandTrust: 99,
          heroScore: heroScore,
          mappedCoverage: mappedCoverage,
          qualityPillarsV4: _v4Pillars(
            formulation: formulation,
            dose: dose,
            evidence: evidence,
            transparency: transparency,
            verification: verification,
            safetyHygiene: safetyHygiene,
          ),
        ),
      ),
    );
  }

  group('Score breakdown section', () {
    testWidgets('header reads "Why this scored {N}" when heroScore present', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(heroScore: 84));

      expect(find.text('Why this scored 84'), findsOneWidget);
      expect(find.text('Product Analysis'), findsNothing);
    });

    testWidgets('header omits the number when heroScore is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Why this scored'), findsOneWidget);
    });

    testWidgets('renders locked pillar labels in order', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Formulation'), findsOneWidget);
      expect(find.text('Dose'), findsOneWidget);
      expect(find.text('Evidence'), findsOneWidget);
      expect(find.text('Transparency'), findsOneWidget);
      expect(find.text('Testing & Brand'), findsOneWidget);
      expect(find.text('Safety Hygiene'), findsOneWidget);
      expect(find.text('Brand trust'), findsNothing);
    });

    testWidgets('renders each v4 pillar on its native score/max scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          formulation: 17.6,
          dose: 16,
          evidence: 18.9,
          transparency: 12.5,
          verification: 13,
          safetyHygiene: 9.3,
        ),
      );

      expect(find.text('17.6/20'), findsOneWidget);
      expect(find.text('16/20'), findsOneWidget);
      expect(find.text('18.9/20'), findsOneWidget);
      expect(find.text('12.5/15'), findsOneWidget);
      expect(find.text('13/15'), findsOneWidget);
      expect(find.text('9.3/10'), findsOneWidget);
      expect(find.text('8/10'), findsNothing);
    });

    testWidgets('shows "No data" for null pillar scores', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('No data'), findsNWidgets(6));
    });

    testWidgets(
      'reveals the pipeline reason but not synthesized badges when tapped',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(verification: 13));

        await tester.tap(find.text('Testing & Brand'));
        await tester.pumpAndSettle();

        expect(
          find.text('Independent testing and brand signals'),
          findsOneWidget,
        );
        expect(find.text('Third-party tested'), findsNothing);
      },
    );

    testWidgets('coverage 0.92 shows percentage and high-confidence copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.92));

      expect(find.text('92%'), findsOneWidget);
      expect(find.textContaining('high-confidence'), findsOneWidget);
    });

    testWidgets('coverage 0.5 shows percentage and partial-coverage copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.5));

      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('partial coverage'), findsOneWidget);
    });

    testWidgets('coverage 0.15 shows percentage and limited-data copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.15));

      expect(find.text('15%'), findsOneWidget);
      expect(find.textContaining('Limited data'), findsOneWidget);
    });

    testWidgets('coverage clamps out-of-range values to 100%', (tester) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 1.5));

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('150%'), findsNothing);
    });

    testWidgets('coverage line hidden when mappedCoverage is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(formulation: 20));

      expect(find.textContaining('database'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets(
      'passes pipeline facts and only named eligible actions to the card',
      (tester) async {
        var evidenceActions = 0;
        final pillars = _v4Pillars(evidence: 12, formulation: 13.9);
        (pillars['evidence'] as Map<String, dynamic>)['explanation'] = {
          'schema_version': 1,
          'facts': [
            {
              'id': 'human_trials',
              'label': 'Human trials',
              'value_display': 'Limited',
            },
          ],
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: buildScoreBreakdownSection(
                ingredientQuality: null,
                safetyPurity: null,
                evidenceResearch: null,
                brandTrust: null,
                heroScore: 63.6,
                mappedCoverage: null,
                qualityPillarsV4: pillars,
                onPillarTap: {
                  'formulation': () {},
                  'evidence': () => evidenceActions++,
                },
              ),
            ),
          ),
        );

        expect(find.text("How it's scored"), findsOneWidget);
        await tester.tap(find.text('Evidence'));
        await tester.pumpAndSettle();
        expect(find.text('Human trials'), findsOneWidget);
        expect(find.text('View clinical evidence'), findsOneWidget);

        await tester.tap(find.text('View clinical evidence'));
        expect(evidenceActions, 1);

        await tester.tap(find.text('Formulation'));
        await tester.pumpAndSettle();
        expect(find.text('View clinical evidence'), findsNothing);
        expect(find.textContaining('See details'), findsNothing);
      },
    );
  });

  group('Score explanation card', () {
    testWidgets('keeps all pillar details collapsed until the user opens one', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHarness());

      expect(find.text('Form selection supports absorption.'), findsNothing);
      expect(find.text('EPA + DHA per day'), findsNothing);

      await tester.tap(find.text('Formulation'));
      await tester.pumpAndSettle();

      expect(find.text('Form selection supports absorption.'), findsOneWidget);
      expect(find.text('EPA + DHA per day'), findsOneWidget);
      expect(find.text('660 mg/day'), findsOneWidget);
      expect(find.text('Mixed'), findsNWidgets(2));
    });

    testWidgets('opening a pillar closes the previously open pillar', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHarness());

      await tester.tap(find.text('Formulation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dose'));
      await tester.pumpAndSettle();

      expect(find.text('Form selection supports absorption.'), findsNothing);
      expect(find.text('Dose is below the studied range.'), findsOneWidget);
    });

    testWidgets('renders the named action after reason and pipeline facts', (
      tester,
    ) async {
      var actionCount = 0;
      await tester.pumpWidget(_cardHarness(onAction: () => actionCount++));

      await tester.tap(find.text('Evidence'));
      await tester.pumpAndSettle();

      final reason = tester.getTopLeft(
        find.text('Clinical support is limited.'),
      );
      final fact = tester.getTopLeft(find.text('Human trials'));
      final action = tester.getTopLeft(find.text('View clinical evidence'));
      expect(reason.dy, lessThan(fact.dy));
      expect(fact.dy, lessThan(action.dy));

      await tester.tap(find.text('View clinical evidence'));
      expect(actionCount, 1);
    });

    testWidgets('has a header action and no generic score rationale', (
      tester,
    ) async {
      var helpCount = 0;
      await tester.pumpWidget(
        _cardHarness(onHowScoringWorks: () => helpCount++),
      );

      expect(find.text("How it's scored"), findsOneWidget);
      expect(find.textContaining('Biggest opportunity'), findsNothing);
      expect(find.textContaining('See details'), findsNothing);

      await tester.tap(find.text("How it's scored"));
      expect(helpCount, 1);
    });

    testWidgets('score number is tinted with its scoring-tier color', (
      tester,
    ) async {
      await tester.pumpWidget(_cardHarness()); // heroScore: 63.6 → fair tier
      final richText = tester.widget<RichText>(
        find
            .byWidgetPredicate(
              (w) =>
                  w is RichText &&
                  w.text.toPlainText().startsWith('Why this scored'),
            )
            .first,
      );
      Color? numberColor;
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == '63.6') numberColor = span.style?.color;
          span.children?.forEach(visit);
        }
      }

      visit(richText.text);
      expect(numberColor, tierForScore(64).color);
    });

    testWidgets('shows every exact-zero reason inline without duplicating it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Formulation',
            score: 0,
            reason: 'No supported forms were identified.',
            facts: const [
              V4PillarFact(
                id: 'supported_forms',
                label: 'Supported forms',
                valueDisplay: 'None',
              ),
            ],
          ),
          _pillar(
            label: 'Dose',
            score: 0,
            reason: 'No studied dose was matched.',
          ),
          _pillar(label: 'Evidence', score: 0, reason: '   '),
        ]),
      );

      expect(find.text('No supported forms were identified.'), findsOneWidget);
      expect(find.text('No studied dose was matched.'), findsOneWidget);
      expect(find.text('   '), findsNothing);
      expect(find.text('No points'), findsNWidgets(3));
      expect(find.text('Supported forms'), findsOneWidget);
    });

    testWidgets('does not substitute compatibility copy for a zero reason', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Formulation',
            score: 0,
            microExplanation: 'Locally generated fallback.',
            facts: const [
              V4PillarFact(
                id: 'form_fact',
                label: 'Form fact',
                valueDisplay: 'Missing',
              ),
            ],
          ),
        ]),
      );

      expect(find.text('Locally generated fallback.'), findsNothing);
      expect(find.text('Form fact'), findsOneWidget);
    });

    testWidgets('initially opens only the first eligible exact-zero pillar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Formulation',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'form_fact',
                label: 'Form fact',
                valueDisplay: 'First',
              ),
            ],
          ),
          _pillar(
            label: 'Dose',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'dose_fact',
                label: 'Dose fact',
                valueDisplay: 'Second',
              ),
            ],
          ),
        ]),
      );

      expect(find.text('Form fact'), findsOneWidget);
      expect(find.text('Dose fact'), findsNothing);
    });

    testWidgets('a wired action alone makes an exact-zero pillar eligible', (
      tester,
    ) async {
      var actionCount = 0;
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Evidence',
            score: 0,
            actionLabel: 'View clinical evidence',
            onAction: () => actionCount++,
          ),
        ]),
      );

      expect(find.text('View clinical evidence'), findsOneWidget);
      await tester.tap(find.text('View clinical evidence'));
      expect(actionCount, 1);
    });

    testWidgets('an action label without a callback is not eligible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Evidence',
            score: 0,
            actionLabel: 'View clinical evidence',
          ),
          _pillar(
            label: 'Transparency',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'label_disclosure',
                label: 'Pipeline fact',
                valueDisplay: 'Missing',
              ),
            ],
          ),
        ]),
      );

      expect(find.text('View clinical evidence'), findsNothing);
      expect(find.text('Pipeline fact'), findsOneWidget);
    });

    testWidgets('ui-only facts do not trigger initial expansion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Evidence',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'ui_evidence_scope',
                label: 'Evidence scope',
                valueDisplay: 'Formula-wide',
              ),
            ],
          ),
        ]),
      );

      expect(find.text('Evidence scope'), findsNothing);

      await tester.tap(find.text('Evidence'));
      await tester.pumpAndSettle();
      expect(find.text('Evidence scope'), findsOneWidget);
    });

    testWidgets('skips ineligible zero pillars before a pipeline-fact zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Evidence',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'ui_evidence_scope',
                label: 'UI-only fact',
                valueDisplay: 'Display context',
              ),
            ],
          ),
          _pillar(
            label: 'Transparency',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'label_disclosure',
                label: 'Pipeline fact',
                valueDisplay: 'Missing',
              ),
            ],
          ),
        ]),
      );

      expect(find.text('UI-only fact'), findsNothing);
      expect(find.text('Pipeline fact'), findsOneWidget);
    });

    testWidgets('manual collapse survives rebuilds with the same signature', (
      tester,
    ) async {
      List<PGPillar> pillars() => [
        _pillar(
          label: 'Formulation',
          score: 0,
          facts: const [
            V4PillarFact(
              id: 'form_fact',
              label: 'Form fact',
              valueDisplay: 'Missing',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(_cardWithPillars(pillars()));
      expect(find.text('Form fact'), findsOneWidget);

      await tester.tap(find.text('Formulation'));
      await tester.pumpAndSettle();
      expect(find.text('Form fact'), findsNothing);

      await tester.pumpWidget(_cardWithPillars(pillars()));
      await tester.pumpAndSettle();
      expect(find.text('Form fact'), findsNothing);
    });

    testWidgets('a changed pillar identity-score signature resets expansion', (
      tester,
    ) async {
      List<PGPillar> pillars({required int max}) => [
        _pillar(
          label: 'Formulation',
          score: 0,
          max: max,
          facts: const [
            V4PillarFact(
              id: 'form_fact',
              label: 'Form fact',
              valueDisplay: 'Missing',
            ),
          ],
        ),
      ];

      await tester.pumpWidget(_cardWithPillars(pillars(max: 20)));
      await tester.tap(find.text('Formulation'));
      await tester.pumpAndSettle();
      expect(find.text('Form fact'), findsNothing);

      await tester.pumpWidget(_cardWithPillars(pillars(max: 15)));
      await tester.pumpAndSettle();
      expect(find.text('Form fact'), findsOneWidget);
    });

    testWidgets('opening another row closes the initially expanded zero row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Formulation',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'form_fact',
                label: 'Form fact',
                valueDisplay: 'Missing',
              ),
            ],
          ),
          _pillar(
            label: 'Dose',
            score: 0,
            facts: const [
              V4PillarFact(
                id: 'dose_fact',
                label: 'Dose fact',
                valueDisplay: 'Missing',
              ),
            ],
          ),
        ]),
      );

      await tester.tap(find.text('Dose'));
      await tester.pumpAndSettle();

      expect(find.text('Form fact'), findsNothing);
      expect(find.text('Dose fact'), findsOneWidget);
    });

    testWidgets('zero-row semantics expose score, reason, status, and state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Formulation',
            score: 0,
            reason: 'No supported forms were identified.',
            facts: const [
              V4PillarFact(
                id: 'form_fact',
                label: 'Form fact',
                valueDisplay: 'Missing',
              ),
            ],
          ),
        ]),
      );

      final row = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Formulation. 0/20. No points. '
                    'No supported forms were identified.',
      );
      var rowNode = tester.getSemantics(row);
      expect(
        rowNode.label,
        'Formulation. 0/20. No points. No supported forms were identified.',
      );
      expect(rowNode.flagsCollection.isButton, isTrue);
      expect(rowNode.flagsCollection.isExpanded, ui.Tristate.isTrue);
      expect(
        rowNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.text('Formulation'));
      await tester.pumpAndSettle();
      rowNode = tester.getSemantics(row);
      expect(rowNode.flagsCollection.isExpanded, ui.Tristate.isFalse);
      semantics.dispose();
    });

    testWidgets('nonzero pillars never auto-expand', (tester) async {
      await tester.pumpWidget(
        _cardWithPillars([
          _pillar(
            label: 'Formulation',
            score: 0.1,
            facts: const [
              V4PillarFact(
                id: 'form_fact',
                label: 'Nonzero fact',
                valueDisplay: 'Present',
              ),
            ],
          ),
        ]),
      );

      expect(find.text('Nonzero fact'), findsNothing);
    });
  });
}

Widget _cardWithPillars(List<PGPillar> pillars) {
  return MaterialApp(
    home: Scaffold(body: PGScoreBreakdownCard(pillars: pillars)),
  );
}

PGPillar _pillar({
  required String label,
  required double score,
  int max = 20,
  String? reason,
  List<V4PillarFact> facts = const [],
  String? actionLabel,
  VoidCallback? onAction,
  String? microExplanation,
}) {
  return PGPillar(
    label: label,
    max: max,
    score: score,
    reason: reason,
    facts: facts,
    actionLabel: actionLabel,
    onAction: onAction,
    // ignore: deprecated_member_use_from_same_package
    microExplanation: microExplanation,
  );
}

Widget _cardHarness({VoidCallback? onAction, VoidCallback? onHowScoringWorks}) {
  return MaterialApp(
    home: Scaffold(
      body: PGScoreBreakdownCard(
        heroScore: 63.6,
        onHowScoringWorks: onHowScoringWorks,
        pillars: [
          const PGPillar(
            label: 'Formulation',
            max: 20,
            score: 13.9,
            reason: 'Form selection supports absorption.',
            facts: [
              V4PillarFact(
                id: 'epa_dha_per_day',
                label: 'EPA + DHA per day',
                valueDisplay: '660 mg/day',
              ),
            ],
          ),
          const PGPillar(
            label: 'Dose',
            max: 20,
            score: 8.7,
            reason: 'Dose is below the studied range.',
          ),
          PGPillar(
            label: 'Evidence',
            max: 20,
            score: 12,
            reason: 'Clinical support is limited.',
            facts: const [
              V4PillarFact(
                id: 'human_trials',
                label: 'Human trials',
                valueDisplay: 'Limited',
              ),
            ],
            actionLabel: 'View clinical evidence',
            onAction: onAction,
          ),
        ],
      ),
    ),
  );
}

Map<String, dynamic> _v4Pillars({
  double? formulation,
  double? dose,
  double? evidence,
  double? transparency,
  double? verification,
  double? safetyHygiene,
}) {
  return {
    'formulation': {
      'score': formulation,
      'max': 20,
      'reason': 'Form, dosage, and bioavailability',
    },
    'dose': {
      'score': dose,
      'max': 20,
      'reason': 'Serving strength and studied ranges',
    },
    'evidence': {
      'score': evidence,
      'max': 20,
      'reason': 'Clinical support behind ingredients',
    },
    'transparency': {
      'score': transparency,
      'max': 15,
      'reason': 'Label clarity and disclosure',
    },
    'verification': {
      'score': verification,
      'max': 15,
      'reason': 'Independent testing and brand signals',
    },
    'safety_hygiene': {
      'score': safetyHygiene,
      'max': 10,
      'reason': 'Clean-label and contaminant risk checks',
    },
  };
}
