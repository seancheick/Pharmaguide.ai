// FIX 1 (P0) regression lock — Home "Recent scans" must never fabricate a
// score for BLOCKED / UNSAFE / NOT_SCORED products.
//
// The old code did `score: (product.qualityScoreV4100 ?? 0).round()`, which
// coerced the pipeline's deliberate NULL (quality_score_status != 'scored')
// into a fabricated "0/100 Poor" tier line. These tests lock:
//   * recentScanFromProduct — the record carries the nullable score +
//     verdict + mappedCoverage through untouched (no `?? 0`, ever).
//   * recentScanScoreDisplayFor — the pure render decision: unsafe/not-scored
//     verdicts and null scores render a verdict label; mapped_coverage < 0.3
//     renders a neutral "Limited data" state (never a tier color).
//   * recentScanStatusLabel — label fallback never implies safety for an
//     inconsistent row (e.g. SAFE verdict with a missing score).
//   * End-to-end: a seeded BLOCKED scan renders "Blocked" on the carousel
//     card — not "0/100" and not "Poor".

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';

ProductsCoreData _row({
  double? score,
  String? verdict,
  double? mappedCoverage,
}) {
  return ProductsCoreData(
    dsldId: 'TEST-1',
    productName: 'Test Supplement',
    qualityScoreV4100: score,
    verdict: verdict,
    mappedCoverage: mappedCoverage,
    exportVersion: 'test',
    exportedAt: '2026-07-05T00:00:00Z',
  );
}

