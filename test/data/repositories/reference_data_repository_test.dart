import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReferenceDataRepository', () {
    late ReferenceDataRepository repo;

    setUp(() {
      repo = ReferenceDataRepository();
    });

    test(
      'loads every selectable clinical condition without schema drift',
      () async {
        final taxonomy = await repo.loadClinicalRiskTaxonomy();
        expect(taxonomy, isNotNull);
        final conditions = taxonomy['conditions'] as List;
        final conditionIds = conditions
            .map((entry) => (entry as Map)['id'] as String)
            .toSet();

        expect(conditions.length, 15);
        expect((conditions.first as Map)['id'], 'pregnancy');
        expect(conditionIds, contains('immunocompromised'));
        expect(conditionIds, hasLength(15));
      },
    );

    test('loads the complete clinical drug-class taxonomy', () async {
      final taxonomy = await repo.loadClinicalRiskTaxonomy();
      final drugClasses = taxonomy['drug_classes'] as List;
      final metadata = taxonomy['_metadata'] as Map;
      expect(drugClasses.length, metadata['drug_classes_count']);
      expect(drugClasses.length, 30);
      expect((drugClasses.first as Map)['id'], 'anticoagulants');
      expect(
        drugClasses.map((entry) => (entry as Map)['id']),
        containsAll(['serotonergic_medications', 'vitamin_k_antagonists']),
      );
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

    test(
      'builds the selectable clinical profile from taxonomy metadata',
      () async {
        final schema = await repo.loadClinicalProfileSchema();

        expect(schema.selectableConditions, hasLength(15));
        expect(
          schema.selectableConditions.map((entry) => entry.id),
          contains('immunocompromised'),
        );
        expect(schema.userSelectableFlags.map((entry) => entry.id), [
          'severely_immunocompromised',
        ]);
        expect(schema.derivedFlagByCondition, {
          'pregnancy': 'pregnant',
          'ttc': 'trying_to_conceive',
          'lactation': 'breastfeeding',
          'surgery_scheduled': 'surgery_scheduled',
        });
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

    test('loads timing_rules placeholder', () async {
      final timing = await repo.loadTimingRules();
      expect(timing['timing_rules'], isA<List<dynamic>>());
    });

    test(
      'timing_rules keeps only corrected evidence-based timing rules',
      () async {
        // Regression guard for the evidence-based corrections: Ca↔Mg
        // "competition" was removed; zinc↔copper is a chronic-dose concern, not
        // a timing one. Magnesium sleep timing was later re-added only as a
        // cautious, non-scoring evening-routine suggestion with sleep-specific
        // evidence.
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
          'timing_collagen_empty_stomach',
          'timing_probiotics_empty_stomach',
        ]) {
          expect(
            ids,
            isNot(contains(removed)),
            reason: '$removed is unsupported as timing advice',
          );
        }

        // The magnesium rule was reframed to evidence-based GI-tolerance guidance.
        final mag = rules.firstWhere(
          (r) => r['id'] == 'timing_magnesium_with_food',
        );
        expect(mag['rule_type'], 'take_with_food');

        final magEvening = rules.firstWhere(
          (r) => r['id'] == 'timing_magnesium_evening',
        );
        expect(magEvening['rule_type'], 'time_of_day');
        expect(magEvening['score_impact'], 0);
        expect(magEvening['evidence_level'], 'possible');
        expect(magEvening['advice'], contains('not a proven sleep aid'));
        expect(
          (magEvening['sources'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((s) => s['url']),
          containsAll([
            'https://pubmed.ncbi.nlm.nih.gov/35184264/',
            'https://pubmed.ncbi.nlm.nih.gov/33865376/',
          ]),
        );
      },
    );

    test('timing_rules excludes dead legacy source URLs', () async {
      final timing = await repo.loadTimingRules();
      final rules = (timing['timing_rules']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final urls = <String>[
        for (final rule in rules)
          for (final source in (rule['sources'] as List<dynamic>? ?? const []))
            if (source is Map && source['url'] is String)
              source['url'] as String,
      ];

      for (final deadUrl in const [
        'https://lpi.oregonstate.edu/mic/dietary-factors/probiotics',
        'https://lpi.oregonstate.edu/mic/dietary-factors/curcumin',
        'https://lpi.oregonstate.edu/mic/dietary-factors/phytochemicals/N-acetylcysteine',
        'https://www.accessdata.fda.gov/drugsatfda_docs/label/2020/021402s043lbl.pdf',
        'https://lpi.oregonstate.edu/mic/dietary-factors/berberine',
        'https://lpi.oregonstate.edu/mic/dietary-factors/alpha-lipoic-acid',
        'https://lpi.oregonstate.edu/mic/dietary-factors/collagen',
        'https://lpi.oregonstate.edu/mic/dietary-factors/quercetin',
        'https://lpi.oregonstate.edu/mic/dietary-factors/bromelain',
        'https://lpi.oregonstate.edu/mic/dietary-factors/ashwagandha',
      ]) {
        expect(urls, isNot(contains(deadUrl)), reason: '$deadUrl returned 404');
      }
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
