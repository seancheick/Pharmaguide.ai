// Release gate: bundled reference data matches its recorded hashes.
//
// The catalog DB and interaction DB already have SHA-256 gates here. Reference
// data had none, so the app repo could not detect that a bundled clinical
// artifact had been edited — parity was enforced only in the pipeline, by a
// script that overwrote the app's copy and then compared it to what it had just
// written. That comparison always agreed.
//
// reference_data_manifest.json is written by
// dsld_clean/scripts/sync_flutter_reference_data.py. A hand-edit to any listed
// asset fails this gate until the pipeline regenerates the manifest, which
// makes the change deliberate rather than silent.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> manifest;

  setUpAll(() {
    final file = File('assets/reference_data/reference_data_manifest.json');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'the reference-data manifest is missing — run '
          'sync_flutter_reference_data.py from the pipeline repo',
    );
    manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('every manifested artifact matches its recorded SHA-256', () {
    final artifacts = manifest['artifacts'] as Map<String, dynamic>;
    expect(artifacts, isNotEmpty);

    for (final entry in artifacts.entries) {
      final file = File(entry.key);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} is listed in the manifest but not bundled',
      );
      final actual = sha256.convert(file.readAsBytesSync()).toString();
      expect(
        actual,
        entry.value,
        reason:
            '${entry.key} does not match its recorded hash. If this change is '
            'intended, make it in dsld_clean/scripts/data and re-run the sync '
            'so the manifest is regenerated.',
      );
    }
  });

  test('the timing rules artifact is covered', () {
    final artifacts = manifest['artifacts'] as Map<String, dynamic>;
    expect(
      artifacts.keys,
      contains('assets/reference_data/timing_rules.json'),
      reason:
          'timing_rules.json drives clinical guidance and must not drop out of '
          'the gate',
    );
  });

  test('timing rules are bundled at the schema the parser requires', () {
    final json =
        jsonDecode(
              File('assets/reference_data/timing_rules.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final metadata = json['_metadata'] as Map<String, dynamic>;
    final rules = json['timing_rules'] as List;

    expect(metadata['schema_version'], '6.0.0');
    expect(metadata['total_entries'], rules.length);

    // The legacy scheduler fields must never come back through the artifact.
    for (final raw in rules) {
      final rule = raw as Map;
      expect(rule.containsKey('rule_type'), isFalse, reason: '${rule['id']}');
      expect(rule.containsKey('daily_slots'), isFalse, reason: '${rule['id']}');
      expect(
        rule.containsKey('daily_plan_eligible'),
        isFalse,
        reason: '${rule['id']}',
      );
      // Every rule carries the full publication contract.
      for (final field in const [
        'category',
        'applies_to',
        'actionability',
        'source_authority',
        'review_status',
        'timing_relation',
      ]) {
        expect(
          rule.containsKey(field),
          isTrue,
          reason: '${rule['id']} is missing $field',
        );
      }
    }
  });
}
