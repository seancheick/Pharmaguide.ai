// The account gate (ADR-013): every branch of the pure decision, then the real
// guard against real folders on disk.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/auth/account_database_cipher.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/recent_searches_service.dart';
import 'package:pharmaguide/services/pending_submission_intent.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_scope.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';
import 'package:pharmaguide/features/ai_share/ai_share_snapshot_pusher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../features/ai_share/ai_share_test_fixtures.dart';

const _a = 'account-a';
const _b = 'account-b';

Future<void> _addMedication(UserDatabase db, String name) => db.addToStack(
  UserStacksLocalCompanion.insert(
    id: 'id-$name',
    name: name,
    type: const Value('medication'),
  ),
);

Future<void> _addHistoryEvent(UserDatabase db, String subjectType) => db
    .into(db.healthHistoryEvents)
    .insert(
      HealthHistoryEventsCompanion.insert(
        id: 'event-$subjectType',
        eventType: 'test',
        source: 'test',
        subjectType: subjectType,
        title: 'Test',
        effectiveAt: DateTime(2026),
      ),
    );

/// Storage whose delete fails, as a held file or a full disk would.
class _UndeletableStorage extends AccountStorage {
  _UndeletableStorage({
    required super.supportDirectory,
    required super.documentsDirectory,
    this.databaseFails = false,
    this.restFails = false,
  });

  final bool databaseFails;
  final bool restFails;

  @override
  Future<void> deleteDatabase(String? uid) async {
    if (databaseFails) throw const FileSystemException('delete refused');
    await super.deleteDatabase(uid);
  }

