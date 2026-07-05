// Shared-device account hygiene — the "clear on account switch" gate.
//
// The next user on a device must not inherit or upload the previous
// user's medical data. The decision is a PURE function
// (`decideAccountAction`) so every branch is unit-testable; the
// destructive clear is wired behind it in `AccountSwitchGuard`.
//
// CRITICAL SAFETY: the clear is destructive and there is NO cloud
// backup for profile/meds/conditions/allergens. It must fire ONLY on a
// genuine different-uid sign-in — never on tokenRefreshed, userUpdated,
// the same uid reappearing, initialSession with the same uid, or
// signedOut.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // Pure decision function — every branch
  // ---------------------------------------------------------------------
  group('decideAccountAction', () {
    AccountSwitchAction decide({
      String? owner,
      String? uid,
      required AuthChangeEvent event,
    }) => decideAccountAction(
      storedOwner: owner,
      incomingUid: uid,
      event: event,
    );

    group('signedIn', () {
      test('owner=null + signin U → adopt (genuine guest data kept)', () {
        expect(
          decide(owner: null, uid: 'U', event: AuthChangeEvent.signedIn),
          AccountSwitchAction.adopt,
        );
      });

      test('owner="" (empty) is treated as never-signed-in → adopt', () {
        expect(
          decide(owner: '', uid: 'U', event: AuthChangeEvent.signedIn),
          AccountSwitchAction.adopt,
        );
      });

      test('owner=U + signin U (same user returning) → keep, no clear', () {
        expect(
          decide(owner: 'U', uid: 'U', event: AuthChangeEvent.signedIn),
          AccountSwitchAction.keep,
        );
      });

      test('owner=V + signin U (V!=U) → clearAndAdopt (account switch)', () {
        expect(
          decide(owner: 'V', uid: 'U', event: AuthChangeEvent.signedIn),
          AccountSwitchAction.clearAndAdopt,
        );
      });

      test('missing/empty uid NEVER clears, even with a stored owner', () {
        expect(
          decide(owner: 'V', uid: null, event: AuthChangeEvent.signedIn),
          AccountSwitchAction.keep,
        );
        expect(
          decide(owner: 'V', uid: '', event: AuthChangeEvent.signedIn),
          AccountSwitchAction.keep,
        );
      });
    });

    group('initialSession', () {
      test('no persisted session (uid null) → keep (fresh guest launch)', () {
        expect(
          decide(
            owner: null,
            uid: null,
            event: AuthChangeEvent.initialSession,
          ),
          AccountSwitchAction.keep,
        );
      });

      test('owner=null + persisted session U → adopt (app-update migration)', () {
        expect(
          decide(owner: null, uid: 'U', event: AuthChangeEvent.initialSession),
          AccountSwitchAction.adopt,
        );
      });

      test('owner=U + initialSession U (same uid) → keep, MUST NOT clear', () {
        expect(
          decide(owner: 'U', uid: 'U', event: AuthChangeEvent.initialSession),
          AccountSwitchAction.keep,
        );
      });

      test(
        'owner=V + initialSession U → clearAndAdopt (interrupted switch '
        'recovery — the only way a different uid session appears at launch)',
        () {
          expect(
            decide(
              owner: 'V',
              uid: 'U',
              event: AuthChangeEvent.initialSession,
            ),
            AccountSwitchAction.clearAndAdopt,
          );
        },
      );
    });

    group('tokenRefreshed / userUpdated — NEVER destructive', () {
      for (final event in [
        AuthChangeEvent.tokenRefreshed,
        AuthChangeEvent.userUpdated,
      ]) {
        test('$event: owner=U + uid U → keep, no clear', () {
          expect(
            decide(owner: 'U', uid: 'U', event: event),
            AccountSwitchAction.keep,
          );
        });

        test('$event: owner=V + uid U MUST NOT clear (keep)', () {
          expect(
            decide(owner: 'V', uid: 'U', event: event),
            AccountSwitchAction.keep,
          );
        });

        test(
          '$event: owner=null + uid U → adopt (non-destructive ownership '
          'stamp; an active session means the current human IS U)',
          () {
            expect(
              decide(owner: null, uid: 'U', event: event),
              AccountSwitchAction.adopt,
            );
          },
        );
      }
    });

    group('signedOut and other events', () {
      test('signOut → keep; owner logic untouched', () {
        expect(
          decide(owner: 'V', uid: null, event: AuthChangeEvent.signedOut),
          AccountSwitchAction.keep,
        );
        expect(
          decide(owner: null, uid: null, event: AuthChangeEvent.signedOut),
          AccountSwitchAction.keep,
        );
      });

      test('passwordRecovery / mfaChallengeVerified → keep, never clear', () {
        for (final event in [
          AuthChangeEvent.passwordRecovery,
          AuthChangeEvent.mfaChallengeVerified,
        ]) {
          expect(
            decide(owner: 'V', uid: 'U', event: event),
            AccountSwitchAction.keep,
          );
          expect(
            decide(owner: null, uid: 'U', event: event),
            AccountSwitchAction.keep,
          );
        }
      });
    });
  });

  // ---------------------------------------------------------------------
  // Owner store — durable uid persistence (SharedPreferences)
  // ---------------------------------------------------------------------
  group('AccountOwnerStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('reads null on a fresh install', () async {
      expect(await AccountOwnerStore().read(), isNull);
    });

    test('write then read round-trips, across instances', () async {
      await AccountOwnerStore().write('uid-1');
      expect(await AccountOwnerStore().read(), 'uid-1');
    });
  });

  // ---------------------------------------------------------------------
  // AccountSwitchGuard — orchestration against a real (in-memory) DB
  // ---------------------------------------------------------------------
  group('AccountSwitchGuard', () {
    late UserDatabase db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = UserDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedUserData(UserDatabase db) async {
      await db.saveProfile(
        const UserProfilesCompanion(
          nickname: Value('Previous User'),
          conditions: Value('["diabetes"]'),
          allergens: Value('["peanut"]'),
          drugClasses: Value('["biguanide"]'),
        ),
      );
      // Dirty supplement (never synced) — would push on next sync.
      await db.addToStack(
        UserStacksLocalCompanion.insert(id: 'supp-1', name: 'Vitamin D'),
      );
      // Medication (PHI, local-only).
      await db.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'med-1',
          name: 'Metformin',
          type: const Value('medication'),
        ),
      );
      // Dirty tombstone — a pending delete that would also push.
      await db.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'tomb-1',
          name: 'Old Supplement',
          deletedAt: Value(DateTime.now()),
        ),
      );
      await db.addFavorite('dsld-1');
      await db.recordScanEvent(dsldId: 'dsld-2', productName: 'Scanned');
      // Product-keyed caches — NOT user data, must survive the clear.
      await db.cacheDetail('dsld-9', '{"detail":true}', null);
      await db.cacheImageUrl('dsld-9', 'https://img.example/x.jpg');
      await db.recordFailedScan('012345678905');
    }

    AccountSwitchGuard guardFor(
      UserDatabase db, {
      Future<void> Function()? clearPerUserPrefs,
    }) => AccountSwitchGuard(
      ownerStore: AccountOwnerStore(),
      db: db,
      clearPerUserPrefs: clearPerUserPrefs,
    );

    test('ADOPT: owner=null + signin U keeps guest data, stamps owner', () async {
      await seedUserData(db);

      final action = await guardFor(db).onAuthEvent(
        event: AuthChangeEvent.signedIn,
        uid: 'U',
      );

      expect(action, AccountSwitchAction.adopt);
      expect(await AccountOwnerStore().read(), 'U');
      // NOTHING cleared — guest data now belongs to U and may sync.
      expect(await db.getProfile(), isNotNull);
      expect((await db.select(db.userStacksLocal).get()).length, 3);
      expect((await db.getFavorites()).length, 1);
    });

    test('KEEP: owner=U + signin U leaves everything untouched', () async {
      await seedUserData(db);
      await AccountOwnerStore().write('U');

      final action = await guardFor(db).onAuthEvent(
        event: AuthChangeEvent.signedIn,
        uid: 'U',
      );

      expect(action, AccountSwitchAction.keep);
      expect(await AccountOwnerStore().read(), 'U');
      expect(await db.getProfile(), isNotNull);
      expect((await db.select(db.userStacksLocal).get()).length, 3);
    });

    test('KEEP: tokenRefreshed with same owner never clears', () async {
      await seedUserData(db);
      await AccountOwnerStore().write('U');

      final action = await guardFor(db).onAuthEvent(
        event: AuthChangeEvent.tokenRefreshed,
        uid: 'U',
      );

      expect(action, AccountSwitchAction.keep);
      expect(await db.getProfile(), isNotNull);
      expect((await db.select(db.userStacksLocal).get()).length, 3);
    });

    test('signOut event does not clear and does not change owner', () async {
      await seedUserData(db);
      await AccountOwnerStore().write('U');

      final action = await guardFor(db).onAuthEvent(
        event: AuthChangeEvent.signedOut,
        uid: null,
      );

      expect(action, AccountSwitchAction.keep);
      expect(await AccountOwnerStore().read(), 'U');
      expect(await db.getProfile(), isNotNull);
      expect((await db.select(db.userStacksLocal).get()).length, 3);
    });

    test(
      'ACCOUNT SWITCH (integration): owner=V + signin U clears every '
      'previous-user row locally and leaves nothing for the sync queue '
      'to push remotely',
      () async {
        await seedUserData(db);
        await AccountOwnerStore().write('V');
        final queue = StackSyncQueue(db);

        // Sanity: before the switch, V has dirty rows that WOULD push,
        // and the sync owner gate would refuse to push them as U.
        expect((await queue.dirtyRows()).isNotEmpty, isTrue);
        expect(ownerAllowsPush(storedOwner: 'V', currentUid: 'U'), isFalse);

        var prefsCleared = false;
        final action = await guardFor(
          db,
          clearPerUserPrefs: () async => prefsCleared = true,
        ).onAuthEvent(event: AuthChangeEvent.signedIn, uid: 'U');

        expect(action, AccountSwitchAction.clearAndAdopt);
        // Zero previous-user rows locally — stack (supplements AND
        // medications AND tombstones), profile, favorites, history.
        expect(await db.select(db.userStacksLocal).get(), isEmpty);
        expect(await db.getProfile(), isNull);
        expect(await db.getFavorites(), isEmpty);
        expect(await db.getRecentScans(), isEmpty);
        // Nothing to push remotely: the dirty/tombstone queue is empty.
        expect(await queue.dirtyRows(), isEmpty);
        expect(await queue.tombstoneRows(), isEmpty);
        // Per-user prefs (recent searches) cleared too.
        expect(prefsCleared, isTrue);
        // Ownership handed to U; U's own writes may sync normally.
        expect(await AccountOwnerStore().read(), 'U');
        expect(ownerAllowsPush(storedOwner: 'U', currentUid: 'U'), isTrue);
        // Product-keyed caches survive — they contain no user data.
        expect(await db.getCachedDetail('dsld-9'), isNotNull);
        expect(await db.getCachedImage('dsld-9'), isNotNull);
        expect(await db.getFailedScans(), isNotEmpty);
      },
    );

    test(
      'clear failure leaves owner=V so the switch retries next sign-in '
      '(owner is stamped LAST — a half-done switch must not look done)',
      () async {
        await seedUserData(db);
        await AccountOwnerStore().write('V');

        await expectLater(
          guardFor(
            db,
            clearPerUserPrefs: () async => throw StateError('prefs boom'),
          ).onAuthEvent(event: AuthChangeEvent.signedIn, uid: 'U'),
          throwsA(isA<StateError>()),
        );

        // Owner unchanged → next sign-in as U re-triggers clearAndAdopt,
        // and the sync owner gate keeps blocking pushes as U meanwhile.
        expect(await AccountOwnerStore().read(), 'V');

        // Recovery: a second successful run completes the switch.
        final retry = await guardFor(db).onAuthEvent(
          event: AuthChangeEvent.signedIn,
          uid: 'U',
        );
        expect(retry, AccountSwitchAction.clearAndAdopt);
        expect(await AccountOwnerStore().read(), 'U');
        expect(await db.select(db.userStacksLocal).get(), isEmpty);
      },
    );
  });
}
