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

  test('probiotic card presents label facts without clinical badges', () {
    final component = _read('lib/core/components/pg_probiotic_section.dart');
    final adapter = _read(
      'lib/features/product_detail/v2/sections/probiotic_section.dart',
    );

    expect(component, isNot(contains('PGProbioticResearchStatus')));
    expect(component, isNot(contains('matched to verified research')));
    expect(adapter, isNot(contains('research_match_status')));
    expect(adapter, isNot(contains('source_urls')));
  });
}
