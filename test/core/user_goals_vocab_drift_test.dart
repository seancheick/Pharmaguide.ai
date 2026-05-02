import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift contract test for the bundled user_goals_vocab.json asset.
///
/// Cutover safety net: keeps the vocab in lockstep with the
/// (still-shipping) `goalLabels` + `goalPriorities` maps in
/// `lib/core/constants/schema_ids.dart` until those maps are migrated
/// to read from the vocab.
void main() {
  group('user_goals_vocab.json drift contract', () {
    final file = File('assets/data/user_goals_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 18 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 18);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical 18 IDs match schema_ids.dart `goals`', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['user_goals'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'GOAL_SLEEP_QUALITY',
          'GOAL_REDUCE_STRESS_ANXIETY',
          'GOAL_INCREASE_ENERGY',
          'GOAL_DIGESTIVE_HEALTH',
          'GOAL_WEIGHT_MANAGEMENT',
          'GOAL_CARDIOVASCULAR_HEART_HEALTH',
          'GOAL_HEALTHY_AGING_LONGEVITY',
          'GOAL_BLOOD_SUGAR_SUPPORT',
          'GOAL_IMMUNE_SUPPORT',
          'GOAL_FOCUS_MENTAL_CLARITY',
          'GOAL_MOOD_EMOTIONAL_WELLNESS',
          'GOAL_MUSCLE_GROWTH_RECOVERY',
          'GOAL_JOINT_BONE_MOBILITY',
          'GOAL_SKIN_HAIR_NAILS',
          'GOAL_LIVER_DETOX',
          'GOAL_PRENATAL_PREGNANCY',
          'GOAL_HORMONAL_BALANCE',
          'GOAL_EYE_VISION_HEALTH',
        }),
      );
    });

    test('vocab `name` matches schema_ids.dart `goalLabels`', () {
      const expected = {
        'GOAL_SLEEP_QUALITY': 'Sleep Quality',
        'GOAL_REDUCE_STRESS_ANXIETY': 'Reduce Stress/Anxiety',
        'GOAL_INCREASE_ENERGY': 'Increase Energy',
        'GOAL_DIGESTIVE_HEALTH': 'Digestive Health',
        'GOAL_WEIGHT_MANAGEMENT': 'Weight Management',
        'GOAL_CARDIOVASCULAR_HEART_HEALTH': 'Cardiovascular/Heart Health',
        'GOAL_HEALTHY_AGING_LONGEVITY': 'Healthy Aging/Longevity',
        'GOAL_BLOOD_SUGAR_SUPPORT': 'Blood Sugar Support',
        'GOAL_IMMUNE_SUPPORT': 'Immune Support',
        'GOAL_FOCUS_MENTAL_CLARITY': 'Focus & Mental Clarity',
        'GOAL_MOOD_EMOTIONAL_WELLNESS': 'Mood & Emotional Wellness',
        'GOAL_MUSCLE_GROWTH_RECOVERY': 'Muscle Growth & Recovery',
        'GOAL_JOINT_BONE_MOBILITY': 'Joint & Bone Mobility',
        'GOAL_SKIN_HAIR_NAILS': 'Skin, Hair, & Nails',
        'GOAL_LIVER_DETOX': 'Liver & Detox Support',
        'GOAL_PRENATAL_PREGNANCY': 'Prenatal/Pregnancy Support',
        'GOAL_HORMONAL_BALANCE': 'Hormonal Balance',
        'GOAL_EYE_VISION_HEALTH': 'Eye & Vision Health',
      };

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['user_goals'] as List).cast<Map<String, dynamic>>();
      final byId = {for (final e in entries) e['id'] as String: e};

      for (final entry in expected.entries) {
        final g = byId[entry.key];
        expect(g, isNotNull, reason: 'goal ${entry.key} missing');
        expect(g!['name'], entry.value,
            reason: '${entry.key} drift: vocab=${g['name']} dart=${entry.value}');
      }
    });

    test('priority matches schema_ids.dart `goalPriorities`', () {
      const expected = {
        'GOAL_SLEEP_QUALITY': 'high',
        'GOAL_REDUCE_STRESS_ANXIETY': 'high',
        'GOAL_INCREASE_ENERGY': 'high',
        'GOAL_DIGESTIVE_HEALTH': 'medium',
        'GOAL_WEIGHT_MANAGEMENT': 'high',
        'GOAL_CARDIOVASCULAR_HEART_HEALTH': 'high',
        'GOAL_HEALTHY_AGING_LONGEVITY': 'high',
        'GOAL_BLOOD_SUGAR_SUPPORT': 'medium',
        'GOAL_IMMUNE_SUPPORT': 'high',
        'GOAL_FOCUS_MENTAL_CLARITY': 'high',
        'GOAL_MOOD_EMOTIONAL_WELLNESS': 'medium',
        'GOAL_MUSCLE_GROWTH_RECOVERY': 'medium',
        'GOAL_JOINT_BONE_MOBILITY': 'medium',
        'GOAL_SKIN_HAIR_NAILS': 'low',
        'GOAL_LIVER_DETOX': 'low',
        'GOAL_PRENATAL_PREGNANCY': 'high',
        'GOAL_HORMONAL_BALANCE': 'medium',
        'GOAL_EYE_VISION_HEALTH': 'low',
      };

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['user_goals'] as List).cast<Map<String, dynamic>>();
      final byId = {for (final e in entries) e['id'] as String: e};

      for (final entry in expected.entries) {
        expect(byId[entry.key]!['priority'], entry.value,
            reason: '${entry.key} priority drift');
      }
    });

    test('every entry has required fields populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['user_goals'] as List).cast<Map<String, dynamic>>();

      for (final g in entries) {
        for (final f in {'id', 'name', 'notes', 'priority'}) {
          expect(g[f], isA<String>(), reason: '${g['id']}: $f not string');
          expect((g[f] as String).trim().isNotEmpty, isTrue,
              reason: '${g['id']}: $f empty');
        }
        expect((g['notes'] as String).length, lessThanOrEqualTo(200),
            reason: '${g['id']}: notes >200 chars');
      }
    });
  });
}
