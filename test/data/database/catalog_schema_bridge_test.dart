import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/catalog_schema_bridge.dart';

Map<String, dynamic> _fixture(String version) {
  return jsonDecode(
        File('test/fixtures/catalog_schema/$version.json').readAsStringSync(),
      )
      as Map<String, dynamic>;
}

void main() {
  for (final testCase in const [
    (version: '2.3.0', confidence: 'moderate', cluster: 'sleep_stack'),
    (version: '2.4.0', confidence: 'high', cluster: 'stress_resilience'),
    (version: '3.0.0-prepared', confidence: 'low', cluster: 'focus_stack'),
  ]) {
    test('reads the ${testCase.version} compatibility fixture', () {
      final fixture = _fixture(testCase.version);
      final core = fixture['core'] as Map<String, dynamic>;
      final blob = fixture['detail_blob'] as Map<String, dynamic>;
      final synergy = blob['synergy_detail'] as Map<String, dynamic>;
      final cluster =
          (synergy['clusters'] as List).single as Map<String, dynamic>;

      expect(catalogQualityScoreConfidence(core), testCase.confidence);
      expect(catalogProductStatusDetail(blob)?['type'], 'discontinued');
      expect(
        catalogHasCanonicalProductStatus(
          coreStatus: core['product_status']?.toString(),
          detailBlob: blob,
        ),
        isTrue,
      );
      expect(catalogSynergyClusterId(cluster), testCase.cluster);
    });
  }

  test('prepared schema 3 fixture contains no deprecated aliases', () {
    final fixture = _fixture('3.0.0-prepared');
    final core = fixture['core'] as Map<String, dynamic>;
    final blob = fixture['detail_blob'] as Map<String, dynamic>;
    final cluster =
        ((blob['synergy_detail'] as Map)['clusters'] as List).single
            as Map<String, dynamic>;

    expect(core, isNot(contains('v4_confidence')));
    expect(blob, isNot(contains('product_status')));
    expect(cluster, isNot(contains('id')));
  });
}
