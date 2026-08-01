// Permanent invariants for timing guidance.
//
// These replace test/legacy_characterization/timing_scheduler_defects_test.dart,
// which documented the defects this file now forbids. Each group below is the
// positive counterpart of a case that used to pass:
//
//   legacy "levothyroxine assigned dinner"  -> "no time is assigned, ever"
//   legacy "O.N.E. reports a conflict"      -> "standalone rules stay out of
//                                               combination products"
//   legacy "caffeine triggers coffee copy"  -> "identity is exact, no aliases"
//   legacy "soy rule never fires"           -> covered by the reachability gate
//
// Nothing here depends on a rule being clinically verified yet, so the file
// stays green through the Section 2 audit.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';

/// O.N.E. Multivitamin — dsld_id 278010, tags exactly as shipped.
const _oneMultivitaminTags = {
  'vitamin_a',
  'vitamin_c',
  'vitamin_d',
  'vitamin_e',
  'zinc',
  'selenium',
  'alpha_lipoic_acid',
  'lutein',
};

const _levothyroxineRxcui = '10582';

TimingOptimization _optimization({
  String ruleId = 'rule',
  required TimingRelation relation,
  TimingCategory category = TimingCategory.howToTake,
  String ingredient1 = 'iron',
  String? ingredient2,
  String? product1Name,
  String? product1StackEntryId,
  String? product2Name,
  String? product2StackEntryId,
  bool involvesMedication = false,
  bool medicationIsProduct1 = false,
}) {
  return TimingOptimization(
    ruleId: ruleId,
    ingredient1: ingredient1,
    ingredient2: ingredient2,
    advice: 'Pipeline-authored advice.',
    relation: relation,
    category: category,
    actionability: TimingActionability.recommended,
    evidenceLevel: EvidenceLevel.established,
    sourceAuthority: SourceAuthority.fdaLabel,
    scoreImpact: -2,
    product1Name: product1Name,
    product1StackEntryId: product1StackEntryId,
    product2Name: product2Name,
    product2StackEntryId: product2StackEntryId,
    involvesMedication: involvesMedication,
    medicationIsProduct1: medicationIsProduct1,
  );
}

/// A minimal verified rule in the shipped schema, for behaviour that cannot be
/// proven from the artifact until Section 2 verifies real rules.
Map<String, dynamic> _rule({
  required String id,
  required Map<String, dynamic> relation,
  required String category,
  String appliesTo = 'any',
  String reviewStatus = 'verified',
  List<String>? ingredient1Tags,
  List<String>? ingredient1Rxcuis,
  List<String>? ingredient2Tags,
  List<String>? ingredient2Rxcuis,
  String ingredient1 = 'iron',
  String? ingredient2,
  String advice = 'Authored advice.',
  bool? clinicianApproved,
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
    'actionability': 'recommended',
    'source_authority': 'fda_label',
    'review_status': reviewStatus,
    if (clinicianApproved != null) 'clinician_approved': clinicianApproved,
    'advice': advice,
    'score_impact': -2,
    'evidence_level': 'established',
    'sources': const <Map<String, dynamic>>[],
  };
}

