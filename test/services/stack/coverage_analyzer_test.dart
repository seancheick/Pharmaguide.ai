// Tests for CoverageAnalyzer — the pure Stack Gap Analysis service.
// Drives the analyzer directly with synthetic inputs; no database,
// no Riverpod.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/coverage_analyzer.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

CoverageProductInput product(
  String name,
  Set<String> goals, {
  Set<String> underdosed = const {},
  String? productRole,
  List<PriorityCoverageAnchor> prenatalCoverage = const [],
  List<PriorityCoverageAnchor> adultMultiCoverage = const [],
}) => CoverageProductInput(
  name: name,
  goalMatches: goals,
  goalMatchesUnderdosed: underdosed,
  productRole: productRole,
  prenatalCoverage: prenatalCoverage,
  adultMultiCoverage: adultMultiCoverage,
);

PriorityCoverageAnchor anchor(
  String id,
  String label,
  String status, {
  double? amount,
  String? unit,
  double? target,
}) => PriorityCoverageAnchor(
  nutrientId: id,
  nutrientName: label,
  status: status,
  productName: 'Basic Prenatal',
  amount: amount,
  unit: unit,
  target: target,
  targetUnit: unit,
);

DepletionMatch depletion({
  String drug = 'Metformin',
  String nutrient = 'Vitamin B12',
  String type = 'depletion',
  CoverageLevel coverage = CoverageLevel.none,
}) {
  return DepletionMatch(
    depletionId: 'dep-$drug-$nutrient',
    drugDisplayName: drug,
    drugClassId: 'class:test',
    nutrientName: nutrient,
    nutrientCanonicalId: nutrient.toLowerCase().replaceAll(' ', '_'),
    depletionType: type,
    severity: 'moderate',
    mechanism: 'test mechanism',
    recommendation: 'test recommendation',
    coverageLevel: coverage,
  );
}

NutrientStatus status({
  String name = 'Vitamin D',
  NutrientTier tier = NutrientTier.underFifty,
  double? pctOfRda = 42.0,
  bool hasUnitConflict = false,
  List<ExcludedNutrientContribution> excluded = const [],
}) {
  return NutrientStatus(
    total: NutrientTotal(
      canonicalId: name.toLowerCase().replaceAll(' ', '_'),
      displayName: name,
      totalAmount: 10,
      unit: 'mcg',
      contributions: const [],
      hasUnitConflict: hasUnitConflict,
      excludedContributions: excluded,
    ),
    tier: tier,
    pctOfRda: pctOfRda,
  );
}

const _excludedContribution = ExcludedNutrientContribution(
  contribution: NutrientContribution(
    stackEntryId: 'e1',
    productName: 'Mixed Units D3',
    amount: 400,
    unit: 'IU',
  ),
  reason: NutrientExclusionReason.unitConflict,
);

