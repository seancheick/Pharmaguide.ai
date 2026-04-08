import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

void main() {
  late UserDatabase db;

  setUp(() {
    db = UserDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('ProfileState DB serialization', () {
    test('toCompanion encodes lists as JSON', () {
      const state = ProfileState(
        nickname: 'Sean',
        ageBracket: '19-30',
        sex: 'Male',
        goals: ['GOAL_SLEEP_QUALITY', 'GOAL_INCREASE_ENERGY'],
        conditions: ['diabetes', 'hypertension'],
        drugClasses: ['statins'],
        allergens: ['ALLERGEN_SOY', 'ALLERGEN_GLUTEN'],
      );
      final companion = state.toCompanion();
      expect(companion.goals.value, '["GOAL_SLEEP_QUALITY","GOAL_INCREASE_ENERGY"]');
      expect(companion.conditions.value, '["diabetes","hypertension"]');
      expect(companion.drugClasses.value, '["statins"]');
      expect(companion.allergens.value, '["ALLERGEN_SOY","ALLERGEN_GLUTEN"]');
    });

    test('toCompanion handles empty lists', () {
      const state = ProfileState();
      final companion = state.toCompanion();
      expect(companion.goals.value, '[]');
      expect(companion.conditions.value, '[]');
    });
  });

  group('Profile DB roundtrip', () {
    test('save and load preserves all fields', () async {
      const original = ProfileState(
        nickname: 'Sean',
        ageBracket: '19-30',
        sex: 'Male',
        goals: ['GOAL_SLEEP_QUALITY', 'GOAL_INCREASE_ENERGY'],
        conditions: ['diabetes', 'hypertension'],
        drugClasses: ['statins', 'antihypertensives'],
        allergens: ['ALLERGEN_SOY'],
      );

      await db.saveProfile(original.toCompanion());
      final row = await db.getProfile();

      expect(row, isNotNull);
      final loaded = ProfileState.fromDbRow(row!);
      expect(loaded.nickname, 'Sean');
      expect(loaded.ageBracket, '19-30');
      expect(loaded.sex, 'Male');
      expect(loaded.goals, ['GOAL_SLEEP_QUALITY', 'GOAL_INCREASE_ENERGY']);
      expect(loaded.conditions, ['diabetes', 'hypertension']);
      expect(loaded.drugClasses, ['statins', 'antihypertensives']);
      expect(loaded.allergens, ['ALLERGEN_SOY']);
    });

    test('save overwrites previous profile (upsert)', () async {
      const first = ProfileState(nickname: 'First', ageBracket: '19-30');
      await db.saveProfile(first.toCompanion());

      const second = ProfileState(
        nickname: 'Updated',
        ageBracket: '31-50',
        sex: 'Female',
        goals: ['GOAL_DIGESTIVE_HEALTH'],
      );
      await db.saveProfile(second.toCompanion());

      final row = await db.getProfile();
      final loaded = ProfileState.fromDbRow(row!);
      expect(loaded.nickname, 'Updated');
      expect(loaded.ageBracket, '31-50');
      expect(loaded.sex, 'Female');
      expect(loaded.goals, ['GOAL_DIGESTIVE_HEALTH']);
    });

    test('getProfile returns null when no profile saved', () async {
      final row = await db.getProfile();
      expect(row, isNull);
    });

    test('empty profile roundtrips correctly', () async {
      const empty = ProfileState();
      await db.saveProfile(empty.toCompanion());
      final row = await db.getProfile();
      final loaded = ProfileState.fromDbRow(row!);
      expect(loaded.nickname, isNull);
      expect(loaded.ageBracket, isNull);
      expect(loaded.goals, isEmpty);
      expect(loaded.conditions, isEmpty);
      expect(loaded.drugClasses, isEmpty);
      expect(loaded.allergens, isEmpty);
    });
  });

  group('ProfileNotifier with DB', () {
    test('loadFromDb restores saved state', () async {
      // Save a profile directly
      const saved = ProfileState(
        nickname: 'TestUser',
        ageBracket: '31-50',
        conditions: ['pregnancy'],
      );
      await db.saveProfile(saved.toCompanion());

      // Create notifier with DB and load
      final notifier = ProfileNotifier(db);
      await notifier.loadFromDb();

      expect(notifier.state.nickname, 'TestUser');
      expect(notifier.state.ageBracket, '31-50');
      expect(notifier.state.conditions, ['pregnancy']);
    });

    test('saveToDb persists current state', () async {
      final notifier = ProfileNotifier(db);
      notifier.setNickname('Persisted');
      notifier.setAgeBracket('51-70');
      notifier.toggleGoal('GOAL_IMMUNE_SUPPORT');
      notifier.toggleCondition('diabetes');
      notifier.toggleDrugClass('statins');
      notifier.toggleAllergen('ALLERGEN_MILK');

      await notifier.saveToDb();

      // Read back from DB directly
      final row = await db.getProfile();
      final loaded = ProfileState.fromDbRow(row!);
      expect(loaded.nickname, 'Persisted');
      expect(loaded.ageBracket, '51-70');
      expect(loaded.goals, ['GOAL_IMMUNE_SUPPORT']);
      expect(loaded.conditions, ['diabetes']);
      expect(loaded.drugClasses, ['statins']);
      expect(loaded.allergens, ['ALLERGEN_MILK']);
    });

    test('loadFromDb with no saved profile keeps default state', () async {
      final notifier = ProfileNotifier(db);
      await notifier.loadFromDb();
      expect(notifier.state.nickname, isNull);
      expect(notifier.state.completeness, 0);
    });

    test('notifier without DB still works (no persistence)', () async {
      final notifier = ProfileNotifier();
      notifier.setNickname('NoDB');
      await notifier.saveToDb(); // Should not throw
      await notifier.loadFromDb(); // Should not throw
      expect(notifier.state.nickname, 'NoDB');
    });
  });
}
