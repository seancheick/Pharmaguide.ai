// Integration tests for the scan → recalled-ingredient flag flow.
//
// These close the biggest untested surface on the recall path: the
// product-contains-ingredient match at
// `lib/features/stack/providers/stack_safety_providers.dart:344`.
//
// Strategy:
//   * Boot in-memory CoreDatabase + UserDatabase (no real DB files).
//   * Seed a single ProductsCoreData row whose `key_ingredient_tags`
//     encode the canonical IDs the test wants to exercise.
//   * Seed a single stack entry pointing at that product.
//   * Override `referenceDataRepositoryProvider` with a fake that
//     returns canned recall JSON — this is why
//     `recalledIngredientsReportProvider` was refactored in Sprint 27.6
//     to read the repo via the provider instead of `new`-ing its own.
//   * Await the provider future and assert violation shape.
//
// We intentionally do NOT load real assets. The fixtures are tiny and
// explicit so a regression in the match logic fails loud on the exact
// ingredient under test.

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

/// Fake repository that serves a single canned recall payload. Extends
/// the real class so the provider's type contract is satisfied without
/// reimplementing the other `load*` methods (they're never called by
/// the recall path under test).
class _FakeReferenceDataRepository extends ReferenceDataRepository {
  _FakeReferenceDataRepository(this._recallPayload);
  final Map<String, dynamic> _recallPayload;

  @override
  Future<Map<String, dynamic>> loadBannedRecalledIngredients() async {
    return _recallPayload;
  }
}

/// Build the standard recall payload with one entry per canonical ID.
/// Shape matches the Sprint 27.6 asset schema (no `warning_message`).
Map<String, dynamic> _recallPayload(List<String> canonicalIds) {
  return {
    'schema_version': '1.1',
    'recalled_ingredients': [
      for (final cid in canonicalIds)
        {
          'canonical_id': cid,
          'common_names': [cid.toLowerCase()],
          'recall_status': 'banned',
          'regulatory_basis': 'FDA — test fixture',
          'reason': 'Test fixture. Not a real warning.',
          'effective_date': '2026-01-01',
          'severity': 'critical',
          'ban_context': 'adulterant_in_supplements',
          'safety_warning':
              'A test-only prescription drug hidden in supplements.',
          'safety_warning_one_liner':
              'Prescription drug hidden in supplements. Stop.',
        },
    ],
  };
}

/// Insert a minimal supplement row into the in-memory core DB. The only
/// field the recall path actually reads is `keyIngredientTags`; the rest
/// are required by the Drift schema but irrelevant to the match.
Future<void> _seedProduct(
  CoreDatabase coreDb, {
  required String dsldId,
  required List<String> keyIngredientTags,
  int hasRecalledFlag = 0,
}) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: 'Test Supplement $dsldId',
          exportVersion: 'test',
          exportedAt: '2026-04-16T00:00:00Z',
          productStatus: const Value('active'),
          keyIngredientTags: Value(jsonEncode(keyIngredientTags)),
          hasRecalledIngredient: Value(hasRecalledFlag),
        ),
      );
}

/// Insert a single supplement stack entry pointing at [dsldId].
Future<void> _seedStack(
  UserDatabase userDb, {
  required String dsldId,
  String name = 'Stack Entry',
}) async {
  await userDb.addToStack(
    UserStacksLocalCompanion.insert(
      id: 'stack_$dsldId',
      name: name,
      dsldId: Value(dsldId),
    ),
  );
}

/// Build a ProviderContainer wired to the in-memory DBs + fake repo.
ProviderContainer _container({
  required CoreDatabase coreDb,
  required UserDatabase userDb,
  required Map<String, dynamic> recallPayload,
}) {
  return ProviderContainer(
    overrides: [
      coreDatabaseProvider.overrideWithValue(coreDb),
      userDatabaseProvider.overrideWithValue(userDb),
      referenceDataRepositoryProvider.overrideWith(
        (ref) => _FakeReferenceDataRepository(recallPayload),
      ),
    ],
  );
}

