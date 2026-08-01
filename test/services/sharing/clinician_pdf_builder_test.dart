import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/sharing/clinician_pdf_builder.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

UserStacksLocalData _stack({
  required String id,
  required String name,
  required String type,
  String? dosage,
  String? frequency,
}) {
  final ts = DateTime.utc(2026, 5, 28, 12);
  return UserStacksLocalData(
    id: id,
    type: type,
    name: name,
    dsldId: null,
    rxcui: null,
    ingredientKeys: null,
    drugClassesCol: null,
    genericRxcui: null,
    ingredientRxcuisCol: null,
    dosage: dosage,
    frequency: frequency,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: null,
  );
}

UserProfile _profile() {
  final ts = DateTime.utc(2026, 5, 28, 12);
  return UserProfile(
    id: 1,
    nickname: null,
    ageBracket: '35-44',
    sex: 'female',
    goals: '["sleep","heart_health"]',
    conditions: '["hypertension"]',
    drugClasses: '["ace_inhibitors"]',
    allergens: '["soy"]',
    profileFlags: '[]',
    createdAt: ts,
    lastUpdated: ts,
  );
}

const _intelligence = StackIntelligence(
  tier: StackTier.decent,
  stackSize: 3,
  issues: [
    StackIssue(
      severity: Severity.caution,
      headline: 'Calcium may affect medication timing',
    ),
  ],
  interactionCount: 1,
  nutrientWarningCount: 1,
  hasRecalledIngredient: false,
  hasContraindicatedInteraction: false,
  hasBannedIngredient: false,
  qualityScore: 72,
);

StackSafetyReport _safetyReport() {
  return const StackSafetyReport(
    nutrientStatuses: [
      NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_d',
          displayName: 'Vitamin D',
          totalAmount: 5000,
          unit: 'IU',
          contributions: [
            NutrientContribution(
              stackEntryId: 'supp-1',
              productName: 'Vitamin D3',
              amount: 5000,
              unit: 'IU',
            ),
          ],
        ),
        tier: NutrientTier.approachingUl,
        rda: 600,
        ul: 4000,
        pctOfRda: 833.3,
        pctOfUl: 125,
        warning: 'Above the upper limit for many adults.',
      ),
    ],
    timingOptimizations: [
      TimingOptimization(
        ruleId: 'timing_calcium_lisinopril',
        ingredient1: 'Calcium',
        ingredient2: 'Lisinopril',
        advice:
            'Separate calcium and this medication unless your clinician says otherwise.',
        ruleType: TimingRuleType.separate,
        separationHours: 2,
        scoreImpact: -2,
        evidenceLevel: EvidenceLevel.probable,
      ),
    ],
  );
}

