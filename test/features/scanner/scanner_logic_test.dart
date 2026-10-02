// Tests for the scanner screen's pure verdict→color policy.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';

ProductsCoreData _product({String dsldId = '100', String? safetyStatus}) =>
    ProductsCoreData(
      dsldId: dsldId,
      productName: 'Test product',
      productSafetyStatus: safetyStatus,
      exportVersion: 'test',
      exportedAt: '2026-10-01T00:00:00Z',
    );

SafetyAlert _alert({
  required String disposition,
  List<String> dsldIds = const ['100'],
}) => SafetyAlert.fromJson({
  'alert_id': 'SA_2026_0001',
  'revision': 1,
  'event_type': 'product_recall',
  'source_url': 'https://www.fda.gov/example',
  'headline': 'Recall',
  'body': 'Recalled.',
  'action': 'Stop taking this product.',
  'consumer_disposition': disposition,
  'resolved_dsld_ids': dsldIds,
  'scope': {'ingredient_canonical_ids': <String>[], 'dsld_ids': <String>[]},
});

void main() {
  group('scanResultIsSafetyCritical', () {
    test('blocked and unsafe catalog products are critical', () {
      expect(
        scanResultIsSafetyCritical(_product(safetyStatus: 'blocked')),
        isTrue,
      );
      expect(
        scanResultIsSafetyCritical(_product(safetyStatus: 'unsafe')),
        isTrue,
      );
    });

    test('caution, clean and not-assessed products are not', () {
      for (final status in [
        'caution',
        'no_known_catalog_concern',
        'not_assessed',
      ]) {
        expect(
          scanResultIsSafetyCritical(_product(safetyStatus: status)),
          isFalse,
          reason: status,
        );
      }
    });

    test('a blocking live recall makes a clean product critical', () {
      final product = _product(safetyStatus: 'no_known_catalog_concern');
      expect(
        scanResultIsSafetyCritical(
          product,
          alerts: [_alert(disposition: 'block')],
        ),
        isTrue,
      );
      expect(
        scanResultIsSafetyCritical(
          product,
          alerts: [
            _alert(disposition: 'block', dsldIds: ['999']),
          ],
        ),
        isFalse,
      );
      expect(
        scanResultIsSafetyCritical(
          product,
          alerts: [_alert(disposition: 'review')],
        ),
        isFalse,
      );
    });
  });

  group('scanRevealKind', () {
    test('a clean catalog product confirms as found (dsld 299750)', () {
      // Liposomal Vitamin C, SAFE 91/100, flashed amber: the scan flow passed
      // its safety status id to a switch that only knew verdict strings.
      expect(
        scanRevealKind(CatalogProductSafetyStatus.noKnownCatalogConcern),
        PGVerdictKind.found,
      );
    });

    test('every other safety status asks for attention', () {
      for (final status in CatalogProductSafetyStatus.values) {
        if (status == CatalogProductSafetyStatus.noKnownCatalogConcern) {
          continue;
        }
        expect(
          scanRevealKind(status),
          PGVerdictKind.attention,
          reason: '$status',
        );
      }
    });
  });
}
