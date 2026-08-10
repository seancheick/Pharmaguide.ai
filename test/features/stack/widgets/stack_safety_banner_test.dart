// Widget tests for [StackSafetyBanner].
//
// The banner is a pure StatelessWidget that renders a pre-built
// [StackSafetyReport] — no providers, no DB, no async. Tests construct
// synthetic reports and assert tone / title / body / action wiring for
// every branch in the widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/features/stack/widgets/stack_safety_banner.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required StackSafetyReport report,
    VoidCallback? onTap,
  }) async {
    final snapshot = const StackIntelligenceEngine().summarizeFromReports(
      stackSize: 1,
      safetyReport: report,
      recalledReport: RecalledIngredientsReport.empty(),
      synergyReport: SynergyReport.empty(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StackSafetyBanner(snapshot: snapshot, onTap: onTap),
        ),
      ),
    );
  }

  InteractionResult makeInteraction({
    required Severity severity,
    Severity? curated,
    String id = 'i1',
    InteractionType type = InteractionType.drugSupplement,
    String agent1 = 'Warfarin',
    String agent2 = 'Fish Oil',
    String mechanism = 'Additive antiplatelet effect.',
    String management = 'Monitor INR closely.',
    String? alertStyle,
  }) {
    return InteractionResult(
      id: id,
      type: type,
      severity: severity,
      evidenceLevel: EvidenceLevel.established,
      agent1Name: agent1,
      agent2Name: agent2,
      mechanism: mechanism,
      management: management,
      alertStyle: alertStyle,
      curatedSeverity: curated,
      doseDependant: false,
      doseThreshold: null,
      sourceUrls: const <String>[],
      source: InteractionSource.pipeline,
    );
  }

  NutrientStatus makeNutrientStatus({
    required NutrientTier tier,
    String canonicalId = 'vit_d',
    String displayName = 'Vitamin D',
    double totalAmount = 5000,
    String unit = 'IU',
    double? ul,
    double? pctOfUl,
    List<NutrientContribution> contributions = const <NutrientContribution>[],
    bool ulIsFallback = false,
  }) {
    return NutrientStatus(
      total: NutrientTotal(
        canonicalId: canonicalId,
        displayName: displayName,
        totalAmount: totalAmount,
        unit: unit,
        contributions: contributions,
      ),
      tier: tier,
      ul: ul,
      pctOfUl: pctOfUl,
      ulIsFallback: ulIsFallback,
    );
  }

  MedicationProfileWarning makeProfileWarning({
    Severity severity = Severity.caution,
  }) {
    return MedicationProfileWarning(
      id: 'MCR_PREGNANCY_NSAIDS:Motrin',
      ruleId: 'MCR_PREGNANCY_NSAIDS',
      medicationName: 'Motrin',
      severity: severity,
      evidenceLevel: EvidenceLevel.established,
      headline: 'Review NSAID use in pregnancy',
      body:
          'NSAIDs such as ibuprofen are generally avoided from 20 weeks '
          'of pregnancy.',
      management: 'Check with your OB/clinician before using NSAIDs.',
      sourceUrls: const <String>[],
    );
  }

  testWidgets('empty report renders nothing', (tester) async {
    await pumpBanner(tester, report: const StackSafetyReport());
    expect(find.byKey(const Key('stack-safety-banner')), findsNothing);
    expect(find.byType(PGSeverityBanner), findsNothing);
  });

  testWidgets('avoid-severity medication interaction → danger tone', (
    tester,
  ) async {
    final report = StackSafetyReport(
      medicationInteractions: [makeInteraction(severity: Severity.avoid)],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.tone, PGBannerTone.danger);
    // 2026-04-30 — softer-tone vocab. "AVOID" → "Not recommended"
    // (severity.dart). "Avoid" word is reserved for contraindicated.
    expect(banner.title, contains('Not recommended'));
    expect(banner.title, contains('Warfarin'));
    expect(banner.title, contains('Fish Oil'));
    expect(banner.body, contains('Monitor INR'));
  });

  testWidgets(
    'a finding plus an incomplete check labels the result as partial',
    (tester) async {
      final report = StackSafetyReport(
        medicationInteractions: [makeInteraction(severity: Severity.avoid)],
        checksIncomplete: true,
      );
      await pumpBanner(tester, report: report);

      final banner = tester.widget<PGSeverityBanner>(
        find.byType(PGSeverityBanner),
      );
      expect(banner.body, contains('results may be incomplete'));
      expect(banner.body, contains('Monitor INR'));
    },
  );

  testWidgets(
    'a finding plus incomplete label coverage labels the result as partial',
    (tester) async {
      final report = StackSafetyReport(
        stackInteractions: [makeInteraction(severity: Severity.caution)],
        coverageIncomplete: true,
      );
      await pumpBanner(tester, report: report);

      final banner = tester.widget<PGSeverityBanner>(
        find.byType(PGSeverityBanner),
      );
      expect(banner.body, contains('results may be incomplete'));
      expect(banner.body, contains('Monitor INR'));
    },
  );

  testWidgets(
    'contraindicated severity → danger tone with "Do not use" label',
    (tester) async {
      final report = StackSafetyReport(
        stackInteractions: [
          makeInteraction(
            severity: Severity.contraindicated,
            agent1: 'St. John\'s Wort',
            agent2: 'SSRI',
            management: 'Do not combine — risk of serotonin syndrome.',
          ),
        ],
      );
      await pumpBanner(tester, report: report);

      final banner = tester.widget<PGSeverityBanner>(
        find.byType(PGSeverityBanner),
      );
      expect(banner.tone, PGBannerTone.danger);
      // 2026-04-30 — softer-tone vocab (severity.dart): contraindicated
      // is now "Do not use" (was "BLOCK — Do Not Use").
      expect(banner.title, contains('Do not use'));
      expect(banner.body, contains('serotonin syndrome'));
    },
  );

  testWidgets('caution-only report → caution tone', (tester) async {
    final report = StackSafetyReport(
      stackInteractions: [
        makeInteraction(
          severity: Severity.caution,
          agent1: 'Calcium',
          agent2: 'Iron',
          management: 'Space doses 2 hours apart.',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.tone, PGBannerTone.caution);
    // 2026-04-30 — softer-tone vocab (severity.dart).
    expect(banner.title, contains('Use caution'));
    expect(banner.body, contains('Space doses'));
  });

  testWidgets('monitor-only report → caution tone', (tester) async {
    final report = StackSafetyReport(
      categoryWarnings: [
        makeInteraction(
          severity: Severity.monitor,
          management: 'Watch for mild side effects.',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.tone, PGBannerTone.caution);
    // 2026-04-30 — softer-tone vocab (severity.dart).
    expect(banner.title, contains('Monitor'));
  });

  testWidgets('medication-profile warning renders type-aware copy', (
    tester,
  ) async {
    final report = StackSafetyReport(
      medicationProfileWarnings: [makeProfileWarning()],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.tone, PGBannerTone.caution);
    expect(banner.title, 'Use caution — Motrin');
    expect(banner.body, contains('generally avoided from 20 weeks'));
    expect(banner.body, contains('Strong Evidence'));
  });

  testWidgets('food advisory note uses info tone and food-note title', (
    tester,
  ) async {
    final report = StackSafetyReport(
      medicationInteractions: [
        makeInteraction(
          severity: Severity.informational,
          agent1: 'Levothyroxine',
          agent2: 'Coffee',
          management: 'Take levothyroxine with water and wait before coffee.',
          alertStyle: 'food_advisory_note',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.tone, PGBannerTone.info);
    expect(banner.title, 'Food note — Levothyroxine × Coffee');
    expect(banner.body, contains('wait before coffee'));
  });

  testWidgets(
    'nutrient exceeds UL → factual upper-limit alert with products and basis',
    (tester) async {
      final report = StackSafetyReport(
        nutrientStatuses: [
          makeNutrientStatus(
            tier: NutrientTier.exceedsUl,
            displayName: 'Vitamin D',
            totalAmount: 125,
            unit: 'mcg',
            ul: 100,
            pctOfUl: 125,
            contributions: const [
              NutrientContribution(
                stackEntryId: 'one',
                productName: 'O.N.E.',
                amount: 50,
                unit: 'mcg',
              ),
              NutrientContribution(
                stackEntryId: 'calcium-k-d',
                productName: 'Calcium K/D',
                amount: 75,
                unit: 'mcg',
              ),
            ],
          ),
        ],
      );
      await pumpBanner(tester, report: report);

      final banner = tester.widget<PGSeverityBanner>(
        find.byType(PGSeverityBanner),
      );
      expect(banner.tone, PGBannerTone.caution);
      // Renamed 2026-08-07: state the finding, don't name the concept first.
      expect(banner.title, 'Vitamin D above upper limit');
      expect(banner.body, contains('125 mcg/day'));
      expect(banner.body, contains('125% of the 100 mcg upper limit'));
      expect(banner.body, contains('O.N.E. (50 mcg/day)'));
      expect(banner.body, contains('Calcium K/D (75 mcg/day)'));
      expect(banner.body, contains('Dietary intake is not included'));
    },
  );

  testWidgets('nutrient approaching UL → caution tone with "near" hint', (
    tester,
  ) async {
    final report = StackSafetyReport(
      nutrientStatuses: [
        makeNutrientStatus(
          tier: NutrientTier.approachingUl,
          displayName: 'Zinc',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    // approachingUl maps to Severity.caution → caution tone
    expect(banner.tone, PGBannerTone.caution);
    expect(banner.title, contains('Zinc'));
    expect(banner.body, contains('near its upper limit'));
  });

  testWidgets('multiple signals → body includes "+N more" suffix', (
    tester,
  ) async {
    final report = StackSafetyReport(
      medicationInteractions: [makeInteraction(severity: Severity.avoid)],
      stackInteractions: [
        makeInteraction(
          id: 'i2',
          severity: Severity.caution,
          agent1: 'Calcium',
          agent2: 'Iron',
        ),
        makeInteraction(
          id: 'i3',
          severity: Severity.monitor,
          agent1: 'Vitamin C',
          agent2: 'Copper',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.tone, PGBannerTone.danger);
    // Top-severity is the medication interaction (avoid > caution > monitor)
    // 2026-04-30 — softer-tone vocab (severity.dart).
    expect(banner.title, contains('Not recommended'));
    expect(banner.body, contains('2 more signals'));
  });

  testWidgets('exactly one extra signal → singular "1 more signal"', (
    tester,
  ) async {
    final report = StackSafetyReport(
      stackInteractions: [
        makeInteraction(severity: Severity.avoid),
        makeInteraction(
          id: 'i2',
          severity: Severity.caution,
          agent1: 'Calcium',
          agent2: 'Iron',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.body, contains('1 more signal'));
    expect(banner.body, isNot(contains('1 more signals')));
  });

  testWidgets('onTap null → no action label rendered', (tester) async {
    final report = StackSafetyReport(
      medicationInteractions: [makeInteraction(severity: Severity.avoid)],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.actionLabel, isNull);
    expect(banner.onAction, isNull);
    expect(find.text('View details'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Interactive overview card. A headline-only card beneath a header counting
  // three findings reads as "there is one issue" — these tests pin the fix.
  // ---------------------------------------------------------------------------

  testWidgets('onTap supplied → single signal shows a "Review details" action '
      'that fires', (tester) async {
    var tapCount = 0;
    final report = StackSafetyReport(
      medicationInteractions: [makeInteraction(severity: Severity.avoid)],
    );
    await pumpBanner(tester, report: report, onTap: () => tapCount++);

    // No PGSeverityBanner: the interactive form lays out its own rows.
    expect(find.byType(PGSeverityBanner), findsNothing);
    expect(find.byKey(const Key('stack-safety-banner')), findsOneWidget);
    expect(find.text('Warfarin × Fish Oil'), findsOneWidget);
    expect(
      find.text('Supplement interaction · Strong Evidence'),
      findsOneWidget,
    );
    // Long clinical copy stays in the sheet.
    expect(find.textContaining('Monitor INR'), findsNothing);
    // "Review all 1" would be nonsense.
    expect(find.text('Review details'), findsOneWidget);

    await tester.tap(find.text('Review details'));
    await tester.pump();
    expect(tapCount, 1);
  });

  testWidgets(
    'interactive card previews EVERY finding, not just the headline',
    (tester) async {
      final report = StackSafetyReport(
        medicationInteractions: [
          makeInteraction(
            id: 'warfarin',
            severity: Severity.avoid,
            agent1: 'Warfarin',
            agent2: 'O.N.E. Multivitamin',
          ),
          makeInteraction(
            id: 'metformin',
            severity: Severity.avoid,
            agent1: 'Metformin',
            agent2: 'O.N.E. Multivitamin',
          ),
        ],
        nutrientStatuses: [
          makeNutrientStatus(
            tier: NutrientTier.exceedsUl,
            ul: 4000,
            pctOfUl: 125,
          ),
        ],
      );
      await pumpBanner(tester, report: report, onTap: () {});

      expect(find.text('Warfarin × O.N.E. Multivitamin'), findsOneWidget);
      expect(find.text('Metformin × O.N.E. Multivitamin'), findsOneWidget);
      expect(find.text('Vitamin D above upper limit'), findsOneWidget);
      // Each finding carries its OWN metadata…
      expect(
        find.text('Supplement interaction · Strong Evidence'),
        findsNWidgets(2),
      );
      expect(find.text('Nutrient upper limit'), findsOneWidget);
      // …and the stack-wide count lives only in the action, never fused onto a
      // single finding's metadata line (that mismatch is what this card fixes).
      expect(find.textContaining('3 safety signals to review'), findsNothing);
      expect(find.text('Review all 3'), findsOneWidget);
    },
  );

  testWidgets('preview beyond three findings states the truncation', (
    tester,
  ) async {
    final report = StackSafetyReport(
      medicationInteractions: [
        for (var i = 0; i < 5; i++)
          makeInteraction(
            id: 'i$i',
            severity: Severity.avoid,
            agent1: 'Drug$i',
            agent2: 'Supplement$i',
          ),
      ],
    );
    await pumpBanner(tester, report: report, onTap: () {});

    expect(find.text('Drug0 × Supplement0'), findsOneWidget);
    expect(find.text('Drug2 × Supplement2'), findsOneWidget);
    expect(find.text('Drug3 × Supplement3'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);
    expect(find.text('Review all 5'), findsOneWidget);
  });

  testWidgets('a good_to_know note is never listed under "Needs attention"', (
    tester,
  ) async {
    final report = StackSafetyReport(
      medicationInteractions: [
        makeInteraction(
          id: 'fa',
          severity: Severity.informational,
          curated: Severity.avoid,
          agent1: 'Grapefruit',
          agent2: 'Atorvastatin',
          alertStyle: 'food_advisory_note',
        ),
      ],
      stackInteractions: [
        makeInteraction(
          id: 'concern',
          severity: Severity.caution,
          agent1: 'Iron',
          agent2: 'Calcium',
        ),
      ],
    );
    await pumpBanner(tester, report: report, onTap: () {});

    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('Iron × Calcium'), findsOneWidget);
    // The advisory is a real signal — counted and reachable — but it belongs to
    // the other group, so it is deferred to the sheet rather than mislabelled.
    expect(find.text('Grapefruit × Atorvastatin'), findsNothing);
    expect(find.text('+1 more'), findsOneWidget);
    expect(find.text('Review all 2'), findsOneWidget);
  });

  testWidgets('interactive card keeps the incomplete-analysis hedge', (
    tester,
  ) async {
    final report = StackSafetyReport(
      medicationInteractions: [makeInteraction(severity: Severity.avoid)],
      checksIncomplete: true,
    );
    await pumpBanner(tester, report: report, onTap: () {});

    expect(
      find.textContaining('results may be incomplete'),
      findsOneWidget,
      reason: 'an unfinished check must never read as an exhaustive list',
    );
  });

  testWidgets('falls back to mechanism when management is empty', (
    tester,
  ) async {
    final report = StackSafetyReport(
      stackInteractions: [
        makeInteraction(
          severity: Severity.avoid,
          mechanism: 'CYP3A4 enzyme inhibition pathway.',
          management: '   ',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    expect(banner.body, contains('CYP3A4'));
  });

  testWidgets(
    'medication interactions outrank stack interactions at same severity',
    (tester) async {
      final report = StackSafetyReport(
        stackInteractions: [
          makeInteraction(
            id: 'stack-1',
            severity: Severity.avoid,
            agent1: 'Supp A',
            agent2: 'Supp B',
            management: 'supp-level management',
          ),
        ],
        medicationInteractions: [
          makeInteraction(
            id: 'med-1',
            severity: Severity.avoid,
            agent1: 'Drug X',
            agent2: 'Supp Y',
            management: 'med-level management',
          ),
        ],
      );
      await pumpBanner(tester, report: report);

      final banner = tester.widget<PGSeverityBanner>(
        find.byType(PGSeverityBanner),
      );
      // Medication bucket comes first at the same severity.
      expect(banner.title, contains('Drug X'));
      expect(banner.title, contains('Supp Y'));
      expect(banner.body, contains('med-level'));
    },
  );

  testWidgets('sub-warn nutrient statuses are ignored by the banner', (
    tester,
  ) async {
    // A stack with only `adequate` / `abundant` nutrient statuses (neither
    // triggers shouldWarn) is treated as empty — the banner collapses.
    final report = StackSafetyReport(
      nutrientStatuses: [
        makeNutrientStatus(tier: NutrientTier.adequate),
        makeNutrientStatus(
          tier: NutrientTier.abundant,
          canonicalId: 'vit_c',
          displayName: 'Vitamin C',
        ),
      ],
    );
    await pumpBanner(tester, report: report);
    expect(find.byType(PGSeverityBanner), findsNothing);
  });

  testWidgets('food advisory never becomes the headline over a real concern '
      '(disposition-first), even at higher underlying severity', (
    tester,
  ) async {
    final report = StackSafetyReport(
      // Displays informational, truly avoid — but placed as good_to_know.
      medicationInteractions: [
        makeInteraction(
          id: 'fa',
          severity: Severity.informational,
          curated: Severity.avoid,
          agent1: 'Grapefruit',
          agent2: 'Atorvastatin',
          alertStyle: 'food_advisory_note',
        ),
      ],
      // A real, actionable concern.
      stackInteractions: [
        makeInteraction(
          id: 'concern',
          severity: Severity.caution,
          agent1: 'Iron',
          agent2: 'Calcium',
          management: 'Space doses apart.',
        ),
      ],
    );
    await pumpBanner(tester, report: report);

    final banner = tester.widget<PGSeverityBanner>(
      find.byType(PGSeverityBanner),
    );
    // The caution concern is the headline; the food advisory's higher
    // underlying severity does NOT hijack the banner tone or title.
    expect(banner.tone, PGBannerTone.caution);
    expect(banner.title, contains('Iron'));
    expect(banner.title, contains('Calcium'));
    expect(banner.title, isNot(contains('Grapefruit')));
    expect(banner.body, contains('Space doses'));
    expect(banner.body, contains('1 more signal'));
  });
}
