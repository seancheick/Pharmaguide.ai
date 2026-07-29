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
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';

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

/// Build a recall payload in the SHIPPED asset's shape.
///
/// `canonical_id` is a RECORD id (`BANNED_SIBUTRAMINE`) — in the real asset
/// all 143 are uppercase-prefixed and none is a catalog ingredient id. The
/// ingredient names live in `common_names`, which is the field the join
/// actually uses. The previous fixture put a lowercase ingredient id in
/// `canonical_id`, a shape that occurs zero times in production, and so
/// green-lit a join that could never match a real product.
Map<String, dynamic> _recallPayload(List<String> ingredientNames) {
  return {
    'schema_version': '1.1',
    'recalled_ingredients': [
      for (final name in ingredientNames)
        {
          'canonical_id': 'BANNED_${name.toUpperCase()}',
          'common_names': [name.toLowerCase()],
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
  int hasBannedFlag = 0,
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
          hasBannedSubstance: Value(hasBannedFlag),
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
          hasBannedFlag: 1,
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
        expect(v.recalledIngredients.single.canonicalId, 'BANNED_SIBUTRAMINE');
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
      'an ingredient-name match alone never invents a banned verdict',
      () async {
        // ONE BRAIN. The pipeline saw these same ingredients and did not flag
        // the product, so this surface must not overrule it. Against the
        // shipped asset the advisory tiers (high_risk / watchlist / recalled)
        // cover garcinia, yohimbe, CBD and red yeast rice — substances in
        // hundreds of products the pipeline deliberately leaves unblocked.
        // Matching on name alone would have turned 107 flagged products into
        // 285 banner-carrying ones.
        final coreDb = CoreDatabase.memory();
        final userDb = UserDatabase.memory();

        await _seedProduct(
          coreDb,
          dsldId: 'TEST_UNFLAGGED_MATCH',
          keyIngredientTags: ['sibutramine'], // name matches the recall record
          // ...but the pipeline set neither flag.
        );
        await _seedStack(userDb, dsldId: 'TEST_UNFLAGGED_MATCH');

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
          isTrue,
          reason:
              'The pipeline did not flag this product; the app must not '
              'derive its own banned verdict from an ingredient name.',
        );
      },
    );

    test('a flagged product with no authored record still warns', () async {
      // 25 of the 107 flagged products in the shipped catalog match no
      // record by name. They must still surface — with the substance
      // unnamed, never dropped, and never ranked `safe`.
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await _seedProduct(
        coreDb,
        dsldId: 'TEST_FLAGGED_UNNAMED',
        keyIngredientTags: ['some_unlisted_compound'],
        hasBannedFlag: 1,
      );
      await _seedStack(
        userDb,
        dsldId: 'TEST_FLAGGED_UNNAMED',
        name: 'Flagged Product',
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
      expect(report.violations, hasLength(1));
      final v = report.violations.single;
      expect(v.recalledIngredients, isEmpty);
      expect(v.bannerMessage, isNotEmpty);
      expect(v.bannerMessage, startsWith('BANNED'));
      expect(v.isBannedSubstance, isTrue);
      expect(v.worstSeverity, isNot(Severity.safe));
    });

    test(
      'a finding plus an incomplete scan labels the alert list as partial',
      () {
        final report = RecalledIngredientsReport(
          violations: [
            RecalledIngredientViolation(
              productDsldId: 'TEST_FLAGGED',
              productName: 'Flagged Product',
              brandName: 'Test Brand',
              recalledIngredients: const [],
              pipelineBannedSubstance: true,
            ),
          ],
          incomplete: true,
        );

        expect(report.bannerMessage, contains('BANNED'));
        expect(report.bannerMessage, contains('additional safety alerts'));
        expect(report.bannerMessage, contains('could not be checked'));
      },
    );

    test('a recall-only flag never renders as a banned substance', () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await _seedProduct(
        coreDb,
        dsldId: 'TEST_RECALL_ONLY',
        keyIngredientTags: ['unrelated_ingredient'],
        hasRecalledFlag: 1,
      );
      await _seedStack(
        userDb,
        dsldId: 'TEST_RECALL_ONLY',
        name: 'Recalled Lot',
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
      final violation = report.violations.single;
      expect(violation.isBannedSubstance, isFalse);
      expect(violation.isRecalledProduct, isTrue);
      expect(violation.bannerMessage, startsWith('RECALLED'));
      expect(violation.bannerMessage, isNot(contains('BANNED')));
    });

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
        hasBannedFlag: 1,
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
        'BANNED_SIBUTRAMINE',
      );
    });

    test('malformed recalled_ingredients yields an incomplete report, '
        'not a false all-clear', () async {
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
      expect(report.incomplete, isTrue);
    });

    test('non-map entries in the recall list are skipped without losing '
        'valid alerts', () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await _seedProduct(
        coreDb,
        dsldId: 'TEST_MIXED_ASSET',
        keyIngredientTags: ['sibutramine'],
        hasBannedFlag: 1,
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
        'BANNED_SIBUTRAMINE',
      );
    });
  });
}
