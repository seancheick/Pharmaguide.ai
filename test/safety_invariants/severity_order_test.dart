// Safety invariant: severity order is sacred.
//
// CLAUDE.md / AGENTS.md / sentry-autofix-playbook.md all hinge on the
// ordering `contraindicated > avoid > caution > monitor > informational
// > safe`. Aliasing, reordering, or changing the weights would silently
// invert verdicts across the entire app (Fit Score, warnings, stack
// risk, depletion checker). This test locks the enum down so a future
// agent — or a future human — cannot reorder by accident.
//
// If this test fails, do NOT just update the expectations. Stop and
// confirm the change is intentional with a human reviewer.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';

void main() {
  group('Safety invariant: severity ordering', () {
    test('enum declaration order is contraindicated → safe', () {
      expect(
        Severity.values.map((s) => s.name).toList(),
        equals(<String>[
          'contraindicated',
          'avoid',
          'caution',
          'monitor',
          'informational',
          'safe',
        ]),
      );
    });

    test('weights are 5, 4, 3, 2, 1, 0 in that order', () {
      expect(Severity.contraindicated.weight, 5);
      expect(Severity.avoid.weight, 4);
      expect(Severity.caution.weight, 3);
      expect(Severity.monitor.weight, 2);
      expect(Severity.informational.weight, 1);
      expect(Severity.safe.weight, 0);
    });

    test('weight ordering matches declaration order (strictly descending)', () {
      final weights = Severity.values.map((s) => s.weight).toList();
      for (var i = 1; i < weights.length; i++) {
        expect(
          weights[i] < weights[i - 1],
          isTrue,
          reason:
              'Severity ${Severity.values[i].name} (weight ${weights[i]}) '
              'must have a strictly lower weight than '
              '${Severity.values[i - 1].name} (weight ${weights[i - 1]}).',
        );
      }
    });

    test('safe is the lowest-weight severity (sort floor)', () {
      final sorted = [...Severity.values]
        ..sort((a, b) => a.weight.compareTo(b.weight));
      expect(sorted.first, Severity.safe);
    });

    test('contraindicated is the highest-weight severity (sort ceiling)', () {
      final sorted = [...Severity.values]
        ..sort((a, b) => b.weight.compareTo(a.weight));
      expect(sorted.first, Severity.contraindicated);
    });

    test('fromString maps known aliases without crossing severity tiers', () {
      // Each alias must resolve to the same tier as the canonical name.
      // A regression here (e.g. "critical" mapping to "avoid") would
      // silently downgrade real safety warnings.
      expect(Severity.fromString('critical'), Severity.contraindicated);
      expect(Severity.fromString('high'), Severity.avoid);
      expect(Severity.fromString('moderate'), Severity.caution);
      expect(Severity.fromString('low'), Severity.monitor);
      expect(Severity.fromString('no_data'), Severity.monitor);
      expect(Severity.fromString('info'), Severity.informational);
    });

    test('unknown severity falls back to caution, never safe', () {
      // Defensive default: a bad enum string should be conservative,
      // not optimistic. Falling back to "safe" would hide real risks.
      expect(Severity.fromString('not-a-real-severity'), Severity.caution);
      expect(Severity.fromString(''), Severity.caution);
    });
  });
}
