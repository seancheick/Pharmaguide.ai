// Tests for the client PREFERRING the pipeline's UL verdict over its own
// recompute in [StackUlChecker], plus the aggregator helper that extracts
// those verdicts ([StackNutrientAggregator.extractPipelineUlVerdicts]).
//
// The pipeline resolves elemental-vs-compound mass and form-aware unit
// conversions the client cannot reconstruct from raw blob quantities. When
// a row carries `over_ul` / `pct_ul` (and was gate-eligible), that verdict
// is authoritative for the UL tier; the raw quantity / reference recompute
// is only a fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

void main() {
  const checker = StackUlChecker(rdaData: _rda);

  group('StackUlChecker — prefers pipeline UL verdict', () {
    test('over_ul:true forces exceedsUl even when recompute is far under', () {
      final statuses = checker.check(
        {'magnesium': _total('magnesium', 100, 'mg')},
        ageBracket: '19-30',
        sex: 'Male',
        pipelineVerdicts: const {
          'magnesium': PipelineUlVerdict(overUl: true, pctUl: 200),
        },
      );
      expect(statuses.single.tier, NutrientTier.exceedsUl);
      expect(statuses.single.shouldWarn, isTrue);
    });

    test('pct_ul>=150 (no over_ul) forces exceedsUl', () {
      final statuses = checker.check(
        {'magnesium': _total('magnesium', 100, 'mg')},
        ageBracket: '19-30',
        sex: 'Male',
        pipelineVerdicts: const {'magnesium': PipelineUlVerdict(pctUl: 150)},
      );
      expect(statuses.single.tier, NutrientTier.exceedsUl);
    });

    test('over_ul:false suppresses a recompute that would exceed', () {
      final statuses = checker.check(
        {'magnesium': _total('magnesium', 2000, 'mg')},
        ageBracket: '19-30',
        sex: 'Male',
        pipelineVerdicts: const {'magnesium': PipelineUlVerdict(overUl: false)},
      );
      expect(statuses.single.tier, isNot(NutrientTier.exceedsUl));
      expect(statuses.single.tier, isNot(NutrientTier.approachingUl));
      expect(statuses.single.warning, isNull);
    });

    test('no verdict falls back to recompute (2000 mg → exceedsUl)', () {
      final statuses = checker.check(
        {'magnesium': _total('magnesium', 2000, 'mg')},
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(statuses.single.tier, NutrientTier.exceedsUl);
    });

    test('a non-definitive verdict (all null) falls back to recompute', () {
      final statuses = checker.check(
        {'magnesium': _total('magnesium', 2000, 'mg')},
        ageBracket: '19-30',
        sex: 'Male',
        pipelineVerdicts: const {'magnesium': PipelineUlVerdict()},
      );
      expect(statuses.single.tier, NutrientTier.exceedsUl);
    });
  });

  group('StackNutrientAggregator.extractPipelineUlVerdicts', () {
    const aggregator = StackNutrientAggregator();

    test('gate-ineligible rows contribute NO verdict', () {
      final verdicts = aggregator.extractPipelineUlVerdicts([
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
              'over_ul': false,
            },
          ],
        ),
      ]);
      expect(verdicts, isEmpty);
    });

    test('reads over_ul / pct_ul from an eligible row', () {
      final verdicts = aggregator.extractPipelineUlVerdicts([
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Niacin',
          ingredients: [
            {
              'canonical_id': 'niacin',
              'name': 'Niacin',
              'quantity': 50,
              'unit': 'mg',
              'over_ul': true,
              'pct_ul': 142.9,
            },
          ],
        ),
      ]);
      expect(verdicts.keys, contains('niacin'));
      expect(verdicts['niacin']!.overUl, isTrue);
      expect(verdicts['niacin']!.pctUl, 142.9);
      expect(verdicts['niacin']!.exceedsUl, isTrue);
    });

    test('rows without any structured decision produce no verdict', () {
      final verdicts = aggregator.extractPipelineUlVerdicts([
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Plain',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium',
              'quantity': 200,
              'unit': 'mg',
            },
          ],
        ),
      ]);
      expect(verdicts, isEmpty);
    });

    test('the most severe verdict wins across duplicate rows', () {
      final verdicts = aggregator.extractPipelineUlVerdicts([
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'A',
          ingredients: [
            {
              'canonical_id': 'zinc',
              'name': 'Zinc',
              'quantity': 5,
              'unit': 'mg',
              'over_ul': false,
              'pct_ul': 40,
            },
            {
              'canonical_id': 'zinc',
              'name': 'Zinc',
              'quantity': 45,
              'unit': 'mg',
              'over_ul': true,
              'pct_ul': 160,
            },
          ],
        ),
      ]);
      expect(verdicts['zinc']!.overUl, isTrue);
      expect(verdicts['zinc']!.pctUl, 160);
      expect(verdicts['zinc']!.exceedsUl, isTrue);
    });

    test('skip_ul_check rows contribute no verdict', () {
      final verdicts = aggregator.extractPipelineUlVerdicts([
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'A',
          ingredients: [
            {
              'canonical_id': 'vitamin_a',
              'name': 'Vitamin A',
              'quantity': 25000,
              'unit': 'iu',
              'skip_ul_check': true,
              'over_ul': true,
            },
          ],
        ),
      ]);
      expect(verdicts, isEmpty);
    });
  });

  group('PipelineUlVerdict.exceedsUl', () {
    test('over_ul boolean gate is authoritative', () {
      expect(const PipelineUlVerdict(overUl: true).exceedsUl, isTrue);
      expect(const PipelineUlVerdict(overUl: false).exceedsUl, isFalse);
      // over_ul:false wins even against a high pct_ul (contradictory data).
      expect(
        const PipelineUlVerdict(overUl: false, pctUl: 999).exceedsUl,
        isFalse,
      );
    });

    test('pct_ul>=150 exceeds only when over_ul is absent', () {
      expect(const PipelineUlVerdict(pctUl: 150).exceedsUl, isTrue);
      expect(const PipelineUlVerdict(pctUl: 149.9).exceedsUl, isFalse);
    });

    test('empty verdict is not definitive', () {
      expect(const PipelineUlVerdict().isDefinitive, isFalse);
      expect(const PipelineUlVerdict(overUl: false).isDefinitive, isTrue);
      expect(const PipelineUlVerdict(pctUl: 10).isDefinitive, isTrue);
    });
  });
}

NutrientTotal _total(String id, double amt, String unit) => NutrientTotal(
  canonicalId: id,
  displayName: id,
  totalAmount: amt,
  unit: unit,
  contributions: const [],
);

const _rda = {
  'nutrient_recommendations': [
    {
      'id': 'magnesium',
      'standard_name': 'Magnesium',
      'unit': 'mg',
      'highest_ul': 350,
      'data': [
        {'group': 'Male', 'age_range': '19-30', 'rda_ai': 400, 'ul': 350},
        {'group': 'Female', 'age_range': '19-30', 'rda_ai': 310, 'ul': 350},
      ],
    },
  ],
};
