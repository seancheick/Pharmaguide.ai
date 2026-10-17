// Dose V4.1 §4 (pipeline docs/plans/DOSE_V41_PLAN.md): the app renders the
// pipeline's recorded Dose result and never recomputes it. The fixture is the
// real pipeline output for Pure Encapsulations Magnesium (Glycinate): 205309
// (1-4 capsules, 480 mg/day = 137% of the 350 mg limit, Dose capped at 10)
// and its once-daily control 299065.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/pipeline/dose_v41_pillars.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final products = fixture['products'] as Map<String, dynamic>;

  List<V4PillarValue> pillarsOf(String id) => parseV4Pillars(
    (products[id] as Map<String, dynamic>)['quality_pillars_v4']
        as Map<String, dynamic>,
  );

  for (final id in ['205309', '299065']) {
    test('$id: every pillar receipt sums to its recorded score', () {
      final pillars = pillarsOf(id);
      expect(hasAllV4Pillars(pillars), isTrue);
      for (final pillar in pillars) {
        final receipt = pillar.receipt;
        expect(receipt, isNotNull, reason: pillar.key);
        final sum = receipt!.pointsByKind.values.fold<double>(
          0,
          (a, b) => a + b,
        );
        expect(sum, closeTo(pillar.score!, 0.051), reason: pillar.key);
      }
      final total = pillars.fold<double>(0, (a, p) => a + p.score!);
      expect(
        total,
        closeTo((products[id] as Map)['quality_score_v4_100'] as num, 0.051),
      );
    });
  }

  test(
    '205309: the Dose cap is itemized and its receipt facts render verbatim',
    () {
      final dose = pillarsOf('205309').firstWhere((p) => p.key == 'dose');
      expect(dose.score, 10.0);
      expect(dose.receipt!.points('cap'), closeTo(-10.0, 1e-9));
      final facts = {for (final f in dose.facts) f.id: f.valueDisplay};
      expect(
        facts['dose_arithmetic'],
        'Adequacy 20/20, capped at 10: Dose 10/20.',
      );
      expect(
        facts['dose_upper_reference'],
        contains('137% of the Magnesium upper limit of 350 mg'),
      );
      expect(
        facts['dose_upper_reference'],
        contains('PharmaGuide scoring policy'),
      );
      expect(
        facts['dose_contributions'],
        contains('120-480 mg/day by directions'),
      );
      expect(
        facts['dose_reference_method'],
        contains('lowest directed daily use'),
      );
    },
  );

  test('299065: no cap, so no upper-limit fact', () {
    final dose = pillarsOf('299065').firstWhere((p) => p.key == 'dose');
    expect(dose.score, 20.0);
    expect(dose.receipt!.points('cap'), 0);
    expect(dose.facts.any((f) => f.id == 'dose_upper_reference'), isFalse);
  });
}
