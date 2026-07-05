// Regression tests for the pipeline `ul_gate_eligible` contract in the
// stack nutrient aggregator.
//
// THE BUG (medical-grade over-warn)
//
// A single-form mineral compound product — e.g. Magtein
// "Magnesium L-Threonate 2000 mg" with NO separate bare-elemental
// "Magnesium" sibling row — carries the full 2000 mg COMPOUND mass on one
// row canonicalized to `magnesium`. The elemental-vs-compound dedup
// (`_compoundDuplicateRows`) only fires when an elemental SIBLING exists,
// so it misses the lone compound row. The client then compares 2000 mg of
// compound to the 350 mg ELEMENTAL magnesium UL → false 571% "exceeds UL".
//
// The pipeline now flags these rows with `ul_gate_eligible: false`
// (reason `compound_mass_not_elemental`). The aggregator must honor that
// decision and exclude the compound mass from the UL recompute, exactly
// as it already excludes an elemental-sibling compound duplicate.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

void main() {
  const aggregator = StackNutrientAggregator();

  group('StackNutrientAggregator — ul_gate_eligible exclusion', () {
    test('Magtein-alone (ul_gate_eligible:false, no elemental sibling) is '
        'excluded from the sum, not counted at compound mass', () {
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Magtein',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium L-Threonate',
              'quantity': 2000,
              'unit': 'mg',
              'ul_gate_eligible': false,
              'ul_gate_ineligible_reason': 'compound_mass_not_elemental',
            },
          ],
        ),
      ];

      final total = aggregator.aggregate(stack)['magnesium']!;

      // The compound mass must NOT sum into the elemental-comparable total.
      expect(total.totalAmount, 0);
      expect(total.contributions, isEmpty);
      // Excluded, but still surfaced so the UI can trace the product.
      expect(total.excludedContributions, hasLength(1));
      expect(
        total.excludedContributions.single.reason,
        NutrientExclusionReason.compoundFormDuplicate,
      );
      expect(total.excludedContributions.single.contribution.amount, 2000);
      // It is NOT a unit conflict — must not raise that UI flag.
      expect(total.hasUnitConflict, isFalse);
    });

    test('ul_gate_eligible:true rows are summed normally (contract is opt-out '
        'only, dual-read safe)', () {
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Chelated Mag',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium',
              'quantity': 200,
              'unit': 'mg',
              'ul_gate_eligible': true,
            },
          ],
        ),
      ];

      final total = aggregator.aggregate(stack)['magnesium']!;
      expect(total.totalAmount, 200);
      expect(total.contributions, hasLength(1));
      expect(total.excludedContributions, isEmpty);
    });

    test('absent ul_gate_eligible field leaves legacy behavior unchanged', () {
      // Catalogs built before the field existed must still sum.
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Legacy Mag',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium',
              'quantity': 200,
              'unit': 'mg',
            },
          ],
        ),
      ];
      expect(aggregator.aggregate(stack)['magnesium']!.totalAmount, 200);
    });

    test('an eligible sibling still sums even when a co-listed compound row '
        'is gated out', () {
      // Elemental 60 mg row (eligible) + compound 2000 mg row (gated out):
      // only the elemental row counts.
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Mixed Mag',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium',
              'quantity': 60,
              'unit': 'mg',
            },
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium L-Threonate',
              'quantity': 2000,
              'unit': 'mg',
              'ul_gate_eligible': false,
            },
          ],
        ),
      ];
      final total = aggregator.aggregate(stack)['magnesium']!;
      expect(total.totalAmount, 60);
      expect(total.contributions, hasLength(1));
      expect(total.excludedContributions, hasLength(1));
    });
  });
}
