// Hardened-parsing contract for the shared v4 pillar parser.
//
//   * num-or-numeric-string scores parse; junk strings → null score
//   * max <= 0 (or unparseable) falls back to the spec max
//   * one malformed entry skips only that entry
//   * hasAllV4Pillars enforces the 6/6 ship rule

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';

Map<String, dynamic> _fullBlob() => {
  'formulation': <String, dynamic>{'score': 18.0, 'max': 20, 'reason': 'r'},
  'dose': <String, dynamic>{'score': 16.0, 'max': 20},
  'evidence': <String, dynamic>{'score': 15.0, 'max': 20},
  'transparency': <String, dynamic>{'score': 12.0, 'max': 15},
  'verification': <String, dynamic>{'score': 11.0, 'max': 15},
  'safety_hygiene': <String, dynamic>{'score': 9.0, 'max': 10},
};

void main() {
  test('parses all six pillars in spec order', () {
    final out = parseV4Pillars(_fullBlob());
    expect(out.length, kV4PillarSpec.length);
    expect(hasAllV4Pillars(out), isTrue);
    expect(out.first.key, 'formulation');
    expect(out.last.key, 'safety_hygiene');
    expect(out.last.label, 'Formula & quality checks');
  });

  test('null / empty blob → empty result, hasAllV4Pillars false', () {
    expect(parseV4Pillars(null), isEmpty);
    expect(parseV4Pillars(const {}), isEmpty);
    expect(hasAllV4Pillars(const []), isFalse);
  });

  test('partial blob (4/6) parses 4 and fails the 6/6 rule', () {
    final blob = _fullBlob()
      ..remove('verification')
      ..remove('safety_hygiene');
    final out = parseV4Pillars(blob);
    expect(out.length, 4);
    expect(hasAllV4Pillars(out), isFalse);
  });

  test('numeric-string score is parsed; junk string → null score', () {
    final blob = _fullBlob();
    (blob['formulation'] as Map<String, dynamic>)['score'] = '18.5';
    (blob['dose'] as Map<String, dynamic>)['score'] = 'not a number';
    final out = parseV4Pillars(blob);
    expect(out.length, 6, reason: 'no entry may throw or be dropped');
    expect(out[0].score, 18.5);
    expect(out[1].score, isNull);
  });

  test('non-finite score is rejected (B#6 NaN guard)', () {
    // The old local _asDouble did `if (v is num) return v.toDouble()` with no
    // isFinite guard, so a NaN / Infinity score flowed straight into the
    // pillar. Routed through asFiniteDouble, a non-finite value now reads null
    // and never corrupts the score.
    final blob = _fullBlob();
    (blob['formulation'] as Map<String, dynamic>)['score'] = double.nan;
    (blob['dose'] as Map<String, dynamic>)['score'] = double.infinity;
    (blob['evidence'] as Map<String, dynamic>)['score'] = 'Infinity';
    final out = parseV4Pillars(blob);
    expect(out.length, 6, reason: 'no entry may throw or be dropped');
    expect(out[0].score, isNull);
    expect(out[1].score, isNull);
    expect(out[2].score, isNull);
  });

  test('max <= 0 or non-numeric max falls back to the spec max', () {
    final blob = _fullBlob();
    (blob['formulation'] as Map<String, dynamic>)['max'] = 0;
    (blob['dose'] as Map<String, dynamic>)['max'] = -5;
    (blob['evidence'] as Map<String, dynamic>)['max'] = 'twenty';
    final out = parseV4Pillars(blob);
    expect(out[0].max, 20);
    expect(out[1].max, 20);
    expect(out[2].max, 20);
  });

  test('one malformed entry skips that entry only', () {
    final blob = _fullBlob();
    blob['dose'] = 'not a map';
    final out = parseV4Pillars(blob);
    expect(out.length, 5);
    expect(out.any((p) => p.key == 'dose'), isFalse);
    expect(hasAllV4Pillars(out), isFalse);
  });

  test('non-string reason is tolerated (null reason, no throw)', () {
    final blob = _fullBlob();
    (blob['formulation'] as Map<String, dynamic>)['reason'] = 42;
    final out = parseV4Pillars(blob);
    expect(out.first.reason, isNull);
  });

  // --- Task 1: schema-v1 explanation facts + presentation status ---

  test('parses schema_version 1 explanation facts in order, verbatim', () {
    final blob = _fullBlob();
    (blob['dose'] as Map<String, dynamic>)['explanation'] = {
      'schema_version': 1,
      'facts': [
        {
          'id': 'epa_dha_per_day',
          'label': 'EPA + DHA per day',
          'value_display': '660 mg/day',
          'detail': 'From the label-directed daily serving.',
        },
        {
          'id': 'omega_form',
          'label': 'Molecular form',
          'value_display': 'Ethyl ester',
        },
      ],
    };
    final dose = parseV4Pillars(blob).firstWhere((p) => p.key == 'dose');
    expect(dose.facts.length, 2);
    expect(dose.facts[0].id, 'epa_dha_per_day');
    expect(dose.facts[0].label, 'EPA + DHA per day');
    expect(dose.facts[0].valueDisplay, '660 mg/day');
    expect(dose.facts[0].detail, 'From the label-directed daily serving.');
    expect(dose.facts[1].id, 'omega_form');
    expect(dose.facts[1].valueDisplay, 'Ethyl ester');
  });

  test('ignores explanation with unsupported schema_version', () {
    final blob = _fullBlob();
    (blob['dose'] as Map<String, dynamic>)['explanation'] = {
      'schema_version': 2,
      'facts': [
        {'id': 'x', 'label': 'X', 'value_display': 'y'},
      ],
    };
    final dose = parseV4Pillars(blob).firstWhere((p) => p.key == 'dose');
    expect(dose.facts, isEmpty);
  });

  test('omits malformed facts but keeps valid ones', () {
    final blob = _fullBlob();
    (blob['dose'] as Map<String, dynamic>)['explanation'] = {
      'schema_version': 1,
      'facts': [
        {'id': 'ok', 'label': 'L', 'value_display': 'good'},
        {'id': '', 'label': 'L', 'value_display': 'no id'},
        {'id': 'no_label', 'value_display': 'no label'},
        {'id': 'no_value_display', 'label': 'L'},
        {'id': 'legacy_display', 'label': 'L', 'display': 'not accepted'},
        'not a map',
      ],
    };
    final dose = parseV4Pillars(blob).firstWhere((p) => p.key == 'dose');
    expect(dose.facts.length, 1);
    expect(dose.facts.single.id, 'ok');
  });

  test('old reason-only blob yields empty facts (backward compatible)', () {
    final out = parseV4Pillars(_fullBlob());
    expect(out.every((p) => p.facts.isEmpty), isTrue);
  });

  test('statusForPillar: >=85% Strong, >=60% Mixed, below 60% Limited', () {
    expect(statusForPillar(17.0, 20), V4PillarStatus.strong); // 85%
    expect(statusForPillar(20.0, 20), V4PillarStatus.strong); // 100%
    expect(
      statusForPillar(13.9, 20),
      V4PillarStatus.mixed,
    ); // 69.5% (Formulation)
    expect(statusForPillar(12.0, 20), V4PillarStatus.mixed); // 60%
    expect(statusForPillar(11.9, 20), V4PillarStatus.limited); // 59.5%
    expect(statusForPillar(double.minPositive, 20), V4PillarStatus.limited);
  });

  test('statusForPillar: exact zero with positive max is No points', () {
    expect(statusForPillar(0.0, 20), V4PillarStatus.noPoints);
    expect(statusForPillar(-0.0, 20), V4PillarStatus.noPoints);
  });

  test('zero score with non-positive or non-finite max stays Limited', () {
    for (final max in <num>[
      0,
      -1,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(statusForPillar(0.0, max), V4PillarStatus.limited);
    }
  });

  test('null and non-finite scores stay Limited', () {
    expect(statusForPillar(null, 20), V4PillarStatus.limited);
    expect(statusForPillar(double.nan, 20), V4PillarStatus.limited);
    expect(statusForPillar(double.infinity, 20), V4PillarStatus.limited);
    expect(
      statusForPillar(double.negativeInfinity, 20),
      V4PillarStatus.limited,
    );
  });

  test('status labels are consumer copy', () {
    expect(v4PillarStatusLabel(V4PillarStatus.strong), 'Strong');
    expect(v4PillarStatusLabel(V4PillarStatus.mixed), 'Mixed');
    expect(v4PillarStatusLabel(V4PillarStatus.limited), 'Limited');
    expect(v4PillarStatusLabel(V4PillarStatus.noPoints), 'No points');
  });

  test('action-label map excludes redundant label-detail navigation', () {
    expect(kV4PillarActionLabels['evidence'], 'View clinical evidence');
    expect(kV4PillarActionLabels['verification'], 'View certifications');
    expect(kV4PillarActionLabels.containsKey('transparency'), isFalse);
    expect(kV4PillarActionLabels.containsKey('formulation'), isFalse);
    expect(kV4PillarActionLabels.containsKey('dose'), isFalse);
    expect(kV4PillarActionLabels.containsKey('safety_hygiene'), isFalse);
  });
}
