import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';

void main() {
  group('CoreDatabase.searchProducts fallback', () {
    late CoreDatabase db;

    setUp(() {
      db = CoreDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'matches multi-token queries across product and brand columns',
      () async {
        await _seedProduct(
          db,
          dsldId: 'A',
          productName: 'Vitamin A',
          brandName: 'Thorne Research',
          score: 70,
        );
        await _seedProduct(
          db,
          dsldId: 'B',
          productName: 'Vitamin C',
          brandName: 'Thorne Research',
          score: 99,
        );

        final results = await db.searchProducts('thorne vitamin a');

        expect(results.map((product) => product.dsldId), ['A']);
      },
    );

    test('treats LIKE wildcards as literal search text', () async {
      await _seedProduct(
        db,
        dsldId: 'A',
        productName: 'Plain Magnesium',
        brandName: 'Brand A',
        score: 99,
      );
      await _seedProduct(
        db,
        dsldId: 'B',
        productName: 'Magnesium 100%',
        brandName: 'Brand B',
        score: 70,
      );

      final percentResults = await db.searchProducts('100%');
      final underscoreResults = await db.searchProducts('_');

      expect(percentResults.map((product) => product.dsldId), ['B']);
      expect(underscoreResults, isEmpty);
    });
  });
}

Future<void> _seedProduct(
  CoreDatabase db, {
  required String dsldId,
  required String productName,
  required String brandName,
  required double score,
}) async {
  await db
      .into(db.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: productName,
          brandName: Value(brandName),
          scoreQuality80: Value(score),
          exportVersion: 'test',
          exportedAt: '2026-05-21T00:00:00Z',
        ),
      );
}
