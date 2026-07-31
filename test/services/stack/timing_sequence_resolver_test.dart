// Tests for TimingSequenceResolver (roadmap Phase 3).
//
// The resolver arranges pipeline-emitted constraints into daily buckets. It is
// a pure function: it never invents a rule, never rewrites advice, and when a
// set cannot be satisfied it says so rather than inventing a compromise.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/services/stack/timing_sequence_resolver.dart';

TimingOptimization _rule({
  required String id,
  required String a,
  required String b,
  required TimingRuleType type,
  int? separationHours,
  int scoreImpact = -2,
  String advice = 'Pipeline-authored advice.',
  String? product1Name,
  String? product1StackEntryId,
  String? product2Name,
  String? product2StackEntryId,
  Set<DailySlot> allowedDailySlots = const {},
  bool dailyPlanEligible = true,
}) {
  return TimingOptimization(
    ruleId: id,
    ingredient1: a,
    ingredient2: b,
    advice: advice,
    ruleType: type,
    separationHours: separationHours,
    scoreImpact: scoreImpact,
    evidenceLevel: EvidenceLevel.established,
    product1Name: product1Name,
    product1StackEntryId: product1StackEntryId,
    product2Name: product2Name,
    product2StackEntryId: product2StackEntryId,
    allowedDailySlots: allowedDailySlots,
    dailyPlanEligible: dailyPlanEligible,
  );
}

DailySlot? _slotOf(TimingSequencePlan plan, String name) {
  for (final entry in plan.itemsBySlot.entries) {
    if (entry.value.contains(name)) return entry.key;
  }
  return null;
}

