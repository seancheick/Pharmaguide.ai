import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';

/// Minimal timing_rules.json for testing — 6 rules covering each rule type.
final _testTimingRulesJson = {
  '_metadata': {'schema_version': '5.1.0', 'total_entries': 7},
  'timing_rules': [
    {
      'id': 'timing_iron_calcium_separate',
      'ingredient1': 'iron',
      'ingredient2': 'calcium',
      'rule_type': 'separate',
      'advice': 'Take iron and calcium at least 2 hours apart.',
      'mechanism': 'Calcium inhibits iron absorption.',
      'separation_hours': 2,
      'score_impact': -2,
      'evidence_level': 'established',
      'sources': [
        {
          'source_type': 'pubmed',
          'url': 'https://pubmed.ncbi.nlm.nih.gov/1984335/',
        },
      ],
    },
    {
      'id': 'timing_iron_vitamin_c_together',
      'ingredient1': 'iron',
      'ingredient2': 'vitamin c',
      'rule_type': 'take_together',
      'advice': 'Take iron with vitamin C to enhance absorption.',
      'mechanism': 'Vitamin C reduces Fe3+ to Fe2+.',
      'separation_hours': null,
      'score_impact': 0,
      'evidence_level': 'established',
      'sources': <Map<String, String>>[],
    },
    {
      'id': 'timing_coq10_with_food',
      'ingredient1': 'coq10',
      'ingredient2': 'dietary fat',
      'rule_type': 'take_with_food',
      'advice': 'Take CoQ10 with a meal containing fat.',
      'mechanism': 'Lipophilic compound needs micellar transport.',
      'separation_hours': null,
      'score_impact': -1,
      'evidence_level': 'established',
      'sources': <Map<String, String>>[],
    },
    {
      'id': 'timing_iron_empty_stomach',
      'ingredient1': 'iron',
      'ingredient2': 'food',
      'rule_type': 'take_on_empty_stomach',
      'advice': 'Take iron on an empty stomach for best absorption.',
      'mechanism': 'Food reduces non-heme iron absorption.',
      'separation_hours': null,
      'score_impact': -1,
      'evidence_level': 'established',
      'sources': <Map<String, String>>[],
    },
    {
      'id': 'timing_thyroid_med_iron_separate',
      'ingredient1': 'levothyroxine',
      'ingredient1_rxcuis': ['10582'],
      'ingredient2': 'iron',
      'rule_type': 'separate',
      'advice': 'Take levothyroxine at least 4 hours apart from iron.',
      'mechanism': 'Iron forms insoluble complexes with levothyroxine.',
      'separation_hours': 4,
      'score_impact': -2,
      'evidence_level': 'established',
      'sources': <Map<String, String>>[],
    },
    {
      'id': 'timing_magnesium_evening',
      'ingredient1': 'magnesium',
      'ingredient2': 'sleep',
      'rule_type': 'time_of_day',
      'advice': 'Consider taking magnesium in the evening.',
      'mechanism': 'May support sleep quality.',
      'separation_hours': null,
      'score_impact': 0,
      'evidence_level': 'possible',
      'sources': <Map<String, String>>[],
    },
    {
      'id': 'timing_psyllium_water_med_spacing',
      'ingredient1': 'psyllium',
      'ingredient2': 'medications',
      'rule_type': 'separate',
      'advice':
          'Mix psyllium with at least 8 oz of liquid, and take other medications at least 3 hours away.',
      'mechanism':
          'Bulk-forming psyllium can swell and delay absorption of some medications.',
      'separation_hours': 3,
      'score_impact': -1,
      'evidence_level': 'established',
      'sources': <Map<String, String>>[],
    },
  ],
};

