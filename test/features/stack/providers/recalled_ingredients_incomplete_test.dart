// FIX 3 — a banned/recalled asset load failure must not silently disable
// recall detection. Before the fix the provider swallowed the error and
// returned an empty report (no error recorded, no hedge), so an
// FDA-recalled product read as "all clear". Now the load failure is
// recorded AND carried as an `incomplete` signal the banner can hedge on.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// Repo whose recall asset load always throws — simulates a corrupt/missing
/// `banned_recalled_ingredients` bundle.
class _ThrowingRecallRepo extends ReferenceDataRepository {
  @override
  Future<Map<String, dynamic>> loadBannedRecalledIngredients() async {
    throw StateError('recall asset unavailable');
  }
}

/// Repo that serves a single canned recall for `sibutramine`.
class _WorkingRecallRepo extends ReferenceDataRepository {
  @override
  Future<Map<String, dynamic>> loadBannedRecalledIngredients() async {
    return {
      'schema_version': '1.1',
      'recalled_ingredients': [
        {
          'canonical_id': 'BANNED_SIBUTRAMINE',
          'common_names': ['sibutramine'],
          'recall_status': 'banned',
          'regulatory_basis': 'FDA — test fixture',
          'reason': 'Test fixture.',
          'effective_date': '2026-01-01',
          'severity': 'critical',
          'ban_context': 'adulterant_in_supplements',
          'safety_warning': 'Prescription drug hidden in supplements.',
          'safety_warning_one_liner': 'Prescription drug hidden. Stop.',
        },
      ],
    };
  }
}

UserStacksLocalData _supplement({
  required String dsldId,
  required String name,
}) {
  final now = DateTime.utc(2026, 7, 5);
  return UserStacksLocalData(
    id: 'stack_$dsldId',
    type: 'supplement',
    name: name,
    dsldId: dsldId,
    addedAt: now,
    clientUpdatedAt: now,
  );
}

Future<void> _seedProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required List<String> tags,
  int hasBannedFlag = 0,
}) async {
  final tagsJson = '[${tags.map((t) => '"$t"').join(',')}]';
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: 'Test $dsldId',
          productStatus: const Value('active'),
          keyIngredientTags: Value(tagsJson),
          hasBannedSubstance: Value(hasBannedFlag),
          exportVersion: 'test',
          exportedAt: '2026-07-05T00:00:00Z',
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recall asset load failure records a crash error (was silent)',
    () async {
      CrashReportingService().clearBuffersForTest();
      final coreDb = CoreDatabase.memory();
      addTearDown(coreDb.close);

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          referenceDataRepositoryProvider.overrideWith(
            (ref) => _ThrowingRecallRepo(),
          ),
          activeStackProvider.overrideWith(
            (ref) async => [_supplement(dsldId: 'SUPP_1', name: 'Test Supp')],
          ),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(
        recalledIngredientsReportProvider.future,
      );

      // Degrades to an empty report (never throws), but the SAME report
      // carries the unavailable state to every consumer.
      expect(report.isEmpty, isTrue);
      expect(report.incomplete, isTrue);
      // ...but the failure is now recorded, not swallowed silently.
      final errors = CrashReportingService().recordedErrors;
      expect(
        errors.any(
          (e) => e.hint == 'stack_safety:recalled_ingredients_load_failed',
        ),
        isTrue,
        reason: 'a recall-detection load failure must be reported',
      );
    },
  );

  test(
    'report provider returns incomplete=false and flags real recalls',
    () async {
      final coreDb = CoreDatabase.memory();
      addTearDown(coreDb.close);
      await _seedProduct(
        coreDb,
        dsldId: 'SUPP_SPIKED',
        tags: ['sibutramine'],
        hasBannedFlag: 1,
      );

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          referenceDataRepositoryProvider.overrideWith(
            (ref) => _WorkingRecallRepo(),
          ),
          activeStackProvider.overrideWith(
            (ref) async => [
              _supplement(dsldId: 'SUPP_SPIKED', name: 'Spiked Supp'),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(
        recalledIngredientsReportProvider.future,
      );

      expect(report.incomplete, isFalse);
      expect(report.isEmpty, isFalse);
      expect(report.violations, hasLength(1));
      expect(
        report.violations.single.recalledIngredients.single.canonicalId,
        'BANNED_SIBUTRAMINE',
      );
    },
  );

  test('missing product hydration marks the recall report incomplete', () async {
    final coreDb = CoreDatabase.memory();
    addTearDown(coreDb.close);

    final container = ProviderContainer(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        referenceDataRepositoryProvider.overrideWith(
          (ref) => _WorkingRecallRepo(),
        ),
        activeStackProvider.overrideWith(
          (ref) async => [
            _supplement(dsldId: 'MISSING_PRODUCT', name: 'Missing Product'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    final report = await container.read(
      recalledIngredientsReportProvider.future,
    );

    expect(report.isEmpty, isTrue);
    expect(
      report.incomplete,
      isTrue,
      reason:
          'A stack product that could not be inspected is unknown, not recall-free.',
    );
  });
}
