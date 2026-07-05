// FIX 4 (P2) — verdict fail-open guard.
//
// An unrecognized, non-empty verdict is contract drift. It must NOT render
// as a calm neutral chip (which bypasses every blocked gate) and it must be
// breadcrumbed to CrashReportingService so the drift is visible. Known
// verdicts and the empty/placeholder verdict are unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

void main() {
  group('VerdictBadge unknown-verdict fail-open guard', () {
    test('unknown verdict is caution-tone, never safe or neutral', () {
      final c = VerdictBadge.colorFor('SOME_NEW_VERDICT');
      expect(c, V2Colors.caution);
      expect(c, isNot(V2Colors.safe));
      expect(c, isNot(V2Colors.fgSubtle));
    });

    test('known verdicts are untouched by the guard', () {
      expect(VerdictBadge.colorFor('SAFE'), V2Colors.safe);
      expect(VerdictBadge.colorFor('BLOCKED'), V2Colors.contraindicated);
      expect(VerdictBadge.colorFor('NOT_SCORED'), V2Colors.fgSubtle);
    });

    test('unknown verdict is breadcrumbed once per session (deduped)', () {
      final crash = CrashReportingService();
      crash.clearBuffersForTest();

      // Unique token so the module-global dedup set hasn't seen it. Each
      // test file runs in its own isolate, so this is fresh here.
      const canary = 'DRIFT_CANARY_XYZZY';
      VerdictBadge.colorFor(canary);
      VerdictBadge.colorFor(canary); // repeat render must NOT double-log
      VerdictBadge.labelFor(canary); // label path shares the dedup

      final hits = crash.breadcrumbs
          .where((b) => b.message.contains(canary))
          .toList();
      expect(
        hits,
        hasLength(1),
        reason: 'contract drift should breadcrumb once per unknown verdict',
      );
    });

    test('empty verdict is not treated as drift (no breadcrumb)', () {
      final crash = CrashReportingService();
      crash.clearBuffersForTest();

      VerdictBadge.colorFor('');
      VerdictBadge.colorFor('   ');

      expect(crash.breadcrumbs, isEmpty);
    });
  });
}