void main() {
  group('TimingEvaluationService', () {
    late TimingEvaluationService service;

    setUp(() {
      service = TimingEvaluationService.fromJson(_testTimingRulesJson);
    });

    test('parses rules from JSON', () {
      expect(service.ruleCount, 7);
    });

    group('supplement × supplement matching', () {
      test('fires separation rule when both ingredients in stack', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
            'Calcium Citrate': {'calcium'},
          },
          medicationNames: [],
        );

        final ironCalcium = results
            .where((r) => r.ruleId == 'timing_iron_calcium_separate')
            .toList();
        expect(ironCalcium, hasLength(1));
        expect(ironCalcium.first.ruleType, TimingRuleType.separate);
        expect(ironCalcium.first.separationHours, 2);
        expect(ironCalcium.first.product1Name, isNotNull);
        expect(ironCalcium.first.product2Name, isNotNull);
      });

      test('fires take_together rule when both ingredients in stack', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
            'Vitamin C': {'vitamin_c'},
          },
          medicationNames: [],
        );

        final ironVitC = results
            .where((r) => r.ruleId == 'timing_iron_vitamin_c_together')
            .toList();
        expect(ironVitC, hasLength(1));
        expect(ironVitC.first.ruleType, TimingRuleType.takeTogether);
      });

      test('does NOT fire when only one side of the pair is in stack', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
          },
          medicationNames: [],
        );

        final ironCalcium = results
            .where((r) => r.ruleId == 'timing_iron_calcium_separate')
            .toList();
        expect(ironCalcium, isEmpty);
      });

      test('fires single-ingredient rules (food context)', () {
        final results = service.evaluateStack(
          supplementTags: {
            'CoQ10 200mg': {'coq10'},
          },
          medicationNames: [],
        );

        final coq10 = results
            .where((r) => r.ruleId == 'timing_coq10_with_food')
            .toList();
        expect(coq10, hasLength(1));
        expect(coq10.first.ruleType, TimingRuleType.takeWithFood);
      });

      test('fires time_of_day rules for magnesium', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Magnesium Glycinate': {'magnesium'},
          },
          medicationNames: [],
        );

        final mag = results
            .where((r) => r.ruleId == 'timing_magnesium_evening')
            .toList();
        expect(mag, hasLength(1));
        expect(mag.first.ruleType, TimingRuleType.timeOfDay);
      });

      test(
        'does not fire psyllium medication spacing without a medication',
        () {
          final results = service.evaluateStack(
            supplementTags: {
              'Psyllium Husk': {'psyllium'},
            },
            medicationNames: [],
          );

          final psyllium = results
              .where((r) => r.ruleId == 'timing_psyllium_water_med_spacing')
              .toList();
          expect(psyllium, isEmpty);
        },
      );

      test(
        'fires psyllium medication spacing when a medication is present',
        () {
          final results = service.evaluateStack(
            supplementTags: {
              'Psyllium Husk': {'psyllium'},
            },
            medicationNames: ['Metformin'],
            medicationRxCuisByName: {
              'Metformin': {'6809'},
            },
          );

          final psyllium = results
              .where((r) => r.ruleId == 'timing_psyllium_water_med_spacing')
              .toList();
          expect(psyllium, hasLength(1));
          expect(psyllium.first.ruleType, TimingRuleType.separate);
          expect(psyllium.first.separationHours, 3);
          expect(psyllium.first.product1Name, 'Psyllium Husk');
          expect(psyllium.first.product2Name, isNull);
        },
      );
    });

    group('medication × supplement matching', () {
      test('fires levothyroxine + iron separation rule', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
          },
          medicationNames: ['Levothyroxine 50mcg'],
          medicationRxCuisByName: {
            'Levothyroxine 50mcg': {'10582'},
          },
        );

        final thyroidIron = results
            .where((r) => r.ruleId == 'timing_thyroid_med_iron_separate')
            .toList();
        expect(thyroidIron, hasLength(1));
        expect(thyroidIron.first.separationHours, 4);
        expect(thyroidIron.first.product1Name, 'Levothyroxine 50mcg');
        expect(thyroidIron.first.product2Name, 'Iron Supplement');
      });

      test('matches a brand through its normalized generic RxCUI', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
          },
          medicationNames: ['Unithroid 100mcg'],
          medicationRxCuisByName: {
            'Unithroid 100mcg': {'890003', '10582'},
          },
        );

        final thyroidIron = results
            .where((r) => r.ruleId == 'timing_thyroid_med_iron_separate')
            .toList();
        expect(thyroidIron, hasLength(1));
      });

      test('does not infer medication identity from a display name', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
          },
          medicationNames: ['Synthroid 100mcg'],
        );

        expect(
          results.where((r) => r.ruleId == 'timing_thyroid_med_iron_separate'),
          isEmpty,
        );
      });

      test('does NOT fire medication rule when medication not in stack', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
          },
          medicationNames: ['Metformin 500mg'],
        );

        final thyroidIron = results
            .where((r) => r.ruleId == 'timing_thyroid_med_iron_separate')
            .toList();
        expect(thyroidIron, isEmpty);
      });
    });

    group('deduplication', () {
      test(
        'each rule fires at most once even with multiple matching products',
        () {
          final results = service.evaluateStack(
            supplementTags: {
              'Iron Bisglycinate': {'iron'},
              'Ferrous Sulfate': {'iron'},
              'Calcium Citrate': {'calcium'},
              'Calcium Carbonate': {'calcium'},
            },
            medicationNames: [],
          );

          final ironCalcium = results
              .where((r) => r.ruleId == 'timing_iron_calcium_separate')
              .toList();
          expect(
            ironCalcium,
            hasLength(1),
            reason: 'Same rule should not fire multiple times',
          );
        },
      );
    });

    group('priority ordering', () {
      test('medication separations sort before supplement separations', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
            'Calcium Citrate': {'calcium'},
          },
          medicationNames: ['Levothyroxine 50mcg'],
          medicationRxCuisByName: {
            'Levothyroxine 50mcg': {'10582'},
          },
        );

        // Should have at least: thyroid+iron (med), iron+calcium (supp)
        expect(results.length, greaterThanOrEqualTo(2));

        // First result should be the medication interaction (higher priority).
        final first = results.first;
        expect(
          first.ruleId,
          'timing_thyroid_med_iron_separate',
          reason: 'Medication interaction should sort first',
        );
      });
    });

    group('evidence level mapping', () {
      test('maps established correctly', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Iron Supplement': {'iron'},
            'Calcium Citrate': {'calcium'},
          },
          medicationNames: [],
        );

        final ironCalcium = results.firstWhere(
          (r) => r.ruleId == 'timing_iron_calcium_separate',
        );
        expect(ironCalcium.evidenceLevel, EvidenceLevel.established);
      });

      test('maps possible to theoretical', () {
        final results = service.evaluateStack(
          supplementTags: {
            'Magnesium Glycinate': {'magnesium'},
          },
          medicationNames: [],
        );

        final mag = results.firstWhere(
          (r) => r.ruleId == 'timing_magnesium_evening',
        );
        expect(mag.evidenceLevel, EvidenceLevel.theoretical);
      });
    });

    group('empty stack', () {
      test('returns empty list for empty supplement stack', () {
        final results = service.evaluateStack(
          supplementTags: {},
          medicationNames: [],
        );
        expect(results, isEmpty);
      });

      test(
        'returns empty list for medications-only stack with no matching rules',
        () {
          final results = service.evaluateStack(
            supplementTags: {},
            medicationNames: ['Metformin 500mg'],
          );
          expect(results, isEmpty);
        },
      );
    });

    group('large stack performance', () {
      test('handles 50+ item stack without timeout', () {
        final largeSuppTags = <String, Set<String>>{};
        final nutrients = [
          'iron',
          'calcium',
          'magnesium',
          'zinc',
          'vitamin_c',
          'vitamin_d',
          'vitamin_e',
          'vitamin_k',
          'coq10',
          'omega_3',
        ];
        for (var i = 0; i < 50; i++) {
          largeSuppTags['Product $i'] = {nutrients[i % nutrients.length]};
        }

        final stopwatch = Stopwatch()..start();
        final results = service.evaluateStack(
          supplementTags: largeSuppTags,
          medicationNames: ['Levothyroxine 50mcg', 'Warfarin 5mg'],
        );
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(100),
          reason: 'Timing evaluation should complete in <100ms',
        );
        expect(results, isNotEmpty);
      });
    });

    group('same-product suppression + semantic dedup', () {
      final rulesJson = {
        'timing_rules': [
          {
            'id': 'vitd_vitk_together',
            'ingredient1': 'vitamin d',
            'ingredient2': 'vitamin k',
            'rule_type': 'take_together',
            'advice': 'Take vitamin D and K together.',
            'separation_hours': null,
            'score_impact': 1,
            'evidence_level': 'established',
            'sources': <Map<String, String>>[],
          },
          {
            'id': 'iron_calcium_separate',
            'ingredient1': 'iron',
            'ingredient2': 'calcium',
            'rule_type': 'separate',
            'advice': 'Take iron and calcium 2h apart.',
            'separation_hours': 2,
            'score_impact': -2,
            'evidence_level': 'established',
            'sources': <Map<String, String>>[],
          },
          {
            'id': 'vitd_food',
            'ingredient1': 'vitamin d',
            'ingredient2': 'dietary fat',
            'rule_type': 'take_with_food',
            'advice': 'Take vitamin D with a fatty meal.',
            'separation_hours': null,
            'score_impact': -1,
            'evidence_level': 'established',
            'sources': <Map<String, String>>[],
          },
          {
            'id': 'vitk_food',
            'ingredient1': 'vitamin k',
            'ingredient2': 'dietary fat',
            'rule_type': 'take_with_food',
            'advice': 'Take vitamin K with a fatty meal.',
            'separation_hours': null,
            'score_impact': -1,
            'evidence_level': 'established',
            'sources': <Map<String, String>>[],
          },
        ],
      };
      late TimingEvaluationService svc;
      setUp(() => svc = TimingEvaluationService.fromJson(rulesJson));

      test(
        'suppresses take_together when both ingredients are one product',
        () {
          // Calcium K/D carries vitamin D and K in the SAME pill — the
          // "Take X with X" self-pairing bug.
          final results = svc.evaluateStack(
            supplementTags: {
              'Calcium K/D': {'vitamin_d', 'vitamin_k'},
            },
            medicationNames: [],
          );
          expect(
            results.where((r) => r.ruleId == 'vitd_vitk_together'),
            isEmpty,
            reason: 'a co-formulated pair is already taken together — no tip',
          );
        },
      );

      test('still fires take_together across two different products', () {
        final results = svc.evaluateStack(
          supplementTags: {
            'Vitamin D3': {'vitamin_d'},
            'Vitamin K2': {'vitamin_k'},
          },
          medicationNames: [],
        );
        final hit = results
            .where((r) => r.ruleId == 'vitd_vitk_together')
            .toList();
        expect(hit, hasLength(1));
        expect(hit.first.product1Name, isNot(hit.first.product2Name));
      });

      test('suppresses separate when both minerals are one product', () {
        final results = svc.evaluateStack(
          supplementTags: {
            'Multivitamin': {'iron', 'calcium'},
          },
          medicationNames: [],
        );
        expect(
          results.where((r) => r.ruleId == 'iron_calcium_separate'),
          isEmpty,
          reason: "ingredients in one pill can't be separated",
        );
      });

      test(
        'uses a different product pair when one product contains both sides',
        () {
          final results = svc.evaluateStack(
            supplementTags: {
              'Multivitamin': {'iron', 'calcium'},
              'Iron Solo': {'iron'},
            },
            medicationNames: [],
          );

          final hit = results
              .where((r) => r.ruleId == 'iron_calcium_separate')
              .single;
          expect(hit.product1Name, 'Iron Solo');
          expect(hit.product2Name, 'Multivitamin');
        },
      );

      test('collapses duplicate take-with-food tips for the same product', () {
        // Vitamin D and K each trip their own with-food rule, but the user
        // should be told to take THAT product with a meal only once.
        final results = svc.evaluateStack(
          supplementTags: {
            'Calcium K/D': {'vitamin_d', 'vitamin_k'},
          },
          medicationNames: [],
        );
        final withFood = results
            .where((r) => r.ruleType == TimingRuleType.takeWithFood)
            .toList();
        expect(withFood, hasLength(1));
        expect(withFood.first.product1Name, 'Calcium K/D');
      });

      test('keeps one actionable meal context when a single product contains '
          'ingredients with conflicting instructions', () {
        final conflicting = TimingEvaluationService.fromJson({
          'timing_rules': [
            {
              'id': 'ala_empty',
              'ingredient1': 'alpha-lipoic acid',
              'ingredient2': 'food',
              'rule_type': 'take_on_empty_stomach',
              'advice': 'Take alpha-lipoic acid on an empty stomach.',
              'score_impact': -1,
              'evidence_level': 'probable',
            },
            {
              'id': 'vitamin_a_with_fat',
              'ingredient1': 'vitamin a',
              'ingredient2': 'dietary fat',
              'rule_type': 'take_with_food',
              'advice': 'Take vitamin A with a meal containing fat.',
              'score_impact': -1,
              'evidence_level': 'established',
            },
          ],
        });

        final results = conflicting.evaluateStack(
          supplementTags: {
            'O.N.E. Multivitamin': {'alpha_lipoic_acid', 'vitamin_a'},
          },
          medicationNames: [],
        );

        final mealContext = results
            .where(
              (result) =>
                  result.ruleType == TimingRuleType.takeWithFood ||
                  result.ruleType == TimingRuleType.takeOnEmptyStomach,
            )
            .toList();
        expect(mealContext, hasLength(1));
        expect(mealContext.single.ruleType, TimingRuleType.takeWithFood);
        expect(mealContext.single.product1Name, 'O.N.E. Multivitamin');
      });
    });

    group('dose gating', () {
      final rulesJson = {
        'timing_rules': [
          {
            'id': 'timing_vitamin_e_vitamin_k_separate',
            'ingredient1': 'vitamin e',
            'ingredient2': 'vitamin k',
            'rule_type': 'separate',
            'advice': 'Space high-dose vitamin E from vitamin K.',
            'separation_hours': 2,
            'score_impact': -2,
            'evidence_level': 'established',
            'min_dose': {'ingredient': 'vitamin e', 'mg': 180},
            'sources': <Map<String, String>>[],
          },
        ],
      };
      late TimingEvaluationService svc;
      setUp(() => svc = TimingEvaluationService.fromJson(rulesJson));

      const both = {
        'O.N.E. Multivitamin': {'vitamin_e'},
        'Calcium K/D': {'vitamin_k'},
      };

      test('fires when the gated dose is at/above threshold', () {
        final results = svc.evaluateStack(
          supplementTags: both,
          medicationNames: [],
          ingredientDosesMg: {'vitamin_e': 180},
        );
        expect(
          results.where(
            (r) => r.ruleId == 'timing_vitamin_e_vitamin_k_separate',
          ),
          hasLength(1),
        );
      });

      test('suppressed when the gated dose is below threshold', () {
        final results = svc.evaluateStack(
          supplementTags: both,
          medicationNames: [],
          ingredientDosesMg: {'vitamin_e': 20},
        );
        expect(
          results.where(
            (r) => r.ruleId == 'timing_vitamin_e_vitamin_k_separate',
          ),
          isEmpty,
          reason: 'vitamin E 20mg is below the 180mg threshold',
        );
      });

      test('suppresses a dose-gated tip when the dose is unknown', () {
        final results = svc.evaluateStack(
          supplementTags: both,
          medicationNames: [],
          // no doses supplied
        );
        expect(
          results.where(
            (r) => r.ruleId == 'timing_vitamin_e_vitamin_k_separate',
          ),
          isEmpty,
          reason: 'dose-conditional copy must not display without a known dose',
        );
      });
    });

    test('calcium carbonate advice does not match generic calcium', () {
      final carbonate = TimingEvaluationService.fromJson({
        'timing_rules': [
          {
            'id': 'timing_calcium_carbonate_with_food',
            'ingredient1': 'calcium carbonate',
            'ingredient2': 'food',
            'rule_type': 'take_with_food',
            'advice': 'Take calcium carbonate with food.',
            'score_impact': 0,
            'evidence_level': 'established',
          },
        ],
      });

      final citrateResults = carbonate.evaluateStack(
        supplementTags: {
          'Calcium Citrate': {'calcium'},
        },
        medicationNames: [],
      );
      final carbonateResults = carbonate.evaluateStack(
        supplementTags: {
          'Calcium Carbonate': {'calcium', 'calcium_carbonate'},
        },
        medicationNames: [],
      );

      expect(citrateResults, isEmpty);
      expect(carbonateResults, hasLength(1));
    });

    test('rejects malformed timing rule payloads instead of defaulting', () {
      expect(
        () => TimingEvaluationService.fromJson({
          '_metadata': {'total_entries': 2},
          'timing_rules': [
            {
              'id': 'bad_rule',
              'ingredient1': 'iron',
              'ingredient2': 'calcium',
              'rule_type': 'renamed_type',
              'advice': 'This payload must fail closed.',
              'score_impact': -1,
              'evidence_level': 'established',
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('TimingRuleType', () {
    test('parses all rule types from string', () {
      expect(TimingRuleType.fromString('separate'), TimingRuleType.separate);
      expect(
        TimingRuleType.fromString('take_together'),
        TimingRuleType.takeTogether,
      );
      expect(
        TimingRuleType.fromString('take_with_food'),
        TimingRuleType.takeWithFood,
      );
      expect(
        TimingRuleType.fromString('take_on_empty_stomach'),
        TimingRuleType.takeOnEmptyStomach,
      );
      expect(
        TimingRuleType.fromString('time_of_day'),
        TimingRuleType.timeOfDay,
      );
    });

    test('rejects unknown type', () {
      expect(() => TimingRuleType.fromString('unknown'), throwsFormatException);
    });
  });

  group('TimingOptimization model', () {
    test('displayPriority ranks medication separations highest', () {
      const medSep = TimingOptimization(
        ruleId: 'test_med',
        ingredient1: 'levothyroxine',
        ingredient2: 'iron',
        advice: 'test',
        ruleType: TimingRuleType.separate,
        scoreImpact: -2,
        evidenceLevel: EvidenceLevel.established,
        product1Name: 'Synthroid',
        involvesMedication: true,
      );

      const suppSep = TimingOptimization(
        ruleId: 'test_supp',
        ingredient1: 'iron',
        ingredient2: 'calcium',
        advice: 'test',
        ruleType: TimingRuleType.separate,
        scoreImpact: -2,
        evidenceLevel: EvidenceLevel.established,
      );

      const foodRule = TimingOptimization(
        ruleId: 'test_food',
        ingredient1: 'coq10',
        ingredient2: 'food',
        advice: 'test',
        ruleType: TimingRuleType.takeWithFood,
        scoreImpact: -1,
        evidenceLevel: EvidenceLevel.established,
      );

      expect(medSep.displayPriority, greaterThan(suppSep.displayPriority));
      expect(suppSep.displayPriority, greaterThan(foodRule.displayPriority));
    });

    test('isSeparation returns true only for separate type', () {
      const sep = TimingOptimization(
        ruleId: 'test',
        ingredient1: 'a',
        ingredient2: 'b',
        advice: 'test',
        ruleType: TimingRuleType.separate,
        scoreImpact: 0,
        evidenceLevel: EvidenceLevel.established,
      );
      const food = TimingOptimization(
        ruleId: 'test',
        ingredient1: 'a',
        ingredient2: 'b',
        advice: 'test',
        ruleType: TimingRuleType.takeWithFood,
        scoreImpact: 0,
        evidenceLevel: EvidenceLevel.established,
      );

      expect(sep.isSeparation, isTrue);
      expect(food.isSeparation, isFalse);
    });

    test('involvesMedication comes from reviewed rule identity', () {
      const medFirst = TimingOptimization(
        ruleId: 'test_med_first',
        ingredient1: 'Levothyroxine',
        ingredient2: 'iron',
        advice: 'test',
        ruleType: TimingRuleType.separate,
        scoreImpact: -2,
        evidenceLevel: EvidenceLevel.established,
        involvesMedication: true,
      );
      const medSecond = TimingOptimization(
        ruleId: 'test_med_second',
        ingredient1: 'calcium',
        ingredient2: 'Warfarin',
        advice: 'test',
        ruleType: TimingRuleType.separate,
        scoreImpact: -2,
        evidenceLevel: EvidenceLevel.established,
        involvesMedication: true,
      );
      const suppOnly = TimingOptimization(
        ruleId: 'test_supp_only',
        ingredient1: 'iron',
        ingredient2: 'calcium',
        advice: 'test',
        ruleType: TimingRuleType.separate,
        scoreImpact: -2,
        evidenceLevel: EvidenceLevel.established,
      );

      expect(medFirst.involvesMedication, isTrue);
      expect(
        medSecond.involvesMedication,
        isTrue,
        reason: 'either RxCUI-authored side must count',
      );
      expect(suppOnly.involvesMedication, isFalse);
    });

    test('involvesMedication does not infer identity from display text', () {
      const med = TimingOptimization(
        ruleId: 'test_no_products',
        ingredient1: 'warfarin',
        ingredient2: 'vitamin k',
        advice: 'test',
        ruleType: TimingRuleType.separate,
        scoreImpact: -2,
        evidenceLevel: EvidenceLevel.established,
      );
      expect(med.involvesMedication, isFalse);
    });
  });
}
