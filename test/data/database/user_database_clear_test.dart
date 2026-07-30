// clearAllLocalUserData — the destructive op behind the account-switch
// guard. Scope contract:
//
//   WIPED (user-owned medical/behavioral data):
//     user_profile        — conditions, allergens, goals, drug classes, flags
//     user_stacks_local   — supplements, medications (PHI), tombstones,
//                           and with them ALL sync dirty/queue state
//     user_favorites      — user-chosen bookmarks
//     user_scan_history   — user scan trail
//
//   PRESERVED (product-keyed, no user linkage):
//     product_detail_cache, product_image_cache — catalog mirrors
//     user_failed_scans   — no-PII device telemetry (see privacy contract
//                           in failed_scans_table.dart)

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';

void main() {
  late UserDatabase db;

  setUp(() {
    db = UserDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'clearAllLocalUserData wipes user data, preserves product caches',
    () async {
      // Seed every table.
      await db.saveProfile(
        const UserProfilesCompanion(
          nickname: Value('V'),
          conditions: Value('["hypertension"]'),
          allergens: Value('["shellfish"]'),
        ),
      );
      await db.addToStack(
        UserStacksLocalCompanion.insert(id: 's1', name: 'Omega-3'),
      );
      await db.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'm1',
          name: 'Lisinopril',
          type: const Value('medication'),
        ),
      );
      await db.addToStack(
        UserStacksLocalCompanion.insert(
          id: 't1',
          name: 'Removed thing',
          deletedAt: Value(DateTime.now()),
        ),
      );
      await db.addFavorite('fav-1');
      await db.recordScanEvent(dsldId: 'scan-1');
      await db.cacheDetail('prod-1', '{"blob":1}', 'abc');
      await db.cacheImageUrl('prod-1', 'https://img/x.jpg');
      await db.recordFailedScan('012345678905');
      await HealthEventRepository(db).append(
        HealthEventDraft(
          eventType: HealthEventTypes.noteAdded,
          source: HealthEventSource.user,
          subjectType: 'note',
          title: 'Private health note',
          effectiveAt: DateTime.now(),
        ),
      );

      await db.clearAllLocalUserData();

      // User data gone — including medications and tombstones.
      expect(await db.getProfile(), isNull);
      expect(await db.select(db.userStacksLocal).get(), isEmpty);
      expect(await db.getFavorites(), isEmpty);
      expect(await db.getRecentScans(), isEmpty);
      expect(await db.select(db.healthHistoryEvents).get(), isEmpty);

      // Product caches + no-PII telemetry intact.
      expect(await db.getCachedDetail('prod-1'), isNotNull);
      expect(await db.getCachedImage('prod-1'), isNotNull);
      expect(await db.getFailedScans(), isNotEmpty);
    },
  );

  test('clearAllLocalUserData on an empty database is a no-op', () async {
    await db.clearAllLocalUserData();
    expect(await db.getProfile(), isNull);
    expect(await db.select(db.userStacksLocal).get(), isEmpty);
  });
}
