import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_timing_advice_card.dart';

void main() {
  testWidgets('PGTimingAdviceCard lays out inside a scrollable stack list', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PGTimingAdviceCard(
                  optimizations: [
                    TimingOptimization(
                      ruleId: 'timing_magnesium_food',
                      ingredient1: 'magnesium',
                      ingredient2: '',
                      advice: 'Take magnesium with a meal',
                      ruleType: TimingRuleType.takeWithFood,
                      scoreImpact: 0,
                      evidenceLevel: EvidenceLevel.theoretical,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Timing guidance'), findsOneWidget);
    expect(
      find.text(
        'When to take items in your stack for better spacing or absorption.',
      ),
      findsOneWidget,
    );
    expect(find.text('Take magnesium with a meal'), findsOneWidget);
  });

  testWidgets('time-of-day advice is shown inline instead of check details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_magnesium_evening',
                  ingredient1: 'magnesium',
                  ingredient2: 'sleep',
                  advice:
                      'Take magnesium in the evening — it supports muscle '
                      'relaxation and sleep quality.',
                  mechanism:
                      'Evening dosing is a practical recommendation based on '
                      'limited sleep-quality evidence.',
                  ruleType: TimingRuleType.timeOfDay,
                  scoreImpact: 0,
                  evidenceLevel: EvidenceLevel.theoretical,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Best time for'), findsNothing);
    expect(find.textContaining('check details'), findsNothing);
    expect(
      find.textContaining('Take magnesium in the evening'),
      findsOneWidget,
    );
    // Mechanism excerpt is folded into the detail sheet — not shown inline,
    // to keep the stack list compact (title only).
    expect(
      find.textContaining('Evening dosing is a practical recommendation'),
      findsNothing,
    );
  });

  testWidgets('separation advice keeps hours visible; mechanism folds to detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_iron_magnesium_separate',
                  ingredient1: 'iron',
                  ingredient2: 'magnesium',
                  advice:
                      'Take iron and magnesium at least 2 hours apart — '
                      'magnesium can reduce non-heme iron absorption.',
                  mechanism:
                      'Magnesium at high supplemental doses may interfere '
                      'with non-heme iron absorption.',
                  ruleType: TimingRuleType.separate,
                  separationHours: 2,
                  scoreImpact: -1,
                  evidenceLevel: EvidenceLevel.theoretical,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Take iron and magnesium'), findsOneWidget);
    // The actionable separation window stays inline...
    expect(find.textContaining('Keep at least 2h apart'), findsOneWidget);
    // ...but the explanatory mechanism is folded into the detail sheet.
    expect(
      find.textContaining('Magnesium at high supplemental doses'),
      findsNothing,
    );
  });

  testWidgets('separation rules render under a "Space these apart" subsection', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_iron_calcium_separate',
                  ingredient1: 'iron',
                  ingredient2: 'calcium',
                  advice: 'Take iron and calcium at least 2 hours apart.',
                  ruleType: TimingRuleType.separate,
                  separationHours: 2,
                  scoreImpact: -2,
                  evidenceLevel: EvidenceLevel.established,
                ),
                TimingOptimization(
                  ruleId: 'timing_magnesium_food',
                  ingredient1: 'magnesium',
                  ingredient2: '',
                  advice: 'Take magnesium with a meal',
                  ruleType: TimingRuleType.takeWithFood,
                  scoreImpact: 0,
                  evidenceLevel: EvidenceLevel.theoretical,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Separations get their own labeled subsection header (eyebrow is caps)...
    expect(find.byKey(const Key('timing-separations-header')), findsOneWidget);
    expect(find.text('SPACE THESE APART'), findsOneWidget);
    // ...and both the separation row and the non-separation row still render.
    expect(find.textContaining('iron and calcium'), findsOneWidget);
    expect(find.textContaining('Take magnesium with a meal'), findsOneWidget);
  });

  testWidgets('no separations → no "Space these apart" header', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_magnesium_food',
                  ingredient1: 'magnesium',
                  ingredient2: '',
                  advice: 'Take magnesium with a meal',
                  ruleType: TimingRuleType.takeWithFood,
                  scoreImpact: 0,
                  evidenceLevel: EvidenceLevel.theoretical,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('timing-separations-header')), findsNothing);
    expect(find.text('Take magnesium with a meal'), findsOneWidget);
  });

  testWidgets('visible rows preserve engine priority order', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              maxVisible: 2,
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_vitamin_k_warfarin',
                  ingredient1: 'vitamin k',
                  ingredient2: 'warfarin',
                  advice: 'Maintain a consistent daily intake of vitamin K.',
                  ruleType: TimingRuleType.takeWithFood,
                  scoreImpact: -2,
                  evidenceLevel: EvidenceLevel.established,
                ),
                TimingOptimization(
                  ruleId: 'timing_iron_calcium',
                  ingredient1: 'iron',
                  ingredient2: 'calcium',
                  advice: 'Take iron and calcium at least 2 hours apart.',
                  ruleType: TimingRuleType.separate,
                  separationHours: 2,
                  scoreImpact: -2,
                  evidenceLevel: EvidenceLevel.established,
                ),
                TimingOptimization(
                  ruleId: 'timing_iron_magnesium',
                  ingredient1: 'iron',
                  ingredient2: 'magnesium',
                  advice: 'Take iron and magnesium at least 2 hours apart.',
                  ruleType: TimingRuleType.separate,
                  separationHours: 2,
                  scoreImpact: -1,
                  evidenceLevel: EvidenceLevel.theoretical,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('consistent daily intake'), findsOneWidget);
    expect(find.textContaining('iron and calcium'), findsOneWidget);
    expect(find.textContaining('iron and magnesium'), findsNothing);
  });

  testWidgets('tapping a tip opens a detail sheet with mechanism + sources', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_iron_calcium_separate',
                  ingredient1: 'iron',
                  ingredient2: 'calcium',
                  advice: 'Take iron and calcium at least 2 hours apart.',
                  mechanism: 'Calcium transiently blocks iron transfer.',
                  ruleType: TimingRuleType.separate,
                  separationHours: 2,
                  scoreImpact: -2,
                  evidenceLevel: EvidenceLevel.established,
                  sourceUrls: ['https://pubmed.ncbi.nlm.nih.gov/1899425/'],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Sheet content is not in the tree until the row is tapped.
    expect(find.text('Why this matters'), findsNothing);

    await tester.tap(find.textContaining('Take iron and calcium'));
    await tester.pumpAndSettle();

    expect(find.text('Why this matters'), findsOneWidget);
    // Mechanism lives only in the detail sheet now (folded out of the row).
    expect(
      find.textContaining('Calcium transiently blocks iron transfer'),
      findsOneWidget,
    );
    expect(find.text('Sources'), findsOneWidget);
    expect(find.textContaining('PubMed'), findsOneWidget);
  });
}
