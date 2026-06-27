import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

InteractionResult _interaction({
  required String id,
  required Severity severity,
  String mechanism = 'mech',
  InteractionType type = InteractionType.supplementSupplement,
}) {
  return InteractionResult(
    id: id,
    type: type,
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    agent1Name: 'A',
    agent2Name: 'B',
    mechanism: mechanism,
    management: 'manage',
    doseDependant: false,
    doseThreshold: null,
    sourceUrls: const <String>[],
    source: InteractionSource.pipeline,
  );
}

NutrientStatus _nutrient({
  required String id,
  required NutrientTier tier,
  String? warning,
}) {
  return NutrientStatus(
    total: NutrientTotal(
      canonicalId: id,
      displayName: id,
      totalAmount: 100,
      unit: 'mg',
      contributions: const <NutrientContribution>[],
    ),
    tier: tier,
    warning: warning,
  );
}

MedicationProfileWarning _profileWarning({
  required String id,
  required Severity severity,
  String headline = 'Review NSAID use in pregnancy',
}) {
  return MedicationProfileWarning(
    id: id,
    ruleId: id,
    medicationName: 'Motrin',
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    headline: headline,
    body: 'NSAIDs are generally avoided from 20 weeks of pregnancy.',
    management: 'Check with your clinician.',
    sourceUrls: const <String>[],
  );
}

RecalledIngredientViolation _violation({
  required String productName,
  required String recallStatus,
  String severity = 'major',
}) {
  return RecalledIngredientViolation(
    productDsldId: 'D-${productName.hashCode}',
    productName: productName,
    brandName: 'Brand',
    recalledIngredients: [
      RecalledIngredientAlert(
        canonicalId: 'IND',
        commonNames: const ['ingredient'],
        recallStatus: recallStatus,
        regulatoryBasis: 'FDA',
        reason: 'reason',
        effectiveDate: '2026-01-01',
        severity: severity,
        safetyWarning: 'warn',
        safetyWarningOneLiner: 'one liner',
        banContext: 'substance',
      ),
    ],
  );
}

StackDoseThresholdAlert _doseAlert({
  String conditionId = 'pregnancy',
  String canonicalId = 'caffeine',
  String displayName = 'Caffeine',
  double totalValue = 240,
  String unit = 'mg',
  double thresholdValue = 200,
}) {
  return StackDoseThresholdAlert(
    conditionId: conditionId,
    canonicalId: canonicalId,
    displayName: displayName,
    totalValue: totalValue,
    unit: unit,
    thresholdValue: thresholdValue,
    thresholdUnit: unit,
    contributions: const [],
  );
}

