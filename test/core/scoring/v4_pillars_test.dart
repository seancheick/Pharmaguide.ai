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
}
