// Tests for the app-side performance/robustness fixes in the database
// layer: open-time index creation, prefix-LIKE search fallback, and
// user-DB cache eviction.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';

Future<Set<String>> _indexNames(
  Future<List<QueryRow>> Function(String sql) runSelect,
) async {
  final rows = await runSelect(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  );
  return rows.map((r) => r.read<String>('name')).toSet();
}

void main() {
  group('CoreDatabase app-side indexes', () {
    late CoreDatabase db;

    setUp(() {
      db = CoreDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('creates idx_core_upc_normalized and idx_core_cat_score', () async {
      final names = await _indexNames((sql) => db.customSelect(sql).get());
      expect(names, contains('idx_core_upc_normalized'));
      expect(names, contains('idx_core_cat_score'));
    });

    test('findByUpc query plan uses the normalized expression index', () async {
      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM products_core '
            'WHERE ${CoreDatabase.upcNormalizeSql} = ? LIMIT 1',
            variables: [Variable.withString('050428381397')],
          )
          .get();
      final detail = plan.map((r) => r.read<String>('detail')).join('\n');
      expect(detail, contains('idx_core_upc_normalized'));
      expect(detail, isNot(contains('SCAN products_core')));
    });

    test(
      'findByUpc matches stored UPC with spaces against scanned digits',
      () async {
        await db.customStatement(
          "INSERT INTO products_core "
          "(dsld_id, product_name, upc_sku, export_version, exported_at) "
          "VALUES ('d1', 'Test Product', '0 50428 38139 7', '2.0.0', '2026-01-01')",
        );
        final hit = await db.findByUpc('050428381397');
        expect(hit?.dsldId, 'd1');
      },
    );
  });

  group('CoreDatabase LIKE fallback', () {
    late CoreDatabase db;

    setUp(() async {
      db = CoreDatabase.memory();
      await db.customStatement(
        "INSERT INTO products_core "
        "(dsld_id, product_name, brand_name, export_version, exported_at) "
        "VALUES ('d1', 'Magnesium Glycinate', 'Thorne', '2.0.0', '2026-01-01')",
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('prefix LIKE fallback fires when FTS table is missing', () async {
      // Memory DB has no products_fts table, so the FTS path throws and
      // the fallback runs.
      final byName = await db.searchProducts('Magnesium');
      expect(byName, hasLength(1));
      final byBrand = await db.searchProducts('Thorne');
      expect(byBrand, hasLength(1));
      // Prefix-only: a mid-string fragment no longer matches.
      final midString = await db.searchProducts('Glycinate');
      expect(midString, isEmpty);
    });

    test('fallback degrades to name/brand-only when ingredients_text is '
        'missing', () async {
      // Simulate the compat-column failure case by dropping the column
      // that _ensureCompatColumns added.
      await db.customStatement(
        'ALTER TABLE products_core DROP COLUMN ingredients_text',
      );
      final results = await db.searchProducts('Magnesium');
      expect(results, hasLength(1));
    });
  });

  group('InteractionDatabase app-side indexes', () {
    test('creates lower() expression indexes at open', () async {
      final db = InteractionDatabase.memory();
      addTearDown(db.close);
      // Force open.
      await db.customStatement('SELECT 1');
      final names = await _indexNames((sql) => db.customSelect(sql).get());
      expect(names, contains('idx_int_a1_canon_lower'));
      expect(names, contains('idx_int_a2_canon_lower'));
      expect(names, contains('idx_rp_canon_a_lower'));
      expect(names, contains('idx_rp_canon_b_lower'));
    });
  });

  group('UserDatabase beforeOpen', () {
    late UserDatabase db;

    setUp(() {
      db = UserDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('creates hot-path indexes', () async {
      final names = await _indexNames((sql) => db.customSelect(sql).get());
      expect(names, contains('idx_user_stack_active'));
      expect(names, contains('idx_user_stack_dsld'));
      expect(names, contains('idx_user_scan_dsld'));
      expect(names, contains('idx_user_fav_added'));
    });
  });

  group('UserDatabase cache eviction', () {
    late UserDatabase db;

    setUp(() {
      db = UserDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> seedDetail(String id, DateTime cachedAt) {
      return db
          .into(db.detailCache)
          .insert(
            DetailCacheCompanion(
              dsldId: Value(id),
              blobJson: const Value('{}'),
              cachedAt: Value(cachedAt),
            ),
          );
    }

    Future<void> seedImage(String id, String url, DateTime cachedAt) {
      return db
          .into(db.productImageCache)
          .insert(
            ProductImageCacheCompanion(
              dsldId: Value(id),
              imageUrl: Value(url),
              cachedAt: Value(cachedAt),
            ),
          );
    }

    test(
      'purgeExpiredCaches evicts stale detail rows, keeps fresh ones',
      () async {
        final now = DateTime.now();
        await seedDetail('fresh', now);
        await seedDetail('stale', now.subtract(const Duration(hours: 25)));

        await db.purgeExpiredCaches();

        expect(await db.getCachedDetail('fresh'), isNotNull);
        expect(await db.getCachedDetail('stale'), isNull);
      },
    );

    test(
      'purgeExpiredCaches applies image TTLs: 30d positive, 7d negative',
      () async {
        final now = DateTime.now();
        await seedImage(
          'pos_fresh',
          'https://x/img.jpg',
          now.subtract(const Duration(days: 29)),
        );
        await seedImage(
          'pos_stale',
          'https://x/img.jpg',
          now.subtract(const Duration(days: 31)),
        );
        await seedImage(
          'neg_fresh',
          'no_image',
          now.subtract(const Duration(days: 6)),
        );
        await seedImage(
          'neg_stale',
          'no_image',
          now.subtract(const Duration(days: 8)),
        );

        await db.purgeExpiredCaches();

        expect(await db.getCachedImage('pos_fresh'), isNotNull);
        expect(await db.getCachedImage('pos_stale'), isNull);
        expect(await db.getCachedImage('neg_fresh'), isNotNull);
        expect(await db.getCachedImage('neg_stale'), isNull);
      },
    );

    test('purgeExpiredCaches drops failed scans older than 90 days', () async {
      await db.recordFailedScan('111111111111');
      // Backdate one row past the retention window.
      await db.customStatement(
        "INSERT INTO user_failed_scans (upc, attempt_count, first_seen, last_seen) "
        "VALUES ('222222222222', 1, ?, ?)",
        [
          DateTime.now()
                  .toUtc()
                  .subtract(const Duration(days: 91))
                  .millisecondsSinceEpoch ~/
              1000,
          DateTime.now()
                  .toUtc()
                  .subtract(const Duration(days: 91))
                  .millisecondsSinceEpoch ~/
              1000,
        ],
      );

      await db.purgeExpiredCaches();

      final remaining = await db.getFailedScans();
      expect(remaining.map((r) => r.upc), ['111111111111']);
    });

    test('clearDetailCache removes all detail rows', () async {
      final now = DateTime.now();
      await seedDetail('a', now);
      await seedDetail('b', now);

      await db.clearDetailCache();

      expect(await db.getCachedDetail('a'), isNull);
      expect(await db.getCachedDetail('b'), isNull);
    });
  });
}
