// The account gate (ADR-013): every branch of the pure decision, then the real
// guard against real folders on disk.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

const _a = 'account-a';
const _b = 'account-b';

Future<void> _addMedication(UserDatabase db, String name) => db.addToStack(
  UserStacksLocalCompanion.insert(
    id: 'id-$name',
    name: name,
    type: const Value('medication'),
  ),
);

Future<List<String>> _names(UserDatabase db) async =>
    (await db.select(db.userStacksLocal).get()).map((r) => r.name).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decideAccountAction', () {
    AccountSwitchAction decide(
      String? owner,
      String? uid,
      AuthChangeEvent event, {
      bool hasData = false,
    }) => decideAccountAction(
      activeOwner: owner,
      incomingUid: uid,
      event: event,
      incomingHasData: hasData,
    );

    const sessionEvents = [
      AuthChangeEvent.signedIn,
      AuthChangeEvent.initialSession,
      AuthChangeEvent.tokenRefreshed,
      AuthChangeEvent.userUpdated,
    ];

    for (final event in sessionEvents) {
      test('$event for the open owner keeps', () {
        expect(decide(_a, _a, event), AccountSwitchAction.keep);
      });

      test('$event from the guest, with no account data, adopts', () {
        expect(decide(null, _a, event), AccountSwitchAction.adoptGuestData);
      });

      test('$event from the guest, with account data, never merges', () {
        expect(
          decide(null, _a, event, hasData: true),
          AccountSwitchAction.switchAccount,
        );
      });

      test('$event for a different account switches, without adopting', () {
        expect(decide(_a, _b, event), AccountSwitchAction.switchAccount);
      });

      test('$event with no uid keeps', () {
        expect(decide(_a, null, event), AccountSwitchAction.keep);
        expect(decide(_a, '', event), AccountSwitchAction.keep);
      });
    }

    test('signed out moves to the guest, and is a no-op for the guest', () {
      expect(
        decide(_a, null, AuthChangeEvent.signedOut),
        AccountSwitchAction.switchToGuest,
      );
      expect(
        decide(null, null, AuthChangeEvent.signedOut),
        AccountSwitchAction.keep,
      );
    });

    test('other events keep', () {
      expect(
        decide(_a, _b, AuthChangeEvent.passwordRecovery),
        AccountSwitchAction.keep,
      );
      expect(
        decide(_a, _b, AuthChangeEvent.mfaChallengeVerified),
        AccountSwitchAction.keep,
      );
    });
  });

  group('AccountSwitchGuard', () {
    late Directory support;
    late Directory documents;
    late AccountStorage storage;

    AccountSwitchGuard guardWith({
      Future<UserDatabase> Function(String path)? open,
      Future<void> Function()? onOwnerChange,
    }) {
      final guard = AccountSwitchGuard(
        ownerStore: AccountOwnerStore(),
        storage: storage,
        openDatabase: open ?? (path) async => UserDatabase.open(path),
        onOwnerChange: onOwnerChange,
      );
      addTearDown(guard.close);
      return guard;
    }

    Future<void> signIn(AccountSwitchGuard guard, String uid) =>
        guard.onAuthEvent(event: AuthChangeEvent.signedIn, uid: uid);
    Future<void> signOut(AccountSwitchGuard guard) =>
        guard.onAuthEvent(event: AuthChangeEvent.signedOut, uid: null);

    Future<void> writeLegacyDatabase(String medication) async {
      final legacy = UserDatabase.open(p.join(documents.path, 'user_data.db'));
      await _addMedication(legacy, medication);
      await legacy.close();
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('account_gate');
      addTearDown(() => root.delete(recursive: true));
      support = await Directory(p.join(root.path, 'support')).create();
      documents = await Directory(p.join(root.path, 'documents')).create();
      storage = AccountStorage(
        supportDirectory: () async => support,
        documentsDirectory: () async => documents,
      );
    });

    test(
      'an account gets its data back after sign-out and a restart',
      () async {
        final guard = guardWith();
        await guard.boot(sessionUid: _a);
        await _addMedication(guard.database!, 'Warfarin');
        await signOut(guard);
        expect(await _names(guard.database!), isEmpty);
        await guard.close();

        final signedOutLaunch = guardWith();
        await signedOutLaunch.boot(sessionUid: null);
        expect(await _names(signedOutLaunch.database!), isEmpty);
        await signedOutLaunch.close();

        final returning = guardWith();
        await returning.boot(sessionUid: _a);
        expect(await _names(returning.database!), ['Warfarin']);
      },
    );

    test(
      'a different account reads nothing, and nothing is destroyed',
      () async {
        final guard = guardWith();
        await guard.boot(sessionUid: _a);
        await _addMedication(guard.database!, 'Warfarin');

        await signIn(guard, _b);
        expect(await _names(guard.database!), isEmpty);
        await _addMedication(guard.database!, 'Metformin');

        await signIn(guard, _a);
        expect(await _names(guard.database!), ['Warfarin']);
      },
    );

    test(
      'a first sign-in takes the guest data, leaving the guest empty',
      () async {
        final guard = guardWith();
        await guard.boot(sessionUid: null);
        await _addMedication(guard.database!, 'Lisinopril');
        await RecentSearchesService().addSearch('magnesium');

        await signIn(guard, _a);
        expect(await _names(guard.database!), ['Lisinopril']);
        expect(
          await RecentSearchesService(scope: guard.account.scope).getRecent(),
          ['magnesium'],
        );

        await signOut(guard);
        expect(await _names(guard.database!), isEmpty);
        expect(await RecentSearchesService().getRecent(), isEmpty);
      },
    );

    test('guest data is never merged into an account that has data', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);
      await _addMedication(guard.database!, 'Warfarin');
      await signOut(guard);
      await _addMedication(guard.database!, 'Aspirin');

      await signIn(guard, _a);
      expect(await _names(guard.database!), ['Warfarin']);

      await signOut(guard);
      expect(await _names(guard.database!), ['Aspirin']);
    });

    test('work in flight on the old handle fails, and lands nowhere', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);
      final held = guard.database!;

      await signIn(guard, _b);

      await expectLater(_addMedication(held, 'Warfarin'), throwsA(anything));
      expect(await _names(guard.database!), isEmpty);
      await signIn(guard, _a);
      expect(await _names(guard.database!), isEmpty);
    });

    test('consumers come down before the handle closes', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);
      final held = guard.database!;
      final steps = <String>[];
      guard
        ..releaseConsumers = () async {
          await _names(held);
          steps.add('released');
        }
        ..onChanged = () => steps.add('changed');

      await signOut(guard);

      expect(steps, ['released', 'changed']);
    });

    test(
      'a failed switch shows no one, and a retry opens the right person',
      () async {
        var failing = false;
        final guard = guardWith(
          open: (path) async {
            if (failing) throw const FileSystemException('disk full');
            return UserDatabase.open(path);
          },
        );
        await guard.boot(sessionUid: _a);
        await _addMedication(guard.database!, 'Warfarin');
        await signOut(guard);
        await _addMedication(guard.database!, 'Aspirin');

        failing = true;
        await signIn(guard, _a);
        expect(guard.database, isNull);
        expect(await AccountOwnerStore().read(), isNull);

        failing = false;
        await guard.retry();
        expect(await _names(guard.database!), ['Warfarin']);
        expect(await AccountOwnerStore().read(), _a);
      },
    );

    test(
      'a failure ending the old owner\'s work does not stop the switch',
      () async {
        final guard = guardWith(
          onOwnerChange: () async => throw StateError('notifications'),
        );
        await guard.boot(sessionUid: _a);
        await _addMedication(guard.database!, 'Warfarin');

        await signOut(guard);

        expect(guard.ownerUid, isNull);
        expect(await _names(guard.database!), isEmpty);
      },
    );

    test('overlapping auth events end on the last, one at a time', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);
      await _addMedication(guard.database!, 'Warfarin');

      await Future.wait([
        signOut(guard),
        signIn(guard, _b),
        signOut(guard),
        signIn(guard, _a),
      ]);

      expect(guard.ownerUid, _a);
      expect(await _names(guard.database!), ['Warfarin']);
    });

    test('the sync owner gate follows the open folder', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);
      expect(
        ownerAllowsPush(
          storedOwner: await AccountOwnerStore().read(),
          currentUid: _a,
        ),
        isTrue,
      );

      await signOut(guard);
      expect(
        ownerAllowsPush(
          storedOwner: await AccountOwnerStore().read(),
          currentUid: _a,
        ),
        isFalse,
      );

      await signIn(guard, _b);
      expect(
        ownerAllowsPush(
          storedOwner: await AccountOwnerStore().read(),
          currentUid: _a,
        ),
        isFalse,
      );
    });

    group('removeAccountData', () {
      test('deletes that account only, moving to the guest first', () async {
        final guard = guardWith();
        await guard.boot(sessionUid: _b);
        await _addMedication(guard.database!, 'Metformin');
        await signIn(guard, _a);
        await _addMedication(guard.database!, 'Warfarin');
        final scope = guard.account.scope;
        await RecentSearchesService(scope: scope).addSearch('warfarin');

        await guard.removeAccountData(_a);

        expect(guard.ownerUid, isNull);
        expect(await storage.hasData(_a), isFalse);
        expect(await RecentSearchesService(scope: scope).getRecent(), isEmpty);

        await signIn(guard, _a);
        expect(await _names(guard.database!), isEmpty);
        await signIn(guard, _b);
        expect(await _names(guard.database!), ['Metformin']);
      });

      test('the sign-out event arriving afterwards changes nothing', () async {
        final guard = guardWith();
        await guard.boot(sessionUid: _a);
        await _addMedication(guard.database!, 'Warfarin');

        await guard.removeAccountData(_a);
        final action = await guard.onAuthEvent(
          event: AuthChangeEvent.signedOut,
          uid: null,
        );

        expect(action, AccountSwitchAction.keep);
        expect(await storage.hasData(_a), isFalse);
      });
    });

    group('moving the old shared store', () {
      test('goes to the owner on record, even when signed out', () async {
        await writeLegacyDatabase('Warfarin');
        await AccountOwnerStore().write(_a);

        final guard = guardWith();
        await guard.boot(sessionUid: null);

        expect(await _names(guard.database!), isEmpty);
        expect(
          File(p.join(documents.path, 'user_data.db')).existsSync(),
          isFalse,
        );
        await signIn(guard, _a);
        expect(await _names(guard.database!), ['Warfarin']);
      });

      test('goes to the owner on record, not whoever is signed in', () async {
        await writeLegacyDatabase('Warfarin');
        await AccountOwnerStore().write(_a);

        final guard = guardWith();
        await guard.boot(sessionUid: _b);

        expect(await _names(guard.database!), isEmpty);
        await signIn(guard, _a);
        expect(await _names(guard.database!), ['Warfarin']);
      });

      test('with no owner it is guest data, and a session adopts it', () async {
        await writeLegacyDatabase('Lisinopril');

        final guard = guardWith();
        await guard.boot(sessionUid: _a);

        expect(await _names(guard.database!), ['Lisinopril']);
        expect(await AccountOwnerStore().read(), _a);
      });

      test('carries attachments and recent searches with it', () async {
        await writeLegacyDatabase('Warfarin');
        await AccountOwnerStore().write(_a);
        SharedPreferences.setMockInitialValues({
          'flutter.account_owner_uid': _a,
          'flutter.recent_searches': <String>['warfarin'],
        });
        final legacy = await Directory(
          p.join(support.path, 'health_history_attachments'),
        ).create();
        await File(p.join(legacy.path, 'photo.jpg')).writeAsString('photo');

        final guard = guardWith();
        await guard.boot(sessionUid: _a);

        final moved = guard.account.attachmentFile('/old/container/photo.jpg');
        expect(moved.readAsStringSync(), 'photo');
        expect(legacy.existsSync(), isFalse);
        expect(
          await RecentSearchesService(scope: guard.account.scope).getRecent(),
          ['warfarin'],
        );
        expect(await RecentSearchesService().getRecent(), isEmpty);
      });

      test('keeps the write-ahead log with its database', () async {
        await writeLegacyDatabase('Warfarin');
        final wal = File(p.join(documents.path, 'user_data.db-wal'));
        await wal.writeAsString('');

        await storage.migrateLegacyStore(owner: _a);

        expect(wal.existsSync(), isFalse);
        expect(
          File('${await storage.databasePathFor(_a)}-wal').existsSync(),
          isTrue,
        );
      });

      test('a crash after the log moved finishes on the next launch', () async {
        await writeLegacyDatabase('Warfarin');
        final target = await storage.databasePathFor(_a);
        await File(
          p.join(documents.path, 'user_data.db-wal'),
        ).writeAsString('');
        await File(
          p.join(documents.path, 'user_data.db-wal'),
        ).rename('$target-wal');

        await storage.migrateLegacyStore(owner: _a);

        expect(File(target).existsSync(), isTrue);
        expect(
          File(p.join(documents.path, 'user_data.db')).existsSync(),
          isFalse,
        );
      });

      test('never overwrites an account that already has a database', () async {
        final guard = guardWith();
        await guard.boot(sessionUid: _a);
        await _addMedication(guard.database!, 'Warfarin');
        await guard.close();
        await writeLegacyDatabase('Stale');

        final next = guardWith();
        await next.boot(sessionUid: _a);

        expect(await _names(next.database!), ['Warfarin']);
        expect(
          File(p.join(documents.path, 'user_data.db')).existsSync(),
          isTrue,
        );
      });
    });

    test('nothing on disk or in preferences names the uid', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);
      await RecentSearchesService(scope: guard.account.scope).addSearch('x');

      final paths = support.listSync(recursive: true).map((e) => e.path);
      expect(paths.where((path) => path.contains(_a)), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final recents = prefs.getKeys().where((k) => k.startsWith('recent'));
      expect(recents.where((key) => key.contains(_a)), isEmpty);
      expect(recents, isNotEmpty);
    });

    test('each account imports attachments into its own folder', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);
      final source = File(p.join(support.path, 'pick.jpg'));
      await source.writeAsString('a');

      Future<String> importAs(ActiveAccount account) async {
        final container = ProviderContainer(
          overrides: [activeAccountProvider.overrideWithValue(account)],
        );
        addTearDown(container.dispose);
        final imported = await container
            .read(healthAttachmentStoreProvider)
            .importImage(XFile(source.path, name: 'pick.jpg'));
        return imported.path;
      }

      final aFile = await importAs(guard.account);
      expect(p.isWithin(guard.account.attachmentsPath!, aFile), isTrue);

      await signIn(guard, _b);
      final bFile = await importAs(guard.account);
      expect(p.isWithin(guard.account.attachmentsPath!, bFile), isTrue);
      expect(p.isWithin(guard.account.attachmentsPath!, aFile), isFalse);

      await guard.removeAccountData(_a);
      expect(File(aFile).existsSync(), isFalse);
      expect(File(bFile).existsSync(), isTrue);
    });

    test(
      'removing an account also removes what lives outside its folder',
      () async {
        final removed = <String>[];
        final guard = AccountSwitchGuard(
          ownerStore: AccountOwnerStore(),
          storage: storage,
          openDatabase: (path) async => UserDatabase.open(path),
          onAccountRemoved: (uid) async => removed.add(uid),
        );
        addTearDown(guard.close);
        await guard.boot(sessionUid: _a);

        await guard.removeAccountData(_a);

        expect(removed, [_a]);
      },
    );

    test('recent searches follow the provider tree\'s account', () async {
      final guard = guardWith();
      await guard.boot(sessionUid: _a);

      RecentSearchesService serviceFor(ActiveAccount account) {
        final container = ProviderContainer(
          overrides: [activeAccountProvider.overrideWithValue(account)],
        );
        addTearDown(container.dispose);
        return container.read(recentSearchesServiceProvider);
      }

      await serviceFor(guard.account).addSearch('warfarin');
      await signOut(guard);
      expect(await serviceFor(guard.account).getRecent(), isEmpty);
      await signIn(guard, _a);
      expect(await serviceFor(guard.account).getRecent(), ['warfarin']);
    });
  });

  group('ActiveAccount without storage', () {
    test('uses the stored attachment path as it is', () {
      expect(
        ActiveAccount.guest.attachmentFile('/some/where/photo.jpg').path,
        '/some/where/photo.jpg',
      );
    });
  });
}
