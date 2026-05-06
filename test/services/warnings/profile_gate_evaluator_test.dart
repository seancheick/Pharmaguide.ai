// Drift-contract test for the v6.0 profile_gate evaluator.
//
// Loads the shared fixture (test/fixtures/profile_gate/
// profile_gate_test_cases.json) — a byte-identical copy of
// dsld_clean/scripts/data/profile_gate_test_cases.json — and asserts the
// Dart evaluator produces identical (fires, severity) output to the
// Python reference for every case.
//
// If this test fails, either:
//   1. The fixture was updated in the pipeline repo and not re-synced
//      into test/fixtures/profile_gate/ here (run the cp command from
//      that directory's README.md); OR
//   2. The Dart evaluator at lib/services/warnings/profile_gate_evaluator.dart
//      has drifted from the Python reference at
//      dsld_clean/scripts/profile_gate_evaluator.py.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';

void main() {
  group('profile_gate evaluator — shared fixture (drift contract)', () {
    final fixtureFile = File(
      'test/fixtures/profile_gate/profile_gate_test_cases.json',
    );

    test('fixture file exists and parses as v6.0 contract', () {
      expect(fixtureFile.existsSync(), isTrue,
          reason: 'fixture must be present at test/fixtures/profile_gate/'
              ' — run the cp from the pipeline repo per the README');
      final data = jsonDecode(fixtureFile.readAsStringSync())
          as Map<String, dynamic>;
      final meta = data['_metadata'] as Map<String, dynamic>;
      expect(meta['evaluator_contract_version'], '6.0',
          reason: 'fixture metadata must declare evaluator_contract_version=6.0');
      expect((data['test_cases'] as List).length, greaterThanOrEqualTo(18));
    });

    test('every fixture case matches the Python reference output', () {
      final data = jsonDecode(fixtureFile.readAsStringSync())
          as Map<String, dynamic>;
      final cases = (data['test_cases'] as List).cast<Map<String, dynamic>>();

      final failures = <String>[];

      for (final c in cases) {
        final name = c['name'] as String;
        final gate = c['gate'] as Map<String, dynamic>;
        final userProfile = UserProfile.fromJson(
          c['user_profile'] as Map<String, dynamic>,
        );
        final productContext = ProductContext.fromJson(
          c['product_context'] as Map<String, dynamic>,
        );
        final expected = c['expected'] as Map<String, dynamic>;
        final baseSeverity = c['base_severity'] as String?;

        final result = evaluateProfileGate(
          gate,
          userProfile,
          productContext,
          baseSeverity: baseSeverity,
        );

        final expectedFires = expected['fires'] as bool;
        final expectedSeverity = expected['severity'] as String?;

        if (result.fires != expectedFires) {
          failures.add(
            '[$name] expected fires=$expectedFires got ${result.fires} '
            '(reason: ${result.reason})',
          );
        }
        if (expectedFires && result.severity != expectedSeverity) {
          failures.add(
            '[$name] expected severity="$expectedSeverity" '
            'got "${result.severity}"',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason: 'Drift detected — Dart and Python disagree on '
            '${failures.length} case(s):\n  ${failures.join("\n  ")}',
      );
    });
  });

  group('profile_gate validator — structural', () {
    test('clean condition gate validates', () {
      final gate = _gate(
        'condition',
        requires: {
          'conditions_any': <String>['diabetes'],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
        },
      );
      expect(validateProfileGate(gate), isEmpty);
    });

    test('unknown gate_type fails', () {
      final gate = _gate(
        'bogus',
        requires: {
          'conditions_any': <String>['x'],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
        },
      );
      final errors = validateProfileGate(gate);
      expect(errors.any((e) => e.contains('gate_type')), isTrue);
    });

    test('condition gate with drug_classes_any populated fails', () {
      final gate = _gate(
        'condition',
        requires: {
          'conditions_any': <String>['diabetes'],
          'drug_classes_any': <String>['anticoagulants'],
          'profile_flags_any': <String>[],
        },
      );
      final errors = validateProfileGate(gate);
      expect(errors.any((e) => e.contains('must only populate')), isTrue);
    });

    test('combination gate without dose and <2 axes fails', () {
      final gate = _gate(
        'combination',
        requires: {
          'conditions_any': <String>['diabetes'],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
        },
      );
      final errors = validateProfileGate(gate);
      expect(errors.any((e) => e.contains('≥2 populated')), isTrue);
    });

    test('combination gate with single axis + dose passes', () {
      final gate = _gate(
        'combination',
        requires: {
          'conditions_any': <String>['diabetes'],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
        },
        dose: {
          'comparator': '>=',
          'value': 1500,
          'severity_if_met': 'avoid',
          'severity_if_not_met': 'caution',
        },
      );
      expect(validateProfileGate(gate), isEmpty);
    });

    test('dose gate without dose block fails', () {
      final gate = _gate('dose');
      final errors = validateProfileGate(gate);
      expect(errors.any((e) => e.contains('non-null dose block')), isTrue);
    });
  });
}

Map<String, dynamic> _gate(
  String gateType, {
  Map<String, dynamic>? requires,
  Map<String, dynamic>? excludes,
  Map<String, dynamic>? dose,
}) {
  return {
    'gate_type': gateType,
    'requires': requires ??
        const {
          'conditions_any': <String>[],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
        },
    'excludes': excludes ??
        const {
          'conditions_any': <String>[],
          'drug_classes_any': <String>[],
          'profile_flags_any': <String>[],
          'product_forms_any': <String>[],
          'nutrient_forms_any': <String>[],
        },
    'dose': dose,
  };
}