void main() {
  const resolver = TimingSequenceResolver();

  test('an empty constraint set yields an empty plan', () {
    final plan = resolver.resolve(const []);
    expect(plan.isEmpty, isTrue);
    expect(plan.isFullySatisfied, isTrue);
  });

  test('a separation constraint places items far enough apart', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_iron_calcium_separate',
        a: 'iron',
        b: 'calcium',
        type: TimingRuleType.separate,
        separationHours: 2,
      ),
    ]);

    expect(plan.isFullySatisfied, isTrue);
    final iron = _slotOf(plan, 'iron');
    final calcium = _slotOf(plan, 'calcium');
    expect(iron, isNotNull);
    expect(calcium, isNotNull);
    expect(
      (iron!.anchorHour - calcium!.anchorHour).abs(),
      greaterThanOrEqualTo(2),
    );
  });

  test('a take-together constraint places items in the same slot', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_iron_vitamin_c_together',
        a: 'iron',
        b: 'vitamin c',
        type: TimingRuleType.takeTogether,
      ),
    ]);

    expect(plan.isFullySatisfied, isTrue);
    expect(_slotOf(plan, 'iron'), _slotOf(plan, 'vitamin c'));
  });

  test('a with-food constraint lands in a food slot', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_vitamin_a_food',
        a: 'vitamin a',
        b: 'dietary fat',
        type: TimingRuleType.takeWithFood,
      ),
    ]);

    expect(_slotOf(plan, 'vitamin a')!.isWithFood, isTrue);
    // The food-context pseudo-ingredient is not a stack item.
    expect(_slotOf(plan, 'dietary fat'), isNull);
  });

  test('an empty-stomach constraint avoids food slots', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_iron_empty_stomach',
        a: 'iron',
        b: 'food',
        type: TimingRuleType.takeOnEmptyStomach,
      ),
    ]);

    expect(_slotOf(plan, 'iron')!.isWithFood, isFalse);
  });

  test('structured time-of-day slots are honored without parsing copy', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_magnesium_evening',
        a: 'magnesium',
        b: 'sleep',
        type: TimingRuleType.timeOfDay,
        advice: 'This wording intentionally contains no time keywords.',
        allowedDailySlots: const {DailySlot.withDinner, DailySlot.bedtime},
      ),
    ]);

    final slot = _slotOf(plan, 'magnesium');
    expect(slot == DailySlot.bedtime || slot == DailySlot.withDinner, isTrue);
  });

  test('time-of-day copy without structured slots fails closed', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_unstructured_evening',
        a: 'magnesium',
        b: 'sleep',
        type: TimingRuleType.timeOfDay,
        advice: 'Take this in the evening before bed.',
      ),
    ]);

    expect(_slotOf(plan, 'magnesium'), isNull);
    expect(plan.isFullySatisfied, isFalse);
    expect(plan.unsatisfied.single.ruleId, 'timing_unstructured_evening');
    expect(
      plan.unsatisfied.single.advice,
      'Take this in the evening before bed.',
    );
  });

  test('the plan schedules physical products, not nutrient components', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_iron_calcium_separate',
        a: 'iron',
        b: 'calcium',
        type: TimingRuleType.separate,
        separationHours: 2,
        product1Name: 'Iron tablet',
        product1StackEntryId: 'stack-iron',
        product2Name: 'Calcium K/D',
        product2StackEntryId: 'stack-calcium',
      ),
    ]);

    expect(_slotOf(plan, 'Iron tablet'), isNotNull);
    expect(_slotOf(plan, 'Calcium K/D'), isNotNull);
    expect(_slotOf(plan, 'iron'), isNull);
    expect(_slotOf(plan, 'calcium'), isNull);
  });

  test('duplicate display names remain distinct and resolve by stack id', () {
    final plan = resolver.resolve([
      _rule(
        id: 'iron_one_with_food',
        a: 'iron',
        b: 'food',
        type: TimingRuleType.takeWithFood,
        product1Name: 'Daily Mineral',
        product1StackEntryId: 'stack-first',
      ),
      _rule(
        id: 'iron_two_empty',
        a: 'iron',
        b: 'food',
        type: TimingRuleType.takeOnEmptyStomach,
        product1Name: 'Daily Mineral',
        product1StackEntryId: 'stack-second',
      ),
    ]);

    expect(plan.slotForStackEntryId('stack-first')?.isWithFood, isTrue);
    expect(plan.slotForStackEntryId('stack-second')?.isWithFood, isFalse);
    expect(
      plan.itemsBySlot.values.expand((items) => items),
      containsAllInOrder(['Daily Mineral', 'Daily Mineral']),
    );
  });

  test(
    'pipeline-ineligible conditional advice is not converted into a slot',
    () {
      final plan = resolver.resolve([
        _rule(
          id: 'timing_magnesium_evening',
          a: 'magnesium',
          b: 'sleep',
          type: TimingRuleType.timeOfDay,
          allowedDailySlots: const {DailySlot.bedtime},
          dailyPlanEligible: false,
        ),
      ]);

      expect(plan.isEmpty, isTrue);
      expect(plan.unsatisfied, isEmpty);
    },
  );

  test('an eligible binary rule without two products fails closed', () {
    const authored =
        'Take other medications at least three hours away from psyllium.';
    final plan = resolver.resolve([
      _rule(
        id: 'timing_psyllium_medications',
        a: 'psyllium',
        b: 'medications',
        type: TimingRuleType.separate,
        separationHours: 3,
        advice: authored,
        product1Name: 'Psyllium Husk',
      ),
    ]);

    expect(plan.isEmpty, isTrue);
    expect(plan.unsatisfied.single.advice, authored);
  });

  test('conflicting food guidance is reported, not silently resolved', () {
    // Both with-food and without-food for the same item: no honest slot exists.
    const withFoodAdvice = 'Take this product with food.';
    const emptyAdvice = 'Take this product on an empty stomach.';
    final plan = resolver.resolve([
      _rule(
        id: 'a_with_food',
        a: 'iron',
        b: 'food',
        type: TimingRuleType.takeWithFood,
        advice: withFoodAdvice,
      ),
      _rule(
        id: 'b_empty',
        a: 'iron',
        b: 'food',
        type: TimingRuleType.takeOnEmptyStomach,
        advice: emptyAdvice,
      ),
    ]);

    expect(plan.isFullySatisfied, isFalse);
    expect(plan.unsatisfied.map((item) => item.ruleId), [
      'a_with_food',
      'b_empty',
    ]);
    expect(plan.unsatisfied.map((item) => item.advice), [
      withFoodAdvice,
      emptyAdvice,
    ]);
  });

  test('a binary rule linked to an unplaceable product is also reported', () {
    const separationAdvice = 'Keep this product away from calcium.';
    final plan = resolver.resolve([
      _rule(
        id: 'a_with_food',
        a: 'iron',
        b: 'food',
        type: TimingRuleType.takeWithFood,
      ),
      _rule(
        id: 'b_empty',
        a: 'iron',
        b: 'food',
        type: TimingRuleType.takeOnEmptyStomach,
      ),
      _rule(
        id: 'c_separate',
        a: 'iron',
        b: 'calcium',
        type: TimingRuleType.separate,
        separationHours: 2,
        advice: separationAdvice,
      ),
    ]);

    expect(
      plan.unsatisfied
          .where((item) => item.ruleId == 'c_separate')
          .single
          .advice,
      separationAdvice,
    );
  });

  test('an over-constrained set reports what it dropped', () {
    // Four items each needing maximum separation cannot fit four buckets whose
    // widest gap is 15 hours.
    final plan = resolver.resolve([
      _rule(
        id: 'r1',
        a: 'a',
        b: 'b',
        type: TimingRuleType.separate,
        separationHours: 20,
      ),
    ]);

    expect(plan.isFullySatisfied, isFalse);
    expect(plan.unsatisfied, hasLength(1));
    expect(plan.unsatisfied.single.ruleId, 'r1');
  });

  test('a dropped constraint keeps the pipeline advice verbatim', () {
    const authored = 'Take these at least 20 hours apart.';
    final plan = resolver.resolve([
      _rule(
        id: 'r1',
        a: 'a',
        b: 'b',
        type: TimingRuleType.separate,
        separationHours: 20,
        advice: authored,
      ),
    ]);

    expect(plan.unsatisfied.single.advice, authored);
  });

  test('the higher-impact constraint survives when both cannot', () {
    final plan = resolver.resolve([
      _rule(
        id: 'weak',
        a: 'x',
        b: 'y',
        type: TimingRuleType.takeTogether,
        scoreImpact: -1,
      ),
      _rule(
        id: 'strong',
        a: 'x',
        b: 'y',
        type: TimingRuleType.separate,
        separationHours: 4,
        scoreImpact: -5,
      ),
    ]);

    expect(plan.unsatisfied, hasLength(1));
    expect(plan.unsatisfied.single.ruleId, 'weak');
  });

  test('the plan is identical under reordered input', () {
    final constraints = [
      _rule(
        id: 'timing_iron_calcium_separate',
        a: 'iron',
        b: 'calcium',
        type: TimingRuleType.separate,
        separationHours: 2,
      ),
      _rule(
        id: 'timing_iron_vitamin_c_together',
        a: 'iron',
        b: 'vitamin c',
        type: TimingRuleType.takeTogether,
      ),
      _rule(
        id: 'timing_magnesium_evening',
        a: 'magnesium',
        b: 'sleep',
        type: TimingRuleType.timeOfDay,
        advice: 'Evening is a reasonable wind-down habit.',
        allowedDailySlots: const {DailySlot.withDinner, DailySlot.bedtime},
      ),
    ];

    final forward = resolver.resolve(constraints);
    final reversed = resolver.resolve(constraints.reversed.toList());

    for (final slot in DailySlot.values) {
      expect(
        reversed.itemsBySlot[slot],
        forward.itemsBySlot[slot],
        reason: 'slot $slot must not depend on input order',
      );
    }
  });

  test('a realistic multi-constraint stack resolves fully', () {
    final plan = resolver.resolve([
      _rule(
        id: 'timing_iron_calcium_separate',
        a: 'iron',
        b: 'calcium',
        type: TimingRuleType.separate,
        separationHours: 2,
      ),
      _rule(
        id: 'timing_iron_vitamin_c_together',
        a: 'iron',
        b: 'vitamin c',
        type: TimingRuleType.takeTogether,
      ),
      _rule(
        id: 'timing_vitamin_d_food',
        a: 'vitamin d',
        b: 'dietary fat',
        type: TimingRuleType.takeWithFood,
      ),
      _rule(
        id: 'timing_magnesium_evening',
        a: 'magnesium',
        b: 'sleep',
        type: TimingRuleType.timeOfDay,
        advice: 'Evening is a reasonable wind-down habit.',
        allowedDailySlots: const {DailySlot.withDinner, DailySlot.bedtime},
      ),
    ]);

    expect(plan.isFullySatisfied, isTrue);
    expect(_slotOf(plan, 'iron'), _slotOf(plan, 'vitamin c'));
    expect(_slotOf(plan, 'vitamin d')!.isWithFood, isTrue);
    expect(plan.orderedItems, isNotEmpty);
  });
}