const _depletions = [
  DepletionMatch(
    depletionId: 'metformin_b12',
    drugDisplayName: 'Metformin',
    drugClassId: 'biguanides',
    nutrientName: 'Vitamin B12',
    nutrientCanonicalId: 'vitamin_b12',
    severity: 'moderate',
    mechanism: 'May reduce absorption over long-term use.',
    recommendation: 'Discuss B12 monitoring with a clinician.',
    evidenceLevel: 'established',
    sourceUrls: [
      'https://www.gov.uk/drug-safety-update/metformin-and-vitamin-b12',
    ],
    alertHeadline: 'Metformin may lower B12 over time',
    monitoringTipShort:
        'Ask whether B12 monitoring makes sense for your care plan.',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'builds a branded clinician PDF with metadata and embedded assets',
    () async {
      final logo = await rootBundle.load('assets/images/report_logo.png');
      final regularFont = await rootBundle.load(
        'assets/fonts/Geist-Regular.ttf',
      );
      final mediumFont = await rootBundle.load('assets/fonts/Geist-Medium.ttf');

      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: _profile(),
        stack: [
          _stack(
            id: 'med-1',
            name: 'Lisinopril',
            type: 'medication',
            dosage: '10 mg',
            frequency: 'daily',
          ),
          _stack(
            id: 'supp-1',
            name: 'Vitamin D3',
            type: 'supplement',
            dosage: '5000 IU',
            frequency: 'daily',
          ),
          _stack(
            id: 'supp-2',
            name: 'Calcium Citrate',
            type: 'supplement',
            dosage: '500 mg',
            frequency: 'daily',
          ),
        ],
        intelligence: _intelligence,
        safetyReport: _safetyReport(),
        depletions: _depletions,
        generatedAt: DateTime.utc(2026, 5, 28, 16, 30),
        logoBytes: logo.buffer.asUint8List(),
        regularFontBytes: regularFont.buffer.asUint8List(),
        mediumFontBytes: mediumFont.buffer.asUint8List(),
      );

      expect(bytes.take(5), orderedEquals('%PDF-'.codeUnits));
      expect(bytes.length, greaterThan(100000));

      final body = latin1.decode(bytes, allowInvalid: true);
      final requiredTokens = [
        'PharmaGuide',
        'Medication',
        'Supplement',
        'Review',
        'Patient-generated',
        'summary',
      ];
      final missing = requiredTokens
          .where((token) => !body.contains(token))
          .toList(growable: false);
      expect(missing, isEmpty);
    },
  );

  test('renders patient profile IDs as clinician-friendly labels', () async {
    final ts = DateTime.utc(2026, 7, 28);
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: UserProfile(
        id: 1,
        ageBracket: '31-50',
        sex: 'Female',
        goals: '["GOAL_SLEEP_QUALITY","GOAL_CARDIOVASCULAR_HEART_HEALTH"]',
        conditions: '["ttc","high_cholesterol"]',
        drugClasses: '["anticoagulants"]',
        allergens: '["ALLERGEN_SOY"]',
        profileFlags: '[]',
        createdAt: ts,
        lastUpdated: ts,
      ),
      stack: const [],
      intelligence: const StackIntelligence(
        tier: StackTier.incomplete,
        stackSize: 0,
        issues: [],
        interactionCount: 0,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
      ),
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      conditionLabels: const {
        'ttc': 'Trying to Conceive',
        'high_cholesterol': 'High Cholesterol',
      },
      generatedAt: ts,
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('Trying'));
    expect(body, contains('Conceive'));
    expect(body, contains('High'));
    expect(body, contains('Cholesterol'));
    expect(body, contains('Blood'));
    expect(body, contains('thinners'));
    expect(body, contains('Sleep'));
    expect(body, contains('Quality'));
    expect(body, contains('Cardiovascular/Heart'));
    expect(body, contains('Health'));
    expect(body, contains('Soy'));
    expect(body, isNot(contains('high_cholesterol')));
    expect(body, isNot(contains('GOAL_SLEEP_QUALITY')));
    expect(body, isNot(contains('ALLERGEN_SOY')));
  });

  test(
    'renders warnings in severity order even if input issues are unsorted',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.unsafe,
          stackSize: 2,
          issues: [
            StackIssue(
              severity: Severity.caution,
              headline: 'Alpha caution issue',
            ),
            StackIssue(
              severity: Severity.contraindicated,
              headline: 'Omega contraindicated issue',
            ),
          ],
          interactionCount: 2,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: true,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 5, 28),
      );

      final body = latin1.decode(bytes, allowInvalid: true);
      final contraindicatedIndex = body.indexOf('Omega');
      final cautionIndex = body.indexOf('Alpha');

      expect(contraindicatedIndex, isNonNegative);
      expect(cautionIndex, isNonNegative);
      expect(contraindicatedIndex, lessThan(cautionIndex));
    },
  );

  test('renders clinician context for curated interaction warnings', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: const StackIntelligence(
        tier: StackTier.concerning,
        stackSize: 2,
        issues: [
          StackIssue(
            severity: Severity.avoid,
            headline: 'Levothyroxine and iron need separation',
          ),
        ],
        interactionCount: 1,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
      ),
      safetyReport: const StackSafetyReport(
        medicationInteractions: [
          InteractionResult(
            id: 'levothyroxine_iron',
            type: InteractionType.drugSupplement,
            severity: Severity.avoid,
            evidenceLevel: EvidenceLevel.established,
            agent1Name: 'Levothyroxine',
            agent2Name: 'Iron',
            mechanism: 'Iron can reduce levothyroxine absorption.',
            management: 'Separate administration by at least four hours.',
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: ['https://dailymed.nlm.nih.gov/dailymed/example'],
            source: InteractionSource.pipeline,
          ),
        ],
      ),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 5, 28),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('Evidence:'));
    expect(body, contains('Established'));
    expect(body, isNot(contains('Strong Evidence')));
    expect(body, contains('Mechanism:'));
    expect(body, contains('reduce'));
    expect(body, contains('Management:'));
    expect(body, contains('Separate'));
    expect(body, contains('dailymed.nlm.nih.gov'));
  });

  test(
    'preserves recall warnings when rich safety signals are also present',
    () async {
      const recallHeadline =
          'WARNING — Example Product is subject to a recall involving lead.';
      const interactionMechanism = 'Iron can reduce levothyroxine absorption.';
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.unsafe,
          stackSize: 2,
          issues: [
            StackIssue(
              severity: Severity.contraindicated,
              headline: recallHeadline,
            ),
            StackIssue(
              severity: Severity.avoid,
              headline: interactionMechanism,
            ),
          ],
          interactionCount: 1,
          nutrientWarningCount: 0,
          hasRecalledIngredient: true,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(
          medicationInteractions: [
            InteractionResult(
              id: 'levothyroxine_iron',
              type: InteractionType.drugSupplement,
              severity: Severity.avoid,
              evidenceLevel: EvidenceLevel.established,
              agent1Name: 'Levothyroxine',
              agent2Name: 'Iron',
              mechanism: interactionMechanism,
              management: 'Separate administration by at least four hours.',
              doseDependant: false,
              doseThreshold: null,
              sourceUrls: [],
              source: InteractionSource.pipeline,
            ),
          ],
        ),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 5, 28),
      );

      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('Example'));
      expect(body, contains('Product'));
      expect(body, contains('recall'));
      expect(body, contains('Evidence:'));
      expect(body, contains('Mechanism:'));
    },
  );

  test('renders nutrient percentages as target, not RDA', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(
        nutrientStatuses: [
          NutrientStatus(
            total: NutrientTotal(
              canonicalId: 'vitamin_k',
              displayName: 'Vitamin K',
              totalAmount: 390,
              unit: 'mcg',
              contributions: [],
            ),
            tier: NutrientTier.aboveAdequateNoUl,
            rda: 120,
            pctOfRda: 325,
          ),
        ],
      ),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 5, 28),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('325%'));
    expect(body, contains('target'));
    expect(body, isNot(contains('325% RDA')));
  });

  test('does not expose the internal stack quality score', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 5, 28),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, isNot(contains('Stack quality score')));
    expect(body, isNot(contains('72/100')));
  });

  test(
    'medication-pair warnings appear in PDF before medication-supplement warnings',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.unsafe,
          stackSize: 2,
          issues: [
            StackIssue(
              severity: Severity.avoid,
              headline: 'Lisinopril / Losartan dual ACE-ARB risk',
            ),
            StackIssue(
              severity: Severity.avoid,
              headline: 'Calcium may reduce medication absorption',
            ),
          ],
          interactionCount: 2,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(
          medicationPairInteractions: [
            InteractionResult(
              id: 'mp-1',
              type: InteractionType.drugDrug,
              severity: Severity.avoid,
              evidenceLevel: EvidenceLevel.established,
              agent1Name: 'Lisinopril',
              agent2Name: 'Losartan',
              mechanism: 'Dual RAAS blockade',
              management: 'Review with prescriber',
              doseDependant: false,
              doseThreshold: null,
              sourceUrls: [],
              source: InteractionSource.pipeline,
            ),
          ],
          medicationInteractions: [
            InteractionResult(
              id: 'mi-1',
              type: InteractionType.drugSupplement,
              severity: Severity.avoid,
              evidenceLevel: EvidenceLevel.probable,
              agent1Name: 'Calcium',
              agent2Name: 'Lisinopril',
              mechanism: 'Reduced absorption',
              management: 'Separate by 2 hours',
              doseDependant: false,
              doseThreshold: null,
              sourceUrls: [],
              source: InteractionSource.pipeline,
            ),
          ],
        ),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 5, 28),
      );

      final body = latin1.decode(bytes, allowInvalid: true);

      // Both warnings should appear in the PDF
      expect(body, contains('Lisinopril'));
      expect(body, contains('Losartan'));
      expect(body, contains('Calcium'));

      // Medication-pair (drug-drug) should appear before med-supp
      // in orderedWarnings — verify via the safety report directly
      const report = StackSafetyReport(
        medicationPairInteractions: [
          InteractionResult(
            id: 'mp-1',
            type: InteractionType.drugDrug,
            severity: Severity.avoid,
            evidenceLevel: EvidenceLevel.established,
            agent1Name: 'Lisinopril',
            agent2Name: 'Losartan',
            mechanism: 'Dual RAAS blockade',
            management: 'Review with prescriber',
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: [],
            source: InteractionSource.pipeline,
          ),
        ],
        medicationInteractions: [
          InteractionResult(
            id: 'mi-1',
            type: InteractionType.drugSupplement,
            severity: Severity.avoid,
            evidenceLevel: EvidenceLevel.probable,
            agent1Name: 'Calcium',
            agent2Name: 'Lisinopril',
            mechanism: 'Reduced absorption',
            management: 'Separate by 2 hours',
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: [],
            source: InteractionSource.pipeline,
          ),
        ],
      );
      final ordered = orderedSignalsFrom(report);
      expect(ordered, hasLength(2));
      expect((ordered[0].payload as InteractionPayload).result.id, 'mp-1');
      expect((ordered[1].payload as InteractionPayload).result.id, 'mi-1');
    },
  );

  test('builds when profile is null and stack is empty', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: const StackIntelligence(
        tier: StackTier.incomplete,
        stackSize: 0,
        issues: [],
        interactionCount: 0,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
      ),
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 5, 28),
    );

    expect(bytes.take(5), orderedEquals('%PDF-'.codeUnits));
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('No'));
    expect(body, contains('warnings'));
  });

  test(
    'states that safety checks did not complete instead of an all-clear',
    () async {
      // Regression: `checksIncomplete` means a safety subsystem failed, so an
      // empty warning list means "not checked", not "nothing found". The app
      // hedges on this flag (stack_safety_details_sheet); the clinician PDF
      // must not print a clean snapshot the app itself refuses to assert.
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.incomplete,
          stackSize: 0,
          issues: [],
          interactionCount: 0,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(checksIncomplete: true),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 5, 28),
      );

      // Words are emitted as separate PDF text operators, so assert on single
      // tokens rather than phrases.
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, isNot(contains('snapshot.')));
      expect(body, contains('all-clear'));
      expect(body, contains('completed'));
    },
  );

  test('states that coverage was incomplete instead of an all-clear', () async {
    // Regression: `coverageIncomplete` means at least one product fell below
    // the 0.3 mapped-coverage trust floor, so its ingredients may never have
    // reached the interaction checks.
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: const StackIntelligence(
        tier: StackTier.incomplete,
        stackSize: 0,
        issues: [],
        interactionCount: 0,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
      ),
      safetyReport: const StackSafetyReport(coverageIncomplete: true),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 5, 28),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, isNot(contains('snapshot.')));
    expect(body, contains('all-clear'));
    expect(body, contains('analyzed,'));
  });

  test(
    'does not print a bare zero interaction count when checks failed',
    () async {
      // The stack-summary counters are derived from the same subsystems that
      // failed. "Interactions flagged: 0" reads as a finding; it must be
      // qualified when the checks behind it did not run.
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.incomplete,
          stackSize: 0,
          issues: [],
          interactionCount: 0,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(checksIncomplete: true),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 5, 28),
      );

      // The counters were removed outright, which satisfies the same intent
      // more directly: there is no bare zero to misread. The hedge that the
      // checks did not run must still be present.
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, isNot(contains('flagged')));
      expect(body, contains('all-clear'));
    },
  );

  test('carries a recall-scan unavailable state into the PDF', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: const StackIntelligence(
        tier: StackTier.decent,
        stackSize: 1,
        issues: [],
        interactionCount: 0,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
        analysisIncomplete: true,
      ),
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 29),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('all-clear'));
    expect(body, contains('completed'));
    expect(body, isNot(contains('snapshot.')));
  });

  test(
    'states depletion analysis was unavailable rather than omitting it',
    () async {
      // Regression (2026-07-24): an `unavailable` load status has empty matches but
      // must NOT read as a clean "no depletions" — the PDF must say so explicitly.
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.incomplete,
          stackSize: 0,
          issues: [],
          interactionCount: 0,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        depletionStatus: MedNutrientLoadStatus.unavailable,
        generatedAt: DateTime.utc(2026, 5, 28),
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('unavailable'));
      expect(body, contains('Medication-nutrient'));
      expect(body.toLowerCase(), isNot(contains('depletion')));
    },
  );

  test('states fallback depletion analysis is partial', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: const StackIntelligence(
        tier: StackTier.incomplete,
        stackSize: 0,
        issues: [],
        interactionCount: 0,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
      ),
      safetyReport: const StackSafetyReport(),
      depletions: _depletions,
      depletionStatus: MedNutrientLoadStatus.fallbackLoaded,
      generatedAt: DateTime.utc(2026, 5, 28),
    );
    final body = latin1.decode(bytes, allowInvalid: true);

    expect(body, contains('Partial'));
    expect(body, contains('fallback'));
    expect(body, contains('Metformin'));
  });

  test(
    'renders reviewed medication-nutrient clinical detail and source',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.decent,
          stackSize: 1,
          issues: [],
          interactionCount: 0,
          nutrientWarningCount: 1,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(),
        depletions: _depletions,
        generatedAt: DateTime.utc(2026, 5, 28),
      );

      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('Associated'));
      expect(body, contains('Evidence:'));
      expect(body, contains('Established'));
      expect(body, contains('Mechanism:'));
      expect(body, contains('Recommendation:'));
      expect(body, contains('gov.uk'));
    },
  );

  test('prints clinical artifact, catalog, and rules provenance', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: const StackIntelligence(
        tier: StackTier.incomplete,
        stackSize: 0,
        issues: [],
        interactionCount: 0,
        nutrientWarningCount: 0,
        hasRecalledIngredient: false,
        hasContraindicatedInteraction: false,
        hasBannedIngredient: false,
      ),
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      clinicalDataVersion: '2026.07.27',
      clinicalDataHash: 'sha256:abc123',
      productCatalogVersion: '2026.07.26.101500',
      interactionRulesVersion: '2026.07.24.001',
      generatedAt: DateTime.utc(2026, 5, 28),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    // Provenance is a label/value table, so labels and values are separate
    // cells. The content hash is deliberately no longer printed.
    expect(body, contains('PROVENANCE'));
    expect(body, contains('version'));
    expect(body, contains('2026.07.27'));
    expect(body, isNot(contains('sha256')));
    expect(body, contains('Product'));
    expect(body, contains('catalog'));
    expect(body, contains('2026.07.26.101500'));
    expect(body, contains('Interaction'));
    expect(body, contains('rules'));
    expect(body, contains('2026.07.24.001'));
  });

  test('includes focused questions for clinician discussion', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: _safetyReport(),
      depletions: _depletions,
      generatedAt: DateTime.utc(2026, 5, 28),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('QUESTIONS'));
    expect(body, contains('timing'));
    expect(body, contains('monitoring'));
    expect(body, contains('represented'));
  });

  test(
    'preserves consumer placement for good-to-know food advisories',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: const [],
        intelligence: const StackIntelligence(
          tier: StackTier.solid,
          stackSize: 1,
          issues: [],
          interactionCount: 1,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(
          stackInteractions: [
            InteractionResult(
              id: 'food-advisory',
              type: InteractionType.drugSupplement,
              severity: Severity.informational,
              curatedSeverity: Severity.avoid,
              evidenceLevel: EvidenceLevel.established,
              agent1Name: 'Grapefruit',
              agent2Name: 'Atorvastatin',
              mechanism: 'Food exposure may change atorvastatin levels.',
              management: 'Discuss unusually high grapefruit intake.',
              alertStyle: 'food_advisory_note',
              doseDependant: false,
              doseThreshold: null,
              sourceUrls: [],
              source: InteractionSource.pipeline,
            ),
          ],
        ),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 7, 29),
      );

      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('GOOD'));
      expect(body, contains('KNOW'));
      expect(body, contains('Good'));
      expect(body, contains('know'));
      expect(body, isNot(contains('Not recommended: Grapefruit')));
      expect(body, contains('Evidence:'));
      expect(body, contains('Established'));
      expect(body, isNot(contains('Strong Evidence')));
    },
  );

  test('does not silently truncate timing guidance', () async {
    final timings = List.generate(
      9,
      (index) => TimingOptimization(
        ruleId: 'timing-$index',
        ingredient1: 'Ingredient $index',
        ingredient2: 'Medication $index',
        advice: 'TimingMarker$index',
        ruleType: TimingRuleType.separate,
        separationHours: 2,
        scoreImpact: -1,
        evidenceLevel: EvidenceLevel.probable,
      ),
    );
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: StackSafetyReport(timingOptimizations: timings),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 29),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('TimingMarker8'));
  });

  test('labels missing provenance instead of omitting it', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 29),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    // Every absent artifact field is named "Unavailable" rather than dropped.
    expect(body, contains('PROVENANCE'));
    expect(
      RegExp('Unavailable').allMatches(body).length,
      greaterThanOrEqualTo(3),
    );
  });

  test('prints medication identity limitations for clinician review', () async {
    final medication = _stack(
      id: 'med-unresolved',
      name: 'Example medication',
      type: 'medication',
    );
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: [medication],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      medicationIdentityStatuses: const {
        'med-unresolved': MedicationIdentityStatus.unresolved,
      },
      generatedAt: DateTime.utc(2026, 7, 29),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('Identity'));
    expect(body, contains('unresolved'));
    expect(body, contains('incomplete'));
  });

  // Restored: this test and the same-bottle timing test below were
  // uncommitted working-tree work, not present at HEAD.
  test(
    'clinician report ignores legacy supplement dose and schedule overrides',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: [
          _stack(
            id: 'med-1',
            name: 'Medication',
            type: 'medication',
            dosage: 'MEDDOSE777',
            frequency: 'Daily',
          ),
          _stack(
            id: 'supp-1',
            name: 'Verified Supplement',
            type: 'supplement',
            dosage: 'LEGACYDOSE888',
            frequency: 'LEGACYSCHEDULE999',
          ),
        ],
        intelligence: const StackIntelligence(
          tier: StackTier.incomplete,
          stackSize: 2,
          issues: [],
          interactionCount: 0,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 7, 31),
      );

      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('MEDDOSE777'));
      expect(body, isNot(contains('LEGACYDOSE888')));
      expect(body, isNot(contains('LEGACYSCHEDULE999')));
    },
  );

  test('reports same-bottle timing conflicts at product level', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(
        timingOptimizations: [
          TimingOptimization(
            ruleId: 'ala_empty',
            ingredient1: 'alpha-lipoic acid',
            ingredient2: 'food',
            advice: 'Take alpha-lipoic acid on an empty stomach.',
            ruleType: TimingRuleType.takeOnEmptyStomach,
            scoreImpact: -1,
            evidenceLevel: EvidenceLevel.probable,
            product1Name: 'O.N.E. Multivitamin',
            product1StackEntryId: 'stack-multi',
          ),
          TimingOptimization(
            ruleId: 'vitamin_a_with_fat',
            ingredient1: 'vitamin a',
            ingredient2: 'dietary fat',
            advice: 'Take vitamin A with a meal containing fat.',
            ruleType: TimingRuleType.takeWithFood,
            scoreImpact: -1,
            evidenceLevel: EvidenceLevel.established,
            product1Name: 'O.N.E. Multivitamin',
            product1StackEntryId: 'stack-multi',
          ),
        ],
      ),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 29),
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('O.N.E.'));
    expect(body, contains('Multivitamin'));
    expect(body, contains('conflicting'));
    expect(body, contains('guidance'));
    // The instructions are now named, but only inside a sentence stating they
    // cannot both be followed - never as separate schedulable advice.
    expect(body, contains('followed'));
  });

  // ===================================================================
  // Reconciliation honesty.
  // ===================================================================

  test(
    'states medications are not entered instead of dropping the section',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: [_stack(id: 'supp-1', name: 'Vitamin D3', type: 'supplement')],
        intelligence: _intelligence,
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 7, 31),
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('MEDICATIONS'));
      expect(body, contains('Reconciliation'));
    },
  );

  test(
    'flags class-only reconciliation when a drug class has no medication',
    () async {
      final ts = DateTime.utc(2026, 7, 31);
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: UserProfile(
          id: 1,
          ageBracket: '31-50',
          sex: 'Male',
          goals: '[]',
          conditions: '[]',
          drugClasses: '["insulin_sulfonylureas"]',
          allergens: '[]',
          profileFlags: '[]',
          createdAt: ts,
          lastUpdated: ts,
        ),
        stack: [_stack(id: 'supp-1', name: 'Chromium', type: 'supplement')],
        intelligence: _intelligence,
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: ts,
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('class-only'));
      expect(body, contains('all-clear'));
    },
  );

  test(
    'does not fire the reconciliation banner without a declared class',
    () async {
      final ts = DateTime.utc(2026, 7, 31);
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: UserProfile(
          id: 1,
          ageBracket: '35-44',
          sex: 'female',
          goals: '[]',
          conditions: '[]',
          drugClasses: '[]',
          allergens: '[]',
          profileFlags: '[]',
          createdAt: ts,
          lastUpdated: ts,
        ),
        stack: [
          _stack(
            id: 'med-1',
            name: 'Lisinopril',
            type: 'medication',
            dosage: '10 mg',
            frequency: 'daily',
          ),
        ],
        intelligence: _intelligence,
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: ts,
      );
      expect(
        latin1.decode(bytes, allowInvalid: true),
        isNot(contains('class-only')),
      );
    },
  );

  test(
    'still requires reconciliation when a saved medication is unrelated',
    () async {
      final ts = DateTime.utc(2026, 7, 31);
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: UserProfile(
          id: 1,
          ageBracket: '51-70',
          sex: 'Male',
          goals: '[]',
          conditions: '[]',
          drugClasses: '["ace_inhibitors"]',
          allergens: '[]',
          profileFlags: '[]',
          createdAt: ts,
          lastUpdated: ts,
        ),
        stack: [_aspirin(ts)],
        intelligence: _intelligence,
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: ts,
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('class-only'));
      expect(body, contains('all-clear'));
    },
  );

  test(
    'clears reconciliation when a saved medication resolves the class',
    () async {
      final ts = DateTime.utc(2026, 7, 31);
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: UserProfile(
          id: 1,
          ageBracket: '51-70',
          sex: 'Male',
          goals: '[]',
          conditions: '[]',
          drugClasses: '["antiplatelets"]',
          allergens: '[]',
          profileFlags: '[]',
          createdAt: ts,
          lastUpdated: ts,
        ),
        stack: [_aspirin(ts)],
        intelligence: _intelligence,
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: ts,
      );
      expect(
        latin1.decode(bytes, allowInvalid: true),
        isNot(contains('class-only')),
      );
    },
  );

  test('names the unresolved class when a medication is entered', () async {
    final ts = DateTime.utc(2026, 7, 31);
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: UserProfile(
        id: 1,
        ageBracket: '51-70',
        sex: 'Male',
        goals: '[]',
        conditions: '[]',
        drugClasses: '["anticoagulants"]',
        allergens: '[]',
        profileFlags: '[]',
        createdAt: ts,
        lastUpdated: ts,
      ),
      stack: [_aspirin(ts)],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: ts,
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('resolves'));
    expect(body, contains('thinners'));
  });

  test('states allergies are not entered rather than omitting them', () async {
    final ts = DateTime.utc(2026, 7, 31);
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: UserProfile(
        id: 1,
        ageBracket: '31-50',
        sex: 'Female',
        goals: '[]',
        conditions: '[]',
        drugClasses: '[]',
        allergens: '[]',
        profileFlags: '[]',
        createdAt: ts,
        lastUpdated: ts,
      ),
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: ts,
    );
    expect(
      latin1.decode(bytes, allowInvalid: true),
      contains('Allergies/intolerances'),
    );
  });

  // ===================================================================
  // Provenance describes artifacts, never the patient's data.
  // ===================================================================

  test('never labels anything in the report "Complete"', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    expect(
      latin1.decode(bytes, allowInvalid: true),
      isNot(contains('Complete')),
    );
  });

  test('keeps technical provenance below the clinical content', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: _profile(),
      stack: [_stack(id: 'supp-1', name: 'Vitamin D3', type: 'supplement')],
      intelligence: _intelligence,
      safetyReport: _safetyReport(),
      depletions: _depletions,
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(
      body.indexOf('PROVENANCE'),
      greaterThan(body.indexOf('SUPPLEMENTS')),
    );
    expect(body.indexOf('PROVENANCE'), greaterThan(body.indexOf('QUESTIONS')));
  });

  test('omits backend-only provenance from the clinician report', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      clinicalDataVersion: '2026.07.30',
      clinicalDataHash: 'sha256:abc123',
      productCatalogVersion: '2026.07.29.184200',
      interactionRulesVersion: '2026.07.28.003',
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, isNot(contains('sha256')));
    expect(body, contains('2026.07.29.184200'));
    expect(body, contains('2026.07.28.003'));
  });

  test('does not print a stack tier in the clinician report', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, isNot(contains('Decent')));
    expect(body, isNot(contains('tier')));
  });

  test('omits the stack summary counters entirely', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, isNot(contains('flagged')));
    expect(body, isNot(contains('SUMMARY')));
  });

  test('repeats a deterministic report id across pages', () async {
    final nutrients = List.generate(
      40,
      (i) => NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'nutrient_$i',
          displayName: 'Nutrient $i',
          totalAmount: (10 + i).toDouble(),
          unit: 'mg',
          contributions: const [],
        ),
        tier: NutrientTier.adequate,
        rda: 100,
        pctOfRda: 50,
      ),
    );
    final generatedAt = DateTime.utc(2026, 7, 31, 21, 22);
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: _profile(),
      stack: const [],
      intelligence: _intelligence,
      safetyReport: StackSafetyReport(nutrientStatuses: nutrients),
      depletions: _depletions,
      generatedAt: generatedAt,
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    final id = ClinicianPdfBuilder.reportIdFor(generatedAt);
    expect(id, startsWith('PG-'));
    expect(RegExp(RegExp.escape(id)).allMatches(body).length, greaterThan(1));
    expect(ClinicianPdfBuilder.reportIdFor(generatedAt), id);
  });

  // ===================================================================
  // Nutrient comparators and coverage.
  // ===================================================================

  test('surfaces a generic-baseline target caveat on nutrient rows', () async {
    final bytes = await _nutrientReport(
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_c',
          displayName: 'Vitamin C',
          totalAmount: 1180,
          unit: 'mg',
          contributions: [
            NutrientContribution(
              stackEntryId: 'supp-1',
              productName: 'CBottle',
              amount: 1180,
              unit: 'mg',
            ),
          ],
        ),
        tier: NutrientTier.aboveTypical,
        rda: 75,
        ul: 2000,
        pctOfRda: 1573,
        pctOfUl: 59,
        rdaIsBaseline: true,
      ),
    );
    expect(latin1.decode(bytes, allowInvalid: true), contains('baseline'));
  });

  test('surfaces a non-personalized upper-limit caveat', () async {
    final bytes = await _nutrientReport(
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'zinc',
          displayName: 'Zinc',
          totalAmount: 25,
          unit: 'mg',
          contributions: [
            NutrientContribution(
              stackEntryId: 'supp-1',
              productName: 'ZBottle',
              amount: 25,
              unit: 'mg',
            ),
          ],
        ),
        tier: NutrientTier.aboveTypical,
        rda: 11,
        ul: 40,
        pctOfRda: 227,
        pctOfUl: 62,
        ulIsFallback: true,
      ),
    );
    expect(
      latin1.decode(bytes, allowInvalid: true),
      contains('non-personalized'),
    );
  });

  test('states when an upper-limit comparison is indeterminate', () async {
    final bytes = await _nutrientReport(
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_a',
          displayName: 'Vitamin A',
          totalAmount: 900,
          unit: 'mcg',
          contributions: [
            NutrientContribution(
              stackEntryId: 'supp-1',
              productName: 'ABottle',
              amount: 900,
              unit: 'mcg',
            ),
          ],
        ),
        tier: NutrientTier.abundant,
        rda: 700,
        ul: 3000,
        pctOfRda: 128,
        ulAssessmentIndeterminate: true,
      ),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('Upper-limit'));
    expect(body, contains('form'));
  });

  test(
    'prints a dose range instead of the max amount at the min percent',
    () async {
      final bytes = await _nutrientReport(
        const NutrientStatus(
          total: NutrientTotal(
            canonicalId: 'niacin',
            displayName: 'Niacin',
            totalAmount: 9876,
            minimumTotalAmount: 1234,
            unit: 'mg',
            contributions: [
              NutrientContribution(
                stackEntryId: 'supp-1',
                productName: 'RangeBottle',
                amount: 9876,
                unit: 'mg',
              ),
            ],
          ),
          // Tiering is based on the minimum/recommended exposure (12.3%),
          // while the PDF also shows the maximum exposure (98.8%).
          tier: NutrientTier.underFifty,
          rda: 10000,
          pctOfRda: 12.3,
          maximumPctOfRda: 98.8,
        ),
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('1,234'));
      expect(body, contains('9,876'));
      expect(body, contains('12.3'));
      expect(body, contains('98.8'));
      expect(body, contains('Below'));
    },
  );

  test('says not quantified rather than printing a clinical zero', () async {
    final bytes = await _nutrientReport(
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'boron',
          displayName: 'Boron',
          totalAmount: 0,
          unit: '',
          contributions: [],
          excludedContributions: [
            ExcludedNutrientContribution(
              contribution: NutrientContribution(
                stackEntryId: 'supp-x',
                productName: 'BlendBottle',
                amount: 1,
                unit: 'blend',
              ),
              reason: NutrientExclusionReason.unsupportedUnit,
            ),
          ],
        ),
        tier: NutrientTier.noRda,
      ),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('quantified'));
    expect(body, contains('usable'));
  });

  test(
    'keeps an unattributed total visible instead of calling it unquantified',
    () async {
      final bytes = await _nutrientReport(
        const NutrientStatus(
          total: NutrientTotal(
            canonicalId: 'magnesium',
            displayName: 'Magnesium',
            totalAmount: 60,
            unit: 'mg',
            contributions: [],
            excludedContributions: [
              ExcludedNutrientContribution(
                contribution: NutrientContribution(
                  stackEntryId: 'supp-mag',
                  productName: 'MagBottle',
                  amount: 400,
                  unit: 'mg',
                ),
                reason: NutrientExclusionReason.compoundFormDuplicate,
              ),
            ],
          ),
          tier: NutrientTier.underFifty,
          rda: 400,
          pctOfRda: 15,
        ),
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('60'));
      expect(body, contains('15%'));
      expect(body, contains('Below'));
      expect(body, isNot(contains('Adequate')));
      expect(body, isNot(contains('quantified')));
    },
  );

  test('does not label a no-reference substance with RDA semantics', () async {
    final bytes = await _nutrientReport(
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'creatine',
          displayName: 'Creatine',
          totalAmount: 5000,
          unit: 'mg',
          contributions: [
            NutrientContribution(
              stackEntryId: 'supp-1',
              productName: 'CrBottle',
              amount: 5000,
              unit: 'mg',
            ),
          ],
        ),
        tier: NutrientTier.noRda,
      ),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, isNot(contains('RDA')));
    expect(body, contains('reference'));
    expect(body, contains('5,000'));
  });

  test('states nutrient totals cover supplements only', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: const [],
      intelligence: _intelligence,
      safetyReport: _safetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    expect(
      latin1.decode(bytes, allowInvalid: true),
      contains('supplement-only'),
    );
  });

  test('attributes each nutrient total to its source products', () async {
    final bytes = await _nutrientReport(
      const NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'chromium',
          displayName: 'Chromium',
          totalAmount: 200,
          unit: 'mcg',
          contributions: [
            NutrientContribution(
              stackEntryId: 'supp-multi',
              productName: 'O.N.E. Multivitamin',
              amount: 200,
              unit: 'mcg',
            ),
          ],
        ),
        tier: NutrientTier.aboveAdequateNoUl,
        rda: 35,
        pctOfRda: 571,
      ),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('Multivitamin'));
    expect(body, contains('Sources'));
  });

  test('flags a supplement that mapped to no nutrient totals', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: [
        _stack(id: 'supp-mapped', name: 'Vitamin D3', type: 'supplement'),
        _stack(id: 'supp-unmapped', name: 'Mystery Blend', type: 'supplement'),
      ],
      intelligence: _intelligence,
      safetyReport: _safetyReport(),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('Mystery'));
    expect(body, contains('Nothing'));
  });

  test(
    'does not accuse a benign duplicate exclusion of being unmapped',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: [_stack(id: 'supp-mag', name: 'MagBottle', type: 'supplement')],
        intelligence: _intelligence,
        safetyReport: const StackSafetyReport(
          nutrientStatuses: [
            NutrientStatus(
              total: NutrientTotal(
                canonicalId: 'magnesium',
                displayName: 'Magnesium',
                totalAmount: 60,
                unit: 'mg',
                contributions: [],
                excludedContributions: [
                  ExcludedNutrientContribution(
                    contribution: NutrientContribution(
                      stackEntryId: 'supp-mag',
                      productName: 'MagBottle',
                      amount: 400,
                      unit: 'mg',
                    ),
                    reason: NutrientExclusionReason.compoundFormDuplicate,
                  ),
                ],
              ),
              tier: NutrientTier.adequate,
              rda: 400,
              pctOfRda: 15,
            ),
          ],
        ),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 7, 31),
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('within'));
      expect(body, isNot(contains('Nothing')));
    },
  );

  test('a benign exclusion does not hide an unusable-unit exclusion', () async {
    final bytes = await const ClinicianPdfBuilder(compress: false).build(
      profile: null,
      stack: [_stack(id: 'supp-b', name: 'BothBottle', type: 'supplement')],
      intelligence: _intelligence,
      safetyReport: const StackSafetyReport(
        nutrientStatuses: [
          NutrientStatus(
            total: NutrientTotal(
              canonicalId: 'magnesium',
              displayName: 'Magnesium',
              totalAmount: 60,
              unit: 'mg',
              contributions: [],
              excludedContributions: [
                ExcludedNutrientContribution(
                  contribution: NutrientContribution(
                    stackEntryId: 'supp-b',
                    productName: 'BothBottle',
                    amount: 400,
                    unit: 'mg',
                  ),
                  reason: NutrientExclusionReason.compoundFormDuplicate,
                ),
                ExcludedNutrientContribution(
                  contribution: NutrientContribution(
                    stackEntryId: 'supp-b',
                    productName: 'BothBottle',
                    amount: 1,
                    unit: 'blend',
                  ),
                  reason: NutrientExclusionReason.unsupportedUnit,
                ),
              ],
            ),
            tier: NutrientTier.adequate,
            rda: 400,
            pctOfRda: 15,
          ),
        ],
      ),
      depletions: const [],
      generatedAt: DateTime.utc(2026, 7, 31),
    );
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('unusable'));
    expect(body, contains('duplicate'));
  });

  test(
    'counts distinct nutrients per supplement, not contribution rows',
    () async {
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: null,
        stack: [_stack(id: 'supp-a', name: 'FormBottle', type: 'supplement')],
        intelligence: _intelligence,
        safetyReport: const StackSafetyReport(
          nutrientStatuses: [
            NutrientStatus(
              total: NutrientTotal(
                canonicalId: 'vitamin_a',
                displayName: 'Vitamin A',
                totalAmount: 900,
                unit: 'mcg',
                contributions: [
                  NutrientContribution(
                    stackEntryId: 'supp-a',
                    productName: 'FormBottle',
                    ingredientName: 'retinyl palmitate',
                    amount: 600,
                    unit: 'mcg',
                  ),
                  NutrientContribution(
                    stackEntryId: 'supp-a',
                    productName: 'FormBottle',
                    ingredientName: 'beta-carotene',
                    amount: 300,
                    unit: 'mcg',
                  ),
                ],
              ),
              tier: NutrientTier.abundant,
              rda: 700,
              pctOfRda: 128,
            ),
          ],
        ),
        depletions: const [],
        generatedAt: DateTime.utc(2026, 7, 31),
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, contains('One'));
      expect(body, isNot(contains('nutrients')));
    },
  );

  // ===================================================================
  // Timing.
  // ===================================================================

  test('renders the resolved daily schedule, not just advice lines', () async {
    final bytes = await _timingReport(const [
      TimingOptimization(
        ruleId: 'iron_with_food',
        ingredient1: 'iron',
        ingredient2: 'food',
        advice: 'Take iron with a meal.',
        ruleType: TimingRuleType.takeWithFood,
        scoreImpact: -1,
        evidenceLevel: EvidenceLevel.probable,
        product1Name: 'AlphaBottle',
        product1StackEntryId: 'stack-alpha',
      ),
    ]);
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('AlphaBottle'));
    expect(body, contains('breakfast'));
  });

  test('does not imply simultaneous administration in the schedule', () async {
    final bytes = await _timingReport(const [
      TimingOptimization(
        ruleId: 'iron_with_food',
        ingredient1: 'iron',
        ingredient2: 'food',
        advice: 'Take iron with a meal.',
        ruleType: TimingRuleType.takeWithFood,
        scoreImpact: -1,
        evidenceLevel: EvidenceLevel.probable,
        product1Name: 'AlphaBottle',
        product1StackEntryId: 'stack-alpha',
      ),
    ]);
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, isNot(contains('Take together')));
    expect(body, contains('window'));
  });

  test('explains what a same-product timing conflict actually is', () async {
    final bytes = await _timingReport(const [
      TimingOptimization(
        ruleId: 'ala_empty',
        ingredient1: 'alpha-lipoic acid',
        ingredient2: 'food',
        advice: 'Take alpha-lipoic acid on an empty stomach.',
        ruleType: TimingRuleType.takeOnEmptyStomach,
        scoreImpact: -1,
        evidenceLevel: EvidenceLevel.probable,
        product1Name: 'O.N.E. Multivitamin',
        product1StackEntryId: 'stack-multi',
      ),
      TimingOptimization(
        ruleId: 'vitamin_a_with_fat',
        ingredient1: 'vitamin a',
        ingredient2: 'dietary fat',
        advice: 'Take vitamin A with a meal containing fat.',
        ruleType: TimingRuleType.takeWithFood,
        scoreImpact: -1,
        evidenceLevel: EvidenceLevel.established,
        product1Name: 'O.N.E. Multivitamin',
        product1StackEntryId: 'stack-multi',
      ),
    ]);
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('followed'));
    expect(body, contains('stomach'));
    expect(body, contains('meal'));
  });

  test('never prints an unsatisfiable timing rule as valid advice', () async {
    final bytes = await _timingReport(const [
      TimingOptimization(
        ruleId: 'unplaceable_tod',
        ingredient1: 'ashwagandha',
        ingredient2: 'sleep',
        advice: 'UNPLACEABLEADVICE',
        ruleType: TimingRuleType.timeOfDay,
        scoreImpact: -1,
        evidenceLevel: EvidenceLevel.probable,
        product1Name: 'SleepBottle',
        product1StackEntryId: 'supp-sleep',
      ),
    ]);
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('UNPLACEABLEADVICE'));
    expect(body, contains('reviewed'));
    expect(body, contains('slot'));
  });

  test(
    'does not assert an all-clear while a declared class is unresolved',
    () async {
      // The banner says the review is partial, so "No stack warnings in the
      // current snapshot" directly below it asserts exactly what the banner
      // denies. An unresolved class means medication checks may not have run.
      final ts = DateTime.utc(2026, 7, 31);
      final bytes = await const ClinicianPdfBuilder(compress: false).build(
        profile: UserProfile(
          id: 1,
          ageBracket: '51-70',
          sex: 'Male',
          goals: '[]',
          conditions: '[]',
          drugClasses: '["insulin_sulfonylureas"]',
          allergens: '[]',
          profileFlags: '[]',
          createdAt: ts,
          lastUpdated: ts,
        ),
        stack: [_aspirin(ts)],
        intelligence: const StackIntelligence(
          tier: StackTier.decent,
          stackSize: 1,
          issues: [],
          interactionCount: 0,
          nutrientWarningCount: 0,
          hasRecalledIngredient: false,
          hasContraindicatedInteraction: false,
          hasBannedIngredient: false,
        ),
        safetyReport: const StackSafetyReport(),
        depletions: const [],
        generatedAt: ts,
      );
      final body = latin1.decode(bytes, allowInvalid: true);
      expect(body, isNot(contains('snapshot.')));
      expect(body, contains('all-clear'));
    },
  );
}

