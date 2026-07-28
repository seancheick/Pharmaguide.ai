import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

class _FakeReferenceDataRepository extends ReferenceDataRepository {
  _FakeReferenceDataRepository(this._depletionsPayload);

  final Map<String, dynamic> _depletionsPayload;

  @override
  Future<({MedNutrientLoadStatus status, Map<String, dynamic> data})>
  loadMedicationDepletions() async {
    return (status: MedNutrientLoadStatus.loaded, data: _depletionsPayload);
  }
}

Map<String, dynamic> _depletionsPayload() {
  return {
    'depletions': [
      {
        'id': 'DEP_METFORMIN_VITAMINB12',
        'drug_ref': {
          'id': '860974',
          'display_name': 'Metformin (type 2 diabetes medication)',
        },
        'depleted_nutrient': {
          'standard_name': 'Vitamin B12',
          'canonical_id': 'vitamin_b12',
        },
        'depletion_type': 'depletion',
        'severity': 'significant',
        'mechanism': 'Metformin impairs B12 absorption.',
        'clinical_impact': 'Long-term metformin can lower B12.',
        'recommendation': 'Consider checking B12 status.',
        'onset_timeline': 'years',
        'evidence_level': 'established',
        'citation_review_status': 'verified',
        'adequacy_threshold_mcg': 250,
        'sources': [
          {'source_type': 'reference', 'url': 'https://example.test/b12'},
        ],
      },
    ],
  };
}

Map<String, dynamic> _orlistatDepletionsPayload() {
  return {
    'depletions': [
      {
        'id': 'DEP_ORLISTAT_VITAMIND',
        'drug_ref': {'type': 'drug', 'id': '37925', 'display_name': 'Orlistat'},
        'depleted_nutrient': {
          'standard_name': 'Vitamin D',
          'canonical_id': 'vitamin_d',
        },
        'depletion_type': 'depletion',
        'severity': 'moderate',
        'citation_review_status': 'verified',
      },
    ],
  };
}

void main() {
  test(
    'depletionReportProvider uses detail-blob nutrient doses, not only keyIngredientTags',
    () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(() async {
        await coreDb.close();
        await userDb.close();
      });

      await coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: 'B12_SUPP',
              productName: 'B12 500 mcg',
              exportVersion: 'test',
              exportedAt: '2026-06-08T00:00:00Z',
              productStatus: const Value('active'),
              keyIngredientTags: const Value('[]'),
            ),
          );

      await userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'med_metformin',
          type: const Value('medication'),
          name: 'Metformin',
          drugClassesCol: const Value('[]'),
        ),
      );
      await userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'supp_b12',
          type: const Value('supplement'),
          name: 'B12 500 mcg',
          dsldId: const Value('B12_SUPP'),
        ),
      );
      await userDb.cacheDetail(
        'B12_SUPP',
        jsonEncode({
          'rda_ul_data': {
            'analyzed_ingredients': [
              {
                'standard_name': 'Vitamin B12',
                'canonical_id': 'vitamin_b12',
                'quantity': 500,
                'unit': 'mcg',
                'skip_ul_check': true,
              },
            ],
          },
          'ingredients': [
            {
              'name': 'Vitamin B12',
              'canonical_id': 'vitamin_b12',
              'quantity': 500,
              'unit': 'mcg',
            },
          ],
        }),
        null,
      );

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          referenceDataRepositoryProvider.overrideWith(
            (ref) => _FakeReferenceDataRepository(_depletionsPayload()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(depletionReportProvider.future);

      expect(report.status, MedNutrientLoadStatus.loaded);
      expect(report.matches, hasLength(1));
      expect(report.matches.single.depletionId, 'DEP_METFORMIN_VITAMINB12');
      expect(report.matches.single.coverageLevel, CoverageLevel.adequate);
    },
  );

  test(
    'depletionReportProvider passes RxCUI identity for brand-name medications',
    () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(() async {
        await coreDb.close();
        await userDb.close();
      });

      await userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'med_xenical',
          type: const Value('medication'),
          name: 'Xenical',
          rxcui: const Value('312962'),
          genericRxcui: const Value('37925'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          referenceDataRepositoryProvider.overrideWith(
            (ref) => _FakeReferenceDataRepository(_orlistatDepletionsPayload()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(depletionReportProvider.future);

      expect(report.matches, hasLength(1));
      expect(report.matches.single.depletionId, 'DEP_ORLISTAT_VITAMIND');
    },
  );
}
