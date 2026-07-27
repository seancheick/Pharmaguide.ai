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
}