void main() {
  group('recalled ingredient scan → flag integration', () {
    test(
      'flags product when key_ingredient_tags contains a banned canonical_id',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();

        await _seedProduct(
          coreDb,
          dsldId: 'TEST_SIBUTRAMINE_PRODUCT',
          keyIngredientTags: ['sibutramine'],
        );
        await _seedStack(
          userDb,
          dsldId: 'TEST_SIBUTRAMINE_PRODUCT',
          name: 'Spiked Weight-Loss Supp',
        );

        final container = _container(
          coreDb: coreDb,
          userDb: userDb,
          recallPayload: _recallPayload(['sibutramine']),
        );
        addTearDown(container.dispose);
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });

        final report = await container.read(
          recalledIngredientsReportProvider.future,
        );

        expect(
          report.isEmpty,
          isFalse,
          reason: 'Expected one violation for the seeded sibutramine match',
        );
        expect(report.violations, hasLength(1));
        final v = report.violations.single;
        expect(v.productDsldId, 'TEST_SIBUTRAMINE_PRODUCT');
        expect(v.recalledIngredients, hasLength(1));
        expect(v.recalledIngredients.single.canonicalId, 'sibutramine');
        expect(
          v.recalledIngredients.single.banContext,
          'adulterant_in_supplements',
        );
        expect(
          v.recalledIngredients.single.safetyWarningOneLiner,
          'Prescription drug hidden in supplements. Stop.',
        );
      },
    );

    test(
      'does NOT flag product when no canonical_id matches the recall list',
      () async {
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();

        await _seedProduct(
          coreDb,
          dsldId: 'TEST_SAFE_PRODUCT',
          keyIngredientTags: ['vitamin_d'],
        );
        await _seedStack(userDb, dsldId: 'TEST_SAFE_PRODUCT');

        final container = _container(
          coreDb: coreDb,
          userDb: userDb,
          // Recall list contains a banned ingredient the product does NOT carry.
          recallPayload: _recallPayload(['sibutramine']),
        );
        addTearDown(container.dispose);
        addTearDown(() async {
          await coreDb.close();
          await userDb.close();
        });

        final report = await container.read(
          recalledIngredientsReportProvider.future,
        );

        expect(
          report.isEmpty,
          isTrue,
          reason:
              'A product with only vitamin_d must not trigger any '
              'recall violation when the recall list only bans sibutramine.',
        );
      },
    );

    test('canonical_id match is case-insensitive', () async {
      // Guards the lesson learned 2026-04-14: canonicalIdsForProduct
      // lowercases all tags before comparison. If that normalization ever
      // regresses, a product with "SIBUTRAMINE" (uppercase) in its tags
      // would silently slip past a recall list keyed on lowercase
      // "sibutramine" — the exact class of bug the fingerprint fix closed.
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await _seedProduct(
        coreDb,
        dsldId: 'TEST_UPPERCASE_TAGS',
        keyIngredientTags: ['SIBUTRAMINE'], // uppercase in product row
      );
      await _seedStack(userDb, dsldId: 'TEST_UPPERCASE_TAGS');

      final container = _container(
        coreDb: coreDb,
        userDb: userDb,
        recallPayload: _recallPayload(['sibutramine']), // lowercase in asset
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await coreDb.close();
        await userDb.close();
      });

      final report = await container.read(
        recalledIngredientsReportProvider.future,
      );

      expect(
        report.isEmpty,
        isFalse,
        reason:
            'Case-insensitive match must still fire when the product '
            "row uses uppercase tags and the recall asset uses lowercase.",
      );
      expect(
        report.violations.single.recalledIngredients.single.canonicalId,
        'sibutramine',
      );
    });

    test('malformed recalled_ingredients (non-list) yields empty report, '
        'no throw', () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await _seedProduct(
        coreDb,
        dsldId: 'TEST_MALFORMED_ASSET',
        keyIngredientTags: ['sibutramine'],
      );
      await _seedStack(userDb, dsldId: 'TEST_MALFORMED_ASSET');

      final container = _container(
        coreDb: coreDb,
        userDb: userDb,
        recallPayload: {
          'schema_version': '1.1',
          // Drifted shape: a map instead of the expected list. The
          // provider must degrade to an empty report instead of
          // throwing a TypeError outside its try/catch.
          'recalled_ingredients': {'canonical_id': 'sibutramine'},
        },
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await coreDb.close();
        await userDb.close();
      });

      final report = await container.read(
        recalledIngredientsReportProvider.future,
      );
      expect(report.isEmpty, isTrue);
    });

    test('non-map entries in the recall list are skipped without losing '
        'valid alerts', () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await _seedProduct(
        coreDb,
        dsldId: 'TEST_MIXED_ASSET',
        keyIngredientTags: ['sibutramine'],
      );
      await _seedStack(userDb, dsldId: 'TEST_MIXED_ASSET');

      final validEntry =
          (_recallPayload(['sibutramine'])['recalled_ingredients'] as List)
              .single;
      final container = _container(
        coreDb: coreDb,
        userDb: userDb,
        recallPayload: {
          'schema_version': '1.1',
          'recalled_ingredients': ['not-a-map', 42, validEntry],
        },
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await coreDb.close();
        await userDb.close();
      });

      final report = await container.read(
        recalledIngredientsReportProvider.future,
      );
      expect(
        report.isEmpty,
        isFalse,
        reason:
            'Malformed sibling entries must not suppress the valid '
            'sibutramine alert.',
      );
      expect(
        report.violations.single.recalledIngredients.single.canonicalId,
        'sibutramine',
      );
    });
  });
}
