import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReferenceDataRepository', () {
    late ReferenceDataRepository repo;

    setUp(() {
      repo = ReferenceDataRepository();
    });

    test('loads clinical_risk_taxonomy with 14 conditions', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      expect(taxonomy, isNotNull);
      final conditions = taxonomy['conditions'] as List;
      expect(conditions.length, 14);
      expect((conditions.first as Map)['id'], 'pregnancy');
    });

    test('loads clinical_risk_taxonomy with 28 drug classes', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      final drugClasses = taxonomy['drug_classes'] as List;
      expect(drugClasses.length, 28);
      expect((drugClasses.first as Map)['id'], 'anticoagulants');
    });

    test('loads clinical_risk_taxonomy with 8 profile flags', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      final profileFlags = taxonomy['profile_flags'] as List;
      expect(profileFlags.length, 8);
      expect(
        profileFlags.map((entry) => (entry as Map)['id']),
        containsAll(['pregnant', 'trying_to_conceive', 'bleeding_history']),
      );
    });

    test('loads user_goals_to_clusters with 18 goals', () async {
      final goals = await repo.loadGoalMappings();
      final mappings = goals['user_goal_mappings'] as List;
      expect(mappings.length, 18);
      expect((mappings.first as Map)['id'], 'GOAL_SLEEP_QUALITY');
    });

    test('loads rda_optimal_uls with nutrient data', () async {
      final rda = await repo.loadRdaOptimalUls();
      expect(rda['nutrient_recommendations'], isA<List<dynamic>>());
      expect(
        (rda['nutrient_recommendations']! as List<dynamic>).isNotEmpty,
        true,
      );
    });

    test('loads timing_rules placeholder', () async {
      final timing = await repo.loadTimingRules();
      expect(timing['timing_rules'], isA<List<dynamic>>());
    });

    test('timing_rules excludes the folklore rules removed 2026-06-27', () async {
      // Regression guard for the evidence-based corrections: Ca↔Mg
      // "competition" and the time-of-day sleep claims are folklore and were
      // removed; zinc↔copper is a chronic-dose concern, not a timing one.
      // See knowledge/timing-rules-research.md.
      final timing = await repo.loadTimingRules();
      final rules = (timing['timing_rules']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final ids = rules.map((r) => r['id'] as String).toSet();

      for (final removed in const [
        'timing_calcium_magnesium_separate',
        'timing_zinc_copper_separate',
        'timing_vitamin_d_morning',
        'timing_b_vitamins_morning',
        'timing_magnesium_evening',
      ]) {
        expect(ids, isNot(contains(removed)), reason: '$removed is folklore');
      }

      // The magnesium rule was reframed to evidence-based GI-tolerance guidance.
      final mag = rules.firstWhere(
        (r) => r['id'] == 'timing_magnesium_with_food',
      );
      expect(mag['rule_type'], 'take_with_food');
    });

    test('loads medication_profile_gate_rules asset', () async {
      final rulesData = await repo.loadMedicationProfileGateRules();
      final rules = rulesData['medication_profile_gate_rules'] as List;
      expect(rules, isNotEmpty);
      expect((rules.first as Map)['id'], 'MCR_PREGNANCY_NSAIDS');
    });

    test('caches after first load', () async {
      final first = await repo.loadClinicalRiskTaxonomy();
      final second = await repo.loadClinicalRiskTaxonomy();
      expect(identical(first, second), true);
    });

    test('caches medication_profile_gate_rules after first load', () async {
      final first = await repo.loadMedicationProfileGateRules();
      final second = await repo.loadMedicationProfileGateRules();
      expect(identical(first, second), true);
    });
  });
}
