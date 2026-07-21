import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_mismatch_action.dart';

void main() {
  group('labelMismatchMetadataFrom', () {
    test('builds report metadata from a label_record + dsld/upc', () {
      final fingerprint = 'a' * 64; // sha256 shape the validator requires
      final meta = labelMismatchMetadataFrom(
        {
          'source_record_id': 'SRC-1',
          'catalog_version': 'v2026.07',
          'formula_fingerprint': fingerprint,
        },
        dsldId: '12345',
        upc: '766298114996',
      );
      expect(meta, isNotNull);
      expect(meta!.dsldId, '12345');
      expect(meta.upc, '766298114996');
      expect(meta.sourceRecordId, 'SRC-1');
      expect(meta.catalogSourceVersion, 'v2026.07');
      expect(meta.formulaFingerprint, fingerprint);
    });

    test('returns null (never throws) on malformed provenance', () {
      expect(
        labelMismatchMetadataFrom(
          const {'formula_fingerprint': 'not-a-sha256'},
          dsldId: '12345',
        ),
        isNull,
      );
    });

    test('blank optional provenance is dropped, not fatal', () {
      // Empty-string catalog_version / fingerprint / source_record_id / upc is
      // a common pipeline data-hygiene quirk. With a valid dsldId it must
      // normalize to null (omitted) and still render the action — not throw
      // invalidMetadataValue and silently kill "Doesn't match your bottle?".
      final meta = labelMismatchMetadataFrom(
        const {
          'source_record_id': '',
          'catalog_version': '',
          'formula_fingerprint': '   ',
        },
        dsldId: '12345',
        upc: '',
      );
      expect(meta, isNotNull);
      expect(meta!.dsldId, '12345');
      expect(meta.upc, isNull);
      expect(meta.sourceRecordId, isNull);
      expect(meta.catalogSourceVersion, isNull);
      expect(meta.formulaFingerprint, isNull);
    });

    test('falls back to source_record_id when dsldId is absent', () {
      final meta = labelMismatchMetadataFrom(
        const {'source_record_id': 'SRC-9'},
      );
      expect(meta?.dsldId, 'SRC-9');
    });

    test('returns null when there is no identifier to report against', () {
      expect(labelMismatchMetadataFrom(null), isNull);
      expect(labelMismatchMetadataFrom(const <String, dynamic>{}), isNull);
    });
  });
}
