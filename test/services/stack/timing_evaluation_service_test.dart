// TimingEvaluationService — matching, identity, gating.
//
// Structural invariants (no dayparts, no medication scheduling, suppression,
// fail-closed parsing) live in timing_guidance_invariants_test.dart. This file
// covers what the service does once a rule is verified: which stack rows it
// matches, how medication identity is resolved, and when a tip is withheld.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';

Map<String, dynamic> _rule({
  required String id,
  required Map<String, dynamic> relation,
  String category = 'how_to_take',
  String appliesTo = 'any',
  String actionability = 'recommended',
  String evidenceLevel = 'established',
  String sourceAuthority = 'fda_label',
  String reviewStatus = 'verified',
  String ingredient1 = 'iron',
  List<String>? ingredient1Tags,
  List<String>? ingredient1Rxcuis,
  String? ingredient2,
  List<String>? ingredient2Tags,
  List<String>? ingredient2Rxcuis,
  String advice = 'Authored advice.',
  int scoreImpact = -2,
  Map<String, dynamic>? minDose,
  List<Map<String, dynamic>> sources = const [],
}) {
  return {
    'id': id,
    'ingredient1': ingredient1,
    if (ingredient1Tags != null) 'ingredient1_tags': ingredient1Tags,
    if (ingredient1Rxcuis != null) 'ingredient1_rxcuis': ingredient1Rxcuis,
    if (ingredient2 != null) 'ingredient2': ingredient2,
    if (ingredient2Tags != null) 'ingredient2_tags': ingredient2Tags,
    if (ingredient2Rxcuis != null) 'ingredient2_rxcuis': ingredient2Rxcuis,
    'timing_relation': relation,
    'category': category,
    'applies_to': appliesTo,
    'actionability': actionability,
    'source_authority': sourceAuthority,
    'review_status': reviewStatus,
    if (minDose != null) 'min_dose': minDose,
    'advice': advice,
    'score_impact': scoreImpact,
    'evidence_level': evidenceLevel,
    'sources': sources,
  };
}

TimingEvaluationService _serviceOf(List<Map<String, dynamic>> rules) =>
    TimingEvaluationService.fromJson({
      '_metadata': {'total_entries': rules.length},
      'timing_rules': rules,
    });

const _separate2h = {'type': 'separate_from', 'minimum_hours': 2};
const _withFood = {'type': 'with_food'};

TimingStackItem _supplement(String id, String name, Set<String> tags) =>
    TimingStackItem.supplement(
      stackEntryId: id,
      displayName: name,
      ingredientTags: tags,
    );

