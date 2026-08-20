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
}) async {
  await db
      .into(db.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: 'Bottle $dsldId',
          exportVersion: 'test',
          exportedAt: '2026-08-19T00:00:00Z',
          upcSku: const Value(_sharedUpc),
          qualityScoreStatus: Value(qualityScoreStatus),
          verdict: Value(verdict),
          qualityScoreV4100: Value(scoreV4),
          productStatus: const Value('active'),
        ),
      );
}

void main() {
  group('resolveByUpc identity contract', () {
    test('returns not found when no label has the barcode', () async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);

      final result = await db.resolveByUpc(_sharedUpc);

      expect(result, isA<UpcNotFound>());
    });

    test('returns the product when exactly one label matches', () async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);
      await _seed(
        db,
        dsldId: 'only',
        qualityScoreStatus: 'scored',
        verdict: 'SAFE',
        scoreV4: 90,
      );

      final result = await db.resolveByUpc(_sharedUpc);

      expect(result, isA<UpcUnique>());
      expect((result as UpcUnique).product.dsldId, 'only');
    });

    test(
      'retains every candidate and never selects by score or safety',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);
        await _seed(
          db,
          dsldId: 'high-score',
          qualityScoreStatus: 'scored',
          verdict: 'SAFE',
          scoreV4: 95,
        );
        await _seed(
          db,
          dsldId: 'blocked',
          qualityScoreStatus: 'blocked',
          verdict: 'BLOCKED',
          scoreV4: null,
        );

        final result = await db.resolveByUpc(_sharedUpc);

        expect(result, isA<UpcAmbiguous>());
        final ids = (result as UpcAmbiguous).candidates
            .map((product) => product.dsldId)
            .toSet();
        expect(ids, {'blocked', 'high-score'});
      },
    );

    test(
      'normalizes UPC-A and leading-zero EAN-13 without duplicate rows',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);
        await _seed(
          db,
          dsldId: 'only',
          qualityScoreStatus: 'scored',
          verdict: 'SAFE',
          scoreV4: 80,
        );

        final result = await db.resolveByUpc('0012345678905');

        expect(result, isA<UpcUnique>());
        expect((result as UpcUnique).product.dsldId, 'only');
      },
    );
  });
}
