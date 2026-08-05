// Release gate: CoreDatabase must open the v4 production catalog contract
// without relying on legacy /80 score columns.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/data/database/core_database.dart';

const _v4Fixture = 'test/fixtures/db/core_v4.fixture.db';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CoreDatabase> openCopy(String fixture) async {
    final tmp = await Directory.systemTemp.createTemp('v4-catalog');
    addTearDown(() => tmp.delete(recursive: true));
    final dst = File(p.join(tmp.path, 'core.db'));
    await File(fixture).copy(dst.path);
    final db = CoreDatabase.open(dst.path);
    addTearDown(db.close);
    return db;
  }

  test('opens the v4 catalog and reads canonical score fields', () async {
    final db = await openCopy(_v4Fixture);
    expect(await db.countProducts(), equals(4));

    final elite = await db.findById('175321'); // Creatine, 98.1 Elite
    expect(elite, isNotNull);
    expect(elite!.qualityScoreV4100, closeTo(98.1, 0.6));
    expect(elite.score100Equivalent, closeTo(98.1, 0.6));
    expect(elite.qualityScoreStatus, 'scored');
    expect(elite.qualityTier, 'Elite');
    expect(elite.scoreModelVersion, 'v4');
    // This frozen v2.0 fixture predates the additive v2.2 consumer-semantics
    // fields. The compatibility layer must add them as nullable rather than
    // rejecting or misclassifying the old catalog.
    expect(elite.productSafetyStatus, isNull);
    expect(elite.qualityAssessmentStatus, isNull);
  });

  test('safety-suppressed product is findable but carries no number', () async {
    final db = await openCopy(_v4Fixture);
    final blocked = await db.findById('204468'); // BLOCKED, banned_ingredient
    expect(
      blocked,
      isNotNull,
      reason:
          'a scan/lookup must still resolve a blocked product so the '
          'detail screen can explain why it is blocked',
    );
    expect(blocked!.qualityScoreV4100, isNull);
    expect(blocked.score100Equivalent, isNull);
    expect(blocked.qualityScoreStatus, 'suppressed_safety');
    expect(blocked.qualityScoreSuppressedReason, 'banned_ingredient');
    expect(blocked.verdict, 'BLOCKED');
  });

  test('ranked browse orders by v4 score and suppresses unsafe rows', () async {
    final db = await openCopy(_v4Fixture);
    final ranked = await db.filterProducts(sortBy: 'score', limit: 10);
    final ids = ranked.map((r) => r.dsldId).toList();

    expect(ids.indexOf('175321'), lessThan(ids.indexOf('78355')));

    final blockedIdx = ids.indexOf('204468');
    if (blockedIdx != -1) {
      expect(blockedIdx, greaterThan(ids.indexOf('78355')));
    }
  });

  test(
    'recommendation pool never contains a safety-suppressed product',
    () async {
      final db = await openCopy(_v4Fixture);
      final current = await db.findById('78355'); // a scored product
      expect(current, isNotNull);
      final pool = await db.fetchBetterAlternativesPool(current!, poolSize: 50);
      expect(pool.map((r) => r.dsldId), isNot(contains('204468')));
    },
  );

  test('new independent fields override a contradictory legacy verdict', () {
    const safeNewContract = ProductsCoreData(
      dsldId: 'new-safe',
      productName: 'New Contract Safe',
      qualityScoreV4100: 82,
      qualityScoreStatus: 'scored',
      productSafetyStatus: 'no_known_catalog_concern',
      qualityAssessmentStatus: 'complete',
      verdict: 'BLOCKED',
      exportVersion: 'test',
      exportedAt: '2026-08-05T00:00:00Z',
    );
    expect(catalogProductIsBlocked(safeNewContract), isFalse);
    expect(catalogProductIsNotScored(safeNewContract), isFalse);

    const blockedNewContract = ProductsCoreData(
      dsldId: 'new-blocked',
      productName: 'New Contract Blocked',
      qualityScoreV4100: 82,
      qualityScoreStatus: 'scored',
      productSafetyStatus: 'blocked',
      qualityAssessmentStatus: 'complete',
      verdict: 'SAFE',
      exportVersion: 'test',
      exportedAt: '2026-08-05T00:00:00Z',
    );
    expect(catalogProductIsBlocked(blockedNewContract), isTrue);
  });

  test('consumer score surfaces do not read legacy verdict directly', () {
    const scoreSurfacePaths = [
      'lib/features/product_detail/v2/product_detail_v2_connected.dart',
      'lib/features/product_detail/v2/sections/hero_section.dart',
      'lib/features/product_detail/v2/sections/better_alternatives_section.dart',
      'lib/features/search/v2/search_v2_screen.dart',
      'lib/features/compare/compare_screen.dart',
      'lib/features/home/v2/home_v2_screen.dart',
      'lib/features/stack/v2/stack_v2_screen.dart',
      'lib/features/quick_check/quick_check_logic.dart',
      'lib/features/quick_check/v2/quick_check_v2_screen.dart',
    ];

    for (final path in scoreSurfacePaths) {
      final source = File(path).readAsStringSync();
      final productReads = source.replaceAll(
        RegExp(r'\bthis\s*\.\s*verdict\b'),
        '',
      );
      expect(
        RegExp(r'\.\s*verdict\b').hasMatch(productReads),
        isFalse,
        reason:
            '$path must consume independent catalog semantics; '
            'legacy verdict fallback belongs only in the compatibility adapter',
      );
    }
  });
}
