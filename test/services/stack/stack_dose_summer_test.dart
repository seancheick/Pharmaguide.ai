import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/consumer_disposition.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart'
    show ClinicalSignal;
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
      expect(rules.single.clinicalSeverity, Severity.caution);
      expect(rules.single.consumerDispositionIfMet, ConsumerDisposition.review);
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
          clinicalSeverity: Severity.caution,
          consumerDispositionIfMet: ConsumerDisposition.review,
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
          clinicalSeverity: Severity.caution,
          consumerDispositionIfMet: ConsumerDisposition.review,
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
      expect(alerts.single.clinicalSeverity, Severity.caution);
      expect(alerts.single.consumerDisposition, ConsumerDisposition.review);
      expect(alerts.single.contributions, hasLength(2));
    });

    group('beta-carotene read against two lines', () {
      StackDoseThresholdRule row(
        String id,
        double threshold,
        double amount, {
        String canonicalId = 'beta_carotene',
      }) => StackDoseThresholdRule(
        conditionId: 'current_smoker',
        canonicalId: canonicalId,
        thresholdValue: threshold,
        thresholdUnit: 'mcg rae',
        normalizedDailyAmount: amount,
        normalizedDailyUnit: 'mcg rae',
        sourceStackEntryId: id,
        sourceProductName: id,
      );

      List<StackDoseThresholdAlert> read(List<StackDoseThresholdRule> rules) =>
          const StackDoseSummer().thresholdAlertsFromNormalizedRules(
            userConditions: const ['current_smoker'],
            thresholdRules: rules,
          );

      test('every alert states the whole stack', () {
        final alerts = read([
          row('a', 7500, 7500),
          row('a', 10000, 7500),
          row('b', 10000, 14280),
        ]);

        expect(alerts, hasLength(2));
        for (final alert in alerts) {
          expect(alert.totalValue, 21780, reason: '${alert.thresholdValue}');
          expect(alert.contributions.map((c) => c.stackEntryId).toSet(), {
            'a',
            'b',
          });
        }
      });

      test('a line that was not crossed stays silent', () {
        final alerts = read([
          row('a', 7500, 5000),
          row('a', 10000, 5000),
          row('b', 10000, 14280),
        ]);

        expect(alerts.map((a) => a.thresholdValue), [10000]);
        expect(alerts.single.totalValue, 19280);
      });

      test('another nutrient keeps each line to its own rows', () {
        final alerts = read([
          row('a', 7500, 7500, canonicalId: 'vitamin_b3_niacin'),
          row('b', 10000, 14280, canonicalId: 'vitamin_b3_niacin'),
        ]);

        expect(alerts.map((a) => a.totalValue), [7500, 14280]);
      });
    });

    test('mixed catalog policies still aggregate one rule conservatively', () {
      const rules = [
        StackDoseThresholdRule(
          conditionId: 'pregnancy',
          canonicalId: 'caffeine',
          thresholdValue: 200,
          thresholdUnit: 'mg',
          clinicalSeverity: Severity.caution,
          consumerDispositionIfMet: ConsumerDisposition.review,
          normalizedDailyAmount: 120,
          normalizedDailyUnit: 'mg',
          sourceStackEntryId: 'a',
          sourceProductName: 'Caffeine A',
        ),
        StackDoseThresholdRule(
          conditionId: 'pregnancy',
          canonicalId: 'caffeine',
          thresholdValue: 200,
          thresholdUnit: 'mg',
          clinicalSeverity: Severity.avoid,
          consumerDispositionIfMet: ConsumerDisposition.block,
          normalizedDailyAmount: 120,
          normalizedDailyUnit: 'mg',
          sourceStackEntryId: 'b',
          sourceProductName: 'Caffeine B',
        ),
      ];

      final alerts = const StackDoseSummer().thresholdAlertsFromNormalizedRules(
        userConditions: const ['pregnancy'],
        thresholdRules: rules,
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.totalValue, 240);
      expect(alerts.single.clinicalSeverity, Severity.avoid);
      expect(alerts.single.consumerDisposition, ConsumerDisposition.block);
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

    test('unknown normalized disposition fails visible as review', () {
      final rules = stackDoseThresholdRulesFromWarnings([
        const InteractionWarning(
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.established,
          title: 'Caffeine / pregnancy',
          mechanism: 'Dose-aware fixture.',
          management: 'Review cumulative dose.',
          conditionIds: ['pregnancy'],
          ingredientName: 'Caffeine',
          ingredientCanonicalId: 'caffeine',
          doseDecision: DoseDecision(
            evaluatedDailyAmount: 240,
            evaluatedUnit: 'mg',
            decisionRule: DoseDecisionRule(
              comparator: '>=',
              threshold: 200,
              thresholdUnit: 'mg',
              consumerDispositionIfMet: 'future_pipeline_value',
            ),
          ),
        ),
      ]);

      final alerts = const StackDoseSummer().thresholdAlertsFromNormalizedRules(
        userConditions: const ['pregnancy'],
        thresholdRules: rules,
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.consumerDisposition, ConsumerDisposition.review);
    });

    test('normalized good-to-know disposition remains visible', () {
      const rule = StackDoseThresholdRule(
        conditionId: 'pregnancy',
        canonicalId: 'caffeine',
        thresholdValue: 200,
        thresholdUnit: 'mg',
        consumerDispositionIfMet: ConsumerDisposition.goodToKnow,
        normalizedDailyAmount: 240,
        normalizedDailyUnit: 'mg',
      );

      final alerts = const StackDoseSummer().thresholdAlertsFromNormalizedRules(
        userConditions: const ['pregnancy'],
        thresholdRules: const [rule],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.consumerDisposition, ConsumerDisposition.goodToKnow);
    });

    test('unknown normalized comparator fails visible as incomplete', () {
      const rule = StackDoseThresholdRule(
        conditionId: 'pregnancy',
        canonicalId: 'caffeine',
        thresholdValue: 200,
        thresholdUnit: 'mg',
        comparator: 'future_comparator',
        normalizedDailyAmount: 240,
        normalizedDailyUnit: 'mg',
      );

      final alerts = const StackDoseSummer().thresholdAlertsFromNormalizedRules(
        userConditions: const ['pregnancy'],
        thresholdRules: const [rule],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.isIncomplete, isTrue);
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

    test('legacy stack comparison honors strict greater-than comparator', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Vitamin D',
          ingredients: [
            {'standard_name': 'Vitamin D', 'quantity': 4000, 'unit': 'IU'},
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['heart_disease'],
        thresholdRules: const [
          StackDoseThresholdRule(
            conditionId: 'heart_disease',
            canonicalId: 'vitamin_d',
            thresholdValue: 4000,
            thresholdUnit: 'IU',
            comparator: '>',
          ),
        ],
      );

      expect(alerts, isEmpty);
    });

    test('unknown legacy comparator fails visible as incomplete', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Caffeine',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 240, 'unit': 'mg'},
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['pregnancy'],
        thresholdRules: const [
          StackDoseThresholdRule(
            conditionId: 'pregnancy',
            canonicalId: 'caffeine',
            thresholdValue: 200,
            thresholdUnit: 'mg',
            comparator: 'future_comparator',
          ),
        ],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.isIncomplete, isTrue);
    });

    test('legacy alerts preserve authored severity and disposition', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Caffeine',
          ingredients: [
            {'standard_name': 'Caffeine', 'quantity': 240, 'unit': 'mg'},
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['pregnancy'],
        thresholdRules: const [
          StackDoseThresholdRule(
            conditionId: 'pregnancy',
            canonicalId: 'caffeine',
            thresholdValue: 200,
            thresholdUnit: 'mg',
            clinicalSeverity: Severity.avoid,
            consumerDispositionIfMet: ConsumerDisposition.block,
          ),
        ],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.clinicalSeverity, Severity.avoid);
      expect(alerts.single.consumerDisposition, ConsumerDisposition.block);
    });

    test('legacy alerts evaluate active medication classes', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Niacin',
          ingredients: [
            {
              'standard_name': 'Niacin',
              'canonical_id': 'vitamin_b3_niacin',
              'quantity': 1100,
              'unit': 'mg',
            },
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const [],
        userDrugClasses: const ['statins'],
        thresholdRules: const [
          StackDoseThresholdRule(
            conditionId: 'statins',
            targetType: 'drug_class',
            canonicalId: 'vitamin_b3_niacin',
            thresholdValue: 1000,
            thresholdUnit: 'mg',
          ),
        ],
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.targetType, 'drug_class');
      expect(alerts.single.conditionId, 'statins');
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

    test('a skipped parent and form of one material are not added', () {
      Map<String, dynamic> row(String path, double amount) => {
        'canonical_id': 'elderberry',
        'standard_name': 'Elderberry',
        'raw_source_path': path,
        'dose_role': 'declared_total',
        'skip_ul_check': true,
        'skip_ul_reason': 'not_ul_applicable',
        'ul_assessment_status': 'not_applicable',
        'per_day_min': amount,
        'per_day_max': amount,
        'converted_unit': 'mg',
      };

      // 293421: 50 mg extract with 3200 mg of raw herb nested under it.
      final totals = const StackDoseSummer().sum([
        StackItemNutrients(
          stackEntryId: 'a',
          productName: 'A',
          ingredients: [
            row('ingredientRows[6]', 50),
            row('ingredientRows[6].nestedRows[0]', 3200),
          ],
        ),
      ]);

      expect(totals['elderberry']?.contributions, isEmpty);
      expect(totals['elderberry']?.excludedContributions, hasLength(2));
      expect(
        totals['elderberry']?.excludedContributions.first.reason,
        StackDoseExclusionReason.skippedByPipeline,
      );
    });

    test('a skipped row the pipeline can read joins the total', () {
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Readable',
          ingredients: [
            {
              'standard_name': 'Caffeine',
              'dose_role': 'declared_total',
              'skip_ul_check': true,
              'ul_assessment_status': 'not_applicable',
              'per_day_min': 300.0,
              'per_day_max': 300.0,
              'converted_unit': 'mg',
            },
          ],
        ),
      ]);

      expect(totals['caffeine']?.totalValue, 300);
      expect(totals['caffeine']?.excludedContributions, isEmpty);
    });

    test('an indeterminate row stays out and marks the total', () {
      final totals = const StackDoseSummer().sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Unresolved',
          ingredients: [
            {
              'standard_name': 'Caffeine',
              'dose_role': 'declared_total',
              'skip_ul_check': true,
              'ul_assessment_status': 'indeterminate',
              'per_day_min': 300.0,
              'per_day_max': 300.0,
              'converted_unit': 'mg',
            },
          ],
        ),
      ]);

      expect(totals['caffeine']?.totalValue, 0);
      expect(totals['caffeine']?.excludedContributions, hasLength(1));
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

  group('cards for one rule on one product', () {
    const summer = StackDoseSummer();

    InteractionWarning card(
      num? amount, {
      String unreadDisposition = 'review',
    }) => InteractionWarning.fromJson({
      'type': 'interaction',
      'severity': 'caution',
      'title': 'Vitamin A / smokers',
      'ingredient_name': 'Vitamin A',
      'ingredient_canonical_id': 'beta_carotene',
      'condition_ids': ['current_smoker'],
      'dose_decision': {
        'clinical_severity': 'caution',
        'evaluation_status': amount == null
            ? 'amount_unknown'
            : 'below_threshold',
        'consumer_disposition': amount == null ? unreadDisposition : 'suppress',
        'evaluated_daily_amount': amount,
        'evaluated_unit': amount == null ? null : 'mcg rae',
        'decision_rule': {
          'threshold': 10000,
          'threshold_unit': 'mcg rae',
          'comparator': '>=',
          'consumer_disposition_if_met': 'review',
          'consumer_disposition_if_not_met': 'suppress',
        },
      },
    });

    List<StackDoseThresholdRule> rules(List<InteractionWarning> cards) =>
        stackDoseThresholdRulesFromWarnings(
          cards,
          stackEntryId: 'a',
          productName: 'A',
        );

    test('the card with an amount wins whichever comes first', () {
      for (final cards in [
        [card(null), card(4500)],
        [card(4500), card(null)],
      ]) {
        final result = rules(cards);

        expect(result, hasLength(1));
        expect(result.single.normalizedDailyAmount, 4500);
        expect(result.single.normalizedDailyUnit, 'mcg rae');
        expect(result.single.amountUnresolved, isTrue);
      }
    });

    test('of two amounts the larger stands, and nothing is unresolved', () {
      final result = rules([card(86), card(4500)]);

      expect(result.single.normalizedDailyAmount, 4500);
      expect(result.single.amountUnresolved, isFalse);
    });

    test('a card with no amount alone carries none and stays unresolved', () {
      final result = rules([card(null), card(null)]);

      expect(result.single.normalizedDailyAmount, isNull);
      expect(result.single.amountUnresolved, isTrue);
    });

    test('a numeric zero was read, so nothing is unresolved', () {
      for (final cards in [
        [card(0), card(4500)],
        [card(4500), card(0)],
        [card(0), card(0)],
      ]) {
        expect(rules(cards).single.amountUnresolved, isFalse);
      }
      expect(rules([card(0), card(4500)]).single.normalizedDailyAmount, 4500);
    });

    test('a card the pipeline suppressed adds nothing to the amount', () {
      final suppressed = card(null, unreadDisposition: 'suppress');

      expect(rules([suppressed]), isEmpty);
      expect(rules([suppressed, card(4500)]).single.amountUnresolved, isFalse);
    });

    test('220806 + 178431 stays 12,000 and keeps the unresolved mark', () {
      final alerts = summer.thresholdAlertsFromNormalizedRules(
        userConditions: const ['current_smoker'],
        thresholdRules: [
          ...stackDoseThresholdRulesFromWarnings(
            [card(null), card(4500)],
            stackEntryId: '220806',
            productName: 'A',
          ),
          ...stackDoseThresholdRulesFromWarnings(
            [card(7500)],
            stackEntryId: '178431',
            productName: 'B',
          ),
        ],
      );

      expect(alerts.single.totalValue, 12000);
      expect(alerts.single.contributions, hasLength(2));
      expect(alerts.single.isIncomplete, isTrue);
    });

    test('a whole mixed-carotenoid weight never counts as beta-carotene', () {
      const summer = StackDoseSummer();
      final totals = summer.sum([
        const StackItemNutrients(
          stackEntryId: 'a',
          productName: 'Blend',
          ingredients: [
            {
              'canonical_id': 'mixed_carotenoids',
              'standard_name': 'Mixed Carotenoids',
              'dose_role': 'declared_total',
              'per_day_min': 30000.0,
              'per_day_max': 30000.0,
              'converted_unit': 'mcg RAE',
            },
            {
              'canonical_id': 'carotenoid_blend',
              'standard_name': 'Proprietary Mixed Carotenoid Blend',
              'dose_role': 'declared_total',
              'per_day_min': 30000.0,
              'per_day_max': 30000.0,
              'converted_unit': 'mcg RAE',
            },
          ],
        ),
      ]);

      final alerts = summer.thresholdAlerts(
        totals: totals,
        userConditions: const ['current_smoker'],
        thresholdRules: const [
          StackDoseThresholdRule(
            conditionId: 'current_smoker',
            canonicalId: 'beta_carotene',
            thresholdValue: 7500,
            thresholdUnit: 'mcg rae',
          ),
        ],
      );

      expect(totals.containsKey('beta_carotene'), isFalse);
      expect(alerts, isEmpty);
    });

    test('with every amount read the alert is complete', () {
      final alerts = summer.thresholdAlertsFromNormalizedRules(
        userConditions: const ['current_smoker'],
        thresholdRules: [
          ...stackDoseThresholdRulesFromWarnings(
            [card(4500)],
            stackEntryId: 'a',
            productName: 'A',
          ),
          ...stackDoseThresholdRulesFromWarnings(
            [card(7500)],
            stackEntryId: 'b',
            productName: 'B',
          ),
        ],
      );

      expect(alerts.single.totalValue, 12000);
      expect(alerts.single.isIncomplete, isFalse);
    });
  });

  group('betaCaroteneStackCardAlert', () {
    const summer = StackDoseSummer();
    const riskFactors = [
      'asbestos_exposure',
      'current_smoker',
      'former_smoker',
    ];

    InteractionWarning doseCard({
      num? amount,
      String canonicalId = 'beta_carotene',
      num threshold = 10000,
      String comparator = '>=',
      List<String> conditionIds = riskFactors,
      List<String> requiredConditions = const [],
      String dispositionIfMet = 'review',
    }) => InteractionWarning.fromJson({
      'type': 'interaction',
      'severity': 'informational',
      'title': 'Vitamin A / dose',
      'ingredient_name': 'Vitamin A',
      'ingredient_canonical_id': canonicalId,
      'condition_ids': conditionIds,
      'profile_gate': {
        'gate_type': 'dose',
        'requires': {'conditions_any': requiredConditions},
        'dose': {'severity_if_met': 'caution'},
      },
      'dose_decision': {
        'clinical_severity': 'informational',
        'evaluation_status': amount == null
            ? 'amount_unknown'
            : 'below_threshold',
        'consumer_disposition': 'suppress',
        'evaluated_daily_amount': amount,
        'evaluated_unit': amount == null ? null : 'mcg rae',
        'threshold': threshold,
        'threshold_unit': 'mcg rae',
        'comparator': comparator,
        'decision_rule': {
          'threshold': threshold,
          'threshold_unit': 'mcg rae',
          'comparator': comparator,
          'consumer_disposition_if_met': dispositionIfMet,
          'consumer_disposition_if_not_met': 'suppress',
        },
      },
    });

    ({
      String stackEntryId,
      String productName,
      Iterable<InteractionWarning> warnings,
    })
    product(String id, List<InteractionWarning> warnings) =>
        (stackEntryId: id, productName: id, warnings: warnings);

    test('two products crossing 20 mg show the approved wording verbatim', () {
      final alert = summer.betaCaroteneStackCardAlert(
        userConditions: const [],
        products: [
          product('a', [doseCard(amount: 7500)]),
          product('b', [doseCard(amount: 7500)]),
        ],
      );

      expect(alert, isNotNull);
      expect(alert!.totalValue, 15000);
      expect(alert.clinicalSeverity, Severity.caution);
      expect(alert.consumerDisposition, ConsumerDisposition.review);
      expect(alert.isIncomplete, isFalse);
      expect(alert.contributions, hasLength(2));
      expect(
        ClinicalSignal.fromDoseThreshold(alert).body,
        'Your stack supplies 20 mg or more of beta-carotene a day. At similar '
        'doses it raised lung cancer risk in smokers, former smokers and '
        'asbestos-exposed workers. Ask your doctor if any apply to you.',
      );
    });

    group('a vitamin A row that reads only as a carotenoid mixture', () {
      // 293269 prints Beta-Carotene and Mixed Carotenoids with no fraction, and
      // 328639 prints Mixed Carotenoids. Both state vitamin A activity, not
      // beta-carotene mass, so neither figure can reach the 20 mg tier.
      Map<String, dynamic> row(num mcgRae) => {
        'canonical_id': 'vitamin_a',
        'standard_name': 'Vitamin A',
        'matched_form': 'beta-carotene from mixed carotenoids',
        'raw_source_path': 'ingredientRows[1]',
        'dose_role': 'declared_total',
        'skip_ul_check': true,
        'skip_ul_reason': 'beta_carotene_no_established_ul',
        'ul_assessment_status': 'not_applicable',
        'per_day_min': mcgRae,
        'per_day_max': mcgRae,
        'converted_unit': 'mcg RAE',
      };

      test('its activity figure is no beta-carotene total', () {
        final totals = summer.sum([
          for (final (id, mcgRae) in const [('293269', 7000), ('328639', 9000)])
            StackItemNutrients(
              stackEntryId: id,
              productName: id,
              ingredients: [row(mcgRae)],
            ),
        ]);

        expect(totals.containsKey('beta_carotene'), isFalse);
      });

      test('a card naming vitamin A adds nothing, however large', () {
        final alert = summer.betaCaroteneStackCardAlert(
          userConditions: const [],
          products: [
            product('293269', [
              doseCard(amount: 7000, canonicalId: 'vitamin_a'),
            ]),
            product('328639', [
              doseCard(amount: 9000, canonicalId: 'vitamin_a'),
            ]),
          ],
        );

        expect(alert, isNull);
      });

      test('a card with no usable amount makes no card and no figure', () {
        final alert = summer.betaCaroteneStackCardAlert(
          userConditions: const [],
          products: [
            product('293269', [doseCard()]),
            product('328639', [doseCard()]),
          ],
        );

        expect(alert, isNull);
      });
    });

    test('exactly 20 mg shows the card and just under it does not', () {
      expect(
        summer.betaCaroteneStackCardAlert(
          userConditions: const [],
          products: [
            product('a', [doseCard(amount: 6000)]),
            product('b', [doseCard(amount: 4000)]),
          ],
        ),
        isNotNull,
      );
      expect(
        summer.betaCaroteneStackCardAlert(
          userConditions: const [],
          products: [
            product('a', [doseCard(amount: 6000)]),
            product('b', [doseCard(amount: 3999)]),
          ],
        ),
        isNull,
      );
    });

    test(
      'any risk-factor id on the card withholds it; other conditions do not',
      () {
        final products = [
          product('a', [doseCard(amount: 15000)]),
        ];
        for (final riskFactor in riskFactors) {
          expect(
            summer.betaCaroteneStackCardAlert(
              userConditions: [riskFactor],
              products: products,
            ),
            isNull,
            reason: riskFactor,
          );
        }
        expect(
          summer.betaCaroteneStackCardAlert(
            userConditions: const ['pregnancy'],
            products: products,
          ),
          isNotNull,
        );
      },
    );

    test('one product counts one amount when both rules land on it', () {
      final alert = summer.betaCaroteneStackCardAlert(
        userConditions: const [],
        products: [
          product('a', [doseCard(amount: 4500), doseCard(amount: 1000)]),
          product('b', [doseCard(amount: 5000)]),
        ],
      );

      expect(alert, isNull);
    });

    test('an unread suppressed card adds nothing and leaves it complete', () {
      for (final cards in [
        [doseCard(amount: 4500), doseCard()],
        [doseCard(), doseCard(amount: 4500)],
      ]) {
        final alert = summer.betaCaroteneStackCardAlert(
          userConditions: const [],
          products: [
            product('a', cards),
            product('b', [doseCard(amount: 7500)]),
          ],
        );

        expect(alert, isNotNull);
        expect(alert!.totalValue, 12000);
        expect(alert.isIncomplete, isFalse);
        expect(
          ClinicalSignal.fromDoseThreshold(alert).body,
          kBetaCaroteneStackCardBody,
        );
      }
    });

    test('only unread amounts make no claim of 20 mg', () {
      expect(
        summer.betaCaroteneStackCardAlert(
          userConditions: const [],
          products: [
            product('a', [doseCard()]),
          ],
        ),
        isNull,
      );
    });

    test(
      'cards other than the every-viewer 20 mg beta-carotene tier are out',
      () {
        for (final card in [
          doseCard(amount: 15000, canonicalId: 'vitamin_a'),
          doseCard(amount: 15000, conditionIds: const []),
          doseCard(amount: 15000, threshold: 7500),
          doseCard(amount: 15000, requiredConditions: const ['current_smoker']),
          doseCard(amount: 15000, dispositionIfMet: 'suppress'),
        ]) {
          expect(
            summer.betaCaroteneStackCardAlert(
              userConditions: const [],
              products: [
                product('a', [card]),
              ],
            ),
            isNull,
          );
        }
      },
    );

    test(
      'a mixture read as zero adds nothing and leaves the card complete',
      () {
        final alert = summer.betaCaroteneStackCardAlert(
          userConditions: const [],
          products: [
            product('a', [doseCard(amount: 14280)]),
            product('b', [doseCard(amount: 0)]),
          ],
        );

        expect(alert, isNotNull);
        expect(alert!.totalValue, 14280);
        expect(alert.contributions.map((c) => c.productName), ['a']);
        expect(alert.isIncomplete, isFalse);
      },
    );

    test('an unknown comparator hedges instead of claiming 20 mg', () {
      final alert = summer.betaCaroteneStackCardAlert(
        userConditions: const [],
        products: [
          product('a', [doseCard(amount: 15000, comparator: '~')]),
        ],
      );

      expect(alert, isNotNull);
      expect(alert!.isIncomplete, isTrue);
      expect(alert.consumerBody, isNull);
    });
  });
}