UserStacksLocalData _aspirin(DateTime ts) => UserStacksLocalData(
  id: 'med-asa',
  type: 'medication',
  name: 'Aspirin',
  dsldId: null,
  rxcui: '1191',
  ingredientKeys: null,
  drugClassesCol: '["class:antiplatelet_agents"]',
  genericRxcui: null,
  ingredientRxcuisCol: null,
  dosage: '81 mg',
  frequency: 'daily',
  addedAt: ts,
  clientUpdatedAt: ts,
  deletedAt: null,
  syncedAt: null,
);

Future<Uint8List> _nutrientReport(NutrientStatus status) {
  return const ClinicianPdfBuilder(compress: false).build(
    profile: null,
    stack: const [],
    intelligence: _intelligence,
    safetyReport: StackSafetyReport(nutrientStatuses: [status]),
    depletions: const [],
    generatedAt: DateTime.utc(2026, 7, 31),
  );
}

Future<Uint8List> _timingReport(List<TimingOptimization> timings) {
  return const ClinicianPdfBuilder(compress: false).build(
    profile: null,
    stack: const [],
    intelligence: _intelligence,
    safetyReport: StackSafetyReport(timingOptimizations: timings),
    depletions: const [],
    generatedAt: DateTime.utc(2026, 7, 31),
  );
}
