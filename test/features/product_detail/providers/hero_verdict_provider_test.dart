// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.1.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/providers/hero_verdict_provider.dart';

void main() {
  group('computeHeroVerdict — product-side blocking (priority 1)', () {
    test('BLOCKED verdict → HeroVerdictBlocked, regardless of warnings', () {
      final out = computeHeroVerdict(
        productVerdict: 'BLOCKED',
        blockingReason: 'Banned substance detected',
        topWarnings: const [],
      );
      expect(out, isA<HeroVerdictBlocked>());
      expect((out as HeroVerdictBlocked).verdict, 'BLOCKED');
      expect(out.blockingReason, 'Banned substance detected');
    });

    test('UNSAFE verdict → HeroVerdictBlocked', () {
      final out = computeHeroVerdict(
        productVerdict: 'UNSAFE',
        blockingReason: '',
        topWarnings: const [],
      );
      expect(out, isA<HeroVerdictBlocked>());
      expect((out as HeroVerdictBlocked).verdict, 'UNSAFE');
    });

    test('lowercase "blocked" still matches (verdict is uppercased)', () {
      final out = computeHeroVerdict(
        productVerdict: 'blocked',
        blockingReason: '',
        topWarnings: const [],
      );
      expect(out, isA<HeroVerdictBlocked>());
      expect((out as HeroVerdictBlocked).verdict, 'BLOCKED');
    });

    test('BLOCKED + bannedSubstanceDetail propagates to result', () {
      final detail = {'substance_name': 'DMAA', 'safety_warning': 'FDA banned'};
      final out = computeHeroVerdict(
        productVerdict: 'BLOCKED',
        blockingReason: 'FDA action',
        topWarnings: const [],
        bannedSubstanceDetail: detail,
      );
      expect(out, isA<HeroVerdictBlocked>());
      expect((out as HeroVerdictBlocked).bannedSubstanceDetail, detail);
    });

    test('BLOCKED wins even when topWarnings has non-blocking severities', () {
      // Sanity: a Caution warning shouldn't downgrade a BLOCKED
      // product. Product-side blocking is the most serious tier.
      final out = computeHeroVerdict(
        productVerdict: 'BLOCKED',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'caution', 'mechanism': 'minor flag'},
        ],
      );
      expect(out, isA<HeroVerdictBlocked>());
    });
  });

  group('computeHeroVerdict — stack-side blocking (priority 2)', () {
    test('Avoid in topWarnings → HeroVerdictAvoid with severity Avoid', () {
      final out = computeHeroVerdict(
        productVerdict: 'RECOMMENDED',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'avoid', 'with': 'metformin'},
        ],
      );
      expect(out, isA<HeroVerdictAvoid>());
      final avoid = out as HeroVerdictAvoid;
      expect(avoid.severity, Severity.avoid);
      expect(avoid.offendingAgent, 'metformin');
    });

    test('Contraindicated in topWarnings → HeroVerdictAvoid with severity '
        'Contraindicated', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'contraindicated', 'with': 'warfarin'},
        ],
      );
      expect(out, isA<HeroVerdictAvoid>());
      expect((out as HeroVerdictAvoid).severity, Severity.contraindicated);
    });

    test('multiple warnings → uses the worst severity', () {
      // Pipeline can ship mixed-severity warnings — make sure we
      // pick the worst one (contraindicated > avoid > caution).
      final out = computeHeroVerdict(
        productVerdict: 'RECOMMENDED',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'caution', 'with': 'aspirin'},
          {'severity': 'contraindicated', 'with': 'warfarin'},
          {'severity': 'monitor', 'with': 'lisinopril'},
        ],
      );
      expect(out, isA<HeroVerdictAvoid>());
      final avoid = out as HeroVerdictAvoid;
      expect(avoid.severity, Severity.contraindicated);
      expect(
        avoid.offendingAgent,
        'warfarin',
        reason:
            'agent should come from the warning that produced '
            'the worst severity, not the first warning in the list',
      );
    });

    test('stack Avoid overrides product-side RECOMMENDED', () {
      // The locked rule: safety > goal match. A medication
      // interaction beats a "this is a great product" verdict.
      final out = computeHeroVerdict(
        productVerdict: 'RECOMMENDED',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'avoid', 'with': 'metformin'},
        ],
      );
      expect(out, isA<HeroVerdictAvoid>());
    });

    test('Avoid without a recognized agent field → null offendingAgent', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'avoid', 'mechanism': 'something opaque'},
        ],
      );
      expect(out, isA<HeroVerdictAvoid>());
      expect((out as HeroVerdictAvoid).offendingAgent, isNull);
    });

    test('agent extraction tries several keys', () {
      // Pipeline shape variance — we try `with`, `interacting_with`,
      // `medication`, `drug`, `agent`, `name` in priority order.
      // First non-empty wins.
      final variants = {
        'with': 'metformin',
        'interacting_with': 'lisinopril',
        'medication': 'aspirin',
        'drug': 'warfarin',
        'agent': 'fish oil',
        'name': 'iron',
      };
      for (final entry in variants.entries) {
        final out = computeHeroVerdict(
          productVerdict: 'GOOD',
          blockingReason: '',
          topWarnings: [
            {'severity': 'avoid', entry.key: entry.value},
          ],
        );
        expect(
          (out as HeroVerdictAvoid).offendingAgent,
          entry.value,
          reason: 'agent extraction failed for key "${entry.key}"',
        );
      }
    });

    test('"with" beats other keys when both are present', () {
      // Order is intentional in the extraction allowlist —
      // make sure that order is honored.
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'avoid', 'with': 'metformin', 'name': 'should-not-win'},
        ],
      );
      expect((out as HeroVerdictAvoid).offendingAgent, 'metformin');
    });

    test('headline composes correctly for Avoid + agent', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'avoid', 'with': 'metformin'},
        ],
      );
      // Voice rule per feedback_copy_voice.md — clinical advisory,
      // no "Avoid"/"Do not take" imperatives. Use caution + the
      // danger-tone banner color does the urgency lift.
      expect((out as HeroVerdictAvoid).headline, 'Use caution with metformin');
    });

    test('headline composes correctly for Contraindicated + agent', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'contraindicated', 'with': 'warfarin'},
        ],
      );
      // contraindicated is the stronger tier — "Not recommended"
      // reads as a firm clinical judgment without imperative shout.
      expect(
        (out as HeroVerdictAvoid).headline,
        'Not recommended with warfarin',
      );
    });

    test('headline degrades gracefully when agent is absent', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'avoid', 'mechanism': 'opaque'},
        ],
      );
      expect((out as HeroVerdictAvoid).headline, 'Use caution for your stack');
    });

    test('headline degrades gracefully for contraindicated + no agent', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'contraindicated', 'mechanism': 'opaque'},
        ],
      );
      expect(
        (out as HeroVerdictAvoid).headline,
        'Not recommended for your stack',
      );
    });

    test('hero headlines never use "Stop"/"Avoid"/"Do not" imperatives', () {
      // Voice-rule guard — feedback_copy_voice.md. Any future change
      // that reintroduces those verbs into the Flutter-derived
      // headline path fails loudly here. Covers both tiers + both
      // agent-present and agent-absent paths.
      const probes = [
        {'severity': 'contraindicated', 'with': 'warfarin'},
        {'severity': 'avoid', 'with': 'metformin'},
        {'severity': 'contraindicated', 'mechanism': 'opaque'},
        {'severity': 'avoid', 'mechanism': 'opaque'},
      ];
      for (final w in probes) {
        final out = computeHeroVerdict(
          productVerdict: 'GOOD',
          blockingReason: '',
          topWarnings: [w],
        );
        final headline = (out as HeroVerdictAvoid).headline;
        expect(headline, isNot(contains('Stop')));
        expect(headline, isNot(contains('Avoid')));
        expect(headline, isNot(contains('Do not')));
      }
    });
  });

  group('computeHeroVerdict — non-blocking severities → HeroVerdictNone', () {
    test('Caution-only warnings → None (lives in Section 2, not hero)', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'caution', 'with': 'aspirin'},
        ],
      );
      expect(out, isA<HeroVerdictNone>());
    });

    test('Monitor-only warnings → None', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'monitor', 'with': 'lisinopril'},
        ],
      );
      expect(out, isA<HeroVerdictNone>());
    });

    test('Informational-only warnings → None', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'informational', 'mechanism': 'context-only flag'},
        ],
      );
      expect(out, isA<HeroVerdictNone>());
    });

    test('Empty warnings + RECOMMENDED → None', () {
      final out = computeHeroVerdict(
        productVerdict: 'RECOMMENDED',
        blockingReason: '',
        topWarnings: const [],
      );
      expect(out, isA<HeroVerdictNone>());
    });

    test('null verdict + no warnings → None', () {
      final out = computeHeroVerdict(
        productVerdict: null,
        blockingReason: '',
        topWarnings: const [],
      );
      expect(out, isA<HeroVerdictNone>());
    });

    test('NOT_SCORED + no warnings → None', () {
      final out = computeHeroVerdict(
        productVerdict: 'NOT_SCORED',
        blockingReason: '',
        topWarnings: const [],
      );
      expect(out, isA<HeroVerdictNone>());
    });
  });

  group('computeHeroVerdict — robustness against malformed input', () {
    test('warning with unrecognized severity string → ignored', () {
      // Pipeline drift could emit a severity we don't recognize.
      // Don't crash — treat the warning as if it had `safe`
      // severity (the orElse fallback).
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'WHATEVER', 'with': 'unknown'},
        ],
      );
      expect(out, isA<HeroVerdictNone>());
    });

    test('warning with non-string severity → ignored', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 42, 'with': 'numeric'},
        ],
      );
      expect(out, isA<HeroVerdictNone>());
    });

    test('warning with severity in mixed case → still normalizes', () {
      final out = computeHeroVerdict(
        productVerdict: 'GOOD',
        blockingReason: '',
        topWarnings: const [
          {'severity': 'AVOID', 'with': 'metformin'},
        ],
      );
      expect(out, isA<HeroVerdictAvoid>());
    });

    test('HeroVerdictAvoid asserts on lower-severity construction', () {
      expect(
        () => HeroVerdictAvoid(severity: Severity.caution),
        throwsAssertionError,
      );
      expect(
        () => HeroVerdictAvoid(severity: Severity.safe),
        throwsAssertionError,
      );
    });
  });
}
