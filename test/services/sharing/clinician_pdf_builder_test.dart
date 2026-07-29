import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/database/user_database.dart';
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
        'Supplement',
        'Stack',
        'Report',
        'Patient-generated',
        'supplement',
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
      generatedAt: ts,
    );

    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('TTC'));
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
    expect(body, contains('Strong'));
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

  test('states that safety checks did not complete instead of an all-clear', () async {
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
  });

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

  test('does not print a bare zero interaction count when checks failed', () async {
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

    // "Interactions flagged:" and "0" are separate text operators, so the
    // qualifier token is what proves the count is not left bare.
    final body = latin1.decode(bytes, allowInvalid: true);
    expect(body, contains('incomplete'));
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
    expect(body, contains('PROVENANCE'));
    expect(body, contains('version:'));
    expect(body, contains('2026.07.27'));
    expect(body, contains('hash:'));
    expect(body, contains('sha256:abc123'));
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
}
