// End-to-end canary for the failure that started this work.
//
// The audit reported: "Calcium K/D -> Morning, before food; Levothyroxine ->
// With dinner". A prescription medication was assigned a mealtime by a solver,
// contradicting its own label, which directs empty-stomach administration
// one-half to one hour before breakfast.
//
// This runs the SHIPPED rule artifact against the SHIPPED catalog tags, through
// the real service and builder, and asserts what the user now sees.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';

/// Calcium K/D — Pure Encapsulations, dsld_id 246021 / 299036, tags exactly as
/// shipped. Note there is no bare `vitamin_k`; that was the tag the old rule
/// set matched on, reaching 248 of 802 vitamin-K products.
const _calciumKdTags = {'vitamin_d', 'vitamin_k1', 'calcium', 'vitamin_k2'};

/// O.N.E. Multivitamin — dsld_id 278010. One capsule carrying both an
/// empty-stomach ingredient and several with-food ingredients.
const _oneMultivitaminTags = {
  'vitamin_a',
  'vitamin_c',
  'vitamin_d',
  'vitamin_e',
  'zinc',
  'alpha_lipoic_acid',
};

const _levothyroxineRxcui = '10582';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TimingEvaluationService service;
  const builder = TimingGuidanceBuilder();

  setUpAll(() async {
    service = TimingEvaluationService.fromJson(
      await ReferenceDataRepository().loadTimingRules(),
    );
  });

  TimingGuidance guidanceFor(List<TimingStackItem> stack) =>
      builder.build(service.evaluateStack(stackItems: stack));

  const levothyroxine = TimingStackItem.medication(
    stackEntryId: 'row-levothyroxine',
    displayName: 'Levothyroxine',
    medicationRxCuis: {_levothyroxineRxcui},
  );
  const calciumKd = TimingStackItem.supplement(
    stackEntryId: 'row-calcium-kd',
    displayName: 'Calcium K/D',
    ingredientTags: _calciumKdTags,
  );

  group('levothyroxine + Calcium K/D', () {
    test('the separation is surfaced, on the supplement row', () {
      final guidance = guidanceFor(const [calciumKd, levothyroxine]);

      expect(
        guidance.products,
        hasLength(1),
        reason: 'guidance attaches to the bottle, not the prescription',
      );
      final product = guidance.products.single;
      expect(product.stackEntryId, 'row-calcium-kd');
      expect(product.productName, 'Calcium K/D');
      expect(product.importantSeparation, hasLength(1));
    });

    test('the interval is the label"s four hours', () {
      final finding = guidanceFor(const [
        calciumKd,
        levothyroxine,
      ]).products.single.importantSeparation.single;

      expect(finding.relation.type, TimingRelationType.separateFrom);
      expect(finding.relation.minimumHours, 4);
      expect(finding.sourceAuthority, SourceAuthority.fdaLabel);
      expect(finding.involvesMedication, isTrue);
      expect(
        finding.sourceUrls.any((u) => u.contains('dailymed')),
        isTrue,
        reason: 'the interval authority must be citable by the user',
      );
    });

    test('the medication is never assigned a time', () {
      final guidance = guidanceFor(const [calciumKd, levothyroxine]);

      expect(
        guidance.products.map((p) => p.stackEntryId),
        isNot(contains('row-levothyroxine')),
      );
      // No daypart survives anywhere in what the user reads.
      final rendered = [
        for (final product in guidance.products)
          for (final item in [
            ...product.importantSeparation,
            ...product.howToTake,
            ...product.optional,
          ])
            item.advice,
      ].join(' ').toLowerCase();
      for (final daypart in [
        'breakfast',
        'lunch',
        'dinner',
        'bedtime',
        'with food',
      ]) {
        expect(
          rendered,
          isNot(contains(daypart)),
          reason: 'a prescription schedule is the prescriber"s, not the app"s',
        );
      }
    });
  });

  group('the rest of the reported failure set stays quiet', () {
    test('O.N.E. Multivitamin produces no conflict and no instruction', () {
      // Also guards the standalone gate's composition half: with the vitamin
      // A, K and zinc rules retired, `vitamin_e` became the only
      // timing-relevant tag on this 25-ingredient capsule, and a
      // rule-coverage-only gate briefly let it qualify as a standalone
      // vitamin E supplement.
      final guidance = guidanceFor(const [
        TimingStackItem.supplement(
          stackEntryId: 'row-one-multi',
          displayName: 'O.N.E. Multivitamin',
          ingredientTags: _oneMultivitaminTags,
        ),
      ]);

      expect(guidance.issues.whereType<ConflictingProductGuidance>(), isEmpty);
      expect(guidance.products, isEmpty);
      expect(guidance.canAssertNoFindings, isTrue);
    });

    test('a caffeine tablet with iron emits no coffee advice', () {
      final results = service.evaluateStack(
        stackItems: const [
          TimingStackItem.supplement(
            stackEntryId: 'row-caffeine',
            displayName: 'Caffeine 200mg',
            ingredientTags: {'caffeine'},
          ),
          TimingStackItem.supplement(
            stackEntryId: 'row-iron',
            displayName: 'Gentle Iron',
            ingredientTags: {'iron'},
          ),
        ],
      );
      expect(
        results.map((r) => r.advice.toLowerCase()),
        everyElement(isNot(contains('coffee'))),
      );
    });

    test('a guarana product with iron emits no coffee advice', () {
      final results = service.evaluateStack(
        stackItems: const [
          TimingStackItem.supplement(
            stackEntryId: 'row-guarana',
            displayName: 'Guarana Extract',
            ingredientTags: {'guarana'},
          ),
          TimingStackItem.supplement(
            stackEntryId: 'row-iron',
            displayName: 'Gentle Iron',
            ingredientTags: {'iron'},
          ),
        ],
      );
      expect(
        results.map((r) => r.advice.toLowerCase()),
        everyElement(isNot(contains('coffee'))),
      );
    });

    test('an iron bottle alone carries only administration guidance', () {
      const iron = TimingStackItem.supplement(
        stackEntryId: 'row-iron',
        displayName: 'Iron 28 mg',
        ingredientTags: {'iron'},
      );
      final alone = guidanceFor(const [iron]).products.single;

      // The levothyroxine separation needs the medication present.
      expect(alone.importantSeparation, isEmpty);
      // What a lone iron bottle does get is the GI note, which is what the
      // NIH ODS iron page actually supports: "Taking iron supplements with
      // food can help minimize these adverse effects." The rule this replaced
      // told users the opposite.
      expect(alone.howToTake, hasLength(1));
      expect(alone.howToTake.single.ruleId, 'timing_iron_with_food_gi');
      expect(
        alone.howToTake.single.relation.type,
        TimingRelationType.withFood,
      );
    });

    test('adding levothyroxine adds the separation without losing the '
        'administration note', () {
      const iron = TimingStackItem.supplement(
        stackEntryId: 'row-iron',
        displayName: 'Iron 28 mg',
        ingredientTags: {'iron'},
      );
      final product = guidanceFor(const [
        iron,
        levothyroxine,
      ]).products.singleWhere((p) => p.stackEntryId == 'row-iron');

      expect(product.importantSeparation.single.relation.minimumHours, 4);
      expect(product.howToTake.single.ruleId, 'timing_iron_with_food_gi');
      // Ordering: the drug-absorption finding outranks the comfort note.
      expect(
        product.importantSeparation.single.displayPriority,
        greaterThan(product.howToTake.single.displayPriority),
      );
    });
  });
}
