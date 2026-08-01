// Widget tests for PGTimingGuidanceCard.
//
// The card draws per-bottle guidance. It must never present a clock time or a
// daypart, never state when a prescribed medication is taken, never render an
// ingredient as if it were a bottle, and never write filler when it has nothing
// to say.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_timing_guidance_card.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';

Future<void> _pump(WidgetTester tester, TimingGuidance guidance) {
  return tester.pumpWidget(
    MaterialApp(
      theme: V2Theme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PGTimingGuidanceCard(guidance: guidance),
        ),
      ),
    ),
  );
}

TimingOptimization _optimization({
  String ruleId = 'rule',
  required TimingRelation relation,
  TimingCategory category = TimingCategory.howToTake,
  String advice = 'Take with a meal.',
  bool involvesMedication = false,
}) {
  return TimingOptimization(
    ruleId: ruleId,
    ingredient1: 'vitamin d',
    advice: advice,
    relation: relation,
    category: category,
    actionability: TimingActionability.recommended,
    evidenceLevel: EvidenceLevel.established,
    sourceAuthority: SourceAuthority.fdaLabel,
    scoreImpact: -1,
    involvesMedication: involvesMedication,
  );
}

ProductTimingGuidance _product({
  String stackEntryId = 'row-1',
  String productName = 'D3 5000 IU',
  List<TimingOptimization> importantSeparation = const [],
  List<TimingOptimization> howToTake = const [],
  List<TimingOptimization> optional = const [],
}) {
  return ProductTimingGuidance(
    stackEntryId: stackEntryId,
    productName: productName,
    importantSeparation: importantSeparation,
    howToTake: howToTake,
    optional: optional,
  );
}

void main() {
  testWidgets('renders guidance under the bottle name, not the nutrient', (
    tester,
  ) async {
    await _pump(
      tester,
      TimingGuidance(
        products: [
          _product(
            productName: 'Nordic Naturals Ultimate Omega',
            howToTake: [
              _optimization(
                relation: const TimingRelation(
                  type: TimingRelationType.withFood,
                ),
                advice: 'Take with a meal containing fat.',
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Nordic Naturals Ultimate Omega'), findsOneWidget);
    expect(find.text('Take with a meal containing fat.'), findsOneWidget);
    // The nutrient behind the rule is never a row of its own.
    expect(find.text('vitamin d'), findsNothing);
  });

  testWidgets('never presents a clock time or a daypart', (tester) async {
    await _pump(
      tester,
      TimingGuidance(
        products: [
          _product(
            importantSeparation: [
              _optimization(
                ruleId: 'sep',
                relation: const TimingRelation(
                  type: TimingRelationType.separateFrom,
                  minimumHours: 4,
                ),
                category: TimingCategory.importantSeparation,
                advice: 'Keep these at least 4 hours apart.',
              ),
            ],
            howToTake: [
              _optimization(
                ruleId: 'sleep',
                relation: const TimingRelation(
                  type: TimingRelationType.beforeEvent,
                  event: TimingEvent.intendedSleep,
                  minimumMinutes: 30,
                  maximumMinutes: 60,
                ),
                advice: 'Take 30 to 60 minutes before your target bedtime.',
              ),
            ],
          ),
        ],
      ),
    );

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');

    // "bedtime" survives only inside the pipeline's authored sentence, which
    // is relative to the user's own target. No app-generated daypart label may
    // appear.
    for (final label in [
      'With breakfast',
      'With dinner',
      'Before bed',
      'Morning, before food',
    ]) {
      expect(rendered, isNot(contains(label)));
    }
    expect(rendered, isNot(matches(RegExp(r'\d{1,2}:\d{2}'))));
    expect(rendered, isNot(contains('PM')));
    expect(rendered, isNot(contains('AM')));
  });

  testWidgets('scopes medication guidance to the prescription', (tester) async {
    await _pump(
      tester,
      TimingGuidance(
        products: [
          _product(
            productName: 'Calcium K/D',
            importantSeparation: [
              _optimization(
                relation: const TimingRelation(
                  type: TimingRelationType.separateFrom,
                  minimumHours: 4,
                ),
                category: TimingCategory.importantSeparation,
                advice:
                    'Keep calcium at least 4 hours away from levothyroxine.',
                involvesMedication: true,
              ),
            ],
          ),
        ],
      ),
    );

    expect(
      find.text('Continue taking your medication exactly as prescribed.'),
      findsOneWidget,
    );
  });

  testWidgets('groups sections by category', (tester) async {
    await _pump(
      tester,
      TimingGuidance(
        products: [
          _product(
            importantSeparation: [
              _optimization(
                ruleId: 'a',
                relation: const TimingRelation(
                  type: TimingRelationType.separateFrom,
                  minimumHours: 2,
                ),
                category: TimingCategory.importantSeparation,
                advice: 'Keep these apart.',
              ),
            ],
            howToTake: [
              _optimization(
                ruleId: 'b',
                relation: const TimingRelation(
                  type: TimingRelationType.withFood,
                ),
                advice: 'Take with food.',
              ),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Important'), findsOneWidget);
    expect(find.text('How to take it'), findsOneWidget);
    expect(find.text('Optional'), findsNothing);
  });

  testWidgets('says nothing found once for the stack, not per product', (
    tester,
  ) async {
    await _pump(tester, const TimingGuidance());

    expect(
      find.text(
        'No important timing findings identified for the products '
        'successfully assessed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('stays silent when the check could not finish', (tester) async {
    await _pump(
      tester,
      const TimingGuidance(
        issues: [AnalysisUnavailable(reason: 'artifact incompatible')],
      ),
    );

    // An incomplete check must never read as a clean result, and the card has
    // no honest sentence to offer here — the unavailable state belongs to the
    // stack safety banner.
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('writes no filler for a product with nothing to say', (
    tester,
  ) async {
    await _pump(tester, TimingGuidance(products: [_product()]));

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    for (final filler in [
      'Follow the product label',
      'Ask your doctor',
      'Take consistently',
    ]) {
      expect(rendered, isNot(contains(filler)));
    }
  });

  test('stack screen composes exactly one timing surface', () {
    final source = File(
      'lib/features/stack/v2/stack_v2_screen.dart',
    ).readAsStringSync();

    expect(source, contains('const _TimingGuidanceSlot()'));
    // The deleted scheduler must not come back through a stale reference.
    expect(source, isNot(contains('_TimingPlanSlot')));
    expect(source, isNot(contains('PGDailyPlanCard')));
    expect(source, isNot(contains('DailySlot')));
  });
}
