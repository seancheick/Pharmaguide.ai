import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/gtin.dart';

/// GTIN width equivalence contract (defect B companion, 2026-08-24).
///
/// The catalog stores GTINs VERBATIM in {8,12,13,14} digit widths
/// (`normalize_upc`, build_final_db.py) — no leading-zero canonicalization.
/// The reader therefore owns GS1 zero-padding equivalence: whatever width a
/// scanner emits, every valid padded/stripped representation must resolve.
Future<void> _seed(CoreDatabase db, String dsldId, String upc) async {
  await db
      .into(db.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: dsldId,
          productName: 'Bottle $dsldId',
          exportVersion: 'test',
          exportedAt: '2026-08-24T00:00:00Z',
          upcSku: Value(upc),
          productStatus: const Value('active'),
        ),
      );
}

void main() {
  group('findAllByUpc width equivalence', () {
    test('EAN-8 stored verbatim resolves from an 8-digit scan', () async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);
      await _seed(db, 'ean8', '96385074');

      final result = await db.resolveByUpc('96385074');

      expect(result, isA<UpcUnique>());
      expect((result as UpcUnique).product.dsldId, 'ean8');
    });

    test('EAN-8 stored as its GTIN-14 padded form still resolves', () async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);
      await _seed(db, 'ean8pad', '000096385074');

      // Some sources store the zero-padded form; an 8-digit scan must
      // still find it. (Stored value here is the 12-width padding row.)
      final result = await db.resolveByUpc('96385074');

      expect(result, isA<UpcNotFound>(), reason: '12-pad is NOT equivalent');

      await _seed(db, 'ean8pad14', '00000096385074');
      final result14 = await db.resolveByUpc('96385074');
      expect(result14, isA<UpcUnique>());
      expect((result14 as UpcUnique).product.dsldId, 'ean8pad14');
    });

    test('GTIN-14 stored verbatim resolves from shorter scans', () async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);
      await _seed(db, 'gtin14', '00016000275447');

      final from12 = await db.resolveByUpc('016000275447');
      expect(from12, isA<UpcUnique>());
      expect((from12 as UpcUnique).product.dsldId, 'gtin14');

      final from13 = await db.resolveByUpc('0016000275447');
      expect(from13, isA<UpcUnique>());
      expect((from13 as UpcUnique).product.dsldId, 'gtin14');
    });

    test('a 14-digit scan resolves shorter stored widths', () async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);
      await _seed(db, 'upca', '016000275447');

      final result = await db.resolveByUpc('00016000275447');

      expect(result, isA<UpcUnique>());
      expect((result as UpcUnique).product.dsldId, 'upca');
    });

    test('existing 12/13 equivalence is unchanged', () async {
      final db = CoreDatabase.memory();
      addTearDown(db.close);
      await _seed(db, 'ean13', '0016000275447');

      final result = await db.resolveByUpc('016000275447');

      expect(result, isA<UpcUnique>());
      expect((result as UpcUnique).product.dsldId, 'ean13');
    });

    test(
      'UPC-E scanner identity resolves an expanded UPC-A catalog row',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);
        await _seed(db, 'upce-expanded', '065100004327');

        final result = await db.resolveByGtin(
          GtinIdentity.parse('06543217', detectedSymbology: GtinSymbology.upcE),
        );

        expect(result, isA<UpcUnique>());
        expect((result as UpcUnique).product.dsldId, 'upce-expanded');
      },
    );

    test(
      'padding-equivalent twins surface as ambiguous, never merged',
      () async {
        final db = CoreDatabase.memory();
        addTearDown(db.close);
        await _seed(db, 'twin-12', '016000275447');
        await _seed(db, 'twin-14', '00016000275447');

        final result = await db.resolveByUpc('016000275447');

        expect(result, isA<UpcAmbiguous>());
        final ids = (result as UpcAmbiguous).candidates
            .map((product) => product.dsldId)
            .toSet();
        expect(ids, {'twin-12', 'twin-14'});
      },
    );
  });
}