void main() {
  group('recentScanFromProduct — record building', () {
    test('BLOCKED product keeps score null — never coerced to 0', () {
      final rec = recentScanFromProduct(
        _row(score: null, verdict: 'BLOCKED'),
        time: 'now',
      );
      expect(rec.score, isNull);
      expect(rec.verdict, 'BLOCKED');
    });

    test('scored product carries score, verdict and coverage through', () {
      final rec = recentScanFromProduct(
        _row(score: 82.4, verdict: 'SAFE', mappedCoverage: 0.9),
        time: '2h ago',
      );
      expect(rec.score, 82.4);
      expect(rec.verdict, 'SAFE');
      expect(rec.mappedCoverage, 0.9);
      expect(rec.time, '2h ago');
    });

    test('null coverage stays null (unknown, not trusted)', () {
      final rec = recentScanFromProduct(_row(score: 70), time: 'now');
      expect(rec.mappedCoverage, isNull);
    });
  });

  group('recentScanScoreDisplayFor — render decision', () {
    test('scored product with trustworthy coverage renders the tier score', () {
      expect(
        recentScanScoreDisplayFor(
          score: 82,
          verdict: 'SAFE',
          mappedCoverage: 0.9,
        ),
        RecentScanScoreDisplay.tierScore,
      );
    });

    test('BLOCKED with null score renders the verdict label', () {
      expect(
        recentScanScoreDisplayFor(
          score: null,
          verdict: 'BLOCKED',
          mappedCoverage: 0.9,
        ),
        RecentScanScoreDisplay.verdictLabel,
      );
    });

    test('UNSAFE verdict suppresses a score even if one leaked through', () {
      expect(
        recentScanScoreDisplayFor(
          score: 60,
          verdict: 'UNSAFE',
          mappedCoverage: 0.9,
        ),
        RecentScanScoreDisplay.verdictLabel,
      );
    });

    test('NOT_SCORED verdict renders the verdict label', () {
      expect(
        recentScanScoreDisplayFor(
          score: null,
          verdict: 'NOT_SCORED',
          mappedCoverage: 0.9,
        ),
        RecentScanScoreDisplay.verdictLabel,
      );
    });

    test('null score with no verdict renders the (not scored) label — '
        'never a fabricated 0', () {
      expect(
        recentScanScoreDisplayFor(
          score: null,
          verdict: null,
          mappedCoverage: 0.9,
        ),
        RecentScanScoreDisplay.verdictLabel,
      );
    });

    test('verdict matching is case/whitespace-insensitive', () {
      expect(
        recentScanScoreDisplayFor(
          score: null,
          verdict: ' blocked ',
          mappedCoverage: 0.9,
        ),
        RecentScanScoreDisplay.verdictLabel,
      );
    });

    test('scored but mapped_coverage < 0.3 renders the neutral limited-data '
        'state — never a tier color', () {
      expect(
        recentScanScoreDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.2,
        ),
        RecentScanScoreDisplay.limitedData,
      );
    });

    test('scored with null coverage is treated as low coverage', () {
      expect(
        recentScanScoreDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: null,
        ),
        RecentScanScoreDisplay.limitedData,
      );
    });

    test('coverage exactly at the 0.3 floor is trusted (floor is `< 0.3`)', () {
      expect(
        recentScanScoreDisplayFor(
          score: 85,
          verdict: 'SAFE',
          mappedCoverage: 0.3,
        ),
        RecentScanScoreDisplay.tierScore,
      );
    });

    test('unsafe verdict beats low coverage (block indicator wins)', () {
      expect(
        recentScanScoreDisplayFor(
          score: null,
          verdict: 'BLOCKED',
          mappedCoverage: 0.1,
        ),
        RecentScanScoreDisplay.verdictLabel,
      );
    });
  });

  group('recentScanStatusLabel', () {
    test('BLOCKED renders "Blocked"', () {
      expect(recentScanStatusLabel('BLOCKED'), 'Blocked');
    });

    test('UNSAFE renders "Unsafe"', () {
      expect(recentScanStatusLabel('UNSAFE'), 'Unsafe');
    });

    test('NOT_SCORED renders "Not scored"', () {
      expect(recentScanStatusLabel('NOT_SCORED'), 'Not scored');
    });

    test('null verdict falls back to "Not scored"', () {
      expect(recentScanStatusLabel(null), 'Not scored');
    });

    test('inconsistent positive verdict without a score never implies '
        'safety — falls back to "Not scored"', () {
      expect(recentScanStatusLabel('SAFE'), 'Not scored');
    });
  });

  group('Recent-scans carousel end-to-end (seeded DB)', () {
    Future<(CoreDatabase, UserDatabase)> makeDbs(WidgetTester tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await coreDb.close();
        await userDb.close();
      });
      return (coreDb, userDb);
    }

    Future<void> seedScan(
      CoreDatabase coreDb,
      UserDatabase userDb, {
      double? score,
      String? verdict,
      double? mappedCoverage,
    }) async {
      await coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: 'recent-1',
              productName: 'Recent Scan Product',
              brandName: const drift.Value('Good Brand'),
              qualityScoreV4100: drift.Value(score),
              verdict: drift.Value(verdict),
              mappedCoverage: drift.Value(mappedCoverage),
              exportVersion: 'test',
              exportedAt: '2026-07-05T00:00:00Z',
            ),
          );
      await userDb.recordScanEvent(
        dsldId: 'recent-1',
        productName: 'Recent Scan Product',
      );
    }

    Future<void> pumpHome(
      WidgetTester tester,
      CoreDatabase coreDb,
      UserDatabase userDb,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coreDatabaseProvider.overrideWithValue(coreDb),
            userDatabaseProvider.overrideWithValue(userDb),
          ],
          child: const MaterialApp(home: HomeV2Screen(showNavBar: false)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('BLOCKED scan renders "Blocked" — never "0/100" / "Poor"', (
      tester,
    ) async {
      final (coreDb, userDb) = await makeDbs(tester);
      await seedScan(coreDb, userDb, score: null, verdict: 'BLOCKED');
      await pumpHome(tester, coreDb, userDb);

      expect(find.text('Recent Scan Product'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.textContaining('/100'), findsNothing);
      expect(find.text('Poor'), findsNothing);
    });

    testWidgets('NOT_SCORED scan renders "Not scored" — never "0/100"', (
      tester,
    ) async {
      final (coreDb, userDb) = await makeDbs(tester);
      await seedScan(coreDb, userDb, score: null, verdict: 'NOT_SCORED');
      await pumpHome(tester, coreDb, userDb);

      expect(find.text('Not scored'), findsOneWidget);
      expect(find.textContaining('/100'), findsNothing);
    });

    testWidgets('scored scan with good coverage renders the tier line', (
      tester,
    ) async {
      final (coreDb, userDb) = await makeDbs(tester);
      await seedScan(
        coreDb,
        userDb,
        score: 82,
        verdict: 'SAFE',
        mappedCoverage: 0.9,
      );
      await pumpHome(tester, coreDb, userDb);

      expect(find.text('82/100'), findsOneWidget);
    });

    testWidgets('low-coverage scan renders "Limited data" — no tier score', (
      tester,
    ) async {
      final (coreDb, userDb) = await makeDbs(tester);
      await seedScan(
        coreDb,
        userDb,
        score: 82,
        verdict: 'SAFE',
        mappedCoverage: 0.1,
      );
      await pumpHome(tester, coreDb, userDb);

      expect(find.text('Limited data'), findsOneWidget);
      expect(find.textContaining('/100'), findsNothing);
    });
  });
}