void main() {
  const engine = StackIntelligenceEngine();
  final emptySynergy = SynergyReport.empty();
  final emptyRecall = RecalledIngredientsReport.empty();

  group('StackIntelligenceEngine.diagnose', () {
    test('empty stack → tier=incomplete, no issues, all flags false', () {
      const report = StackSafetyReport();

      final intelligence = engine.diagnose(
        stackSize: 0,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      expect(intelligence.tier, StackTier.incomplete);
      expect(intelligence.stackSize, 0);
      expect(intelligence.issues, isEmpty);
      expect(intelligence.hasBannedIngredient, isFalse);
      expect(intelligence.hasRecalledIngredient, isFalse);
      expect(intelligence.hasContraindicatedInteraction, isFalse);
      expect(intelligence.interactionCount, 0);
      expect(intelligence.nutrientWarningCount, 0);
    });

    test('single banned ingredient + clean stack → unsafe', () {
      final recall = RecalledIngredientsReport(
        violations: [
          _violation(productName: 'Banned Product', recallStatus: 'banned'),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 5,
        safetyReport: const StackSafetyReport(),
        recalledReport: recall,
        synergyReport: emptySynergy,
        qualityScore: 90,
      );

      expect(intelligence.tier, StackTier.unsafe);
      expect(intelligence.hasBannedIngredient, isTrue);
      expect(intelligence.hasRecalledIngredient, isTrue);
      expect(intelligence.issues, isNotEmpty);
      expect(intelligence.issues.first.headline, contains('Banned Product'));
    });

    test(
      'warning-status recall → unsafe + hasRecalledIngredient (not banned)',
      () {
        final recall = RecalledIngredientsReport(
          violations: [
            _violation(
              productName: 'Watchlist Product',
              recallStatus: 'warning',
              severity: 'major',
            ),
          ],
        );

        final intelligence = engine.diagnose(
          stackSize: 4,
          safetyReport: const StackSafetyReport(),
          recalledReport: recall,
          synergyReport: emptySynergy,
        );

        expect(intelligence.tier, StackTier.unsafe);
        expect(intelligence.hasRecalledIngredient, isTrue);
        expect(intelligence.hasBannedIngredient, isFalse);
      },
    );

    test('contraindicated interaction → unsafe', () {
      final report = StackSafetyReport(
        medicationInteractions: [
          _interaction(id: 'x1', severity: Severity.contraindicated),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 3,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      expect(intelligence.tier, StackTier.unsafe);
      expect(intelligence.hasContraindicatedInteraction, isTrue);
      expect(intelligence.interactionCount, 1);
    });

    test('avoid-level interaction → concerning', () {
      final report = StackSafetyReport(
        stackInteractions: [_interaction(id: 's1', severity: Severity.avoid)],
      );

      final intelligence = engine.diagnose(
        stackSize: 4,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
      );

      expect(intelligence.tier, StackTier.concerning);
      expect(intelligence.interactionCount, 1);
      expect(intelligence.hasContraindicatedInteraction, isFalse);
    });

    test('medication-profile warning counts as a stack interaction issue', () {
      final report = StackSafetyReport(
        medicationProfileWarnings: [
          _profileWarning(
            id: 'MCR_PREGNANCY_NSAIDS',
            severity: Severity.caution,
          ),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 2,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
      );

      expect(intelligence.interactionCount, 1);
      expect(intelligence.tier, StackTier.decent);
      final issue = intelligence.issues.single;
      expect(issue.headline, contains('Motrin'));
      expect(issue.headline, contains('Review NSAID use in pregnancy'));
      expect(issue.headline, contains('20 weeks'));
    });

    test('two nutrients approaching/exceeding UL → concerning', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(
            id: 'iron',
            tier: NutrientTier.approachingUl,
            warning: 'iron near UL',
          ),
          _nutrient(
            id: 'zinc',
            tier: NutrientTier.exceedsUl,
            warning: 'zinc over UL',
          ),
        ],
      );

      final intelligence = engine.diagnose(
        stackSize: 3,
        safetyReport: report,
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
      );

      expect(intelligence.tier, StackTier.concerning);
      expect(intelligence.nutrientWarningCount, 2);
      expect(
        intelligence.issues.any((i) => i.headline == 'zinc over UL'),
        isTrue,
      );
    });

    test('clean stack with qualityScore 90 → optimized', () {
      final intelligence = engine.diagnose(
        stackSize: 6,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 90,
      );

      expect(intelligence.tier, StackTier.optimized);
      expect(intelligence.issues, isEmpty);
      expect(intelligence.interactionCount, 0);
    });

    test('cumulative dose threshold alert caps clean stack at decent', () {
      final intelligence = engine.diagnose(
        stackSize: 3,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 95,
        doseThresholdAlerts: [_doseAlert()],
      );

      expect(intelligence.tier, StackTier.decent);
      expect(intelligence.nutrientWarningCount, 1);
      expect(intelligence.issues.single.severity, Severity.caution);
      expect(intelligence.issues.single.headline, contains('Caffeine'));
      expect(intelligence.issues.single.headline, contains('240 mg'));
    });

    test('clean stack with qualityScore 75 → solid', () {
      final intelligence = engine.diagnose(
        stackSize: 4,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: emptySynergy,
        qualityScore: 75,
      );

      expect(intelligence.tier, StackTier.solid);
    });

    test(
      'issues sort with recalls before interactions and severity-ordered',
      () {
        final report = StackSafetyReport(
          stackInteractions: [
            _interaction(
              id: 'sx',
              severity: Severity.caution,
              mechanism: 'mid-tier supplement issue',
            ),
          ],
          medicationInteractions: [
            _interaction(
              id: 'mx',
              severity: Severity.avoid,
              mechanism: 'medication conflict',
            ),
          ],
        );
        final recall = RecalledIngredientsReport(
          violations: [
            _violation(productName: 'Tainted', recallStatus: 'banned'),
          ],
        );

        final intelligence = engine.diagnose(
          stackSize: 5,
          safetyReport: report,
          recalledReport: recall,
          synergyReport: emptySynergy,
        );

        // Recall first.
        expect(intelligence.issues.first.headline, contains('Tainted'));
        // Then medication avoid before supplement caution.
        expect(intelligence.issues[1].headline, 'medication conflict');
        expect(intelligence.issues[2].headline, 'mid-tier supplement issue');
      },
    );
  });

  group('StackIntelligenceEngine.diagnoseFromReports', () {
    test('computes the shared quality score before deriving the tier', () {
      final synergy = SynergyReport(
        matches: [
          SynergyMatch(
            clusterId: 'sleep_support',
            clusterName: 'Sleep support',
            matchedIngredients: const ['magnesium', 'l_theanine'],
            mechanism: 'Complementary sleep-support stack.',
            bonusPoints: 8,
            evidenceTier: 'moderate',
            citations: const [],
          ),
        ],
        totalBonusPoints: 8,
      );

      final intelligence = engine.diagnoseFromReports(
        stackSize: 2,
        safetyReport: const StackSafetyReport(),
        recalledReport: emptyRecall,
        synergyReport: synergy,
      );

      expect(intelligence.qualityScore, 100);
      expect(intelligence.tier, StackTier.optimized);
      expect(intelligence.issues, isEmpty);
    });

    test('stack-health surfaces use the shared diagnosis composition', () {
      for (final path in const [
        'lib/features/home/v2/home_v2_screen.dart',
        'lib/features/stack/v2/stack_v2_screen.dart',
        'lib/features/stack/widgets/share_clinician_report_button.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('diagnoseFromReports('), reason: path);
        expect(source, isNot(contains('StackSafetyScorer().compute')));
      }
    });

    test(
      'stack-health surfaces pass cumulative dose alerts into diagnosis',
      () {
        for (final path in const [
          'lib/features/home/v2/home_v2_screen.dart',
          'lib/features/stack/v2/stack_v2_screen.dart',
          'lib/features/stack/widgets/share_clinician_report_button.dart',
        ]) {
          final source = File(path).readAsStringSync();
          expect(
            source,
            contains('stackDoseThresholdAlertsProvider'),
            reason: path,
          );
          expect(source, contains('doseThresholdAlerts:'), reason: path);
        }
      },
    );
  });
}
