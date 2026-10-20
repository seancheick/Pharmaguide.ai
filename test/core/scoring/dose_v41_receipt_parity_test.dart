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
    '205309: the Dose cap is itemized and its one consumer fact renders verbatim',
    () {
      final dose = pillarsOf('205309').firstWhere((p) => p.key == 'dose');
      expect(dose.score, 10.0);
      expect(dose.receipt!.points('cap'), closeTo(-10.0, 1e-9));
      expect(
        dose.reason,
        'The higher directed daily amounts of Magnesium exceed its established '
        'upper limit (137% of the limit at the highest directed use), so Dose '
        'is capped at 10.',
      );
      // Only the pipeline's consumer fact reaches the app; audit detail
      // (arithmetic, policy, contributions) stays in the blob.
      expect(dose.facts.length, 1);
      expect(dose.facts.single.id, 'dose_upper_limit_result');
      expect(
        dose.facts.single.valueDisplay,
        'Up to 480 mg a day: 137% of the 350 mg Magnesium upper limit '
        '(general adult)',
      );
    },
  );

  test('299065: no cap, and a policy target is never shown as a reference', () {
    final dose = pillarsOf('299065').firstWhere((p) => p.key == 'dose');
    expect(dose.score, 20.0);
    expect(dose.receipt!.points('cap'), 0);
    // Its only reference is PharmaGuide's 20%-of-DV contribution target:
    // scoring policy, so no consumer fact; the reason stands alone.
    expect(dose.facts, isEmpty);
    expect(dose.reason, isNotNull);
  });
}
