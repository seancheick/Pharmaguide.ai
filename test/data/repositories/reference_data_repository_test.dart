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

    test('loads clinical_risk_taxonomy with 9 drug classes', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      final drugClasses = taxonomy['drug_classes'] as List;
      expect(drugClasses.length, 9);
      expect((drugClasses.first as Map)['id'], 'anticoagulants');
    });

    test('loads user_goals_to_clusters with 18 goals', () async {
      final goals = await repo.loadGoalMappings();
      final mappings = goals['user_goal_mappings'] as List;
      expect(mappings.length, 18);
      expect((mappings.first as Map)['id'], 'GOAL_SLEEP_QUALITY');
    });

    test('loads rda_optimal_uls with nutrient data', () async {
      final rda = await repo.loadRdaOptimalUls();
      expect(rda['nutrient_recommendations'], isA<List>());
      expect((rda['nutrient_recommendations'] as List).isNotEmpty, true);
    });

    test('loads timing_rules placeholder', () async {
      final timing = await repo.loadTimingRules();
      expect(timing['timing_rules'], isA<List>());
    });

    test('caches after first load', () async {
      final first = await repo.loadClinicalRiskTaxonomy();
      final second = await repo.loadClinicalRiskTaxonomy();
      expect(identical(first, second), true);
    });
  });
}
