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
        // Regression guard for the evidence-based corrections: Ca<->Mg
        // "competition" was removed; zinc<->copper is a chronic-dose concern,
        // not a timing one. Magnesium-evening was REJECTED on 2026-08-01 — its
        // own mechanism text conceded no trial compares evening to morning
        // dosing, and with the scheduler gone it had no defensible relation.
        // See knowledge/timing-rules-research.md and
        // dsld_clean/scripts/data/timing_rules_rejected.json.
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
          'timing_magnesium_evening',
          // Rejected 2026-08-01 after source verification. Each entry's full
          // reasoning and citations live in
          // dsld_clean/scripts/data/timing_rules_rejected.json.
          'timing_magnesium_with_food',
          'timing_ashwagandha_with_food',
          'timing_zinc_with_food',
          'timing_vitamin_k_with_food',
          'timing_iron_empty_stomach',
          'timing_omega3_with_meal',
          'timing_fat_soluble_vitamins_with_food',
          'timing_coffee_iron_separate',
          'timing_thyroid_med_coffee_separate',
        ]) {
          expect(
            ids,
            isNot(contains(removed)),
            reason: '$removed is unsupported as timing advice',
          );
        }

        // The iron GI note survives, but re-authored FROM its source rather
        // than inherited: the NIH ODS iron page recommends taking iron with
        // food to minimize GI effects, which is the opposite of what
        // timing_iron_empty_stomach told users.
        final iron = rules.firstWhere(
          (r) => r['id'] == 'timing_iron_with_food_gi',
        );
        expect(iron['timing_relation']['type'], 'with_food');
        expect(iron['review_status'], 'verified');
        expect(iron['supersedes'], 'timing_iron_empty_stomach');
      },
    );

    test('a verified rule carries the full publication contract', () async {
      // Section 2 promotes rules one at a time. Promotion is only legitimate
      // when the rule also carries the evidence of its own verification, so a
      // future edit cannot flip review_status alone.
      final timing = await repo.loadTimingRules();
      final rules = (timing['timing_rules']! as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final verified = rules
          .where((r) => r['review_status'] == 'verified')
          .toList();
      expect(
        verified,
        isNotEmpty,
        reason: 'Section 2 has promoted rules; this guard must stay meaningful',
      );

      for (final rule in verified) {
        final id = rule['id'];
        expect(
          rule['canaries'],
          isNotNull,
          reason: '$id is verified without catalog canaries',
        );
        final canaries = rule['canaries'] as Map<String, dynamic>;
        expect(
          canaries['negative'],
          isNotEmpty,
          reason:
              '$id has no negative canary — reachability alone does not prove '
              'a rule stops firing where it should not',
        );
        expect(
          (rule['sources'] as List<dynamic>),
          isNotEmpty,
          reason: '$id is verified without a source',
        );
        // fda_label is the strongest authority the app can display and must
        // not be assignable without an FDA source.
        if (rule['source_authority'] == 'fda_label') {
          expect(
            (rule['sources'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .any((s) => s['source_type'] == 'fda'),
            isTrue,
            reason: '$id claims FDA authority without an FDA source',
          );
        }
      }
    });

    test('a suppressed rule records why it is suppressed', () async {
      final timing = await repo.loadTimingRules();
      final rules = (timing['timing_rules']! as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final rule in rules.where(
        (r) => r['review_status'] == 'needs_revision',
      )) {
        expect(
          rule['review_note'],
          isNotNull,
          reason:
              '${rule['id']} is suppressed with no recorded blocker — the next '
              'reader cannot tell whether it is unsafe or merely unfinished',
        );
      }
    });

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
