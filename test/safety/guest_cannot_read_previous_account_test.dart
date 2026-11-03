// Release blocker A5 (ADR-013). Each account, and the guest, has its own folder,
// so a guest can't read what the signed-out user left behind. This runs the real
// guard against real files on disk.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a guest cannot read the medication the signed-out user left behind',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('guest_gate');
      addTearDown(() => root.delete(recursive: true));
      final guard = AccountSwitchGuard(
        ownerStore: AccountOwnerStore(),
        storage: AccountStorage(
          supportDirectory: () async => root,
          documentsDirectory: () async => root,
        ),
        openDatabase: (path) async => UserDatabase.open(path),
      );
      addTearDown(guard.close);

      await guard.boot(sessionUid: 'previous-account');
      await guard.database!.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'previous-account-medication',
          name: 'Warfarin',
          type: const Value('medication'),
        ),
      );

      await guard.onAuthEvent(event: AuthChangeEvent.signedOut, uid: null);

      final container = ProviderContainer(
        overrides: [userDatabaseProvider.overrideWithValue(guard.database!)],
      );
      addTearDown(container.dispose);
      final stack = await container.read(activeStackProvider.future);
      expect(stack.map((item) => item.name), isNot(contains('Warfarin')));
    },
  );
}