void main() {
  group('rule parsing', () {
    test('parses a verified rule and indexes both sides', () {
      final service = _serviceOf([
        _rule(
          id: 'timing_iron_calcium_separate',
          ingredient1Tags: const ['iron'],
          ingredient2: 'calcium',
          ingredient2Tags: const ['calcium'],
          relation: _separate2h,
          category: 'important_separation',
        ),
      ]);
      expect(service.ruleCount, 1);
      expect(service.suppressedRuleCount, 0);
    });

    test('rejects a metadata count that disagrees with the array', () {
      expect(
        () => TimingEvaluationService.fromJson({
          '_metadata': {'total_entries': 5},
          'timing_rules': [
            _rule(
              id: 'a',
              ingredient1Tags: const ['iron'],
              relation: _withFood,
            ),
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps the legacy `possible` tier to theoretical, never upward', () {
      final service = _serviceOf([
        _rule(
          id: 'timing_possible',
          ingredient1Tags: const ['iron'],
          relation: _withFood,
          evidenceLevel: 'possible',
        ),
      ]);
      final result = service.evaluateStack(
        stackItems: [_supplement('row-iron', 'Iron', {'iron'})],
      );
      expect(result.single.evidenceLevel, EvidenceLevel.theoretical);
    });

    test('rejects a rule with neither tags nor rxcuis on side one', () {
      expect(
        () => _serviceOf([_rule(id: 'timing_bare', relation: _withFood)]),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('supplement matching', () {
    late TimingEvaluationService service;

    setUp(() {
      service = _serviceOf([
        _rule(
          id: 'timing_iron_calcium_separate',
          ingredient1: 'iron',
          ingredient1Tags: const ['iron'],
          ingredient2: 'calcium',
          ingredient2Tags: const ['calcium'],
          relation: _separate2h,
          category: 'important_separation',
        ),
      ]);
    });

    test('fires when both sides are in the stack as separate rows', () {
      final results = service.evaluateStack(
        stackItems: [
          _supplement('row-iron', 'Gentle Iron', {'iron'}),
          _supplement('row-cal', 'Calcium Citrate', {'calcium'}),
        ],
      );
      expect(results, hasLength(1));
      expect(results.single.separationHours, 2);
    });

    test('does not fire when only one side is present', () {
      final results = service.evaluateStack(
        stackItems: [_supplement('row-iron', 'Gentle Iron', {'iron'})],
      );
      expect(results, isEmpty);
    });

    test('product names stay aligned with the authored ingredient sides', () {
      final results = service.evaluateStack(
        stackItems: [
          _supplement('row-cal', 'Calcium Citrate', {'calcium'}),
          _supplement('row-iron', 'Gentle Iron', {'iron'}),
        ],
      );
      final result = results.single;
      expect(result.ingredient1, 'iron');
      expect(result.product1Name, 'Gentle Iron');
      expect(result.ingredient2, 'calcium');
      expect(result.product2Name, 'Calcium Citrate');
    });

    test('suppresses a separation when both minerals are one bottle', () {
      final results = service.evaluateStack(
        stackItems: [
          _supplement('row-combo', 'Cal-Mag-Iron', {'iron', 'calcium'}),
        ],
      );
      expect(
        results,
        isEmpty,
        reason: 'a rule cannot separate two nutrients inside one capsule',
      );
    });

    test('duplicate display names remain separate physical rows', () {
      final results = service.evaluateStack(
        stackItems: [
          _supplement('row-a', 'Iron', {'iron'}),
          _supplement('row-b', 'Iron', {'calcium'}),
        ],
      );
      expect(results, hasLength(1));
      expect(results.single.product1StackEntryId, 'row-a');
      expect(results.single.product2StackEntryId, 'row-b');
    });

    test('fires a unary rule once per bottle carrying the tag', () {
      final results = _serviceOf([
        _rule(
          id: 'timing_vitamin_d_with_food',
          ingredient1: 'vitamin d',
          ingredient1Tags: const ['vitamin_d'],
          relation: _withFood,
        ),
      ]).evaluateStack(
        stackItems: [
          _supplement('row-d3', 'D3 5000', {'vitamin_d'}),
          _supplement('row-multi', 'Multi', {'vitamin_d', 'zinc'}),
        ],
      );
      expect(results, hasLength(2));
      expect(
        results.map((r) => r.product1StackEntryId),
        containsAll(['row-d3', 'row-multi']),
      );
    });

    test('collapses duplicate with-food tips for the same bottle', () {
      final results = _serviceOf([
        _rule(
          id: 'timing_vitamin_d_with_food',
          ingredient1: 'vitamin d',
          ingredient1Tags: const ['vitamin_d'],
          relation: _withFood,
        ),
        _rule(
          id: 'timing_vitamin_k_with_food',
          ingredient1: 'vitamin k',
          ingredient1Tags: const ['vitamin_k1'],
          relation: _withFood,
        ),
      ]).evaluateStack(
        stackItems: [
          _supplement('row-dk', 'D+K', {'vitamin_d', 'vitamin_k1'}),
        ],
      );
      expect(
        results,
        hasLength(1),
        reason: 'the user is told to take this bottle with food once',
      );
    });

    test('returns an empty list for an empty stack', () {
      expect(service.evaluateStack(stackItems: const []), isEmpty);
    });

    test('handles a 50+ item stack without timing out', () {
      final stack = [
        for (var i = 0; i < 60; i++)
          _supplement('row-$i', 'Product $i', {'iron', 'calcium'}),
      ];
      final stopwatch = Stopwatch()..start();
      service.evaluateStack(stackItems: stack);
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('medication identity', () {
    late TimingEvaluationService service;

    setUp(() {
      service = _serviceOf([
        _rule(
          id: 'timing_thyroid_med_iron_separate',
          ingredient1: 'levothyroxine',
          ingredient1Rxcuis: const ['10582'],
          ingredient2: 'iron',
          ingredient2Tags: const ['iron'],
          relation: const {'type': 'separate_from', 'minimum_hours': 4},
          category: 'important_separation',
        ),
      ]);
    });

    test('fires through a reviewed RxCUI', () {
      final results = service.evaluateStack(
        stackItems: [
          _supplement('row-iron', 'Gentle Iron', {'iron'}),
          const TimingStackItem.medication(
            stackEntryId: 'row-levo',
            displayName: 'Synthroid',
            medicationRxCuis: {'10582'},
          ),
        ],
      );
      expect(results, hasLength(1));
      expect(results.single.involvesMedication, isTrue);
      expect(results.single.medicationIsProduct1, isTrue);
      expect(results.single.separationHours, 4);
    });

    test('matches a brand through its normalized generic RxCUI', () {
      final results = service.evaluateStack(
        stackItems: [
          _supplement('row-iron', 'Gentle Iron', {'iron'}),
          const TimingStackItem.medication(
            stackEntryId: 'row-levo',
            displayName: 'Euthyrox',
            medicationRxCuis: {'999999', '10582'},
          ),
        ],
      );
      expect(results, hasLength(1));
    });

    test('never infers medication identity from a display name', () {
      final results = service.evaluateStack(
        stackItems: [
          _supplement('row-iron', 'Gentle Iron', {'iron'}),
          const TimingStackItem.medication(
            stackEntryId: 'row-levo',
            displayName: 'Levothyroxine 50mcg',
            medicationRxCuis: {},
          ),
        ],
      );
      expect(results, isEmpty, reason: 'display text is not clinical identity');
    });

    test('does not fire when the medication is absent', () {
      final results = service.evaluateStack(
        stackItems: [_supplement('row-iron', 'Gentle Iron', {'iron'})],
      );
      expect(results, isEmpty);
    });
  });

  group('dose gating', () {
    late TimingEvaluationService service;

    setUp(() {
      service = _serviceOf([
        _rule(
          id: 'timing_iron_zinc_separate',
          ingredient1: 'iron',
          ingredient1Tags: const ['iron'],
          ingredient2: 'zinc',
          ingredient2Tags: const ['zinc'],
          relation: _separate2h,
          category: 'important_separation',
          minDose: const {'tag': 'iron', 'mg': 25},
        ),
      ]);
    });

    List<TimingOptimization> evaluate(Map<String, double> doses) =>
        service.evaluateStack(
          stackItems: [
            _supplement('row-iron', 'Iron', {'iron'}),
            _supplement('row-zinc', 'Zinc', {'zinc'}),
          ],
          ingredientDosesMg: doses,
        );

    test('fires at or above the threshold', () {
      expect(evaluate({'iron': 25}), hasLength(1));
      expect(evaluate({'iron': 65}), hasLength(1));
    });

    test('is suppressed below the threshold', () {
      expect(evaluate({'iron': 18}), isEmpty);
    });

    test('is suppressed when the dose is unknown', () {
      expect(
        evaluate(const {}),
        isEmpty,
        reason:
            'dose-conditional copy must never imply a threshold was crossed '
            'without a measured total',
      );
      expect(evaluate({'zinc': 50}), isEmpty);
    });
  });

  group('ordering and derived fields', () {
    test('important separations outrank how-to-take guidance', () {
      final results = _serviceOf([
        _rule(
          id: 'timing_with_food',
          ingredient1: 'iron',
          ingredient1Tags: const ['iron'],
          relation: _withFood,
        ),
        _rule(
          id: 'timing_separate',
          ingredient1: 'iron',
          ingredient1Tags: const ['iron'],
          ingredient2: 'calcium',
          ingredient2Tags: const ['calcium'],
          relation: _separate2h,
          category: 'important_separation',
        ),
      ]).evaluateStack(
        stackItems: [
          _supplement('row-iron', 'Iron', {'iron'}),
          _supplement('row-cal', 'Calcium', {'calcium'}),
        ],
      );
      expect(results.first.ruleId, 'timing_separate');
    });

    test('evidence breaks ties within a category, never across', () {
      const weakSeparation = TimingOptimization(
        ruleId: 'weak',
        ingredient1: 'a',
        advice: 'x',
        relation: TimingRelation(
          type: TimingRelationType.separateFrom,
          minimumHours: 2,
        ),
        category: TimingCategory.importantSeparation,
        actionability: TimingActionability.informational,
        evidenceLevel: EvidenceLevel.noData,
        sourceAuthority: SourceAuthority.mechanism,
        scoreImpact: 0,
      );
      const strongHowTo = TimingOptimization(
        ruleId: 'strong',
        ingredient1: 'b',
        advice: 'y',
        relation: TimingRelation(type: TimingRelationType.withFood),
        category: TimingCategory.howToTake,
        actionability: TimingActionability.recommended,
        evidenceLevel: EvidenceLevel.established,
        sourceAuthority: SourceAuthority.fdaLabel,
        scoreImpact: 0,
      );
      expect(
        weakSeparation.displayPriority,
        greaterThan(strongHowTo.displayPriority),
        reason:
            'strong evidence must not promote a rule into a more prominent '
            'category',
      );
    });

    test('isSeparation covers both separation relations', () {
      for (final type in TimingRelationType.values) {
        final optimization = TimingOptimization(
          ruleId: 'r',
          ingredient1: 'a',
          advice: 'x',
          relation: TimingRelation(
            type: type,
            minimumHours: 2,
            event: TimingEvent.intendedSleep,
            minimumMinutes: 30,
          ),
          category: TimingCategory.howToTake,
          actionability: TimingActionability.recommended,
          evidenceLevel: EvidenceLevel.established,
          sourceAuthority: SourceAuthority.reference,
          scoreImpact: 0,
        );
        expect(
          optimization.isSeparation,
          type == TimingRelationType.separateFrom ||
              type == TimingRelationType.separateFromMedications,
        );
      }
    });

    test('involvesMedication comes from reviewed rule identity only', () {
      final results = _serviceOf([
        _rule(
          id: 'timing_supplement_only',
          ingredient1: 'iron',
          ingredient1Tags: const ['iron'],
          ingredient2: 'calcium',
          ingredient2Tags: const ['calcium'],
          relation: _separate2h,
          category: 'important_separation',
        ),
      ]).evaluateStack(
        stackItems: [
          _supplement('row-iron', 'Levothyroxine lookalike', {'iron'}),
          _supplement('row-cal', 'Calcium', {'calcium'}),
        ],
      );
      expect(results.single.involvesMedication, isFalse);
    });
  });
}
