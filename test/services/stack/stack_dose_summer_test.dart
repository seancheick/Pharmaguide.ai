import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

const _pregnancyCaffeineRule = StackDoseThresholdRule(
  conditionId: 'pregnancy',
  canonicalId: 'caffeine',
  displayName: 'Caffeine',
  thresholdValue: 200,
  thresholdUnit: 'mg',
);

const _bleedingOmegaRule = StackDoseThresholdRule(
  conditionId: 'bleeding_disorders',
  canonicalId: 'omega_3',
  displayName: 'Omega-3',
  thresholdValue: 3000,
  thresholdUnit: 'mg',
);

const _surgeryOmegaRule = StackDoseThresholdRule(
  conditionId: 'surgery_scheduled',
  canonicalId: 'omega_3',
  displayName: 'Omega-3',
  thresholdValue: 3000,
  thresholdUnit: 'mg',
);

void main() {
  group('StackDoseSummer', () {
    test('extracts stack threshold rules from emitted warning metadata', () {
      final rules = stackDoseThresholdRulesFromWarnings([
        const InteractionWarning(
          severity: Severity.monitor,
          evidenceLevel: EvidenceLevel.established,
          title: 'Caffeine / pregnancy',
          mechanism: 'High caffeine may matter during pregnancy.',
          management: 'Keep under threshold.',
          conditionIds: ['pregnancy'],
          ingredientName: 'Caffeine',
          doseThresholdEvaluation: {
            'thresholds_checked': [
              {
                'threshold_value': 200,
                'threshold_unit': 'mg',
                'comparator': '>',
              },
            ],
          },
        ),
      ]);

      expect(rules, hasLength(1));
      expect(rules.single.conditionId, 'pregnancy');
      expect(rules.single.canonicalId, 'caffeine');
      expect(rules.single.thresholdValue, 200);
      expect(rules.single.thresholdUnit, 'mg');
    });

    test('extracts compact declarative rule and normalized exposure', () {
      final rules = stackDoseThresholdRulesFromWarnings(
        [
          const InteractionWarning(
            severity: Severity.caution,
            evidenceLevel: EvidenceLevel.established,
            title: 'Vitamin D / heart disease',
            mechanism: 'High-dose context.',
            management: 'Review high doses.',
            conditionIds: ['heart_disease'],
            ingredientName: 'Vitamin D',
            ingredientCanonicalId: 'vitamin_d',
            doseDecision: DoseDecision(
              clinicalSeverity: 'caution',
              evaluationStatus: 'below_threshold',
              consumerDisposition: 'suppress',
              evaluatedDailyAmount: 2000,
              evaluatedUnit: 'IU',
              normalizedPerServingAmount: 2000,
              normalizedPerServingUnit: 'IU',
              evaluatedServingMultiplier: 1,
              decisionRule: DoseDecisionRule(
                comparator: '>',
                threshold: 4000,
                thresholdUnit: 'IU',
                consumerDispositionIfMet: 'review',
                consumerDispositionIfNotMet: 'suppress',
              ),
            ),
          ),
        ],
        stackEntryId: 'stack-a',
        productName: 'Vitamin D A',
      );

      expect(rules, hasLength(1));
      expect(rules.single.comparator, '>');
      expect(rules.single.clinicalSeverity, 'caution');
      expect(rules.single.consumerDispositionIfMet, 'review');
      expect(rules.single.normalizedDailyAmount, 2000);
      expect(rules.single.normalizedDailyUnit, 'IU');
      expect(rules.single.sourceStackEntryId, 'stack-a');
    });

    test('does not reinterpret display names for new declarative rules', () {
      final rules = stackDoseThresholdRulesFromWarnings([
        const InteractionWarning(
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.established,
          title: 'Vitamin D / heart disease',
          mechanism: 'High-dose context.',
          management: 'Review high doses.',
          conditionIds: ['heart_disease'],
          ingredientName: 'Vitamin D',
          doseDecision: DoseDecision(
            evaluatedDailyAmount: 2000,
            evaluatedUnit: 'IU',
            decisionRule: DoseDecisionRule(
              comparator: '>',
              threshold: 4000,
              thresholdUnit: 'IU',
            ),
          ),
        ),
      ]);

      expect(rules, isEmpty);
    });

    test('aggregates pipeline-normalized exposures without app conversion', () {
      const rules = [
        StackDoseThresholdRule(
          conditionId: 'heart_disease',
          canonicalId: 'vitamin_d',
          displayName: 'Vitamin D',
          thresholdValue: 4000,
          thresholdUnit: 'IU',
          comparator: '>',
          clinicalSeverity: 'caution',
          consumerDispositionIfMet: 'review',
          normalizedDailyAmount: 2000,
          normalizedDailyUnit: 'IU',
          sourceStackEntryId: 'a',
          sourceProductName: 'Vitamin D A',
        ),
        StackDoseThresholdRule(
          conditionId: 'heart_disease',
          canonicalId: 'vitamin_d',
          displayName: 'Vitamin D',
          thresholdValue: 4000,
          thresholdUnit: 'IU',
          comparator: '>',
          clinicalSeverity: 'caution',
          consumerDispositionIfMet: 'review',
          normalizedDailyAmount: 2500,
          normalizedDailyUnit: 'IU',
          sourceStackEntryId: 'b',
          sourceProductName: 'Vitamin D B',
        ),
      ];

      final alerts = const StackDoseSummer().thresholdAlertsFromNormalizedRules(
        userConditions: const ['heart_disease'],
        thresholdRules: rules,
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.totalValue, 4500);
      expect(alerts.single.unit, 'iu');
      expect(alerts.single.clinicalSeverity, 'caution');
      expect(alerts.single.consumerDisposition, 'review');
      expect(alerts.single.contributions, hasLength(2));
    });

    test('aggregates declarative drug-class thresholds across products', () {
      final rules = [
        for (final entry in const [('a', 600.0), ('b', 500.0)])
          StackDoseThresholdRule(
            conditionId: 'statins',
            targetType: 'drug_class',
            canonicalId: 'vitamin_b3_niacin',
            displayName: 'Niacin',
            thresholdValue: 1000,
            thresholdUnit: 'mg',
            comparator: '>=',
            normalizedDailyAmount: entry.$2,
            normalizedDailyUnit: 'mg',
            sourceStackEntryId: entry.$1,
            sourceProductName: 'Niacin ${entry.$1}',
          ),
      ];

      final alerts = const StackDoseSummer().thresholdAlertsFromNormalizedRules(
        userConditions: const [],
        userDrugClasses: const ['statins'],
        thresholdRules: rules,
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.targetType, 'drug_class');
      expect(alerts.single.conditionId, 'statins');
      expect(alerts.single.totalValue, 1100);
    });

    test(
      'normalized stack comparison honors strict greater-than comparator',
      () {
        const rule = StackDoseThresholdRule(
          conditionId: 'heart_disease',
          canonicalId: 'vitamin_d',
          thresholdValue: 4000,
          thresholdUnit: 'IU',
          comparator: '>',
          normalizedDailyAmount: 4000,
          normalizedDailyUnit: 'IU',
        );

        final alerts = const StackDoseSummer()
            .thresholdAlertsFromNormalizedRules(
              userConditions: const ['heart_disease'],
              thresholdRules: const [rule],
            );

        expect(alerts, isEmpty);
      },
    );

    test('extracts stack threshold rules from detail blob warning lists', () {
      final rules = stackDoseThresholdRulesFromDetailBlob({
        'warnings_profile_gated': [
          {
            'severity': 'monitor',
            'evidence_level': 'established',
            'title': 'Caffeine / pregnancy',
            'detail': 'High caffeine may matter during pregnancy.',
            'action': 'Keep under threshold.',
            'condition_ids': ['pregnancy'],
            'ingredient_name': 'Caffeine',
            'dose_threshold_evaluation': {
              'thresholds_checked': [
                {'threshold_value': 200, 'threshold_unit': 'mg'},
              ],
            },
          },
        ],
      });

      expect(rules, hasLength(1));
      expect(rules.single.conditionId, 'pregnancy');
      expect(rules.single.canonicalId, 'caffeine');
    });

    test('sums the same ingredient across products', () {
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Energy A',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'b',
          productName: 'Energy B',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'c',
          productName: 'Energy C',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          ],
        ),
      ]);

      expect(totals['caffeine']?.totalValue, 240);
      expect(totals['caffeine']?.unit, 'mg');
      expect(totals['caffeine']?.contributions, hasLength(3));
    });

    test('normalizes simple mass units into the first seen unit', () {
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'ALA A',
          ingredients: [
            {
              'standard_name': 'Alpha Lipoic Acid',
              'quantity': 0.3,
              'unit': 'g',
            },
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'b',
          productName: 'ALA B',
          ingredients: [
            {
              'standard_name': 'Alpha Lipoic Acid',
              'quantity': 300,
              'unit': 'mg',
            },
          ],
        ),
      ]);

      expect(totals['alpha_lipoic_acid']?.totalValue, 0.6);
      expect(totals['alpha_lipoic_acid']?.unit, 'g');
    });

    test('compareThreshold fails open when the fish-oil (omega) total dropped '
        'an excluded contribution', () {
      // The omega/fish_oil threshold builds a FRESH combined total, which
      // previously dropped the source total's exclusions — so a
      // not-provided-unit fish-oil row undercounted (600, not 1400) and the
      // below-floor suppression fired anyway, hiding a real bleeding warning.
      // The combined total must inherit the exclusion and fail open, never
      // return `below`.
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Fish Oil A',
          ingredients: [
            {'standard_name': 'Fish Oil', 'quantity': 600, 'unit': 'mg'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'b',
          productName: 'Fish Oil B',
          ingredients: [
            // 'np' (not provided) unit → excluded from the sum
            {'standard_name': 'Fish Oil', 'quantity': 800, 'unit': 'np'},
          ],
        ),
      ]);

      final comparison = const StackDoseSummer().compareThreshold(
        totals: totals,
        canonicalId: 'fish_oil',
        thresholdValue: 1000,
        thresholdUnit: 'mg',
      );
      expect(comparison, StackDoseThresholdComparison.unavailable);
    });

    test('thresholdAlerts surfaces an incomplete below-threshold subtotal', () {
      // This is the alert-generating path, not the pairwise suppression path.
      // A known subtotal below the threshold is NOT enough to clear the stack
      // if another contribution was excluded; the true total could be above
      // threshold. Surface an incomplete alert instead of silently dropping
      // the issue.
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Caffeine A',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 160, 'unit': 'mg'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'b',
          productName: 'Caffeine B',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'np'},
          ],
        ),
      ]);

      final alerts = const StackDoseSummer().thresholdAlerts(
        totals: totals,
        userConditions: const ['pregnancy'],
        thresholdRules: const [_pregnancyCaffeineRule],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.isIncomplete, isTrue);
      expect(alerts.single.totalValue, 160);
      expect(alerts.single.thresholdValue, 200);
    });

    test('does not convert unsupported units like IU into mass units', () {
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Retinol IU',
          ingredients: [
            {'standard_name': 'Vitamin A', 'quantity': 3000, 'unit': 'IU'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'b',
          productName: 'Vitamin A RAE',
          ingredients: [
            {'standard_name': 'Vitamin A', 'quantity': 900, 'unit': 'mcg RAE'},
          ],
        ),
      ]);

      expect(totals['vitamin_a']?.totalValue, 3000);
      expect(totals['vitamin_a']?.unit, 'iu');
      expect(totals['vitamin_a']?.hasExcludedContributions, isTrue);
      expect(
        totals['vitamin_a']?.excludedContributions.single.reason,
        StackDoseExclusionReason.unitConflict,
      );
    });

    test('skips missing, NP, and pipeline-skipped rows', () {
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Dirty Rows',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': ''},
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'NP'},
            {
              'standard_name': 'Caffeine',
              'quantity': 80,
              'unit': 'mg',
              'skip_ul_check': true,
            },
          ],
        ),
      ]);

      expect(totals['caffeine']?.totalValue, 0);
      expect(totals['caffeine']?.excludedContributions, hasLength(3));
    });

    test('flags cumulative condition thresholds across products', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Energy A',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'b',
          productName: 'Energy B',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'c',
          productName: 'Energy C',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['pregnancy'],
        thresholdRules: const [_pregnancyCaffeineRule],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.conditionId, 'pregnancy');
      expect(alerts.single.canonicalId, 'caffeine');
      expect(alerts.single.totalValue, 240);
      expect(alerts.single.thresholdValue, 200);
    });

    test('does not flag positive condition-threshold entries', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'd',
          productName: 'Vitamin D',
          ingredients: [
            {'standard_name': 'Vitamin D', 'quantity': 5000, 'unit': 'IU'},
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['pregnancy'],
        thresholdRules: const [],
      );

      expect(alerts, isEmpty);
    });

    test('sums split EPA and DHA rows for omega-3 threshold alerts', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'fish-oil-a',
          productName: 'Fish Oil A',
          ingredients: [
            {'standard_name': 'EPA', 'quantity': 1200, 'unit': 'mg'},
            {'standard_name': 'DHA', 'quantity': 800, 'unit': 'mg'},
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'fish-oil-b',
          productName: 'Fish Oil B',
          ingredients: [
            {'standard_name': 'EPA', 'quantity': 700, 'unit': 'mg'},
            {'standard_name': 'DHA', 'quantity': 400, 'unit': 'mg'},
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['bleeding_disorders'],
        thresholdRules: const [_bleedingOmegaRule],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.canonicalId, 'omega_3');
      expect(alerts.single.displayName, 'Omega-3 (EPA/DHA)');
      expect(alerts.single.totalValue, 3100);
      expect(alerts.single.thresholdValue, 3000);
      expect(alerts.single.contributions, hasLength(4));
    });

    test(
      'prefers EPA plus DHA over fish oil parent mass for omega thresholds',
      () {
        const summer = StackDoseSummer();
        final totals = summer.sum([
          const StackItemNutrients(
            stackEntryId: 'fish-oil',
            productName: 'Fish Oil',
            ingredients: [
              {'standard_name': 'Fish Oil', 'quantity': 2500, 'unit': 'mg'},
              {'standard_name': 'EPA', 'quantity': 690, 'unit': 'mg'},
              {'standard_name': 'DHA', 'quantity': 310, 'unit': 'mg'},
            ],
          ),
        ]);

        final alerts = summer.thresholdAlerts(
          totals: totals,
          userConditions: const ['surgery_scheduled'],
          thresholdRules: const [_surgeryOmegaRule],
        );

        expect(
          alerts,
          isEmpty,
          reason:
              'EPA + DHA is 1000 mg; fish-oil parent mass must not be added.',
        );
      },
    );

    test('uses total omega-3 fallback when EPA and DHA are absent', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'fish-oil',
          productName: 'Fish Oil',
          ingredients: [
            {'standard_name': 'Fish Oil', 'quantity': 4000, 'unit': 'mg'},
            {'standard_name': 'Omega-3', 'quantity': 3200, 'unit': 'mg'},
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['surgery_scheduled'],
        thresholdRules: const [_surgeryOmegaRule],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.canonicalId, 'omega_3');
      expect(alerts.single.totalValue, 3200);
      expect(alerts.single.contributions, hasLength(1));
    });
  });
}
