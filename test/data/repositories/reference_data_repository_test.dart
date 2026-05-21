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

    test('loads clinical_risk_taxonomy with 23 drug classes', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      final drugClasses = taxonomy['drug_classes'] as List;
      expect(drugClasses.length, 23);
      expect((drugClasses.first as Map)['id'], 'anticoagulants');
    });

    test('loads v6 profile gate taxonomy blocks', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      expect(taxonomy['profile_flags'], isA<List<dynamic>>());
      expect(taxonomy['product_forms'], isA<List<dynamic>>());
      expect((taxonomy['profile_flags'] as List).length, 8);
      expect((taxonomy['product_forms'] as List).length, 9);
    });

    test(
      'normalizes banned_recalled_ingredients for stack consumers',
      () async {
        final recallData = await repo.loadBannedRecalledIngredients();
        expect(recallData.containsKey('ingredients'), isFalse);
        expect(recallData['recalled_ingredients'], isA<List<dynamic>>());

        final entries = recallData['recalled_ingredients'] as List<dynamic>;
        expect(entries.length, 156);

        final first = entries.first as Map<dynamic, dynamic>;
        expect(first['canonical_id'], 'ADULTERANT_MELOXICAM');
        expect(first['common_names'], isA<List<dynamic>>());
        expect(first['recall_status'], 'banned');
        expect(first['severity'], 'critical');
        expect((first['safety_warning'] as String).trim(), isNotEmpty);
      },
    );

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

    test('RDA omega reference is ALA, not EPA/DHA or fish-oil mass', () async {
      final rda = await repo.loadRdaOptimalUls();
      final entries = rda['nutrient_recommendations']! as List<dynamic>;
      final ids = entries
          .whereType<Map<dynamic, dynamic>>()
          .map((entry) => entry['id'])
          .toSet();

      expect(ids, contains('alpha_linolenic_acid'));
      expect(ids, isNot(contains('omega_3_fatty_acids')));
    });

    test('loads timing_rules placeholder', () async {
      final timing = await repo.loadTimingRules();
      expect(timing['timing_rules'], isA<List<dynamic>>());
    });

    test('caches after first load', () async {
      final first = await repo.loadClinicalRiskTaxonomy();
      final second = await repo.loadClinicalRiskTaxonomy();
      expect(identical(first, second), true);
    });
  });
}