void main() {
  const analyzer = CoverageAnalyzer();

  group('SUPPORTED bucket', () {
    test('goal served by one product lists that product', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product('Magnesium Glycinate', {'GOAL_SLEEP_QUALITY'}),
          product('Fish Oil', {'GOAL_CARDIOVASCULAR_HEART_HEALTH'}),
        ],
      );
      expect(report.supported, hasLength(1));
      expect(report.supported.first.goalId, 'GOAL_SLEEP_QUALITY');
      expect(report.supported.first.goalLabel, 'Sleep Quality');
      expect(report.supported.first.productNames, ['Magnesium Glycinate']);
      expect(report.unaddressedGoals, isEmpty);
    });

    test('goal served by multiple products lists all of them', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_IMMUNE_SUPPORT'],
        products: [
          product('Vitamin C', {'GOAL_IMMUNE_SUPPORT'}),
          product('Zinc', {'GOAL_IMMUNE_SUPPORT'}),
        ],
      );
      expect(report.supported.single.productNames, ['Vitamin C', 'Zinc']);
    });
  });

  group('PARTIALLY SUPPORTED bucket', () {
    test('goal only in goalMatchesUnderdosed lands in partiallySupported', () {
      // The magnesium-only screenshot case: magnesium present but below the
      // effective stress dose → partially supported, NOT unaddressed.
      final report = analyzer.analyze(
        goals: const ['GOAL_REDUCE_STRESS_ANXIETY'],
        products: [
          product(
            'Magnesium Glycinate',
            const {},
            underdosed: {'GOAL_REDUCE_STRESS_ANXIETY'},
          ),
        ],
      );
      expect(report.partiallySupported, hasLength(1));
      expect(
        report.partiallySupported.first.goalId,
        'GOAL_REDUCE_STRESS_ANXIETY',
      );
      expect(report.partiallySupported.first.productNames, [
        'Magnesium Glycinate',
      ]);
      // Mutually exclusive with the other goal buckets.
      expect(report.supported, isEmpty);
      expect(report.unaddressedGoals, isEmpty);
    });

    test('partial-only product does not mark coverage incomplete', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_REDUCE_STRESS_ANXIETY'],
        products: [
          product(
            'Magnesium Glycinate',
            const {},
            underdosed: {'GOAL_REDUCE_STRESS_ANXIETY'},
          ),
        ],
      );

      expect(report.partiallySupported, hasLength(1));
      expect(
        report.coverageIncomplete,
        isFalse,
        reason:
            'goal_matches can be empty when goal_matches_underdosed is populated',
      );
    });

    test('full support wins when a goal is both supported and underdosed', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product('Strong Sleep Formula', {'GOAL_SLEEP_QUALITY'}),
          product(
            'Trace Magnesium',
            const {},
            underdosed: {'GOAL_SLEEP_QUALITY'},
          ),
        ],
      );
      expect(report.supported, hasLength(1));
      expect(report.partiallySupported, isEmpty);
      expect(report.unaddressedGoals, isEmpty);
    });

    test('no underdosed goals → empty partiallySupported', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product('Melatonin', {'GOAL_SLEEP_QUALITY'}),
        ],
      );
      expect(report.partiallySupported, isEmpty);
    });
  });

  group('UNADDRESSED bucket — goals', () {
    test('goal with no supporting product lands in unaddressedGoals', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_CARDIOVASCULAR_HEART_HEALTH'],
        products: [
          product('Melatonin', {'GOAL_SLEEP_QUALITY'}),
        ],
      );
      expect(report.supported, isEmpty);
      expect(report.unaddressedGoals, hasLength(1));
      final goal = report.unaddressedGoals.first;
      expect(goal.goalLabel, 'Cardiovascular/Heart Health');
      // Calm-advisory copy: names the goal, never a product, never an
      // imperative.
      expect(
        goal.message,
        'Nothing in your stack currently supports your '
        'cardiovascular/heart health goal.',
      );
    });

    test('products with empty goal_matches do not support anything', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [product('Mystery Blend', const {})],
      );
      expect(report.supported, isEmpty);
      expect(report.unaddressedGoals, hasLength(1));
    });

    test('empty goal_matches marks coverage incomplete and hedges the copy '
        '(unpopulated column ≠ "supports no goals")', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product('Mystery Blend', const {}),
          product('Fish Oil', {'GOAL_CARDIOVASCULAR_HEART_HEALTH'}),
        ],
      );
      expect(report.coverageIncomplete, isTrue);
      final goal = report.unaddressedGoals.single;
      expect(goal.hedged, isTrue);
      expect(
        goal.message,
        "We couldn't confirm anything in your stack supports your "
        'sleep quality goal.',
      );
    });

    test('all products populated → confident copy, no hedge', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product('Fish Oil', {'GOAL_CARDIOVASCULAR_HEART_HEALTH'}),
        ],
      );
      expect(report.coverageIncomplete, isFalse);
      final goal = report.unaddressedGoals.single;
      expect(goal.hedged, isFalse);
      expect(goal.message, startsWith('Nothing in your stack'));
    });

    test('coverageIncomplete=true hedges goal copy even when populated', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product('Fish Oil', {'GOAL_CARDIOVASCULAR_HEART_HEALTH'}),
        ],
        coverageIncomplete: true,
      );
      expect(report.unaddressedGoals.single.hedged, isTrue);
    });
  });

  group('PRIORITY GAPS bucket', () {
    test(
      'prenatal goal plus prenatal base surfaces missing DHA and choline',
      () {
        final report = analyzer.analyze(
          goals: const ['GOAL_PRENATAL_PREGNANCY'],
          products: [
            product(
              'Basic Prenatal',
              const {'GOAL_PRENATAL_PREGNANCY'},
              productRole: 'prenatal_base',
              prenatalCoverage: [
                anchor('dha', 'DHA', 'missing', target: 200, unit: 'mg'),
                anchor(
                  'choline',
                  'Choline',
                  'missing',
                  target: 450,
                  unit: 'mg',
                ),
                anchor('folate', 'Folate', 'covered', amount: 600, target: 600),
              ],
            ),
          ],
        );

        expect(report.priorityGaps.map((g) => g.nutrientId), [
          'dha',
          'choline',
        ]);
        expect(report.priorityGaps.first.detail, contains('Not confirmed'));
      },
    );

    test('separate DHA companion satisfies base-product DHA gap', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_PRENATAL_PREGNANCY'],
        products: [
          product(
            'Basic Prenatal',
            const {'GOAL_PRENATAL_PREGNANCY'},
            productRole: 'prenatal_base',
            prenatalCoverage: [
              anchor('dha', 'DHA', 'missing', target: 200, unit: 'mg'),
              anchor('choline', 'Choline', 'missing', target: 450, unit: 'mg'),
            ],
          ),
          product(
            'Prenatal DHA',
            const {},
            productRole: 'prenatal_dha_companion',
            prenatalCoverage: [
              anchor(
                'dha',
                'DHA',
                'covered',
                amount: 250,
                target: 200,
                unit: 'mg',
              ),
            ],
          ),
        ],
      );

      expect(report.priorityGaps.map((g) => g.nutrientId), ['choline']);
    });

    test('below-target companion amounts can add up across stack', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_PRENATAL_PREGNANCY'],
        products: [
          product(
            'Basic Prenatal',
            const {'GOAL_PRENATAL_PREGNANCY'},
            productRole: 'prenatal_base',
            prenatalCoverage: [
              anchor(
                'choline',
                'Choline',
                'below_target',
                amount: 250,
                target: 450,
                unit: 'mg',
              ),
            ],
          ),
          product(
            'Choline',
            const {},
            productRole: 'targeted_gap_filler',
            prenatalCoverage: [
              anchor(
                'choline',
                'Choline',
                'below_target',
                amount: 250,
                target: 450,
                unit: 'mg',
              ),
            ],
          ),
        ],
      );

      expect(report.priorityGaps, isEmpty);
    });

    test('prenatal anchors do not surface without prenatal goal', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product(
            'Basic Prenatal',
            const {},
            productRole: 'prenatal_base',
            prenatalCoverage: [
              anchor('dha', 'DHA', 'missing', target: 200, unit: 'mg'),
            ],
          ),
        ],
      );

      expect(report.priorityGaps, isEmpty);
    });

    test('adult iron-free multi surfaces missing adult core but not iron', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product(
            'Adult Multi Iron-Free',
            const {},
            productRole: 'adult_multi_iron_free',
            adultMultiCoverage: [
              anchor(
                'vitamin_d',
                'Vitamin D',
                'missing',
                target: 20,
                unit: 'mcg',
              ),
              anchor('folate', 'Folate', 'covered', amount: 400, target: 400),
            ],
          ),
        ],
      );

      expect(report.priorityGaps.map((g) => g.nutrientId), ['vitamin_d']);
      expect(
        report.priorityGaps.map((g) => g.nutrientId),
        isNot(contains('iron')),
      );
    });

    test('medication interaction owns vitamin K guidance for warfarin', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product(
            'Adult Multi',
            const {},
            productRole: 'adult_multi_standard',
            adultMultiCoverage: [
              anchor(
                'vitamin_k',
                'Vitamin K',
                'below_target',
                amount: 30,
                target: 120,
                unit: 'mcg',
              ),
            ],
          ),
        ],
        depletions: [
          depletion(
            drug: 'Warfarin',
            nutrient: 'Vitamin K',
            type: 'functional_antagonism',
          ),
        ],
      );

      expect(
        report.priorityGaps.map((gap) => gap.nutrientId),
        isNot(contains('vitamin_k')),
      );
    });

    test('separate adult anchor product satisfies adult multi gap', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product(
            'Adult Multi Iron-Free',
            const {},
            productRole: 'adult_multi_iron_free',
            adultMultiCoverage: [
              anchor(
                'vitamin_d',
                'Vitamin D',
                'missing',
                target: 20,
                unit: 'mcg',
              ),
            ],
          ),
          product(
            'Vitamin D3',
            const {},
            productRole: 'targeted_gap_filler',
            adultMultiCoverage: [
              anchor(
                'vitamin_d',
                'Vitamin D',
                'covered',
                amount: 25,
                target: 20,
                unit: 'mcg',
              ),
            ],
          ),
        ],
      );

      expect(report.priorityGaps, isEmpty);
    });

    test('adult anchors do not surface without an adult multi role', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product(
            'Vitamin D3',
            const {},
            productRole: 'targeted_gap_filler',
            adultMultiCoverage: [
              anchor(
                'vitamin_d',
                'Vitamin D',
                'missing',
                target: 20,
                unit: 'mcg',
              ),
            ],
          ),
        ],
      );

      expect(report.priorityGaps, isEmpty);
    });
  });

  group('UNADDRESSED bucket — depletions', () {
    test('unreplenished depletion produces doctor-conversation copy', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [
          product('Melatonin', {'GOAL_SLEEP_QUALITY'}),
        ],
        depletions: [depletion(coverage: CoverageLevel.none)],
      );
      expect(report.unreplenishedDepletions, hasLength(1));
      final dep = report.unreplenishedDepletions.first;
      expect(dep.nutrientName, 'Vitamin B12');
      expect(
        dep.message,
        'Metformin may lower Vitamin B12 over time — nothing in your '
        'stack provides Vitamin B12. Worth a conversation with your '
        'doctor.',
      );
      expect(report.unaddressedCount, 1);
    });

    test('adequately covered depletion is not a gap', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('B12 Complex', const {})],
        depletions: [depletion(coverage: CoverageLevel.adequate)],
      );
      expect(report.unreplenishedDepletions, isEmpty);
      expect(report.underdosed, isEmpty);
    });

    test('coverage-irrelevant depletion types are ignored', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('Anything', const {})],
        depletions: [
          depletion(type: 'monitoring_stability'),
          depletion(type: 'functional_antagonism', nutrient: 'Calcium'),
        ],
      );
      expect(report.unreplenishedDepletions, isEmpty);
    });

    test('duplicate (drug, nutrient) depletion rows surface once', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('Anything', const {})],
        depletions: [depletion(), depletion()],
      );
      expect(report.unreplenishedDepletions, hasLength(1));
    });
  });

  group('UNDERDOSED bucket', () {
    test('underFifty RDA nutrient is underdosed with percent detail', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('D3 Drops', const {})],
        nutrientStatuses: [status(pctOfRda: 42.0)],
      );
      expect(report.underdosed, hasLength(1));
      final row = report.underdosed.first;
      expect(row.nutrientName, 'Vitamin D');
      expect(row.source, UnderdosedSource.rda);
      expect(
        row.detail,
        'Supplements provide about 42% of the daily reference amount. '
        'Food and drinks are not included.',
      );
    });

    test('adequate/abundant tiers are not underdosed', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('D3 Drops', const {})],
        nutrientStatuses: [
          status(tier: NutrientTier.adequate),
          status(name: 'Zinc', tier: NutrientTier.abundant),
          status(name: 'Iron', tier: NutrientTier.noRda, pctOfRda: null),
        ],
      );
      expect(report.underdosed, isEmpty);
    });

    test('partial depletion coverage is underdosed with med context', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('Low-dose B12', const {})],
        depletions: [depletion(coverage: CoverageLevel.partial)],
      );
      expect(report.underdosed, hasLength(1));
      final row = report.underdosed.first;
      expect(row.source, UnderdosedSource.depletion);
      expect(row.detail, contains('Metformin'));
      // A partial depletion is not also an unaddressed gap.
      expect(report.unreplenishedDepletions, isEmpty);
    });

    test('percentage is skipped when the total has a unit conflict', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product('D3 Drops', {'GOAL_SLEEP_QUALITY'}),
        ],
        nutrientStatuses: [status(pctOfRda: 42.0, hasUnitConflict: true)],
      );
      expect(
        report.underdosed.single.detail,
        'Present in your supplements, but the amount could not be compared '
        'reliably. Food and drinks are not included.',
      );
    });

    test('percentage is skipped when contributions were excluded', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product('D3 Drops', {'GOAL_SLEEP_QUALITY'}),
        ],
        nutrientStatuses: [
          status(pctOfRda: 42.0, excluded: const [_excludedContribution]),
        ],
      );
      expect(report.underdosed.single.detail, isNot(contains('%')));
    });

    test('displayed percent clamps to 1..49 inside the under-50 bucket', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product('D3 Drops', {'GOAL_SLEEP_QUALITY'}),
        ],
        nutrientStatuses: [
          status(pctOfRda: 0.4),
          status(name: 'Zinc', pctOfRda: 49.6),
        ],
      );
      final details = report.underdosed.map((u) => u.detail).toList();
      expect(
        details,
        contains(
          'Supplements provide about 1% of the daily reference amount. '
          'Food and drinks are not included.',
        ),
      );
      expect(
        details,
        contains(
          'Supplements provide about 49% of the daily reference amount. '
          'Food and drinks are not included.',
        ),
      );
    });

    test('depletion framing wins when RDA and depletion both flag', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('Low-dose B12', const {})],
        nutrientStatuses: [status(name: 'Vitamin B12', pctOfRda: 30)],
        depletions: [depletion(coverage: CoverageLevel.partial)],
      );
      expect(report.underdosed, hasLength(1));
      expect(report.underdosed.first.source, UnderdosedSource.depletion);
    });
  });

  group('empty states', () {
    test('empty stack → isEmpty report, no buckets', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: const [],
      );
      expect(report.isEmpty, isTrue);
      expect(report.hasStack, isFalse);
      expect(report.supported, isEmpty);
      expect(report.unaddressedGoals, isEmpty);
    });

    test('no goals → hasGoals false, no goal buckets, no fake analysis', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [
          product('Fish Oil', {'GOAL_CARDIOVASCULAR_HEART_HEALTH'}),
        ],
      );
      expect(report.isEmpty, isFalse);
      expect(report.hasGoals, isFalse);
      expect(report.supported, isEmpty);
      expect(report.unaddressedGoals, isEmpty);
    });

    test('coverageIncomplete flag passes through', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: [product('Mystery', const {})],
        coverageIncomplete: true,
      );
      expect(report.coverageIncomplete, isTrue);
    });

    test('hasStackOverride keeps the card alive (with depletion gaps) when '
        'every supplement failed hydration', () {
      final report = analyzer.analyze(
        goals: const ['GOAL_SLEEP_QUALITY'],
        products: const [],
        depletions: [depletion(coverage: CoverageLevel.none)],
        coverageIncomplete: true,
        hasStackOverride: true,
      );
      expect(report.isEmpty, isFalse);
      expect(report.hasStack, isTrue);
      expect(report.unreplenishedDepletions, hasLength(1));
      expect(report.coverageIncomplete, isTrue);
    });

    test('goalsOptedOut passes through to the report', () {
      final report = analyzer.analyze(
        goals: const [],
        products: [product('Fish Oil', const {})],
        goalsOptedOut: true,
      );
      expect(report.goalsOptedOut, isTrue);
      expect(report.hasGoals, isFalse);
    });
  });
}
