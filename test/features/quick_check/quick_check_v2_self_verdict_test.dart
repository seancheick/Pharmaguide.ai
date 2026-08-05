// FIX 2 (P1) — Quick Check must be verdict-aware.
//
// "Safe to take together?" pairs two products. If a SELECTED product is
// itself BLOCKED/UNSAFE, the neutral "No interaction catalogued" pair result
// must NOT read as an all-clear on a banned product. `unsafeSelfVerdicts` is
// the pure decision the screen uses to raise a self-verdict banner above the
// pair result whenever a selected product is unsafe on its own.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/quick_check/v2/quick_check_v2_screen.dart';

void main() {
  group('Quick Check self-verdict guard (unsafeSelfVerdicts)', () {
    test('flags a BLOCKED selection, leaves a SAFE one alone', () {
      final out = unsafeSelfVerdicts(const [
        QuickCheckSelection('Ephedra Cut', 'BLOCKED'),
        QuickCheckSelection('Vitamin D3', 'SAFE'),
      ]);
      expect(out.map((s) => s.name), ['Ephedra Cut']);
    });

    test('flags an UNSAFE selection and ignores null slots', () {
      final out = unsafeSelfVerdicts(const [
        QuickCheckSelection('DMAA Pre-Workout', 'UNSAFE'),
        null,
      ]);
      expect(out.map((s) => s.name), ['DMAA Pre-Workout']);
    });

    test('normalizes case/whitespace (matches isUnsafeVerdict)', () {
      final out = unsafeSelfVerdicts(const [
        QuickCheckSelection('X', '  blocked  '),
      ]);
      expect(out, hasLength(1));
    });

    test('does not flag non-blocking catalog safety states', () {
      final out = unsafeSelfVerdicts(const [
        QuickCheckSelection('a', 'NO_KNOWN_CATALOG_CONCERN'),
        QuickCheckSelection('b', 'CAUTION'),
        QuickCheckSelection('c', 'NOT_ASSESSED'),
        QuickCheckSelection('d', 'NOT_ASSESSED'),
        QuickCheckSelection('e', 'WEIRD_FUTURE'),
      ]);
      expect(out, isEmpty);
    });

    test('flags both slots when both selections are unsafe', () {
      final out = unsafeSelfVerdicts(const [
        QuickCheckSelection('a', 'BLOCKED'),
        QuickCheckSelection('b', 'UNSAFE'),
      ]);
      expect(out.map((s) => s.name), ['a', 'b']);
    });
  });
}
