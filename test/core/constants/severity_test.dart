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
    });

    test('fromString returns safe for unknown values', () {
      expect(Severity.fromString('unknown'), Severity.safe);
      expect(Severity.fromString(''), Severity.safe);
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