  @override
  Future<void> delete(String? uid) async {
    if (restFails) throw const FileSystemException('delete refused');
    await super.delete(uid);
  }
}

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
      String? Function()? readSessionUid,
      bool askBeforeAdoptingGuest = false,
      Future<void> Function()? clearSharedReport,
      Future<void> Function()? purgeAiShare,
      Future<void> Function(String uid)? onAccountRemoved,
      AccountStorage? storageOverride,
    }) {
      final guard = AccountSwitchGuard(
        ownerStore: AccountOwnerStore(),
        storage: storageOverride ?? storage,
        openDatabase: open ?? (path) async => UserDatabase.open(path),
        onOwnerChange: onOwnerChange,
        readSessionUid: readSessionUid,
        askBeforeAdoptingGuest: askBeforeAdoptingGuest,
        clearSharedReport: clearSharedReport ?? () async {},
        purgeAiShare: purgeAiShare ?? () async {},
        onAccountRemoved: onAccountRemoved,
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

    test(
      'sign-out clears a pending submission even when reminder cleanup fails',
      () async {
        final guard = guardWith(
          onOwnerChange: () async => throw StateError('notifications'),
        );
        await guard.boot(sessionUid: _a);
        await PendingSubmissionIntent.saveLabelMismatch('12345');
        expect(await PendingSubmissionIntent.peek(), isNotNull);
        await signOut(guard);
        expect(await PendingSubmissionIntent.peek(), isNull);
      },
    );

    test(
      'guest sign-in preserves the submission that requested authentication',
      () async {
        final guard = guardWith();
        await guard.boot(sessionUid: null);
        await PendingSubmissionIntent.saveLabelMismatch('12345');
        await signIn(guard, _a);
        expect(await PendingSubmissionIntent.peek(), isNotNull);
      },
    );

    test(
      'retry after a failed open uses the current session, never the expired owner',
      () async {
        String? session = _a;
        var failing = true;
        final guard = guardWith(
          readSessionUid: () => session,
          open: (path) async {
            if (failing) throw const FileSystemException('unavailable');
            return UserDatabase.open(path);
          },
        );
        await guard.boot(sessionUid: session);
        expect(guard.database, isNull);
        // The unavailable screen has no auth listener. Expiration can happen
        // here, before the user retries the failed database open.
        session = null;
        failing = false;
        await guard.retry();
        expect(guard.ownerUid, isNull);
        expect(guard.account.scope, AccountStorage.guestScope);
        expect(await AccountOwnerStore().read(), isNull);
      },
    );

    test(
      'a session lost while a database opens never publishes that owner',
      () async {
        String? session = _a;
        final guard = guardWith(
          readSessionUid: () => session,
          open: (path) async {
            session = null;
            return UserDatabase.open(path);
          },
        );
        await guard.boot(sessionUid: _a);
        expect(guard.database, isNull);
        await guard.retry();
        expect(guard.database, isNotNull);
        expect(guard.ownerUid, isNull);
      },
    );

    test(
      'boot cleans up the previous owner before opening the current session',
      () async {
        await AccountOwnerStore().write(_a);
        var cleaned = false;
        final guard = guardWith(
          onOwnerChange: () async => cleaned = true,
          open: (path) async {
            expect(
              cleaned,
              isTrue,
              reason: 'old reminders and sharing must end first',
            );
            return UserDatabase.open(path);
          },
        );
        await guard.boot(sessionUid: null);
        expect(cleaned, isTrue);
        expect(guard.database, isNotNull);
      },
    );

    test(
      'a storage lookup failure during sign-out cannot leave account data open',
      () async {
        var failPaths = false;
        storage = AccountStorage(
          supportDirectory: () async {
            if (failPaths) {
              throw const FileSystemException('unavailable directory');
            }
            return support;
          },
          documentsDirectory: () async => documents,
        );
        final guard = guardWith();
        await guard.boot(sessionUid: _a);
        await _addMedication(guard.database!, 'Warfarin');
        failPaths = true;
        await expectLater(signOut(guard), completes);
        expect(guard.database, isNull);
        expect(guard.ownerUid, isNull);
      },
    );

    test(
      'a retained old provider tree cannot schedule after switching owners',
      () async {
        final guard = guardWith();
        await guard.boot(sessionUid: _a);
        final oldAccount = guard.account;
        await signOut(guard);
        var wrote = false;
        await expectLater(
          guard.runNotificationWork(() async {
            wrote = true;
          }, account: oldAccount),
          throwsStateError,
        );
        expect(wrote, isFalse);
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

    group('starting over after a lost key', () {
      /// Opens normally until [lock] names an account's database as lost.
      late Object? failure;
      late String? failingScope;
      late int opens;

      Future<UserDatabase> openOrFail(String path) async {
        opens++;
        final error = failure;
        if (error != null && path.contains(failingScope!)) throw error;
        return UserDatabase.open(path);
      }

      void lock(String? uid, Object error) {
        failure = error;
        failingScope = AccountStorage.scopeFor(uid);
      }

      File databaseOf(String? uid) => File(
        p.join(
          support.path,
          'users',
          AccountStorage.scopeFor(uid),
          AccountStorage.databaseName,
        ),
      );

      setUp(() {
        failure = null;
        failingScope = null;
        opens = 0;
      });

      /// A guard on the locked account, its data on disk.
      Future<AccountSwitchGuard> lockedGuard({
        Future<void> Function()? onOwnerChange,
        Future<void> Function()? purgeAiShare,
        Future<void> Function(String uid)? onAccountRemoved,
        String? Function()? readSessionUid,
        AccountStorage? storageOverride,
        Object error = const AccountKeyLost(),
      }) async {
        final first = guardWith(open: openOrFail);
        await first.boot(sessionUid: _a);
        await _addMedication(first.database!, 'Warfarin');
        await first.close();
        lock(_a, error);
        final guard = guardWith(
          open: openOrFail,
          onOwnerChange: onOwnerChange,
          purgeAiShare: purgeAiShare,
          onAccountRemoved: onAccountRemoved,
          readSessionUid: readSessionUid,
          storageOverride: storageOverride,
        );
        await guard.boot(sessionUid: _a);
        expect(guard.database, isNull);
        return guard;
      }

      final otherFailures = <String, Object>{
        'a store read that errors': const AccountKeyUnavailable(),
        'a damaged database': StateError('file is not a database'),
        'a full disk': const FileSystemException('No space left on device'),
      };
      for (final MapEntry(key: name, value: error) in otherFailures.entries) {
        test('$name offers a retry only, and the erase refuses', () async {
          var purges = 0;
          final guard = await lockedGuard(
            error: error,
            purgeAiShare: () async => purges++,
          );
          final before = databaseOf(_a).readAsBytesSync();

          expect(guard.canStartOver, isFalse);
          await expectLater(guard.startOver(), throwsStateError);

          expect(databaseOf(_a).readAsBytesSync(), before);
          expect(guard.database, isNull);
          expect(purges, 0);

          failure = null;
          await guard.retry();
          expect(await _names(guard.database!), ['Warfarin']);
        });
      }

      test('a lost key offers it, and a healthy account never does', () async {
        final healthy = guardWith(open: openOrFail);
        await healthy.boot(sessionUid: _a);
        await _addMedication(healthy.database!, 'Warfarin');
        expect(healthy.canStartOver, isFalse);
        await expectLater(healthy.startOver(), throwsStateError);
        expect(await _names(healthy.database!), ['Warfarin']);
        await healthy.close();

        lock(_a, const AccountKeyLost());
        final guard = guardWith(open: openOrFail);
        await guard.boot(sessionUid: _a);
        expect(guard.canStartOver, isTrue);
      });

      test('a retry that opens the data takes the offer away', () async {
        final guard = await lockedGuard();
        expect(guard.canStartOver, isTrue);

        failure = null;
        await guard.retry();

        expect(guard.canStartOver, isFalse);
        await expectLater(guard.startOver(), throwsStateError);
        expect(await _names(guard.database!), ['Warfarin']);
      });

      test('erases the locked account and opens an empty one', () async {
        final removed = <String>[];
        final guard = await lockedGuard(
          onAccountRemoved: (uid) async => removed.add(uid),
        );
        final scope = guard.account.scope;
        await RecentSearchesService(scope: scope).addSearch('warfarin');
        failure = null;

        await guard.startOver();

        expect(guard.ownerUid, _a);
        expect(await _names(guard.database!), isEmpty);
        expect(guard.canStartOver, isFalse);
        expect(await RecentSearchesService(scope: scope).getRecent(), isEmpty);
        expect(removed, [_a]);
      });

      test('another account and the guest keep everything', () async {
        final others = guardWith(open: openOrFail);
        await others.boot(sessionUid: _a);
        await _addMedication(others.database!, 'Warfarin');
        await signIn(others, _b);
        await _addMedication(others.database!, 'Metformin');
        final bScope = others.account.scope;
        await RecentSearchesService(scope: bScope).addSearch('b search');
        await signOut(others);
        await _addMedication(others.database!, 'Guest item');
        final guestScope = others.account.scope;
        await RecentSearchesService(
          scope: guestScope,
        ).addSearch('guest search');
        await signIn(others, _a);
        await others.close();

        lock(_a, const AccountKeyLost());
        final guard = guardWith(open: openOrFail);
        await guard.boot(sessionUid: _a);
        expect(guard.canStartOver, isTrue);
        failure = null;

        await guard.startOver();

        expect(await _names(guard.database!), isEmpty);
        await signOut(guard);
        expect(await _names(guard.database!), ['Guest item']);
        expect(await RecentSearchesService(scope: guestScope).getRecent(), [
          'guest search',
        ]);
        await signIn(guard, _b);
        expect(await _names(guard.database!), ['Metformin']);
        expect(await RecentSearchesService(scope: bScope).getRecent(), [
          'b search',
        ]);
      });

      test(
        'a guest waiting to be adopted is not pulled into the new start',
        () async {
          final seed = guardWith(open: openOrFail);
          await seed.boot(sessionUid: _a);
          await _addMedication(seed.database!, 'Warfarin');
          await signOut(seed);
          await _addMedication(seed.database!, 'Guest item');
          await seed.close();

          // No owner on record and a session found: this open adopts the guest
          // if the account has no database, which is what erasing leaves.
          lock(_a, const AccountKeyLost());
          final guard = guardWith(open: openOrFail);
          await guard.boot(sessionUid: _a);
          expect(guard.canStartOver, isTrue);
          failure = null;

          await guard.startOver();

          expect(await _names(guard.database!), isEmpty);
          expect(databaseOf(null).existsSync(), isTrue);
          await signOut(guard);
          expect(await _names(guard.database!), ['Guest item']);
        },
      );

      test('a locked guest erases the guest only', () async {
        final seed = guardWith(open: openOrFail);
        await seed.boot(sessionUid: _a);
        await _addMedication(seed.database!, 'Warfarin');
        await signOut(seed);
        await _addMedication(seed.database!, 'Guest item');
        await seed.close();

        lock(null, const AccountKeyLost());
        final guard = guardWith(open: openOrFail);
        await guard.boot(sessionUid: null);
        expect(guard.canStartOver, isTrue);
        failure = null;

        await guard.startOver();

        expect(guard.ownerUid, isNull);
        expect(await _names(guard.database!), isEmpty);
        await signIn(guard, _a);
        expect(await _names(guard.database!), ['Warfarin']);
      });

      test('a failed erase changes nothing, and nothing new opens', () async {
        var ownerWork = 0;
        var purges = 0;
        final removed = <String>[];
        final guard = await lockedGuard(
          onOwnerChange: () async => ownerWork++,
          purgeAiShare: () async => purges++,
          onAccountRemoved: (uid) async => removed.add(uid),
          storageOverride: _UndeletableStorage(
            supportDirectory: () async => support,
            documentsDirectory: () async => documents,
            databaseFails: true,
          ),
        );
        final scope = guard.account.scope;
        await RecentSearchesService(scope: scope).addSearch('warfarin');
        final before = databaseOf(_a).readAsBytesSync();
        final opensBefore = opens;
        final ownerWorkBefore = ownerWork;

        await expectLater(
          guard.startOver(),
          throwsA(isA<FileSystemException>()),
        );

        expect(guard.database, isNull, reason: 'still locked');
        expect(guard.canStartOver, isTrue, reason: 'it can be tried again');
        expect(databaseOf(_a).readAsBytesSync(), before);
        expect(opens, opensBefore, reason: 'nothing new was created');
        expect(ownerWork, ownerWorkBefore);
        expect(purges, 0);
        expect(removed, isEmpty);
        expect(await RecentSearchesService(scope: scope).getRecent(), [
          'warfarin',
        ]);
      });

      test(
        'once the database is gone, a failed cleanup never leaves the person locked',
        () async {
          final guard = await lockedGuard(
            purgeAiShare: () async => throw StateError('purge failed'),
            onAccountRemoved: (_) async => throw StateError('drafts failed'),
            storageOverride: _UndeletableStorage(
              supportDirectory: () async => support,
              documentsDirectory: () async => documents,
              restFails: true,
            ),
          );
          failure = null;

          await guard.startOver();

          expect(await _names(guard.database!), isEmpty);
        },
      );

      test('a session that changed underneath refuses the erase', () async {
        String? session = _a;
        final guard = await lockedGuard(readSessionUid: () => session);
        final before = databaseOf(_a).readAsBytesSync();
        session = _b;

        await expectLater(guard.startOver(), throwsStateError);

        expect(databaseOf(_a).readAsBytesSync(), before);
        expect(guard.database, isNull);
      });

      test('the erased account leaves no reminder behind', () async {
        var ownerWork = 0;
        final guard = await lockedGuard(onOwnerChange: () async => ownerWork++);
        final before = ownerWork;
        failure = null;

        await guard.startOver();

        expect(ownerWork, before + 1);
      });

      test('offline: it still finishes, and nothing uploads again', () async {
        final backend = FakeAiShareBackend()..failWith = StateError('offline');
        final prefs = AiSharePrefsStore(MemoryPreferencesStore());
        await prefs.recordShare('c-1', AiShareScope.detailedReport, 24);
        await prefs.setKeepUpdated('c-1', true);
        final guard = await lockedGuard(
          purgeAiShare: () =>
              purgeAiShareData(prefs: prefs, snapshots: backend.client()),
        );
        failure = null;

        await guard.startOver();

        expect(await _names(guard.database!), isEmpty);
        expect(backend.deletes, hasLength(1), reason: 'it did try');
        expect(await prefs.readAll(), isEmpty);

        backend.failWith = null;
        final pushed = await AiShareSnapshotPusher(
          isSignedIn: () => true,
          prefs: prefs,
          client: backend.client(),
          loadData: () async => aiShareFixture(),
        ).refreshAfterStackChange();
        expect(pushed, 0);
        expect(backend.uploads, isEmpty);
      });

      test('online: the snapshots are deleted', () async {
        final backend = FakeAiShareBackend();
        final prefs = AiSharePrefsStore(MemoryPreferencesStore());
        final guard = await lockedGuard(
          purgeAiShare: () =>
              purgeAiShareData(prefs: prefs, snapshots: backend.client()),
        );
        failure = null;

        await guard.startOver();

        expect(backend.deletes.single.body, {'all': true});
      });

      testWidgets('a delete that never answers gives up after ten seconds', (
        tester,
      ) async {
        final prefs = AiSharePrefsStore(MemoryPreferencesStore());
        var finished = false;
        unawaited(
          purgeAiShareData(
            prefs: prefs,
            snapshots: AiShareSnapshotClient(
              isSignedIn: () => true,
              invoke: (_, _) => Completer<AiShareInvokeResponse>().future,
            ),
          ).then((_) => finished = true),
        );

        await tester.pump(const Duration(seconds: 9));
        expect(finished, isFalse);
        await tester.pump(const Duration(seconds: 2));
        expect(finished, isTrue);
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

      test(
        'a leftover legacy store never changes owners on a later launch',
        () async {
          final existing = UserDatabase.open(await storage.databasePathFor(_a));
          await _addMedication(existing, 'Current A');
          await existing.close();
          await writeLegacyDatabase('Legacy A');
          await AccountOwnerStore().write(_a);

          final first = guardWith();
          await first.boot(sessionUid: _b);
          expect(await _names(first.database!), isEmpty);
          await first.close();

          // The active owner is now B. A retained shared store must not be
          // migrated as B's data when B's current folder is removed.
          await storage.delete(_b);
          final next = guardWith();
          await next.boot(sessionUid: _b);
          expect(await _names(next.database!), isEmpty);
        },
      );

      test(
        'colliding legacy attachments never become guest attachments',
        () async {
          final existing = UserDatabase.open(await storage.databasePathFor(_a));
          await existing.close();
          final account = await storage.accountFor(_a);
          await Directory(account.attachmentsPath!).create();
          final legacy = await Directory(
            p.join(support.path, 'health_history_attachments'),
          ).create();
          await File(
            p.join(legacy.path, 'private.jpg'),
          ).writeAsString('private');
          await AccountOwnerStore().write(_a);

          final first = guardWith();
          await first.boot(sessionUid: null);
          await first.close();
          final next = guardWith();
          await next.boot(sessionUid: null);
          expect(
            next.account.attachmentFile('private.jpg').existsSync(),
            isFalse,
          );
        },
      );

      test(
        'a store recreated by an older build still opens, keeping every archive',
        () async {
          final guard = guardWith();
          await guard.boot(sessionUid: _a);
          await _addMedication(guard.database!, 'Current');
          final folder = guard.account.folder!;
          await Directory(guard.account.attachmentsPath!).create();
          await guard.close();

          Future<void> writeLegacyAttachment(String content) async {
            final legacy = await Directory(
              p.join(support.path, 'health_history_attachments'),
            ).create();
            await File(p.join(legacy.path, 'photo.jpg')).writeAsString(content);
          }

          Future<AccountSwitchGuard> launchWithLeftovers(String label) async {
            await writeLegacyDatabase(label);
            await writeLegacyAttachment(label);
            final launch = guardWith();
            await launch.boot(sessionUid: _a);
            return launch;
          }

          final second = await launchWithLeftovers('First');
          expect(await _names(second.database!), ['Current']);
          await second.close();

          // A downgrade and upgrade leaves the same paths behind again. Refusing
          // here would lock this person out on every launch, retry included.
          final third = await launchWithLeftovers('Second');
          expect(third.database, isNotNull);
          expect(await _names(third.database!), ['Current']);
          expect(
            File(p.join(documents.path, 'user_data.db')).existsSync(),
            isFalse,
          );

          final archived = Directory(p.join(folder, 'legacy'))
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => file.path)
              .toList();
          expect(
            archived.where((f) => f.endsWith('user_data.db')),
            hasLength(2),
          );
          final photos = archived
              .where((f) => f.endsWith('photo.jpg'))
              .toList();
          expect(photos.map((f) => File(f).readAsStringSync()).toSet(), {
            'First',
            'Second',
          });

          await third.removeAccountData(_a);
          expect(Directory(folder).existsSync(), isFalse);
        },
      );

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
          isFalse,
        );
        final archive = File(
          p.join(next.account.folder!, 'legacy', 'user_data.db'),
        );
        expect(archive.existsSync(), isTrue);
        await next.removeAccountData(_a);
        expect(archive.existsSync(), isFalse);
      });
    });

    group('guest data at sign-in', () {
      AccountSwitchGuard asking({String? Function()? readSessionUid}) =>
          guardWith(
            askBeforeAdoptingGuest: true,
            readSessionUid: readSessionUid,
          );

      /// Resolves when the guard asks, so a test can never pass by not asking.
      Future<void> asked(AccountSwitchGuard guard) {
        final question = Completer<void>();
        guard.onGuestDataQuestion = question.complete;
        return question.future.timeout(const Duration(seconds: 5));
      }

      Future<AccountSwitchGuard> guestWithMedication() async {
        final guard = asking();
        await guard.boot(sessionUid: null);
        await _addMedication(guard.database!, 'Friend med');
        return guard;
      }

      test('nothing moves until the person answers', () async {
        final guard = await guestWithMedication();
        final question = asked(guard);

        final signingIn = signIn(guard, _a);
        await question;

        expect(guard.awaitingGuestDataAnswer, isTrue);
        expect(guard.ownerUid, isNull);
        expect(await storage.hasData(_a), isFalse);

        guard.answerGuestDataQuestion(true);
        await signingIn;
      });

      test('yes moves the data into the account', () async {
        final guard = await guestWithMedication();
        final question = asked(guard);
        final signingIn = signIn(guard, _a);
        await question;

        guard.answerGuestDataQuestion(true);
        await signingIn;

        expect(guard.awaitingGuestDataAnswer, isFalse);
        expect(guard.ownerUid, _a);
        expect(await _names(guard.database!), ['Friend med']);
      });

      test(
        'no leaves the account empty and the guest data where it was',
        () async {
          final guard = await guestWithMedication();
          await RecentSearchesService().addSearch('friend search');
          final question = asked(guard);
          final signingIn = signIn(guard, _a);
          await question;

          guard.answerGuestDataQuestion(false);
          await signingIn;

          expect(guard.ownerUid, _a);
          expect(await _names(guard.database!), isEmpty);
          final accountSearches = RecentSearchesService(
            scope: guard.account.scope,
          );
          expect(await accountSearches.getRecent(), isEmpty);

          await signOut(guard);
          expect(await _names(guard.database!), ['Friend med']);
          expect(await RecentSearchesService().getRecent(), ['friend search']);
        },
      );

      test('the same account is only asked once', () async {
        final guard = await guestWithMedication();
        final question = asked(guard);
        final signingIn = signIn(guard, _a);
        await question;
        guard.answerGuestDataQuestion(false);
        await signingIn;
        await signOut(guard);

        await signIn(guard, _a);

        expect(guard.awaitingGuestDataAnswer, isFalse);
        expect(await _names(guard.database!), isEmpty);
      });

      test('a different account is asked for itself', () async {
        final guard = await guestWithMedication();
        final first = asked(guard);
        final signingInA = signIn(guard, _a);
        await first;
        guard.answerGuestDataQuestion(false);
        await signingInA;
        await signOut(guard);

        final second = asked(guard);
        final signingInB = signIn(guard, _b);
        await second;
        guard.answerGuestDataQuestion(true);
        await signingInB;

        expect(guard.ownerUid, _b);
        expect(await _names(guard.database!), ['Friend med']);
      });

      test('a second answer changes nothing', () async {
        final guard = await guestWithMedication();
        final question = asked(guard);
        final signingIn = signIn(guard, _a);
        await question;

        guard.answerGuestDataQuestion(false);
        guard.answerGuestDataQuestion(true);
        await signingIn;

        expect(await _names(guard.database!), isEmpty);
      });

      test('an empty guest adopts without asking', () async {
        final guard = asking();
        await guard.boot(sessionUid: null);
        var questions = 0;
        guard.onGuestDataQuestion = () => questions++;

        await signIn(guard, _a);

        expect(questions, 0);
        expect(guard.ownerUid, _a);
      });

      test('an account with data here never asks', () async {
        final first = guardWith();
        await first.boot(sessionUid: _a);
        await _addMedication(first.database!, 'Mine');
        await first.close();
        final guard = await guestWithMedication();
        var questions = 0;
        guard.onGuestDataQuestion = () => questions++;

        await signIn(guard, _a);

        expect(questions, 0);
        expect(await _names(guard.database!), ['Mine']);
      });

      final personal = <String, Future<void> Function(UserDatabase)>{
        'a profile': (db) => db.saveProfile(
          const UserProfilesCompanion(id: Value(1), sex: Value('female')),
        ),
        'a stack item': (db) => _addMedication(db, 'Item'),
        'a favorite': (db) => db.addFavorite('123'),
        'a scan': (db) => db.recordScanEvent(dsldId: '123', upcSku: '456'),
        'a history entry': (db) => _addHistoryEvent(db, 'medication'),
        'a cleared profile with retained personal history': (db) async {
          await _addHistoryEvent(db, 'profile');
          await db.customStatement(
            "UPDATE health_history_events SET previous_value_json = "
            "'{\"conditions\":[\"pregnancy\"]}' WHERE subject_type = 'profile'",
          );
        },
      };
      personal.forEach((name, add) {
        test('$name is something to ask about', () async {
          final guard = asking();
          await guard.boot(sessionUid: null);
          await add(guard.database!);
          final question = asked(guard);

          final signingIn = signIn(guard, _a);
          await question;
          guard.answerGuestDataQuestion(false);
          await signingIn;
        });
      });

      test('a recent search is something to ask about', () async {
        final guard = asking();
        await guard.boot(sessionUid: null);
        await RecentSearchesService().addSearch('private search');
        final question = asked(guard);

        final signingIn = signIn(guard, _a);
        await question;
        guard.answerGuestDataQuestion(false);
        await signingIn;
      });

      test('a blank profile, a removed item and caches are not', () async {
        final guard = asking();
        await guard.boot(sessionUid: null);
        await guard.database!.saveProfile(
          const UserProfilesCompanion(id: Value(1)),
        );
        await _addHistoryEvent(guard.database!, 'profile');
        await _addMedication(guard.database!, 'Removed');
        await guard.database!.customStatement(
          'UPDATE user_stacks_local SET deleted_at = 1',
        );
        await guard.database!.recordFailedScan('000');
        var questions = 0;
        guard.onGuestDataQuestion = () => questions++;

        await signIn(guard, _a);

        expect(questions, 0);
      });

      test('a guest database that cannot be read still asks', () async {
        final failing = asking();
        await failing.boot(sessionUid: null);
        await failing.database!.customStatement('DROP TABLE user_favorites');
        final question = asked(failing);

        final signingIn = signIn(failing, _a);
        await question;
        failing.answerGuestDataQuestion(false);
        await signingIn;

        expect(failing.ownerUid, _a);
      });

      test('a restart during the question asks again', () async {
        final guard = await guestWithMedication();
        final question = asked(guard);
        unawaited(signIn(guard, _a));
        await question;
        // The app dies here: the session exists and nothing else changed.

        final relaunch = asking(readSessionUid: () => _a);
        await relaunch.boot(sessionUid: _a);

        // Asked from the first frame, with nothing open for a tree to read.
        expect(relaunch.awaitingGuestDataAnswer, isTrue);
        expect(relaunch.database, isNull);
        expect(relaunch.ownerUid, isNull);
        expect(await AccountOwnerStore().read(), isNull);
        expect(await storage.hasData(_a), isFalse);

        relaunch.answerGuestDataQuestion(true);
        await relaunch.onAuthEvent(
          event: AuthChangeEvent.initialSession,
          uid: _a,
        );

        expect(relaunch.ownerUid, _a);
        expect(await _names(relaunch.database!), ['Friend med']);
      });

      test('a restart with an empty guest adopts without asking', () async {
        final seed = asking();
        await seed.boot(sessionUid: null);
        await seed.close();

        final relaunch = asking(readSessionUid: () => _a);
        await relaunch.boot(sessionUid: _a);

        expect(relaunch.awaitingGuestDataAnswer, isFalse);
        expect(relaunch.ownerUid, _a);
      });

      test('a session that ends during the question moves nothing', () async {
        var session = _a as String?;
        final seed = asking();
        await seed.boot(sessionUid: null);
        await _addMedication(seed.database!, 'Friend med');
        await seed.close();
        final guard = asking(readSessionUid: () => session);
        await guard.boot(sessionUid: _a);
        expect(guard.awaitingGuestDataAnswer, isTrue);

        session = null;
        guard.answerGuestDataQuestion(true);
        await guard.onAuthEvent(event: AuthChangeEvent.signedOut, uid: null);

        expect(guard.ownerUid, isNull);
        expect(await _names(guard.database!), ['Friend med']);
        expect(await storage.hasData(_a), isFalse);
      });

      test('closing during the question finishes', () async {
        final guard = await guestWithMedication();
        final question = asked(guard);
        unawaited(signIn(guard, _a));
        await question;

        await guard.close().timeout(const Duration(seconds: 5));

        expect(await storage.hasData(_a), isFalse);
      });

      test('an upgrade with a session and no owner stays silent', () async {
        await writeLegacyDatabase('My old data');

        final guard = asking(readSessionUid: () => _a);
        await guard.boot(sessionUid: _a);

        expect(guard.awaitingGuestDataAnswer, isFalse);
        expect(guard.ownerUid, _a);
        expect(await _names(guard.database!), ['My old data']);
      });

      test('retry from the error screen cannot skip the question', () async {
        final seed = asking();
        await seed.boot(sessionUid: null);
        await _addMedication(seed.database!, 'Friend med');
        await seed.close();
        var session = 'none';
        var failNextOpen = true;
        final guard = guardWith(
          askBeforeAdoptingGuest: true,
          readSessionUid: () => session == 'none' ? null : session,
          open: (path) async {
            if (failNextOpen) {
              failNextOpen = false;
              throw const FileSystemException('unavailable');
            }
            return UserDatabase.open(path);
          },
        );
        await guard.boot(sessionUid: null);
        expect(guard.database, isNull);

        session = _a;
        final question = asked(guard);
        final retrying = guard.retry();
        await question;
        guard.answerGuestDataQuestion(false);
        await retrying;

        expect(guard.ownerUid, _a);
        expect(await _names(guard.database!), isEmpty);
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

    group('the shared clinician report copy', () {
      var clears = 0;
      Future<void> countClear() async => clears++;
      setUp(() => clears = 0);

      test('is cleared on every launch, even with the same owner', () async {
        final guard = guardWith(clearSharedReport: countClear);
        await guard.boot(sessionUid: null);
        expect(clears, 1);
      });

      test('is cleared at sign-out', () async {
        final guard = guardWith(clearSharedReport: countClear);
        await guard.boot(sessionUid: _a);
        clears = 0;
        await signOut(guard);
        expect(clears, 1);
      });

      test('is cleared when switching straight to another account', () async {
        final guard = guardWith(clearSharedReport: countClear);
        await guard.boot(sessionUid: _a);
        clears = 0;
        await signIn(guard, _b);
        expect(clears, 1);
      });

      test('is cleared when an account that is not open is removed', () async {
        final guard = guardWith(clearSharedReport: countClear);
        await guard.boot(sessionUid: _a);
        await signOut(guard);
        clears = 0;
        await guard.removeAccountData(_a);
        expect(clears, 1);
      });

      test('a clear that never finishes does not hold up launch', () async {
        final guard = guardWith(
          clearSharedReport: () => Completer<void>().future,
        );
        await guard.boot(sessionUid: _a);
        expect(guard.database, isNotNull);
      });

      test('a failed clear blocks neither launch nor sign-out', () async {
        final guard = guardWith(
          clearSharedReport: () async =>
              throw const FileSystemException('refused'),
        );
        await guard.boot(sessionUid: _a);
        expect(guard.database, isNotNull);
        expect(guard.ownerUid, _a);

        await signOut(guard);
        expect(guard.database, isNotNull);
        expect(guard.ownerUid, isNull);
      });
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
