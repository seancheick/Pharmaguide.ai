// FIX 3 (P1) — a corrupt/missing interaction DB must SURFACE, not read as
// "no interactions".
//
// When the bundled interaction DB fails to materialize at bootstrap,
// main.dart leaves `interactionDatabaseProvider` at its default throwing
// definition, so watching it raises UnimplementedError. The provider used
// to catch that and return `const []`, which is byte-for-byte identical to
// "no interactions found" — every med×supplement check silently disabled
// while the page's hedge banner never fired.
//
// Contract now: DB-unavailable surfaces as an AsyncError so
// `personalizedWarningsFailed` (product_detail_v2_connected.dart) flips true
// and the "couldn't check" banner shows — mirroring Quick Check's
// "Database unavailable" state.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/providers/personalized_warnings_provider.dart';

const _dsldId = 'dsld-test';

Future<void> _seedProduct(CoreDatabase coreDb) async {
  await coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: _dsldId,
          productName: 'Test Product',
          exportVersion: 'test',
          exportedAt: '2026-07-05T00:00:00Z',
          keyIngredientTags: const Value('["iron"]'),
        ),
      );
}

void main() {
  test(
    'interaction DB unavailable → provider surfaces error (not empty list)',
    () async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(coreDb.close);
      addTearDown(userDb.close);

      await _seedProduct(coreDb);
      // A non-empty stack so the lookup gets past the empty-stack short
      // circuit and actually reaches the interaction-DB watch.
      await userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'med-1',
          type: const Value('medication'),
          name: 'Metformin',
          rxcui: const Value('6809'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          // interactionDatabaseProvider intentionally NOT overridden —
          // this reproduces a bootstrap where the bundled interaction DB
          // failed to materialize (main.dart skips the override, leaving
          // the default `throw UnimplementedError`).
        ],
      );
      addTearDown(container.dispose);

      // Must SURFACE as an AsyncError, not resolve to an empty (all-clear)
      // list. The exact thrown type is Riverpod-version dependent (a raw
      // UnimplementedError, or a ProviderException wrapping it), so match
      // on the DB-unavailable sentinel either way.
      await expectLater(
        container.read(personalizedInteractionWarningsProvider(_dsldId).future),
        throwsA(
          predicate(
            (Object e) =>
                e is UnimplementedError ||
                e.toString().contains('interactionDatabaseProvider'),
            'a DB-unavailable failure that surfaces (never an empty list)',
          ),
        ),
      );
    },
  );
}
