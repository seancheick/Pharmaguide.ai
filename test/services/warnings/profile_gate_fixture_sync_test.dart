// Content lock for the vendored profile_gate fixture (cross-repo drift gate).
//
// test/fixtures/profile_gate/profile_gate_test_cases.json is a byte-identical
// COPY of the canonical fixture in the pipeline repo
// (dsld_clean/scripts/data/profile_gate_test_cases.json). The evaluator parity
// test (profile_gate_evaluator_test.dart) only proves the Dart evaluator agrees
// with THIS copy — if the copy silently goes stale, that test keeps passing
// against the wrong expectations.
//
// This test freezes the copy's content to a pinned SHA-256 that MUST equal the
// pin in the pipeline repo's scripts/tests/test_profile_gate_fixture_sync.py.
// The two identical pins are the actual cross-repo parity contract: the fixture
// cannot change in either repo without a visible, reviewed pin bump in both.
//
// To change the fixture: edit the canonical file, recompute `shasum -a 256`,
// update BOTH pins, and re-copy the file into test/fixtures/profile_gate/.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profile_gate fixture — content lock (cross-repo drift gate)', () {
    final fixture = File(
      'test/fixtures/profile_gate/profile_gate_test_cases.json',
    );

    // SHA-256 of the vendored fixture bytes. MUST equal PINNED_SHA256 in the
    // pipeline repo's scripts/tests/test_profile_gate_fixture_sync.py.
    const pinnedSha256 =
        'ea6e5ae87d46c8c8e1f1fe8220c15cab6aa1950cf9c8c6195a8de9defdc81e66';

    test('vendored fixture matches the pinned canonical hash', () {
      expect(
        fixture.existsSync(),
        isTrue,
        reason: 'fixture must be present at test/fixtures/profile_gate/',
      );
      final actual = sha256.convert(fixture.readAsBytesSync()).toString();
      expect(
        actual,
        pinnedSha256,
        reason:
            'profile_gate fixture content changed or drifted from the pipeline '
            'copy.\n  actual: $actual\n  pinned: $pinnedSha256\n'
            'If intentional, update this pin AND the pipeline pin '
            '(scripts/tests/test_profile_gate_fixture_sync.py) and re-copy the '
            'canonical fixture in.',
      );
    });

    test('fixture entry counts are internally consistent', () {
      final data =
          jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
      final meta = data['_metadata'] as Map<String, dynamic>;
      final n = (data['test_cases'] as List).length;
      expect(meta['total_entries'], n, reason: '_metadata.total_entries != cases');
      expect(meta['case_count'], n, reason: '_metadata.case_count != cases');
    });
  });
}
