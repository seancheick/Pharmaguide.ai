// FIX 4 (P2) — verdict fail-open guard.
//
// An unrecognized, non-empty verdict is contract drift. It must NOT render
// as a calm neutral chip (which bypasses every blocked gate) and it must be
// breadcrumbed to CrashReportingService so the drift is visible. Known
// verdicts and the empty/placeholder verdict are unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

void main() {
  group('VerdictBadge unknown-verdict fail-open guard', () {
    test('unknown verdict is caution-tone, never safe or neutral', () {
      final c = VerdictBadge.colorFor(V2Palette.light, 'SOME_NEW_VERDICT');
      expect(c, V2Palette.light.caution);
      expect(c, isNot(V2Palette.light.safe));
      expect(c, isNot(V2Palette.light.fgSubtle));
    });

    test('known verdicts are untouched by the guard', () {
      expect(VerdictBadge.colorFor(V2Palette.light, 'SAFE'), V2Palette.light.safe);
      expect(VerdictBadge.colorFor(V2Palette.light, 'BLOCKED'), V2Palette.light.contraindicated);
      expect(VerdictBadge.colorFor(V2Palette.light, 'NOT_SCORED'), V2Palette.light.fgSubtle);
    });

    test('unknown verdict is breadcrumbed once per session (deduped)', () {
      final crash = CrashReportingService();
      crash.clearBuffersForTest();

      // Unique token so the module-global dedup set hasn't seen it. Each
      // test file runs in its own isolate, so this is fresh here.
      const canary = 'DRIFT_CANARY_XYZZY';
      VerdictBadge.colorFor(V2Palette.light, canary);
      VerdictBadge.colorFor(V2Palette.light, canary); // repeat render must NOT double-log
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

      VerdictBadge.colorFor(V2Palette.light, '');
      VerdictBadge.colorFor(V2Palette.light, '   ');

      expect(crash.breadcrumbs, isEmpty);
    });
  });
}
