import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/data/clinical_profile_schema.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

void main() {
  group('ProfileState', () {
    test('copyWith clears only explicitly null nullable fields', () {
      const state = ProfileState(
        nickname: 'Sean',
        ageBracket: '71+',
        sex: 'Female',
        goals: ['GOAL_SLEEP_QUALITY'],
        conditions: ['pregnancy'],
        drugClasses: ['anticoagulants'],
        allergens: ['ALLERGEN_SOY'],
        profileFlags: ['bleeding_history'],
      );
      for (final cleared in [
        state.copyWith(nickname: null),
        state.copyWith(ageBracket: null),
        state.copyWith(sex: null),
      ]) {
        expect(cleared.goals, state.goals);
        expect(cleared.conditions, state.conditions);
        expect(cleared.drugClasses, state.drugClasses);
        expect(cleared.allergens, state.allergens);
        expect(cleared.profileFlags, state.profileFlags);
      }
      expect(state.copyWith(nickname: null).nickname, isNull);
      expect(state.copyWith(nickname: null).ageBracket, '71+');
      expect(state.copyWith(ageBracket: null).ageBracket, isNull);
      expect(state.copyWith(ageBracket: null).sex, 'Female');
      expect(state.copyWith(sex: null).sex, isNull);
      expect(state.copyWith(sex: null).nickname, 'Sean');
      expect(state.copyWith().nickname, 'Sean');
      expect(state.copyWith().ageBracket, '71+');
      expect(state.copyWith().sex, 'Female');
    });

    test('empty profile has no fields set', () {
      const state = ProfileState();
      expect(state.ageBracket, isNull);
      expect(state.sex, isNull);
      expect(state.goals, isEmpty);
    });
  });

  group('ProfileNotifier', () {
    test('nullable setters clear demographics and notify consumers', () {
      final notifier = ProfileNotifier();
      final container = ProviderContainer(
        overrides: [profileProvider.overrideWith((ref) => notifier)],
      );
      addTearDown(container.dispose);
      final observed = <ProfileState>[];
      container.listen(profileProvider, (_, next) => observed.add(next));
      notifier.setNickname('Sean');
      notifier.setAgeBracket('71+');
      notifier.setSex('Female');
      notifier.setGoals(['GOAL_SLEEP_QUALITY']);
      notifier.setAgeBracket(null);
      expect(container.read(profileProvider).ageBracket, isNull);
      expect(container.read(profileProvider).sex, 'Female');
      notifier.setSex(null);
      notifier.setNickname(null);
      final cleared = container.read(profileProvider);
      expect(cleared.ageBracket, isNull);
      expect(cleared.sex, isNull);
      expect(cleared.nickname, isNull);
      expect(cleared.goals, ['GOAL_SLEEP_QUALITY']);
      expect(cleared.toCompanion().ageBracket.value, isNull);
      expect(cleared.toCompanion().sex.value, isNull);
      expect(observed.last, same(cleared));
      expect(observed[observed.length - 3].ageBracket, isNull);
    });

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

    test(
      'evaluator flags follow the canonical clinical profile schema',
      () async {
        final notifier = ProfileNotifier();
        notifier.toggleCondition('future_condition');
        notifier.setProfileFlags([
          'bleeding_history',
          'severely_immunocompromised',
        ]);
        expect(notifier.state.profileFlags, [
          'bleeding_history',
          'severely_immunocompromised',
        ]);

        final container = ProviderContainer(
          overrides: [
            profileProvider.overrideWith((ref) => notifier),
            clinicalProfileSchemaProvider.overrideWith(
              (ref) async => const ClinicalProfileSchema(
                selectableConditions: [],
                userSelectableFlags: [],
                derivedFlagByCondition: {
                  'future_condition': 'future_derived_flag',
                },
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        expect(
          await container.read(evaluatorProfileFlagsProvider.future),
          containsAll([
            'bleeding_history',
            'severely_immunocompromised',
            'future_derived_flag',
          ]),
        );
      },
    );

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
