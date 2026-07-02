import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

void main() {
  group('StackDoseSummer', () {
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
      );

      expect(alerts, hasLength(1));
      expect(alerts.single.canonicalId, 'omega_3');
      expect(alerts.single.totalValue, 3200);
      expect(alerts.single.contributions, hasLength(1));
    });
  });
}