TimingEvaluationService _serviceOf(List<Map<String, dynamic>> rules) =>
    TimingEvaluationService.fromJson({
      '_metadata': {'total_entries': rules.length},
      'timing_rules': rules,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const builder = TimingGuidanceBuilder();

  group('a prescribed medication is never given a time', () {
    test('guidance for a medication rule attaches to the supplement row', () {
      final guidance = builder.build([
        _optimization(
          ruleId: 'timing_calcium_levothyroxine',
          relation: const TimingRelation(
            type: TimingRelationType.separateFrom,
            minimumHours: 4,
          ),
          category: TimingCategory.importantSeparation,
          ingredient1: 'levothyroxine',
          ingredient2: 'calcium',
          product1Name: 'Levothyroxine',
          product1StackEntryId: 'row-levothyroxine',
          product2Name: 'Calcium K/D',
          product2StackEntryId: 'row-calcium-kd',
          involvesMedication: true,
          medicationIsProduct1: true,
        ),
      ]);

      expect(guidance.products, hasLength(1));
      expect(guidance.products.single.stackEntryId, 'row-calcium-kd');
      expect(guidance.products.single.productName, 'Calcium K/D');
      expect(
        guidance.products.map((p) => p.stackEntryId),
        isNot(contains('row-levothyroxine')),
        reason: 'the prescription must never carry app-issued guidance',
      );
    });

    test('a unary rule about a medication is never emitted at all', () {
      final service = _serviceOf([
        _rule(
          id: 'timing_levothyroxine_empty_stomach',
          ingredient1: 'levothyroxine',
          ingredient1Rxcuis: const [_levothyroxineRxcui],
          relation: const {'type': 'empty_stomach'},
          category: 'how_to_take',
        ),
      ]);

      final results = service.evaluateStack(
        stackItems: const [
          TimingStackItem.medication(
            stackEntryId: 'row-levothyroxine',
            displayName: 'Levothyroxine',
            medicationRxCuis: {_levothyroxineRxcui},
          ),
        ],
      );

      expect(
        results,
        isEmpty,
        reason:
            'how a prescription is taken is the prescriber s instruction, not '
            'the app s',
      );
    });
  });

  group('no generated clock times or dayparts', () {
    const forbidden = [
      'breakfast',
      'lunch',
      'dinner',
      'bedtime',
      'morning',
      'evening',
    ];

    test('the relation vocabulary contains no daypart', () {
      for (final type in TimingRelationType.values) {
        for (final word in forbidden) {
          expect(
            type.wireValue.toLowerCase(),
            isNot(contains(word)),
            reason: '${type.wireValue} reintroduces a daypart',
          );
        }
      }
    });

    test('events are user-defined anchors, never clock times', () {
      for (final event in TimingEvent.values) {
        expect(event.wireValue, isNot(matches(RegExp(r'\d'))));
      }
      // `intended_sleep` is answerable by the user. A slot at hour 22 is not.
      expect(TimingEvent.values, contains(TimingEvent.intendedSleep));
    });

    test('no shipped rule authors a daypart in structured data', () async {
      final json = await ReferenceDataRepository().loadTimingRules();
      final rules = json['timing_rules'] as List;
      for (final raw in rules) {
        final rule = raw as Map;
        expect(
          rule.containsKey('daily_slots'),
          isFalse,
          reason: '${rule['id']} still carries daily_slots',
        );
        expect(
          rule.containsKey('rule_type'),
          isFalse,
          reason: '${rule['id']} still carries the legacy rule_type',
        );
        final relationType =
            (rule['timing_relation'] as Map)['type'] as String;
        for (final word in forbidden) {
          expect(relationType, isNot(contains(word)));
        }
      }
    });
  });

  group('a nutrient never masquerades as a bottle', () {
    test('an optimization with no stack row is reported, not rendered', () {
      final guidance = builder.build([
        _optimization(
          ruleId: 'timing_orphan',
          relation: const TimingRelation(type: TimingRelationType.withFood),
          ingredient1: 'vitamin a',
          // No product1Name / product1StackEntryId: the old code fell back to
          // the ingredient name here and drew "Vitamin A" as if it were a row.
        ),
      ]);

      expect(guidance.products, isEmpty);
      expect(guidance.issues, hasLength(1));
      expect(guidance.issues.single, isA<IdentityUnresolved>());
      expect(
        guidance.canAssertNoFindings,
        isFalse,
        reason: 'an unresolved identity means the check did not finish',
      );
    });

    test('every rendered product carries a real stack row id', () {
      final guidance = builder.build([
        _optimization(
          ruleId: 'timing_with_food',
          relation: const TimingRelation(type: TimingRelationType.withFood),
          product1Name: 'Fish Oil',
          product1StackEntryId: 'row-fish-oil',
        ),
      ]);

      for (final product in guidance.products) {
        expect(product.stackEntryId, isNotEmpty);
      }
    });
  });

  group('identity is exact — no aliases, no invented tags', () {
    test('a rule matches only the canonical tags it names', () {
      final service = _serviceOf([
        _rule(
          id: 'timing_coffee_iron_separate',
          ingredient1: 'coffee',
          ingredient1Tags: const ['coffee'],
          ingredient2: 'iron',
          ingredient2Tags: const ['iron'],
          relation: const {'type': 'separate_from', 'minimum_hours': 1},
          category: 'important_separation',
          advice: 'Keep iron away from coffee.',
        ),
      ]);

      // A caffeine tablet and a guarana extract are not coffee. The former
      // alias map expanded `caffeine` to include `guarana`, so both fired.
      for (final tag in ['caffeine', 'guarana']) {
        final results = service.evaluateStack(
          stackItems: [
            TimingStackItem.supplement(
              stackEntryId: 'row-$tag',
              displayName: tag,
              ingredientTags: {tag},
            ),
            const TimingStackItem.supplement(
              stackEntryId: 'row-iron',
              displayName: 'Gentle Iron',
              ingredientTags: {'iron'},
            ),
          ],
        );
        expect(
          results,
          isEmpty,
          reason: '$tag must not inherit coffee guidance',
        );
      }
    });

    test('an unmatched ingredient name is not normalised into a tag', () {
      // The old fallback turned "vitamin b12" into `vitamin_b12`, a tag the
      // catalog never emits, making a dead rule look reachable.
      final service = _serviceOf([
        _rule(
          id: 'timing_b12',
          ingredient1: 'vitamin b12',
          ingredient1Tags: const ['vitamin_b12_cobalamin'],
          relation: const {'type': 'with_food'},
          category: 'how_to_take',
        ),
      ]);

      final missed = service.evaluateStack(
        stackItems: const [
          TimingStackItem.supplement(
            stackEntryId: 'row-b12',
            displayName: 'B12',
            ingredientTags: {'vitamin_b12'},
          ),
        ],
      );
      expect(missed, isEmpty);

      final hit = service.evaluateStack(
        stackItems: const [
          TimingStackItem.supplement(
            stackEntryId: 'row-b12',
            displayName: 'B12',
            ingredientTags: {'vitamin_b12_cobalamin'},
          ),
        ],
      );
      expect(hit, hasLength(1));
    });
  });

  group('standalone rules stay out of combination products', () {
    List<Map<String, dynamic>> multivitaminRuleSet() => [
      _rule(
        id: 'timing_ala_empty_stomach',
        ingredient1: 'alpha-lipoic acid',
        ingredient1Tags: const ['alpha_lipoic_acid'],
        relation: const {'type': 'empty_stomach'},
        category: 'how_to_take',
        appliesTo: 'standalone',
      ),
      _rule(
        id: 'timing_vitamin_d_with_food',
        ingredient1: 'vitamin d',
        ingredient1Tags: const ['vitamin_d'],
        relation: const {'type': 'with_food'},
        category: 'how_to_take',
        appliesTo: 'standalone',
      ),
    ];

    test('O.N.E. Multivitamin produces no self-conflict', () {
      final guidance = builder.build(
        _serviceOf(multivitaminRuleSet()).evaluateStack(
          stackItems: const [
            TimingStackItem.supplement(
              stackEntryId: 'row-one-multi',
              displayName: 'O.N.E. Multivitamin',
              ingredientTags: _oneMultivitaminTags,
            ),
          ],
        ),
      );

      expect(
        guidance.issues.whereType<ConflictingProductGuidance>(),
        isEmpty,
        reason:
            'ALA and vitamin D are both trace ingredients here; neither '
            'standalone rule should have fired in the first place',
      );
      expect(guidance.products, isEmpty);
    });

    test('the same rule still fires on a single-ingredient bottle', () {
      final results = _serviceOf(multivitaminRuleSet()).evaluateStack(
        stackItems: const [
          TimingStackItem.supplement(
            stackEntryId: 'row-ala',
            displayName: 'Alpha Lipoic Acid 600mg',
            ingredientTags: {'alpha_lipoic_acid'},
          ),
        ],
      );

      expect(results, hasLength(1));
      expect(results.single.ruleId, 'timing_ala_empty_stomach');
    });

    test('applies_to: any still reaches a combination product', () {
      final results = _serviceOf([
        _rule(
          id: 'timing_vitamin_d_with_food',
          ingredient1: 'vitamin d',
          ingredient1Tags: const ['vitamin_d'],
          relation: const {'type': 'with_food'},
          category: 'how_to_take',
          appliesTo: 'any',
        ),
      ]).evaluateStack(
        stackItems: const [
          TimingStackItem.supplement(
            stackEntryId: 'row-one-multi',
            displayName: 'O.N.E. Multivitamin',
            ingredientTags: _oneMultivitaminTags,
          ),
        ],
      );

      expect(results, hasLength(1));
    });
  });

  group('suppression: only verified rules can reach a user', () {
    for (final status in ['needs_revision', 'rejected']) {
      test('a $status rule is never indexed or emitted', () {
        final service = _serviceOf([
          _rule(
            id: 'timing_unverified',
            ingredient1Tags: const ['iron'],
            relation: const {'type': 'with_food'},
            category: 'how_to_take',
            reviewStatus: status,
          ),
        ]);

        expect(service.ruleCount, 0);
        expect(service.suppressedRuleCount, 1);
        expect(
          service.evaluateStack(
            stackItems: const [
              TimingStackItem.supplement(
                stackEntryId: 'row-iron',
                displayName: 'Gentle Iron',
                ingredientTags: {'iron'},
              ),
            ],
          ),
          isEmpty,
        );
      });
    }

    test('a migration-placeholder relation can never be verified', () {
      // The schema migration parked `with_food` on rules whose legacy
      // `take_together` had no equivalent. That value was never authored by the
      // pipeline, so promoting such a rule would publish a placeholder as
      // clinical guidance. The parser refuses rather than trusting review.
      Map<String, dynamic> placeholder(String status) =>
          _rule(
            id: 'timing_placeholder',
            ingredient1Tags: const ['calcium'],
            relation: const {'type': 'with_food'},
            category: 'how_to_take',
            reviewStatus: status,
          )..['_relation_is_migration_placeholder'] = true;

      expect(
        () => _serviceOf([placeholder('verified')]),
        throwsA(isA<FormatException>()),
      );
      // Suppressed is fine — that is where they all sit today.
      expect(_serviceOf([placeholder('needs_revision')]).ruleCount, 0);
    });

    test('no shipped placeholder rule is verified', () async {
      final json = await ReferenceDataRepository().loadTimingRules();
      for (final raw in json['timing_rules'] as List) {
        final rule = raw as Map;
        if (rule['_relation_is_migration_placeholder'] == true) {
          expect(
            rule['review_status'],
            isNot('verified'),
            reason: '${rule['id']} would ship a parked relation',
          );
        }
      }
    });

    test('a verified optional rule requires explicit clinician approval', () {
      expect(
        () => _serviceOf([
          _rule(
            id: 'timing_optional_unapproved',
            ingredient1Tags: const ['quercetin'],
            relation: const {'type': 'with_food'},
            category: 'optional',
          ),
        ]),
        throwsA(isA<FormatException>()),
      );

      expect(
        _serviceOf([
          _rule(
            id: 'timing_optional_approved',
            ingredient1Tags: const ['quercetin'],
            relation: const {'type': 'with_food'},
            category: 'optional',
            clinicianApproved: true,
          ),
        ]).ruleCount,
        1,
      );
    });
  });

  group('the artifact fails closed', () {
    Map<String, dynamic> validRule() => _rule(
      id: 'timing_valid',
      ingredient1Tags: const ['iron'],
      relation: const {'type': 'with_food'},
      category: 'how_to_take',
    );

    for (final field in [
      'category',
      'applies_to',
      'review_status',
      'actionability',
      'source_authority',
      'timing_relation',
    ]) {
      test('a rule missing $field is rejected', () {
        final rule = validRule()..remove(field);
        expect(
          () => _serviceOf([rule]),
          throwsA(isA<FormatException>()),
          reason: '$field must never default',
        );
      });
    }

    test('a malformed min_dose throws instead of dropping the gate', () {
      final rule = validRule()
        ..['min_dose'] = {'ingredient': 'iron', 'mg': 25};
      expect(
        () => _serviceOf([rule]),
        throwsA(isA<FormatException>()),
        reason:
            'the legacy key silently produced a rule that always fires; a dose '
            'gate either gates or the artifact is rejected',
      );
    });

    test('a separation without a second identity is rejected', () {
      final rule = validRule()
        ..['timing_relation'] = {'type': 'separate_from', 'minimum_hours': 4};
      expect(() => _serviceOf([rule]), throwsA(isA<FormatException>()));
    });

    test('a unary relation carrying a second identity is rejected', () {
      final rule = validRule()..['ingredient2_tags'] = ['calcium'];
      expect(() => _serviceOf([rule]), throwsA(isA<FormatException>()));
    });
  });

  group('conflicting guidance for one bottle yields silence, not a guess', () {
    test('with-food and empty-stomach on one row renders nothing', () {
      final guidance = builder.build([
        _optimization(
          ruleId: 'a_with_food',
          relation: const TimingRelation(type: TimingRelationType.withFood),
          product1Name: 'Combo',
          product1StackEntryId: 'row-combo',
        ),
        _optimization(
          ruleId: 'b_empty_stomach',
          relation: const TimingRelation(
            type: TimingRelationType.emptyStomach,
          ),
          product1Name: 'Combo',
          product1StackEntryId: 'row-combo',
        ),
      ]);

      expect(guidance.products, isEmpty);
      final issue = guidance.issues.single as ConflictingProductGuidance;
      expect(issue.productName, 'Combo');
      expect(issue.ruleIds, ['a_with_food', 'b_empty_stomach']);
    });
  });

  group('no findings is only asserted when the check finished', () {
    test('a clean empty result may say nothing was found', () {
      expect(builder.build(const []).canAssertNoFindings, isTrue);
    });

    test('an unavailable analysis may not', () {
      const guidance = TimingGuidance(
        issues: [AnalysisUnavailable(reason: 'artifact incompatible')],
      );
      expect(guidance.canAssertNoFindings, isFalse);
    });
  });
}
