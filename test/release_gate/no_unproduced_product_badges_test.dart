import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test(
    'product detail has no heavy-metal UI without an authoritative producer',
    () {
      final connected = _read(
        'lib/features/product_detail/v2/product_detail_v2_connected.dart',
      );
      final gallery = _read('lib/dev/v2_gallery.dart');

      expect(connected, isNot(contains('heavy_metal_detail')));
      expect(connected, isNot(contains('buildHeavyMetalSection')));
      expect(gallery, isNot(contains('PGHeavyMetalWarning')));
    },
  );

  test('catalog detail has no formula-history UI without a producer', () {
    final labelMatch = _read(
      'lib/features/product_detail/v2/sections/label_match_section.dart',
    );

    expect(labelMatch, isNot(contains('FormulaHistoryModel')));
    expect(labelMatch, isNot(contains('View formula history')));
    expect(labelMatch, isNot(contains('No source-linked formula history')));
  });

  // The probiotic research badge is NOT in this file's category. Its fields do
  // have an authoritative producer -- `enrich_supplements_v3` derives
  // research_match_status / evidence_scope / review_status / source_urls
  // specifically so the card can qualify a strain listing. Hiding the
  // qualification leaves the strain listed unannotated, which claims more than
  // showing it does.
  test('probiotic card still qualifies strains it lists', () {
    final adapter = _read(
      'lib/features/product_detail/v2/sections/probiotic_section.dart',
    );

    expect(adapter, contains('research_match_status'));
    expect(adapter, contains('source_urls'));
    // Unreviewed and rejected matches must not reach an affirmative badge.
    expect(adapter, isNot(contains("'pending_review' => PGProbiotic")));
    expect(adapter, isNot(contains("'rejected' => PGProbiotic")));
  });
}
