import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

void main() {
  group('ProfileState', () {
    test('empty profile has no fields set', () {
      const state = ProfileState();
      expect(state.ageBracket, isNull);
      expect(state.sex, isNull);
      expect(state.goals, isEmpty);
    });
  });

  group('ProfileNotifier', () {
    test('toggleGoal adds and removes', () {
      final notifier = ProfileNotifier();
      notifier.toggleGoal('GOAL_SLEEP_QUALITY');
      expect(notifier.state.goals, ['GOAL_SLEEP_QUALITY']);
      notifier.toggleGoal('GOAL_SLEEP_QUALITY');
      expect(notifier.state.goals, isEmpty);
    });

    test('toggleGoal enforces max 2', () {
      final notifier = ProfileNotifier();
      notifier.toggleGoal('GOAL_SLEEP_QUALITY');
      notifier.toggleGoal('GOAL_INCREASE_ENERGY');
      notifier.toggleGoal('GOAL_DIGESTIVE_HEALTH'); // Should be ignored
      expect(notifier.state.goals, hasLength(2));
      expect(notifier.state.goals, contains('GOAL_SLEEP_QUALITY'));
      expect(notifier.state.goals, contains('GOAL_INCREASE_ENERGY'));
    });

    test('toggleCondition adds and removes', () {
      final notifier = ProfileNotifier();
      notifier.toggleCondition('pregnancy');
      expect(notifier.state.conditions, ['pregnancy']);
      notifier.toggleCondition('pregnancy');
      expect(notifier.state.conditions, isEmpty);
    });

    test('toggleDrugClass adds and removes', () {
      final notifier = ProfileNotifier();
      notifier.toggleDrugClass('anticoagulants');
      expect(notifier.state.drugClasses, ['anticoagulants']);
      notifier.toggleDrugClass('anticoagulants');
      expect(notifier.state.drugClasses, isEmpty);
    });

    test('toggleAllergen adds and removes', () {
      final notifier = ProfileNotifier();
      notifier.toggleAllergen('ALLERGEN_SOY');
      expect(notifier.state.allergens, ['ALLERGEN_SOY']);
      notifier.toggleAllergen('ALLERGEN_SOY');
      expect(notifier.state.allergens, isEmpty);
    });

    test('copyWith preserves unmodified fields', () {
      const state = ProfileState(
        nickname: 'Sean',
        ageBracket: '19-30',
        sex: 'Male',
      );
      final updated = state.copyWith(goals: ['GOAL_SLEEP_QUALITY']);
      expect(updated.nickname, 'Sean');
      expect(updated.ageBracket, '19-30');
      expect(updated.goals, ['GOAL_SLEEP_QUALITY']);
    });
  });
}
