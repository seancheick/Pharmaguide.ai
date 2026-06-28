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
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

void main() {
  Future<void> pumpBanner(
    WidgetTester tester, {
    required StackSafetyReport report,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StackSafetyBanner(report: report, onTap: onTap),
        ),
      ),
    );
  }

  InteractionResult makeInteraction({
    required Severity severity,
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
  }) {
    return NutrientStatus(
      total: NutrientTotal(
        canonicalId: canonicalId,
        displayName: displayName,
        totalAmount: 5000,
        unit: 'IU',
        contributions: const <NutrientContribution>[],
      ),
      tier: tier,
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
    'nutrient exceeds UL → title uses display name, body hints overage',
    (tester) async {
      final report = StackSafetyReport(
        nutrientStatuses: [
          makeNutrientStatus(
            tier: NutrientTier.exceedsUl,
            displayName: 'Vitamin D',
          ),
        ],
      );
      await pumpBanner(tester, report: report);

      final banner = tester.widget<PGSeverityBanner>(
        find.byType(PGSeverityBanner),
      );
      // exceedsUl maps to Severity.avoid → danger tone
      expect(banner.tone, PGBannerTone.danger);
      expect(banner.title, contains('Vitamin D'));
      expect(banner.body, contains('exceeds upper limit'));
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

  testWidgets('onTap supplied → "View details" action appears and fires', (
    tester,
  ) async {
    var tapCount = 0;
    final report = StackSafetyReport(
      medicationInteractions: [makeInteraction(severity: Severity.avoid)],
    );
    await pumpBanner(tester, report: report, onTap: () => tapCount++);

    expect(find.text('View details'), findsOneWidget);
    await tester.tap(find.text('View details'));
    await tester.pump();
    expect(tapCount, 1);
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
}
