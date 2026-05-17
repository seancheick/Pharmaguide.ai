import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';

void main() {
  group('Severity', () {
    test('ordering is contraindicated > avoid > caution > monitor > safe', () {
      expect(
        Severity.contraindicated.weight,
        greaterThan(Severity.avoid.weight),
      );
      expect(Severity.avoid.weight, greaterThan(Severity.caution.weight));
      expect(Severity.caution.weight, greaterThan(Severity.monitor.weight));
      expect(Severity.monitor.weight, greaterThan(Severity.safe.weight));
    });

    test('fromString parses valid severity', () {
      expect(Severity.fromString('contraindicated'), Severity.contraindicated);
      expect(Severity.fromString('avoid'), Severity.avoid);
      expect(Severity.fromString('caution'), Severity.caution);
      expect(Severity.fromString('monitor'), Severity.monitor);
      expect(Severity.fromString('informational'), Severity.informational);
      expect(Severity.fromString('safe'), Severity.safe);
    });

    test('fromString parses pipeline-emitted severities conservatively', () {
      expect(Severity.fromString('critical'), Severity.contraindicated);
      expect(Severity.fromString('high'), Severity.avoid);
      expect(Severity.fromString('moderate'), Severity.caution);
      expect(Severity.fromString('low'), Severity.monitor);
      expect(Severity.fromString('no_data'), Severity.monitor);
    });

    test('fromString does not silently downgrade unknown values to safe', () {
      expect(Severity.fromString('unknown'), Severity.caution);
      expect(Severity.fromString(''), Severity.caution);
    });

    test('isKnownString tracks accepted pipeline vocabulary', () {
      for (final value in [
        'contraindicated',
        'critical',
        'avoid',
        'high',
        'caution',
        'moderate',
        'monitor',
        'low',
        'no_data',
        'informational',
        'info',
        'safe',
      ]) {
        expect(Severity.isKnownString(value), isTrue);
      }

      expect(Severity.isKnownString('unknown'), isFalse);
      expect(Severity.isKnownString(''), isFalse);
    });

    test('e2cPenalty returns correct values', () {
      expect(Severity.contraindicated.e2cPenalty, -8);
      expect(Severity.avoid.e2cPenalty, -5);
      expect(Severity.caution.e2cPenalty, -3);
      expect(Severity.monitor.e2cPenalty, -1);
      expect(Severity.safe.e2cPenalty, 0);
    });
  });

  group('EvidenceLevel', () {
    test('fromString parses valid levels', () {
      expect(
        EvidenceLevel.fromString('established'),
        EvidenceLevel.established,
      );
      expect(EvidenceLevel.fromString('probable'), EvidenceLevel.probable);
      expect(
        EvidenceLevel.fromString('theoretical'),
        EvidenceLevel.theoretical,
      );
    });

    test('fromString returns theoretical for unknown', () {
      expect(EvidenceLevel.fromString('unknown'), EvidenceLevel.theoretical);
    });
  });
}
