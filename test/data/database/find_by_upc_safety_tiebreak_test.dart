// FIX 1 (P1) — findByUpc tie-break must be SAFETY-FIRST.
//
// When two catalog rows share a UPC (private-label duplicates), a
// suppressed/blocked twin (quality_score_status != 'scored', or verdict
// BLOCKED/UNSAFE) must WIN the tie so the detail screen can surface the
// block. Under-warning is the costlier error and we can't know which
// physical bottle the user scanned. The previous ORDER BY put active +
// highest-score first, which always masked a blocked twin (NULL score → 0).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';

const _sharedUpc = '012345678905';

Future<void> _seed(
  CoreDatabase db, {
  required String dsldId,
  required String? qualityScoreStatus,
  required String? verdict,
  required double? scoreV4,
  required String? productStatus,
}) async {
  await db
      .into(db.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: 'Twin $dsldId',
          exportVersion: 'test',
          exportedAt: '2026-07-05T00:00:00Z',
          upcSku: const Value(_sharedUpc),
          qualityScoreStatus: Value(qualityScoreStatus),
          verdict: Value(verdict),
          qualityScoreV4100: Value(scoreV4),
          productStatus: Value(productStatus),
        ),
      );
}

void main() {
  group('findByUpc safety-first tie-break', () {
    test(
      'suppressed twin (status != scored) WINS over a scored active twin',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);

        // Scored, active, high score — the row the OLD ordering surfaced.
        await _seed(
          db,
          dsldId: 'scored-twin',
          qualityScoreStatus: 'scored',
          verdict: 'SAFE',
          scoreV4: 90.0,
          productStatus: 'active',
        );
        // Blocked twin: suppressed (status != scored), NULL score, still
        // active. Must win the tie so the block can be shown.
        await _seed(
          db,
          dsldId: 'blocked-twin',
          qualityScoreStatus: 'blocked',
          verdict: 'BLOCKED',
          scoreV4: null,
          productStatus: 'active',
        );

        final row = await db.findByUpc(_sharedUpc);
        expect(row, isNotNull);
        expect(row!.dsldId, 'blocked-twin');
      },
    );

    test(
      'verdict UNSAFE wins even if status somehow reads scored (defensive OR)',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);

        await _seed(
          db,
          dsldId: 'safe-twin',
          qualityScoreStatus: 'scored',
          verdict: 'SAFE',
          scoreV4: 88.0,
          productStatus: 'active',
        );
        await _seed(
          db,
          dsldId: 'unsafe-twin',
          qualityScoreStatus: 'scored',
          verdict: 'UNSAFE',
          scoreV4: 70.0,
          productStatus: 'active',
        );

        final row = await db.findByUpc(_sharedUpc);
        expect(row, isNotNull);
        expect(row!.dsldId, 'unsafe-twin');
      },
    );

    test(
      'no-regression: among two scored/safe twins, highest score still wins',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);

        await _seed(
          db,
          dsldId: 'low-score',
          qualityScoreStatus: 'scored',
          verdict: 'SAFE',
          scoreV4: 60.0,
          productStatus: 'active',
        );
        await _seed(
          db,
          dsldId: 'high-score',
          qualityScoreStatus: 'scored',
          verdict: 'SAFE',
          scoreV4: 95.0,
          productStatus: 'active',
        );

        final row = await db.findByUpc(_sharedUpc);
        expect(row, isNotNull);
        expect(row!.dsldId, 'high-score');
      },
    );
  });
}
