// Release blocker A5 (ADR-013). Nothing separates accounts on the phone yet, so
// a guest reads what the signed-out user left behind. This stays skipped until
// per-account storage lands, and must pass before any public release.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';

void main() {
  test(
    'a guest cannot read the medication the signed-out user left behind',
    () async {
      final userDb = UserDatabase.memory();
      addTearDown(userDb.close);
      await userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'previous-account-medication',
          name: 'Warfarin',
          type: const Value('medication'),
        ),
      );
      // Sign-out keeps the row, and a guest session uses the same database.
      final container = ProviderContainer(
        overrides: [userDatabaseProvider.overrideWithValue(userDb)],
      );
      addTearDown(container.dispose);

      final stack = await container.read(activeStackProvider.future);

      expect(stack.map((item) => item.name), isNot(contains('Warfarin')));
    },
    skip: 'A5: per-account storage is not built yet (ADR-013)',
  );
}
