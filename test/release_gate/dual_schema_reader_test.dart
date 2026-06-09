// Release gate: the migrated [CoreDatabase] must open BOTH catalog schemas
// without a "no such column" crash:
//
//   * legacy v3 bundle  — 92 cols, has `score_quality_80`, no v4 columns
//   * v4 build          — 102 cols (export schema 2.0.0): dropped the /80
//                         columns, added the v4 /100 contract
//
// This is the dual-reader safety net for the v4 cutover window (Codex's
// release-ordering concern): the app ships the v4 reader FIRST and keeps the
// v3 bundle until the v4 catalog is OTA'd. A v4-only reader crashes on the v3
// bundle (missing `quality_score_v4_100`); a v3-only reader crashes on the v4
// build (missing `score_quality_80`). The compat backfill in
// `CoreDatabase.beforeOpen` adds whichever side is missing.
//
// Fixtures are small real-schema catalogs built from a real v4 build and the
// shipped v3 bundle by test/fixtures/db/build_dual_schema_fixtures.py.
//
// Run with: flutter test test/release_gate/dual_schema_reader_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';

const _v3Fixture = 'test/fixtures/db/core_v3.fixture.db';
const _v4Fixture = 'test/fixtures/db/core_v4.fixture.db';

double? _effective(ProductsCoreData r) =>
    r.qualityScoreV4100 ?? r.score100Equivalent ?? r.scoreQuality80;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `beforeOpen` ALTERs the file (adds compat columns), so always open a
  // writable temp COPY — never the committed fixture.
  Future<CoreDatabase> openCopy(String fixture) async {
    final tmp = await Directory.systemTemp.createTemp('dual-schema');
    addTearDown(() => tmp.delete(recursive: true));
    final dst = File(p.join(tmp.path, 'core.db'));
    await File(fixture).copy(dst.path);
    final db = CoreDatabase.open(dst.path);
    addTearDown(db.close);
    return db;
  }

  group('dual-schema reader: legacy v3 bundle (has score_quality_80)', () {
    test('opens, runs typed queries that touch v4 columns, ranks by score',
        () async {
      final db = await openCopy(_v3Fixture);
      expect(await db.countProducts(), greaterThan(0));

      // filterProducts is a typed query — its generated SQL now references
      // the v4 columns. Against a v3 bundle those are absent and would throw
      // "no such column" without the beforeOpen compat backfill.
      final ranked = await db.filterProducts(sortBy: 'score', limit: 10);
      expect(ranked, isNotEmpty);

      // On a v3 bundle the effective score falls back to the /100 mirror.
      final scores = ranked.map(_effective).whereType<double>().toList();
      expect(
        scores,
        isNotEmpty,
        reason: 'v3 rows must still yield a numeric score to rank on',
      );
      for (var i = 1; i < scores.length; i++) {
        expect(
          scores[i - 1],
          greaterThanOrEqualTo(scores[i]),
          reason: 'ranked list must be descending by effective score',
        );
      }
    });
  });

  group('dual-schema reader: v4 build (dropped /80, added v4 /100)', () {
    test('opens + typed queries work despite the dropped score_quality_80',
        () async {
      final db = await openCopy(_v4Fixture);
      expect(await db.countProducts(), equals(4));

      final elite = await db.findById('175321'); // Creatine, 98.1 Elite
      expect(elite, isNotNull);
      expect(elite!.qualityScoreV4100, closeTo(98.1, 0.6));
      expect(elite.qualityScoreStatus, 'scored');
      expect(elite.qualityTier, 'Elite');
      expect(elite.scoreModelVersion, 'v4');
      // The dropped /80 column reads back NULL (compat-backfilled), no crash.
      expect(elite.scoreQuality80, isNull);
    });

    test('safety-suppressed product is findable but carries no number',
        () async {
      final db = await openCopy(_v4Fixture);
      final blocked = await db.findById('204468'); // BLOCKED, banned_ingredient
      expect(
        blocked,
        isNotNull,
        reason: 'a scan/lookup must still RESOLVE a blocked product so the '
            'detail screen can explain why it is blocked',
      );
      expect(blocked!.qualityScoreV4100, isNull);
      expect(
        blocked.score100Equivalent,
        isNull,
        reason: 'the /100 mirror must also be NULL for a suppressed row',
      );
      expect(blocked.qualityScoreStatus, 'suppressed_safety');
      expect(blocked.qualityScoreSuppressedReason, 'banned_ingredient');
      expect(blocked.verdict, 'BLOCKED');
    });

    test('ranked browse orders by v4 score; a suppressed row never outranks '
        'a real score', () async {
      final db = await openCopy(_v4Fixture);
      final ranked = await db.filterProducts(sortBy: 'score', limit: 10);
      final ids = ranked.map((r) => r.dsldId).toList();

      // Elite 98.1 outranks Poor 26.6.
      expect(ids.indexOf('175321'), lessThan(ids.indexOf('78355')));

      // The suppressed (NULL-score) row must sort LAST, not above a scored one.
      final blockedIdx = ids.indexOf('204468');
      if (blockedIdx != -1) {
        expect(
          blockedIdx,
          greaterThan(ids.indexOf('78355')),
          reason: 'a suppressed/NULL-score row must sort last',
        );
      }
    });

    test('recommendation pool never contains a safety-suppressed product',
        () async {
      final db = await openCopy(_v4Fixture);
      final current = await db.findById('78355'); // a scored product
      expect(current, isNotNull);
      final pool = await db.fetchBetterAlternativesPool(current!, poolSize: 50);
      expect(
        pool.map((r) => r.dsldId),
        isNot(contains('204468')),
        reason: 'fetchBetterAlternativesPool must exclude suppressed rows',
      );
    });
  });
}
